package app.gymmie.android

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * The member app's workout reminders: one alarm at a time, for the next planned day at the member's chosen time.
 * The setting itself (on/off, time, which weekdays) lives in the member's log and is pushed here by the Dart side
 * every time it changes; this class only keeps the last copy so the reminder survives a restart and a reboot.
 */
object Reminders {
    private const val PREFS = "gymmie_reminders"
    private const val KEY = "config"
    private const val CHANNEL = "workout_reminders"
    private const val REQUEST = 7101
    const val ACTION = "app.gymmie.android.WORKOUT_REMINDER"

    fun save(ctx: Context, cfg: JSONObject?) {
        val e = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
        if (cfg == null) e.remove(KEY) else e.putString(KEY, cfg.toString())
        e.apply()
    }

    fun load(ctx: Context): JSONObject? =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)?.let { runCatching { JSONObject(it) }.getOrNull() }

    private fun pending(ctx: Context): PendingIntent = PendingIntent.getBroadcast(
        ctx, REQUEST, Intent(ctx, ReminderReceiver::class.java).setAction(ACTION),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun dateOf(c: Calendar) = "%04d-%02d-%02d".format(c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH))

    /** The next moment the reminder is due after [nowMs], or null (switched off, or no planned weekday). Pure, for the tests. */
    fun nextTrigger(cfg: JSONObject?, nowMs: Long): Long? {
        if (cfg == null || !cfg.optBoolean("on", false)) return null
        val days = cfg.optJSONArray("days") ?: JSONArray()
        if (days.length() == 0) return null
        val wanted = (0 until days.length()).map { days.optInt(it) }.toSet()
        val skipThrough = cfg.optString("skipThrough", "")
        for (offset in 0..14) {
            val c = Calendar.getInstance().apply {
                timeInMillis = nowMs
                add(Calendar.DAY_OF_MONTH, offset)
                set(Calendar.HOUR_OF_DAY, cfg.optInt("hour", 8))
                set(Calendar.MINUTE, cfg.optInt("minute", 0))
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            if (c.timeInMillis <= nowMs) continue
            if ((c.get(Calendar.DAY_OF_WEEK) - 1) !in wanted) continue
            if (skipThrough.isNotEmpty() && dateOf(c) <= skipThrough) continue // already trained that day
            return c.timeInMillis
        }
        return null
    }

    /** (Re)arms the alarm from the saved copy; returns when it will ring, or null if nothing is due. */
    fun schedule(ctx: Context): Long? {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(pending(ctx))
        val at = nextTrigger(load(ctx), System.currentTimeMillis()) ?: return null
        // Not exact on purpose: a reminder does not need the exact-alarm permission, and a few minutes either way do not matter.
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending(ctx))
        return at
    }

    fun cancel(ctx: Context) {
        (ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(pending(ctx))
        save(ctx, null)
    }

    fun notify(ctx: Context, cfg: JSONObject) {
        if (!NotificationManagerCompat.from(ctx).areNotificationsEnabled()) return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Workout reminders", NotificationManager.IMPORTANCE_DEFAULT))
        val open = PendingIntent.getActivity(
            ctx, REQUEST, ctx.packageManager.getLaunchIntentForPackage(ctx.packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val n = NotificationCompat.Builder(ctx, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle(cfg.optString("title", "Time to train"))
            .setContentText(cfg.optString("body", "Your workout is planned for today."))
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        runCatching { NotificationManagerCompat.from(ctx).notify(REQUEST, n) } // refused without the permission: nothing to do
    }
}

/** The alarm rang: show the reminder (if it is still wanted) and arm the next one. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val cfg = Reminders.load(context) ?: return
        if (cfg.optBoolean("on", false)) Reminders.notify(context, cfg)
        Reminders.schedule(context)
    }
}

/** After a reboot or an app update alarms are gone: arm the saved reminder again. */
class ReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) Reminders.schedule(context)
    }
}
