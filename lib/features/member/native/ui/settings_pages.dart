// The Settings pages. Every row reads the member's log through [Prefs] and writes it back through the store,
// so the setting is saved on the phone at once and syncs with the account like any other change.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/network/api_exception.dart';
import '../domain/accent.dart';
import '../domain/backup.dart';
import '../domain/equipment.dart';
import '../domain/rows.dart';
import '../domain/settings.dart';
import '../domain/starter.dart';
import '../log_store.dart';
import '../../../../core/legal/notices.dart';
import 'account_pages.dart';
import 'alerts.dart';
import 'profile_screen.dart';
import 'reminders.dart';
import 'scope.dart';
import 'settings_screen.dart';
import 'settings_widgets.dart';
import 'theme.dart';
import 'widgets.dart';

const _openGymSource = String.fromEnvironment('OPENGYM_SOURCE_URL', defaultValue: 'https://github.com/DuarteSantos8/openGym');

/// What the chosen accent is called: a preset's colour name, or "Your own color".
String accentLabel(Json s) {
  final k = accentKeyOf(s);
  return k == customAccent ? 'Your own color' : (accentNames[k] ?? 'Green');
}

/// What a page's rows need: the scope, the settings, and the way to change one.
class SettingsEnv {
  SettingsEnv(this.context, this.sc);
  final BuildContext context;
  final NativeScope sc;
  MemberLogStore get st => sc.store;
  Prefs get p => Prefs(sc.state);

  /// Writes one setting (null removes it, so the default applies again).
  void set(String key, Object? value) => st.update((s) {
    if (value == null) {
      s.remove(key);
    } else {
      s[key] = value;
    }
  });

  void setWc(String key, bool value) => st.update((s) => s['wc'] = {...asMap(s['wc']), key: value});
}

class SettingsPage extends StatelessWidget {
  const SettingsPage(this.id, {super.key, this.find});
  final String id;
  final String? find;

  @override
  Widget build(BuildContext context) {
    final sc = NativeScope.of(context);
    final build = _builders[id]!;
    return ListenableBuilder(listenable: sc.store, builder: (context, _) =>
        SettingsScaffold(title: pageInfo(id).title, flash: find, children: build(SettingsEnv(context, sc))));
  }
}

final Map<String, List<Widget> Function(SettingsEnv e)> _builders = {
  'workout': _workout,
  'advanced': _advanced,
  'alerts': _alerts,
  'plan': _plan,
  'units': _units,
  'equipment': _equipment,
  'look': _look,
  'data': _data,
  'about': _about,
  'account': _account,
};

// ---- Workout ---------------------------------------------------------------------------------------------------------

List<Widget> _workout(SettingsEnv e) {
  final p = e.p;
  return [
    SettingsSection(title: 'Rest', footer: 'Scroll to 0:00 to turn the rest timer off.', children: [
      SettingsRow(
        icon: Icons.timer_outlined, tint: OG.orange, title: 'Rest timer', value: fmtRest(p.restSec), chevron: true,
        onTap: () async {
          final v = await pickDuration(e.context, title: 'Rest timer', seconds: p.restSec, maxSeconds: 900, footer: 'Scroll to 0:00 to turn the rest timer off.');
          if (v != null) e.set('restSec', v);
        },
      ),
    ]),
    SettingsSection(title: 'Logging', children: [
      SegmentedRow<String>(
        icon: Icons.speed_rounded, tint: OG.purple, title: 'Effort per set', value: p.effort,
        options: const [('none', 'Off'), ('rir', 'RIR'), ('rpe', 'RPE')],
        onChanged: (v) => e.st.update((s) {
          s['effort'] = v;
          s.remove('showRir');
        }),
        subtitle: 'How close to failure each set was.',
      ),
      SettingsRow(icon: Icons.info_outline, tint: OG.purple, title: 'What are RIR and RPE?', chevron: true, onTap: () => showEffortHelp(e.context)),
      SelectRow<String>(
        icon: Icons.history_rounded, title: 'Shown under each exercise', value: p.logRef, tint: OG.blue,
        options: const [
          SelectOption('last', 'Last time', subtitle: 'What you did the last time, in that routine.'),
          SelectOption('best', 'Best set', subtitle: 'Your heaviest set of the exercise, from any workout.'),
        ],
        onChanged: (v) => e.set('logRef', v),
      ),
      SwitchRow(
        icon: Icons.unfold_less_rounded, tint: OG.teal, title: 'Collapse completed exercises',
        subtitle: 'A finished exercise folds into one line.', value: p.collapseCompleted, onChanged: (v) => e.set('collapseCompleted', v),
      ),
    ]),
    SettingsSection(title: 'Before and during', children: [
      SwitchRow(
        icon: Icons.monitor_weight_outlined, tint: OG.green, title: 'Weigh in before workouts',
        subtitle: 'Asks for your body weight when a workout starts. Off starts the session straight away.',
        value: p.weighIn, onChanged: (v) => e.set('weighIn', v),
      ),
      SwitchRow(
        icon: Icons.light_mode_outlined, tint: OG.yellow, title: 'Keep screen awake',
        subtitle: 'The screen stays on while a workout is running, so you do not have to unlock your phone between sets.',
        value: p.keepAwake, onChanged: (v) => e.set('keepAwake', v),
      ),
      SegmentedRow<String>(
        icon: Icons.image_outlined, tint: OG.teal, title: 'Exercise pictures', value: p.gifSize,
        options: const [('full', 'Full'), ('mini', 'Small'), ('off', 'Hidden')],
        onChanged: (v) => e.set('gifSize', v),
      ),
    ]),
    SettingsSection(children: [
      SettingsRow(icon: Icons.build_rounded, tint: OG.grey, title: 'Fine-tuning', subtitle: 'Planned sessions, buttons', chevron: true, onTap: () => openSettingsPage(e.context, 'advanced')),
    ]),
  ];
}

List<Widget> _advanced(SettingsEnv e) {
  final p = e.p;
  return [
    SettingsSection(title: 'Sessions', children: [
      SelectRow<String>(
        icon: Icons.assignment_outlined, tint: OG.green, title: 'Planned sessions start from', value: p.startFrom,
        options: const [
          SelectOption('plan', 'Your plan', subtitle: 'The routine’s sets and reps. Your history decides the weight.'),
          SelectOption('last', 'Your last session', subtitle: 'The reps you logged last time in that routine, carried over.'),
        ],
        onChanged: (v) => e.set('startFrom', v),
      ),
    ]),
    SettingsSection(title: 'Buttons on the workout screen', footer: 'Off, tap the number and type it.', children: [
      SwitchRow(
        icon: Icons.add_circle_outline, tint: OG.green, title: 'Weight and reps buttons',
        subtitle: 'The plus and minus buttons beside every number.', value: p.steppers, onChanged: (v) => e.setWc('steppers', v),
      ),
    ]),
  ];
}

// ---- Timer alerts ----------------------------------------------------------------------------------------------------

List<Widget> _alerts(SettingsEnv e) {
  final p = e.p;
  return [
    SettingsSection(title: 'When a rest ends', footer: 'These play when the rest timer reaches zero, also when the screen is on another app.', children: [
      SwitchRow(
        icon: Icons.volume_up_rounded, tint: OG.pink, title: 'Play a sound', value: p.sound,
        onChanged: (v) {
          e.set('sound', v);
          if (v) RestAlerts.previewSound();
        },
      ),
      SwitchRow(
        icon: Icons.vibration_rounded, tint: OG.indigo, title: 'Vibrate', value: p.vibrate,
        onChanged: (v) {
          e.set('vibrate', v);
          if (v) RestAlerts.previewVibration();
        },
      ),
      SwitchRow(icon: Icons.flash_on_rounded, tint: OG.yellow, title: 'Flash the screen', value: p.timerFlash, onChanged: (v) => e.set('timerFlash', v)),
    ]),
    SettingsSection(title: 'Reminders', footer: 'A notice at this time on the days that have a routine in your plan. It is skipped on a day you have already trained.', children: [
      SwitchRow(
        icon: Icons.alarm_rounded, tint: OG.orange, title: 'Workout day reminder', value: p.reminderOn,
        subtitle: p.reminderOn ? 'Planned days at ${p.reminderTime}' : null,
        onChanged: (v) async {
          if (v && !await WorkoutReminders.allowed() && e.context.mounted) {
            toast(e.context, 'Allow notifications for Gymmie in your phone settings to get reminders.');
          }
          e.set('reminder', {'on': v, 'time': p.reminderTime});
        },
      ),
      SettingsRow(
        icon: Icons.schedule_rounded, tint: OG.blue, title: 'Reminder time', value: p.reminderTime, enabled: p.reminderOn,
        onTap: () async {
          final parts = p.reminderTime.split(':');
          final t = await showTimePicker(context: e.context, initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])));
          if (t != null) e.set('reminder', {'on': true, 'time': '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'});
        },
      ),
    ]),
  ];
}

// ---- Plan & schedule -------------------------------------------------------------------------------------------------

List<Widget> _plan(SettingsEnv e) {
  final p = e.p;
  return [
    SettingsSection(children: [
      SegmentedRow<int>(
        icon: Icons.calendar_today_rounded, tint: OG.orange, title: 'Week starts on', value: p.weekStart,
        options: const [(1, 'Monday'), (0, 'Sunday')], onChanged: (v) => e.set('weekStart', v),
      ),
    ]),
    SettingsSection(footer: 'Adds the plan’s routines and puts them on its weekdays. Your own routines are never touched.', children: [
      SettingsRow(icon: Icons.assignment_turned_in_outlined, tint: OG.green, title: 'Load starter plan', chevron: true, onTap: () => showStarterPlans(e.context)),
    ]),
  ];
}

/// "Choose starter plan": adds the routines and the weekdays, after asking when a weekday is already planned.
Future<void> showStarterPlans(BuildContext context) async {
  final sc = NativeScope.of(context);
  final id = await showSheet<String>(context, title: 'Choose starter plan', builder: (ctx) => [
    for (final plan in starterPlans) ListTile(
      leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: OG.card2, borderRadius: BorderRadius.circular(10)), child: Icon(Icons.assignment_outlined, color: OG.dim)),
      title: Text(plan.name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('${plan.daysPerWeek} days per week · ${plan.about}', style: TextStyle(color: OG.dim, fontSize: 12.5)),
      trailing: Icon(Icons.chevron_right, color: OG.dim),
      onTap: () => Navigator.pop(ctx, plan.id),
    ),
  ]);
  if (id == null || !context.mounted) return;
  final plan = starterPlanById(id)!;
  final week = asMap(sc.state['week']);
  final routineIds = {for (final r in asRows(sc.state['routines'])) '${r['id']}'};
  bool taken(int day) {
    final v = week['$day'];
    return (v is List ? v : [v]).any((x) => routineIds.contains('$x'));
  }
  if (plan.days.any(taken)) {
    const names = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    final ok = await confirm(context, 'Load ${plan.name}?', message: 'The new plan goes on ${plan.days.map((d) => names[d]).join(', ')}. Your existing routines stay; only those days of the weekly plan change.', ok: 'Load plan');
    if (!ok || !context.mounted) return;
  }
  sc.store.update((s) => loadStarterPlan(s, id));
  if (context.mounted) toast(context, '${plan.name} loaded');
}

// ---- Units -----------------------------------------------------------------------------------------------------------

List<Widget> _units(SettingsEnv e) {
  final p = e.p;
  return [
    SettingsSection(footer: 'Switching the unit offers to convert every stored weight.', children: [
      SegmentedRow<String>(
        icon: Icons.scale_outlined, tint: OG.teal, title: 'Weight unit', value: p.unit,
        options: const [('kg', 'kg'), ('lb', 'lb')], onChanged: (v) => _switchUnit(e, v),
      ),
      SegmentedRow<int>(
        icon: Icons.straighten_rounded, tint: OG.teal, title: 'Weight decimals', subtitle: 'How precisely weights are shown.', value: p.decimals,
        options: const [(1, '0.5'), (2, '0.25')], onChanged: (v) => e.set('wdec', v),
      ),
      SelectRow<String>(
        icon: Icons.show_chart_rounded, tint: OG.teal, title: '1RM formula', value: p.oneRmFormula,
        options: const [
          SelectOption('epley', 'Epley', subtitle: 'The common one. A bit generous at higher reps.'),
          SelectOption('brzycki', 'Brzycki', subtitle: 'More conservative above five reps.'),
          SelectOption('lombardi', 'Lombardi', subtitle: 'Generous, especially at high reps.'),
          SelectOption('oconner', 'O’Conner', subtitle: 'The most conservative of the classics.'),
          SelectOption('mayhew', 'Mayhew'),
          SelectOption('wathan', 'Wathan'),
          SelectOption('lander', 'Lander'),
          SelectOption('weighted', 'Blend of all', subtitle: 'Averages seven formulas and reads your RIR when you log it.'),
        ],
        onChanged: (v) => e.set('oneRmFormula', v),
      ),
    ]),
  ];
}

/// Two honest choices on a unit switch: convert the numbers, or keep them and only change the label.
Future<void> _switchUnit(SettingsEnv e, String to) async {
  final from = e.p.unit;
  if (to == from) return;
  final r = await showSheet<bool>(e.context, title: 'Convert to $to?',
    subtitle: 'Every stored weight (logged sets, working weights, routine targets, body weight) is in $from. Convert the numbers, or keep them and only change the label?',
    builder: (ctx) => [
      ListTile(leading: const Icon(Icons.calculate_outlined), title: const Text('Convert the numbers'), onTap: () => Navigator.pop(ctx, true)),
      ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Keep the numbers, change the label'), onTap: () => Navigator.pop(ctx, false)),
    ]);
  if (r == null) return; // closing the sheet leaves the unit as it was
  e.st.setUnit(to, convert: r, equipmentOf: (id) => e.sc.catalogue.byId(id)?.equipment);
}

// ---- Equipment -------------------------------------------------------------------------------------------------------

List<Widget> _equipment(SettingsEnv e) {
  final p = e.p;
  final profiles = p.equipProfiles;
  final all = allEquipment(e.sc.allExercises);
  final active = profiles.where((x) => x['id'] == p.activeEquipId).firstOrNull;
  return [
    if (profiles.isNotEmpty) SettingsSection(
      footer: 'With a profile on, the exercise library and the picker only show what you can do with that equipment. Body weight exercises always stay.',
      children: [
        SwitchRow(
          icon: Icons.filter_alt_outlined, tint: OG.green, title: 'Filter by equipment', value: p.equipFilterOn,
          onChanged: (v) => e.st.update((s) {
            s['equipFilterOn'] = v;
            if (v && s['activeEquipId'] == null && profiles.isNotEmpty) s['activeEquipId'] = profiles.first['id'];
          }),
        ),
        SelectRow<String>(
          icon: Icons.home_outlined, tint: OG.blue, title: 'Active profile', value: '${active?['id'] ?? profiles.first['id']}',
          options: [for (final x in profiles) SelectOption('${x['id']}', '${x['name']}')],
          onChanged: (v) => e.set('activeEquipId', v),
        ),
      ],
    ),
    SettingsSection(title: 'Profiles', children: [
      for (final x in profiles) SettingsRow(
        icon: Icons.fitness_center_rounded, tint: OG.indigo, title: '${x['name']}', value: '${profileEquipment(x).length} items', chevron: true,
        onTap: () => _editProfile(e, x, all),
      ),
      SettingsRow(icon: Icons.add_circle_outline, tint: OG.green, title: 'Add equipment profile', onTap: () => _addProfile(e, all)),
    ]),
  ];
}

Future<void> _addProfile(SettingsEnv e, List<String> all) async {
  final c = TextEditingController();
  final name = await showDialog<String>(
    context: e.context,
    builder: (ctx) => AlertDialog(
      title: const Text('New equipment profile'),
      content: TextField(controller: c, autofocus: true, maxLength: 30, decoration: const InputDecoration(hintText: 'Home, Gym, Hotel…'), onSubmitted: (v) => Navigator.pop(ctx, v.trim())),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Add'))],
    ),
  );
  if (name == null || name.isEmpty || !e.context.mounted) return;
  final profile = newProfile(name);
  e.st.update((s) {
    final list = [...asRows(s['equipProfiles']), profile];
    s['equipProfiles'] = list;
    s['activeEquipId'] ??= profile['id'];
  });
  if (e.context.mounted) await _editProfile(e, profile, all);
}

Future<void> _editProfile(SettingsEnv e, Json profile, List<String> all) async {
  final nameCtl = TextEditingController(text: '${profile['name']}');
  final have = {...profileEquipment(profile)};
  final result = await showModalBottomSheet<String>(
    context: e.context, isScrollControlled: true, showDragHandle: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(e.context).height * 0.9),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) => SafeArea(child: Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(ctx).bottom + 12),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: nameCtl, maxLength: 30, decoration: const InputDecoration(labelText: 'Profile name')),
        const SizedBox(height: 6),
        Text('What do you have?', style: TextStyle(color: OG.dim, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Flexible(child: SingleChildScrollView(child: Wrap(spacing: 8, runSpacing: 4, children: [
          for (final q in all) FilterChip(
            label: Text(q), selected: have.contains(q),
            onSelected: (on) => setState(() => on ? have.add(q) : have.remove(q)),
          ),
        ]))),
        const SizedBox(height: 12),
        FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () => Navigator.pop(ctx, 'delete'), style: OutlinedButton.styleFrom(foregroundColor: OG.red), child: const Text('Delete profile')),
      ]),
    ))),
  );
  if (result == null) return;
  final id = profile['id'];
  e.st.update((s) {
    final list = asRows(s['equipProfiles']);
    if (result == 'delete') {
      s['equipProfiles'] = [for (final x in list) if (x['id'] != id) x];
      if (s['activeEquipId'] == id) {
        s.remove('activeEquipId');
        s['equipFilterOn'] = false;
      }
    } else {
      s['equipProfiles'] = [
        for (final x in list)
          if (x['id'] == id) {...x, 'name': nameCtl.text.trim().isEmpty ? x['name'] : nameCtl.text.trim(), 'equipment': have.toList(), 'accV': accV} else x,
      ];
    }
  });
}

// ---- Look & Home -----------------------------------------------------------------------------------------------------

List<Widget> _look(SettingsEnv e) {
  final p = e.p;
  return [
    SettingsSection(footer: 'Your look follows you to every phone you sign in on.', children: [
      SegmentedRow<String>(
        icon: Icons.dark_mode_outlined, tint: OG.indigo, title: 'Theme', value: p.theme,
        options: const [('dark', 'Dark'), ('light', 'Light'), ('system', 'System')], onChanged: (v) => e.set('theme', v),
      ),
      _AccentPicker(env: e),
      SegmentedRow<String>(
        icon: Icons.accessibility_new_rounded, tint: OG.teal, title: 'Body diagram', value: p.bodyFigure,
        options: const [('male', 'Male'), ('female', 'Female')], onChanged: (v) => e.set('body', v),
      ),
    ]),
    SettingsSection(title: 'On Home', children: [
      SwitchRow(
        icon: Icons.qr_code_2_rounded, tint: OG.blue, title: 'Gym check-in', subtitle: 'Show the check-in code button on your gym card.',
        value: p.checkInCard, onChanged: (v) => e.set('checkIn', v),
      ),
      SwitchRow(
        icon: Icons.monitor_weight_outlined, tint: OG.green, title: 'Body weight', subtitle: 'Show the body weight card on Home.',
        value: p.weightCard, onChanged: (v) => e.set('showWeightCard', v),
      ),
      SwitchRow(
        icon: Icons.cloud_outlined, tint: OG.blue, title: 'Show connection status',
        subtitle: 'Off: the banner at the top is hidden. A dot on Home still warns when syncing is stuck.',
        value: p.connectionBar, onChanged: (v) => e.set('connStatus', v),
      ),
    ]),
  ];
}

/// The presets, then one swatch for a colour of the member's own.
class _AccentPicker extends StatelessWidget {
  const _AccentPicker({required this.env});
  final SettingsEnv env;

  @override
  Widget build(BuildContext context) {
    final s = env.sc.state;
    final key = accentKeyOf(s);
    final dark = OG.palette.dark;
    final mine = cleanHex(s['accentCustom']);
    final shown = mine == null ? null : readableIn(mine, dark ? 'dark' : 'light');
    Widget swatch(Color color, bool selected, VoidCallback onTap, {Widget? child, String? label, required String id}) => Semantics(
      label: label, button: true, selected: selected,
      child: GestureDetector(
        key: ValueKey('accent-$id'),
        onTap: onTap,
        child: Container(
          width: 36, height: 36, alignment: Alignment.center,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: selected ? OG.text : Colors.transparent, width: 2.5)),
          child: child ?? (selected ? Icon(Icons.check, size: 18, color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white) : null),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 30, height: 30, alignment: Alignment.center,
            decoration: BoxDecoration(color: OG.purple.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.palette_outlined, size: 18, color: OG.purple),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text('Accent color', style: TextStyle(fontSize: 16, color: OG.text, fontWeight: FontWeight.w500))),
          Text(accentLabel(s), style: TextStyle(color: OG.dim, fontSize: 15)),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final k in accentNames.keys)
            swatch(Color(0xFF000000 | int.parse((dark ? accentDark : accentLight)[k]!.substring(1), radix: 16)), key == k,
              () => env.set('accent', k), label: accentNames[k], id: k),
          swatch(
            shown == null ? Colors.transparent : Color(0xFF000000 | int.parse(shown.substring(1), radix: 16)), key == customAccent,
            () async {
              if (key == customAccent || mine == null) {
                final hex = await showColorDialog(context, mine ?? accentDark[accentKeyOf(s)]!);
                if (hex != null) {
                  env.st.update((st) {
                    st['accentCustom'] = hex;
                    st['accent'] = customAccent;
                  });
                }
              } else {
                env.set('accent', customAccent);
              }
            },
            label: 'Your own color',
            id: 'custom',
            child: mine == null ? const _RainbowRing() : null,
          ),
        ]),
        if (mine != null && key == customAccent && shown != mine) Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text('Drawn as ${shown!.toUpperCase()} so it stays readable on this theme.', style: TextStyle(color: OG.dim, fontSize: 12)),
        ),
      ]),
    );
  }
}

class _RainbowRing extends StatelessWidget {
  const _RainbowRing();
  @override
  Widget build(BuildContext context) => Container(
    width: 36, height: 36,
    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: SweepGradient(colors: [Color(0xFFFF453A), Color(0xFFFFD60A), Color(0xFF30D158), Color(0xFF40C8E0), Color(0xFF0A84FF), Color(0xFFBF5AF2), Color(0xFFFF453A)])),
    child: Center(child: Container(width: 20, height: 20, decoration: BoxDecoration(color: OG.card, shape: BoxShape.circle), child: Icon(Icons.add, size: 14, color: OG.text))),
  );
}

/// A colour of the member's own: red, green and blue sliders with a hex field. Returns '#rrggbb'.
Future<String?> showColorDialog(BuildContext context, String initial) {
  var hex = cleanHex(initial) ?? '#30d158';
  final c = TextEditingController(text: hex);
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final n = int.parse(hex.substring(1), radix: 16);
      final rgb = [(n >> 16) & 255, (n >> 8) & 255, n & 255];
      void apply(List<int> v) {
        hex = '#${v.map((x) => x.clamp(0, 255).toRadixString(16).padLeft(2, '0')).join()}';
        c.text = hex;
        setState(() {});
      }
      final color = Color(0xFF000000 | n);
      return AlertDialog(
        title: const Text('Your own color'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(height: 44, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12))),
          const SizedBox(height: 8),
          for (final (i, label) in ['R', 'G', 'B'].indexed) Row(children: [
            SizedBox(width: 18, child: Text(label, style: TextStyle(color: OG.dim))),
            Expanded(child: Slider(value: rgb[i].toDouble(), min: 0, max: 255, onChanged: (v) => apply([for (var k = 0; k < 3; k++) k == i ? v.round() : rgb[k]]))),
          ]),
          TextField(
            controller: c, maxLength: 7, decoration: const InputDecoration(labelText: 'Hex'),
            onChanged: (v) {
              final ok = cleanHex(v.startsWith('#') ? v : '#$v');
              if (ok != null) setState(() => hex = ok);
            },
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, hex), child: const Text('Use this color')),
        ],
      );
    }),
  );
}

// ---- Data & backup ---------------------------------------------------------------------------------------------------

List<Widget> _data(SettingsEnv e) => [
  SettingsSection(title: 'Back up', footer: 'The file is the same one openGym exports, so a log moves between the two. It does not include a workout you have not finished.', children: [
    SettingsRow(icon: Icons.ios_share_rounded, tint: OG.blue, title: 'Export backup (JSON)', chevron: true, onTap: () => _exportBackup(e)),
  ]),
  SettingsSection(title: 'Bring data in', footer: 'Importing adds to your log: nothing you already logged is deleted. To start over from a backup, delete your training data first.', children: [
    SettingsRow(icon: Icons.file_download_outlined, tint: OG.teal, title: 'Import backup', chevron: true, onTap: () => _importBackup(e)),
  ]),
  SettingsSection(children: [
    SettingsRow(icon: Icons.delete_outline, danger: true, title: 'Delete all my training data', onTap: () => deleteEverything(e.context, e.sc)),
  ]),
];

Future<void> _exportBackup(SettingsEnv e) async {
  try {
    final dir = await getTemporaryDirectory();
    final name = backupFileName(DateTime.now());
    final f = File('${dir.path}/$name');
    await f.writeAsString(exportBackup(e.sc.state), flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'application/json')], subject: name));
  } catch (_) {
    if (e.context.mounted) toast(e.context, 'Could not export your backup.');
  }
}

Future<void> _importBackup(SettingsEnv e) async {
  final context = e.context;
  Json doc;
  try {
    final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json']);
    if (picked == null) return;
    final path = picked.path;
    if (path == null) throw const BackupError('Could not open this file.');
    final size = await File(path).length();
    if (size > backupMaxBytes) throw const BackupError('This file is too large to be a backup.');
    doc = parseBackup(await File(path).readAsString());
  } on BackupError catch (err) {
    if (context.mounted) toast(context, err.message);
    return;
  } catch (_) {
    if (context.mounted) toast(context, 'Could not read this file.');
    return;
  }
  if (!context.mounted) return;
  final s = backupSummary(doc);
  final ok = await confirm(context, 'Import backup?',
    message: 'This adds ${s.workouts} workout${s.workouts == 1 ? '' : 's'}, ${s.routines} routine${s.routines == 1 ? '' : 's'} and ${s.weighIns} weigh-in${s.weighIns == 1 ? '' : 's'} to your log. Nothing you already logged is removed.',
    ok: 'Import');
  if (!ok || !context.mounted) return;
  e.st.importBackup(doc);
  toast(context, 'Backup imported');
}

/// "Delete all my training data": the account's copy and this phone's, after asking.
Future<void> deleteEverything(BuildContext context, NativeScope sc) async {
  if (!await confirm(context, 'Delete all your training data?', message: 'Workouts, routines and weigh-ins are erased from this phone and your account. This cannot be undone.', ok: 'Delete everything', danger: true)) return;
  try {
    await sc.store.eraseAll();
    if (context.mounted) toast(context, 'Your training data was deleted.');
  } catch (_) {
    if (context.mounted) toast(context, 'Could not reach the server. Try again when online.');
  }
}

// ---- About -----------------------------------------------------------------------------------------------------------

List<Widget> _about(SettingsEnv e) => [
  Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 18),
    child: Center(child: Image.asset('assets/brand/logo_title.png', height: 150, fit: BoxFit.contain, semanticLabel: 'Gymmie')),
  ),
  SettingsSection(children: [
    _VersionRow(),
    SettingsRow(icon: Icons.gavel_rounded, tint: OG.grey, title: 'Open-source licences', chevron: true, onTap: () => showNotices(e.context)),
    SettingsRow(icon: Icons.code_rounded, tint: OG.green, title: 'Source code', subtitle: 'The training log is free software (AGPL v3).', chevron: true,
      onTap: () => launchUrl(Uri.parse(_openGymSource), mode: LaunchMode.externalApplication)),
  ]),
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Text(
      'Gymmie is free software (AGPL-3.0). The member app is a port of openGym; $gymManeAttribution (the “Choose a focus” flow). '
      'Exercise pictures © Aliaksandr Makatserchyk, gymvisual.com, used for openGym only.',
      style: TextStyle(color: OG.dim, fontSize: 12, height: 1.4),
    ),
  ),
];

class _VersionRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) => FutureBuilder<PackageInfo>(
    future: PackageInfo.fromPlatform(),
    builder: (context, snap) => SettingsRow(icon: Icons.info_outline_rounded, tint: OG.dim, title: 'Version', value: snap.hasData ? 'v${snap.data!.version}' : '…'),
  );
}

// ---- My account ------------------------------------------------------------------------------------------------------

List<Widget> _account(SettingsEnv e) {
  final sc = e.sc;
  final st = e.st;
  final status = switch (st.status) {
    SyncStatus.syncing => 'Syncing…',
    SyncStatus.offline => 'Offline. Changes are saved on this phone.',
    SyncStatus.error => 'Sync problem. Will retry.',
    SyncStatus.idle => st.dirty ? 'Changes waiting to sync' : 'All changes saved to your account',
  };
  return [
    SettingsSection(title: 'Your gym', children: [
      SettingsRow(
        icon: Icons.badge_outlined, title: 'My profile', subtitle: '${sc.overview.gym.name} · membership, payments and gym details', chevron: true,
        onTap: () => pushPage(e.context, const ProfileScreen()),
      ),
      SettingsRow(
        icon: Icons.assignment_late_outlined, tint: OG.orange, title: 'Membership requests', subtitle: 'Ask to renew, change plan or cancel', chevron: true,
        onTap: () => pushPage(e.context, const RequestsScreen()),
      ),
    ]),
    SettingsSection(title: 'You', children: [
      SettingsRow(icon: Icons.edit_outlined, tint: OG.green, title: 'Edit profile', subtitle: 'Name, photo, contact and fitness profile', chevron: true, onTap: () => pushPage(e.context, const EditProfileScreen())),
      SettingsRow(icon: Icons.notifications_none_rounded, tint: OG.red, title: 'Notifications', subtitle: 'Gym messages and expiry reminders', chevron: true, onTap: () => pushPage(e.context, const NotificationsScreen())),
      SettingsRow(icon: Icons.visibility_outlined, tint: OG.purple, title: 'Privacy', subtitle: 'What your trainer can see', chevron: true, onTap: () => pushPage(e.context, const PrivacyScreen())),
      SettingsRow(icon: Icons.lock_outline_rounded, tint: OG.blue, title: 'Devices & security', subtitle: 'Signed-in phones, phone number', chevron: true, onTap: () => pushPage(e.context, const DevicesScreen())),
    ]),
    SettingsSection(title: 'Sync', footer: 'Your training log is private to you. Your gym’s staff cannot read it. The settings on these pages are part of it, so they follow you to every phone.', children: [
      SettingsRow(
        icon: st.status == SyncStatus.offline ? Icons.cloud_off : Icons.cloud_done_outlined, tint: st.status == SyncStatus.offline ? OG.orange : OG.acc,
        title: 'Sync now', subtitle: status, onTap: st.status == SyncStatus.syncing ? null : () => st.sync(),
      ),
    ]),
    SettingsSection(children: [
      SettingsRow(icon: Icons.logout_rounded, tint: OG.red, title: 'Sign out', onTap: () async {
        if (!await confirm(e.context, 'Sign out?', message: st.dirty ? 'Unsynced changes are sent first when you are online.' : 'Your training log stays safe in your account.', ok: 'Sign out')) return;
        await sc.signOut();
      }),
      SettingsRow(
        icon: Icons.shield_outlined, tint: OG.red, danger: true, title: 'Sign out everywhere', subtitle: 'Ends your sessions on every phone. You can sign in again with your phone number.',
        onTap: () async {
          if (!await confirm(e.context, 'Sign out everywhere?', message: 'You will be signed out on every phone you used, including this one. Your training log stays safe in your account.', ok: 'Sign out everywhere', danger: true)) return;
          try {
            await sc.signOutEverywhere();
          } on ApiException catch (err) {
            if (e.context.mounted) toast(e.context, err.isNetwork ? 'You need to be online to sign out everywhere.' : 'Could not sign you out everywhere. Try again.');
          }
        },
      ),
    ]),
    SettingsSection(footer: 'Erases your training log, photo and contact details from your account. Your gym keeps your membership and payment records.', children: [
      SettingsRow(icon: Icons.delete_forever_outlined, tint: OG.red, danger: true, title: 'Delete my account', chevron: true, onTap: () => pushPage(e.context, const DeleteAccountScreen())),
    ]),
  ];
}

// ---- Effort help -----------------------------------------------------------------------------------------------------

Future<void> showEffortHelp(BuildContext context) => showSheet<void>(context, title: 'Effort per set',
  subtitle: 'How hard a set was, logged next to weight and reps. Two scales for the same judgement, counted from opposite ends.',
  builder: (ctx) => [
    Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), child: Column(children: [
      for (final (i, r) in const [
        ('RIR', 'RPE', 'How it felt'),
        ('0', '10', 'Nothing left, went to failure'),
        ('1', '9', 'One more rep in the tank'),
        ('2', '8', 'Two more reps'),
        ('3', '7', 'Three more reps'),
        ('4+', '≤6', 'Easy, warm-up territory'),
      ].indexed) Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
        decoration: BoxDecoration(color: i == 3 ? OG.acc.withValues(alpha: 0.15) : null, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          SizedBox(width: 44, child: Text(r.$1, style: TextStyle(fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w600, color: i == 0 ? OG.dim : OG.text))),
          SizedBox(width: 44, child: Text(r.$2, style: TextStyle(fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w600, color: i == 0 ? OG.dim : OG.text))),
          Expanded(child: Text(r.$3, style: TextStyle(color: i == 0 ? OG.dim : OG.text))),
        ]),
      ),
      const SizedBox(height: 10),
      Text('RIR counts the reps you left in the tank; RPE reads the same effort off a 10-point scale, so RPE ≈ 10 − RIR. Pick whichever you already think in. The highlighted row is where most working sets land. Sets you have already logged keep their own scale.',
        style: TextStyle(color: OG.dim, fontSize: 12.5, height: 1.45)),
    ])),
  ],
);
