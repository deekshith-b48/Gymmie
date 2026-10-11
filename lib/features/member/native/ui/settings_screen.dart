// Settings, laid out as openGym's: an account card, a few rows that each open a page, and a search over every
// row. Each page's rows read and write the member's log (domain/settings.dart), so a change shows at once, is
// saved on the phone, and follows the member to the account (and their other phones) through the normal sync.
import 'package:flutter/material.dart';

import '../domain/settings.dart';
import '../log_store.dart' show SyncStatus;
import 'scope.dart';
import 'settings_pages.dart';
import 'settings_widgets.dart';
import 'theme.dart';

/// Which page a row lives on, and what the root shows for it.
class PageInfo {
  const PageInfo(this.id, this.title, this.icon, this.tint, {this.parent});
  final String id;
  final String title;
  final IconData icon;
  final Color tint;
  final String? parent;
}

Color _c(int v) => Color(0xFF000000 | v);

final List<PageInfo> settingsPages = [
  PageInfo('workout', 'Workout', Icons.play_arrow_rounded, _c(0x30D158)),
  PageInfo('alerts', 'Timer alerts', Icons.volume_up_rounded, _c(0xFF375F)),
  PageInfo('plan', 'Plan & schedule', Icons.calendar_month_rounded, _c(0xFF9F0A)),
  PageInfo('units', 'Units', Icons.straighten_rounded, _c(0x40C8E0)),
  PageInfo('equipment', 'Equipment', Icons.fitness_center_rounded, _c(0x5E5CE6)),
  PageInfo('look', 'Look & Home', Icons.palette_rounded, _c(0xBF5AF2)),
  PageInfo('data', 'Data & backup', Icons.folder_rounded, _c(0x0A84FF)),
  PageInfo('about', 'About', Icons.info_outline_rounded, _c(0x8E8E93)),
  PageInfo('account', 'My account', Icons.person_rounded, _c(0x8E8E93)),
  PageInfo('advanced', 'Fine-tuning', Icons.build_rounded, _c(0x8E8E93), parent: 'workout'),
];

PageInfo pageInfo(String id) => settingsPages.firstWhere((p) => p.id == id);

/// The rows of the root, in groups.
const rootGroups = [
  ['workout', 'alerts'],
  ['plan', 'units', 'equipment'],
  ['look'],
  ['data', 'about'],
];

/// One searchable row: [kw] are extra words people type for it.
class SearchEntry {
  const SearchEntry(this.page, this.title, this.icon, [this.kw = '']);
  final String page;
  final String title;
  final IconData icon;
  final String kw;
}

const settingsIndex = <SearchEntry>[
  SearchEntry('workout', 'Rest timer', Icons.timer_outlined, 'rest pause break seconds minutes countdown'),
  SearchEntry('workout', 'Effort per set', Icons.speed_rounded, 'rir rpe effort reps in reserve difficulty'),
  SearchEntry('workout', 'Shown under each exercise', Icons.history_rounded, 'last time best set reference previous'),
  SearchEntry('workout', 'Collapse completed exercises', Icons.unfold_less_rounded, 'collapse fold hide done finished'),
  SearchEntry('workout', 'Weigh in before workouts', Icons.monitor_weight_outlined, 'body weight weigh scale start'),
  SearchEntry('workout', 'Keep screen awake', Icons.light_mode_outlined, 'wake lock screen sleep display on'),
  SearchEntry('workout', 'Exercise pictures', Icons.image_outlined, 'gif animation media images small hidden'),
  SearchEntry('workout', 'Fine-tuning', Icons.build_rounded, 'advanced more options'),
  SearchEntry('advanced', 'Planned sessions start from', Icons.assignment_outlined, 'start plan last session reps carry over'),
  SearchEntry('advanced', 'Weight and reps buttons', Icons.add_circle_outline, 'steppers plus minus buttons'),
  SearchEntry('alerts', 'Play a sound', Icons.volume_up_rounded, 'sound audio beep chime'),
  SearchEntry('alerts', 'Vibrate', Icons.vibration_rounded, 'vibration haptic buzz'),
  SearchEntry('alerts', 'Flash the screen', Icons.flash_on_rounded, 'flash light blink'),
  SearchEntry('alerts', 'Workout day reminder', Icons.alarm_rounded, 'reminder notification alarm remind train planned day time'),
  SearchEntry('plan', 'Week starts on', Icons.calendar_today_rounded, 'monday sunday first day week'),
  SearchEntry('plan', 'Load starter plan', Icons.assignment_turned_in_outlined, 'starter template beginner program routine push pull legs'),
  SearchEntry('units', 'Weight unit', Icons.scale_outlined, 'kg lb lbs pounds kilos kilograms'),
  SearchEntry('units', 'Weight decimals', Icons.straighten_rounded, 'decimals precision microplates rounding'),
  SearchEntry('units', '1RM formula', Icons.show_chart_rounded, 'one rep max epley brzycki lombardi estimate'),
  SearchEntry('equipment', 'Filter by equipment', Icons.filter_alt_outlined, 'equipment filter home gym'),
  SearchEntry('equipment', 'Active profile', Icons.home_outlined, 'equipment profile home gym'),
  SearchEntry('equipment', 'Add equipment profile', Icons.add_circle_outline, 'equipment profile home gym hotel'),
  SearchEntry('look', 'Theme', Icons.dark_mode_outlined, 'dark mode light mode appearance night system'),
  SearchEntry('look', 'Accent color', Icons.palette_outlined, 'color colour accent tint custom own hex'),
  SearchEntry('look', 'Body diagram', Icons.accessibility_new_rounded, 'muscle map body male female'),
  SearchEntry('look', 'Gym check-in', Icons.qr_code_2_rounded, 'qr code membership card check in'),
  SearchEntry('look', 'Body weight', Icons.monitor_weight_outlined, 'weight card home'),
  SearchEntry('look', 'Show connection status', Icons.cloud_outlined, 'sync offline banner bar connection'),
  SearchEntry('data', 'Export backup (JSON)', Icons.ios_share_rounded, 'export backup json download save share'),
  SearchEntry('data', 'Import backup', Icons.file_download_outlined, 'import restore backup json openGym'),
  SearchEntry('data', 'Delete all my training data', Icons.delete_outline, 'delete wipe reset erase everything'),
  SearchEntry('about', 'Version', Icons.info_outline_rounded, 'version about licence license source code open source'),
  SearchEntry('account', 'Sync now', Icons.sync_rounded, 'server sync upload refresh status connection'),
  SearchEntry('account', 'Notifications', Icons.notifications_none_rounded, 'messages from my gym promotions offers announcements broadcast whatsapp sms opt out expiry reminder alerts'),
  SearchEntry('account', 'Edit profile', Icons.edit_outlined, 'name photo email phone address emergency contact fitness goal age birthday height'),
  SearchEntry('account', 'Privacy', Icons.visibility_outlined, 'trainer see share visibility health data hide training summary'),
  SearchEntry('account', 'Devices & security', Icons.lock_outline_rounded, 'password phone number change sessions devices security'),
  SearchEntry('account', 'Membership requests', Icons.assignment_late_outlined, 'renew renewal cancel cancellation change plan upgrade'),
  SearchEntry('account', 'Delete my account', Icons.delete_forever_outlined, 'close account erase remove data gdpr'),
  SearchEntry('account', 'My profile', Icons.badge_outlined, 'membership gym profile plan'),
  SearchEntry('account', 'Sign out', Icons.logout_rounded, 'log out logout'),
  SearchEntry('account', 'Sign out everywhere', Icons.shield_outlined, 'log out all devices phones sessions'),
];

String _fold(String s) => s.toLowerCase();

/// Rows whose title, page or keywords contain every word typed.
List<SearchEntry> searchSettings(String query) {
  final words = _fold(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return const [];
  bool hit(SearchEntry e) {
    final hay = _fold('${e.title} ${pageInfo(e.page).title} ${e.kw}');
    return words.every(hay.contains);
  }
  final found = [for (final e in settingsIndex) if (hit(e)) e];
  int rank(SearchEntry e) => _fold(e.title).contains(words.first) ? 0 : 1;
  found.sort((a, b) => rank(a).compareTo(rank(b)));
  return found;
}

void openSettingsPage(BuildContext context, String id, {String? find}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SettingsPage(id, find: find)));

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sc = NativeScope.of(context);
    return ListenableBuilder(listenable: sc.store, builder: (context, _) {
      final hits = searchSettings(_q.text);
      final searching = _q.text.trim().isNotEmpty;
      final initial = sc.memberName.trim().isEmpty ? '?' : sc.memberName.trim()[0].toUpperCase();
      final sub = sc.store.dirty && sc.store.status != SyncStatus.syncing ? 'Changes waiting to sync' : sc.overview.gym.name;
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          Padding(padding: const EdgeInsets.only(bottom: 16), child: TextField(
            controller: _q,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search settings', prefixIcon: const Icon(Icons.search),
              suffixIcon: searching ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_q.clear)) : null,
            ),
          )),
          if (searching)
            hits.isEmpty
                ? Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('No setting matches “${_q.text.trim()}”.', style: TextStyle(color: OG.dim))))
                : SettingsSection(title: '${hits.length} ${hits.length == 1 ? 'result' : 'results'}', children: [
                    for (final h in hits.take(40)) SettingsRow(
                      icon: h.icon, title: h.title, tint: pageInfo(h.page).tint, subtitle: _trail(h.page), chevron: true,
                      onTap: () => openSettingsPage(context, h.page, find: h.title),
                    ),
                  ])
          else ...[
            SettingsSection(children: [
              Material(color: Colors.transparent, child: InkWell(
                onTap: () => openSettingsPage(context, 'account'),
                child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
                  CircleAvatar(radius: 22, backgroundColor: OG.acc.withValues(alpha: 0.2), child: Text(initial, style: TextStyle(color: OG.acc, fontWeight: FontWeight.w800, fontSize: 18))),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(sc.memberName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    Text(sub, style: TextStyle(color: OG.dim, fontSize: 13)),
                  ])),
                  Icon(Icons.chevron_right, color: OG.dim),
                ])),
              )),
            ]),
            for (final g in rootGroups) SettingsSection(children: [
              for (final id in g) SettingsRow(
                icon: pageInfo(id).icon, title: pageInfo(id).title, tint: pageInfo(id).tint, value: previewOf(id, sc), chevron: true,
                onTap: () => openSettingsPage(context, id),
              ),
            ]),
            Center(child: Text('Gymmie member app · training log from openGym', style: TextStyle(color: OG.dim, fontSize: 12))),
          ],
        ]),
      );
    });
  }

  String _trail(String page) {
    final p = pageInfo(page);
    return p.parent == null ? p.title : '${pageInfo(p.parent!).title} › ${p.title}';
  }
}

/// The value a root row shows, so most questions are answered without opening the page.
String? previewOf(String id, NativeScope sc) {
  final p = Prefs(sc.state);
  switch (id) {
    case 'workout':
      return p.restSec > 0 ? '${fmtRest(p.restSec)} rest' : 'No rest timer';
    case 'alerts':
      final on = [if (p.sound) 'Sound', if (p.vibrate) 'Vibrate', if (p.timerFlash) 'Flash'];
      return on.isEmpty ? 'Silent' : on.join(' · ');
    case 'plan':
      return p.weekStart == 0 ? 'Week from Sun' : 'Week from Mon';
    case 'units':
      return '${p.unit} · ${p.decimals == 2 ? '0.25' : '0.5'}';
    case 'equipment':
      final active = p.equipProfiles.where((e) => e['id'] == p.activeEquipId).firstOrNull;
      return p.equipFilterOn && active != null ? '${active['name']}' : 'Everything';
    case 'look':
      return '${const {'dark': 'Dark', 'light': 'Light', 'system': 'System'}[p.theme]} · ${accentLabel(sc.state)}';
    default:
      return null;
  }
}
