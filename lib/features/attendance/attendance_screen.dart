import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/auth/permissions.dart';
import '../../core/state/async_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/files.dart';
import '../../core/util/format.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../core/widgets/period_filter.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../../data/models/finance.dart';
import '../../data/repositories/finance_repository.dart';
import '../members/member_picker.dart';

/// Attendance logs for a day, with manual marking, QR scan and guest check-in.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final _repo = getIt<AttendanceRepository>();
  DateTime _day = DateTime.now();
  String? _source;
  late final PagedCubit<AttendanceLog> _cubit = PagedCubit<AttendanceLog>(
    fetch: _repo.logs,
    parse: AttendanceLog.fromJson,
    pageSize: 50,
    query: {'date': Fmt.ymd(_day)},
  );

  bool get _isToday => Fmt.ymd(_day) == Fmt.ymd(DateTime.now());

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  void _setDay(DateTime d) {
    setState(() => _day = d);
    _cubit.setQuery({
      'date': Fmt.ymd(d),
      if (_source != null) 'source': _source,
    });
  }

  Future<void> _mark({DateTime? at}) async {
    final m = await pickMember(
      context,
      title: at == null ? 'Mark attendance' : 'Add Manual Attendance',
    );
    if (m == null || !mounted) return;
    String? iso;
    if (at != null) {
      final d = await showDatePicker(
        context: context,
        initialDate: _day,
        firstDate: DateTime.now().subtract(const Duration(days: 365)),
        lastDate: DateTime.now(),
      );
      if (d == null || !mounted) return;
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
      if (t == null) return;
      final dt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
      if (dt.isAfter(DateTime.now())) {
        if (mounted) {
          showToast(
            context,
            'Selected date and time cannot be in the future.',
            error: true,
          );
        }
        return;
      }
      iso = dt.toUtc().toIso8601String();
    }
    if (!mounted) return;
    try {
      await runWithProgress(
        context,
        () => _repo.mark(m.id, at: iso),
        success: 'Attendance marked successfully',
      ).then((r) {
        if (r != null) _cubit.reload();
      });
    } catch (_) {}
  }

  Future<void> _guest() async {
    final name = await promptText(
      context,
      title: 'Add Guest',
      label: 'Guest Name',
      hint: 'Enter name',
      required: true,
      maxLength: 80,
    );
    if (name == null || !mounted) return;
    final phone = await promptText(
      context,
      title: 'Guest Phone (optional)',
      label: 'Guest Phone',
      hint: 'Enter Phone number',
      keyboardType: TextInputType.phone,
      validator: (v) => V.phone(v, optional: true),
    );
    if (phone == null || !mounted) return;
    if (await runOk(
      context,
      () => _repo.addGuest(
        name,
        phone: phone.isEmpty
            ? null
            : (phone.startsWith('+') ? phone : '+91$phone'),
      ),
      success: 'Attendance marked successfully',
    )) {
      _cubit.reload();
    }
  }

  Future<void> _export() async {
    final period = await showPeriodSheet(
      context,
      PeriodSel.thisMonth,
      allowAll: false,
      only: const {
        'today',
        'thisWeek',
        'last7Days',
        'last30Days',
        'thisMonth',
        'lastMonth',
        'custom',
      },
    );
    if (period == null || !mounted) return;
    final bytes = await runWithProgress(
      context,
      () => _repo.export({...period.query}),
    );
    if (bytes != null && mounted) {
      await shareBytes(
        context,
        bytes,
        'attendance-${period.key}.csv',
        'text/csv',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = getIt<SessionCubit>().state;
    final canWrite = s.can(Perm.attendanceWrite);
    final canDelete = s.role == 'owner' || s.role == 'manager';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Export Attendance',
            onPressed: _export,
          ),
        ],
      ),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: () => showAppSheet<void>(
                context,
                title: 'Mark attendance',
                builder: (ctx) => Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.how_to_reg_outlined),
                      title: const Text('Mark attendance'),
                      subtitle: const Text('Check a member in now'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _mark();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.qr_code_scanner),
                      title: const Text('Scan member QR'),
                      subtitle: const Text('QR Attendance'),
                      onTap: () {
                        Navigator.pop(ctx);
                        context
                            .push('/attendance/scan')
                            .then((_) => _cubit.reload());
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.history),
                      title: const Text('Add Manual Attendance'),
                      subtitle: const Text('Pick a past date and time'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _mark(at: DateTime.now());
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.person_add_alt_outlined),
                      title: const Text('Add Guest'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _guest();
                      },
                    ),
                  ],
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Mark'),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () =>
                        _setDay(_day.subtract(const Duration(days: 1))),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _day,
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 730),
                          ),
                          lastDate: DateTime.now(),
                        );
                        if (d != null) _setDay(d);
                      },
                      child: Column(
                        children: [
                          Text(
                            _isToday ? 'Today' : Fmt.dateLong(Fmt.ymd(_day)),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          if (_isToday)
                            Text(
                              Fmt.dateLong(Fmt.ymd(_day)),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _isToday
                        ? null
                        : () => _setDay(_day.add(const Duration(days: 1))),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (final (v, l) in [
                    (null, 'All'),
                    ('manual', 'Manual'),
                    ('qr', 'QR'),
                    ('biometric', 'Biometric'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: PillChip(
                        label: l,
                        selected: _source == v,
                        onTap: () {
                          _source = v;
                          _setDay(_day);
                        },
                      ),
                    ),
                ],
              ),
            ),
            BlocBuilder<PagedCubit<AttendanceLog>, PagedState<AttendanceLog>>(
              bloc: _cubit,
              builder: (context, st) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${st.total} check-in${st.total == 1 ? '' : 's'}',
                    style: const TextStyle(color: AppColors.info),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PagedListBody<AttendanceLog>(
                cubit: _cubit,
                separator: 8,
                empty: EmptyState(
                  asset: 'assets/empty_days.svg',
                  title: _isToday
                      ? 'No one has checked in yet'
                      : 'No attendance on this day',
                  message: 'Members who check in by QR, biometric device or manual marking appear here.',
                ),
                itemBuilder: (context, a) => AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  onTap: a.memberId == null
                      ? null
                      : () => context.push('/members/${a.memberId}'),
                  child: Row(
                    children: [
                      UserAvatar(
                        name: a.name ?? 'Guest',
                        url: a.photoUrl,
                        radius: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.name ?? 'Guest',
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              'In ${Fmt.time(a.checkIn)}${a.checkOut == null ? '' : ' · Out ${Fmt.time(a.checkOut)}'}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Tag(
                        a.kind == 'guest' ? 'Guest' : a.source,
                        tone: a.source == 'biometric'
                            ? Tone.info
                            : Tone.neutral,
                      ),
                      if (canWrite && a.checkOut == null && _isToday)
                        IconButton(
                          icon: const Icon(Icons.logout, size: 20),
                          tooltip: 'Check Out',
                          onPressed: () async {
                            if (await runOk(
                              context,
                              () => _repo.checkout(a.id),
                              success: 'Checked out',
                            )) {
                              _cubit.reload();
                            }
                          },
                        ),
                      if (canDelete)
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: AppColors.danger,
                          ),
                          tooltip: 'Delete Log',
                          onPressed: () async {
                            if (!await confirmDialog(
                                  context,
                                  title: 'Delete Log',
                                  message: 'This action cannot be undone',
                                  confirmLabel: 'Delete',
                                  destructive: true,
                                ) ||
                                !context.mounted) {
                              return;
                            }
                            if (await runOk(
                              context,
                              () => _repo.delete(a.id),
                              success: 'Deleted Log',
                            )) {
                              _cubit.reload();
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
