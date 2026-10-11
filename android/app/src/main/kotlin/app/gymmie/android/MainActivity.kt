package app.gymmie.android

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private var pendingPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gymmie/reminders").setMethodCallHandler { call, result ->
            when (call.method) {
                // {on, hour, minute, days: [0..6, Sunday = 0], title, body, skipThrough: 'yyyy-MM-dd'?}
                "schedule" -> {
                    val cfg = JSONObject().apply {
                        put("on", call.argument<Boolean>("on") ?: false)
                        put("hour", call.argument<Int>("hour") ?: 8)
                        put("minute", call.argument<Int>("minute") ?: 0)
                        put("days", JSONArray(call.argument<List<Int>>("days") ?: emptyList<Int>()))
                        put("title", call.argument<String>("title") ?: "Time to train")
                        put("body", call.argument<String>("body") ?: "Your workout is planned for today.")
                        put("skipThrough", call.argument<String>("skipThrough") ?: "")
                    }
                    Reminders.save(this, cfg)
                    result.success(Reminders.schedule(this))
                }
                "cancel" -> { Reminders.cancel(this); result.success(null) }
                "status" -> result.success(mapOf(
                    "allowed" to NotificationManagerCompat.from(this).areNotificationsEnabled(),
                    "next" to Reminders.nextTrigger(Reminders.load(this), System.currentTimeMillis()),
                ))
                "requestPermission" -> requestNotificationPermission(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            result.success(NotificationManagerCompat.from(this).areNotificationsEnabled())
            return
        }
        pendingPermission?.success(false)
        pendingPermission = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7102)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 7102) {
            pendingPermission?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            pendingPermission = null
        }
    }
}
