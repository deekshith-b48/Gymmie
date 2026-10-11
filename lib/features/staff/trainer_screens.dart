import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/state/async_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/format.dart';
import '../../core/util/json.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../core/widgets/states.dart';
import '../../data/models/finance.dart';
import '../../data/models/members.dart';
import '../../data/repositories/finance_repository.dart';
import '../../data/repositories/trainer_repository.dart';
import '../members/member_picker.dart';

const _dayNames = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

/// "Trainer Session/Class Bookings": the day's sessions for a trainer (own schedule, or any trainer for managers).
class TrainerScheduleScreen extends StatefulWidget {
  const TrainerScheduleScreen({super.key});
  @override
  State<TrainerScheduleScreen> createState() => _TrainerScheduleScreenState();
}

class _TrainerScheduleScreenState extends State<TrainerScheduleScreen> {
  final _repo = getIt<TrainerRepository>();
  final _isTrainer = getIt<SessionCubit>().state.role == 'trainer';
  DateTime _day = DateTime.now();
  String? _trainerId;
  List<StaffMember> _trainers = [];
  late AsyncCubit<List<Booking>> _cubit = _make();

  AsyncCubit<List<Booking>> _make() => AsyncCubit(
    () => _repo.bookings(
      trainerId: _isTrainer ? null : _trainerId,
      date: Fmt.ymd(_day),
    ),
    autoLoad: _isTrainer || _trainerId != null,
  );

  @override
  void initState() {
    super.initState();
    if (!_isTrainer) {
      getIt<StaffRepository>()
          .trainers()
          .then((t) {
            if (!mounted) return;
            setState(() {
              _trainers = t;
              _trainerId = t.firstOrNull?.userId;
              _reset();
            });
          })
          .catchError((Object _) {});
    }
  }

  void _reset() {
    _cubit.close();
    _cubit = _make();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trainer Session/Class Bookings'),
        actions: [
          if (_isTrainer)
            IconButton(
              icon: const Icon(Icons.schedule),
              tooltip: 'Weekly Working Hours',
              onPressed: () => context.push('/trainer/hours'),
            ),
        ],
      ),
      floatingActionButton: (_isTrainer || _trainerId != null)
          ? FloatingActionButton.extended(
              onPressed: () async {
                await context.push(
                  '/trainer/book${_trainerId == null ? '' : '?trainerId=$_trainerId'}',
                );
                setState(_reset);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Booking'),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            if (!_isTrainer)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _trainers.isEmpty
                    ? const InfoBanner(
                        'Add a trainer under Manage Staff to schedule sessions.',
                        warning: true,
                      )
                    : DropdownField<String>(
                        label: 'Select Trainer',
                        value: _trainerId,
                        items: _trainers.map((t) => t.userId).toList(),
                        labelOf: (id) =>
                            _trainers.firstWhere((t) => t.userId == id).name,
                        onChanged: (v) => setState(() {
                          _trainerId = v;
                          _reset();
                        }),
                      ),
              ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(() {
                    _day = _day.subtract(const Duration(days: 1));
                    _reset();
                  }),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _day,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 60),
                        ),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (d != null) {
                        setState(() {
                          _day = d;
                          _reset();
                        });
                      }
                    },
                    child: Center(
                      child: Text(
                        Fmt.dateLong(Fmt.ymd(_day)),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(() {
                    _day = _day.add(const Duration(days: 1));
                    _reset();
                  }),
                ),
              ],
            ),
            Expanded(
              child: (!_isTrainer && _trainerId == null)
                  ? const SizedBox.shrink()
                  : AsyncBody<List<Booking>>(
                      key: ValueKey(_cubit),
                      cubit: _cubit,
                      isEmpty: (d) => d.isEmpty,
                      empty: EmptyState(
                        icon: Icons.event_available_outlined,
                        title: 'No sessions booked',
                        message: _isTrainer
                            ? 'Set your working hours to allow bookings, then add a booking.'
                            : 'No bookings for this trainer on this day.',
                        actionLabel: _isTrainer ? 'Set Hours' : null,
                        onAction: () => context.push('/trainer/hours'),
                      ),
                      builder: (context, list) => ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final b = list[i];
                          return AppCard(
                            child: Row(
                              children: [
                                Container(
                                  width: 78,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.chip,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        Fmt.hhmm(b.start),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        'to',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                      Text(
                                        Fmt.hhmm(b.end),
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        b.memberName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (b.memberPhone != null)
                                        Text(
                                          b.memberPhone!,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.close,
                                    color: AppColors.danger,
                                  ),
                                  tooltip: 'Cancel Booking',
                                  onPressed: () async {
                                    if (!await confirmDialog(
                                          context,
                                          title: 'Cancel this booking?',
                                          message: "Cancelling a booking later won't affect sessions remaining.",
                                          confirmLabel: 'Cancel Booking',
                                          cancelLabel: 'Keep Booking',
                                          destructive: true,
                                        ) ||
                                        !context.mounted) {
                                      return;
                                    }
                                    if (await runOk(
                                      context,
                                      () => _repo.cancel(b.id),
                                      success: 'Booking cancelled successfully',
                                    )) {
                                      _cubit.refresh();
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class WorkingHoursScreen extends StatefulWidget {
  const WorkingHoursScreen({super.key});
  @override
  State<WorkingHoursScreen> createState() => _WorkingHoursScreenState();
}

class _WorkingHoursScreenState extends State<WorkingHoursScreen> {
  final _repo = getIt<TrainerRepository>();
  List<WorkDay>? _days;
  Object? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _repo
        .workHours()
        .then((d) => mounted ? setState(() => _days = d) : null)
        .catchError((Object e) {
          if (mounted) setState(() => _error = e);
        });
  }

  Future<void> _pick(WorkDay d, bool start) async {
    final cur = (start ? d.start : d.end).split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(cur[0]),
        minute: int.parse(cur[1]),
      ),
    );
    if (t == null) return;
    final v =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    setState(() => start ? d.start = v : d.end = v);
  }

  Future<void> _save() async {
    for (final d in _days!.where((d) => d.enabled)) {
      if (d.start.compareTo(d.end) >= 0) {
        return showToast(
          context,
          'End of working hours must be after the start (${_dayNames[d.day]})',
          error: true,
        );
      }
    }
    setState(() => _saving = true);
    try {
      await _repo.saveWorkHours(_days!);
      if (mounted) {
        showToast(context, 'Working hours updated successfully');
        context.pop();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Weekly Working Hours')),
        body: ErrorState(error: toApiException(_error!)),
      );
    }
    final days = _days;
    if (days == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Weekly Working Hours')),
        body: const LoadingBox(),
      );
    }
    final order = [1, 2, 3, 4, 5, 6, 0];
    return Scaffold(
      appBar: AppBar(title: const Text('Weekly Working Hours')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Manage your availability for each day',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const Gap(12),
                for (final i in order)
                  Builder(
                    builder: (_) {
                      final d = days.firstWhere((x) => x.day == i);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _dayNames[i],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Switch(
                                    value: d.enabled,
                                    onChanged: (v) =>
                                        setState(() => d.enabled = v),
                                  ),
                                ],
                              ),
                              if (d.enabled)
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          minimumSize: const Size(0, 44),
                                        ),
                                        onPressed: () => _pick(d, true),
                                        child: Text(Fmt.hhmm(d.start)),
                                      ),
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      child: Text('to'),
                                    ),
                                    Expanded(
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          minimumSize: const Size(0, 44),
                                        ),
                                        onPressed: () => _pick(d, false),
                                        child: Text(Fmt.hhmm(d.end)),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LoadingButton(
                label: 'Save Working Hours',
                onPressed: _save,
                loading: _saving,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Slot {
  _Slot(this.date, this.start, this.end);
  String date;
  String start;
  String end;
  SlotCheck? check;
}

/// Book one or more sessions for a member ("Add Booking" → "Review Bookings").
class AddBookingScreen extends StatefulWidget {
  const AddBookingScreen({super.key, this.trainerId});
  final String? trainerId;
  @override
  State<AddBookingScreen> createState() => _AddBookingScreenState();
}

class _AddBookingScreenState extends State<AddBookingScreen> {
  final _repo = getIt<TrainerRepository>();
  MemberSummary? _member;
  final List<_Slot> _slots = [];
  BookingPreview? _preview;
  bool _busy = false;

  Future<void> _addSlot() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      helpText: 'Start time',
      initialTime: const TimeOfDay(hour: 7, minute: 0),
    );
    if (t == null) return;
    final end = TimeOfDay(hour: (t.hour + 1) % 24, minute: t.minute);
    String f(TimeOfDay x) =>
        '${x.hour.toString().padLeft(2, '0')}:${x.minute.toString().padLeft(2, '0')}';
    setState(() {
      _slots.add(_Slot(Fmt.ymd(d), f(t), f(end)));
      _preview = null;
    });
  }

  List<Json> get _body => [
    for (final s in _slots) {'date': s.date, 'start': s.start, 'end': s.end},
  ];

  Future<void> _review() async {
    if (_member == null || _slots.isEmpty) return;
    setState(() => _busy = true);
    try {
      final p = await _repo.preview(
        memberId: _member!.id,
        trainerId: widget.trainerId,
        slots: _body,
      );
      if (mounted) setState(() => _preview = p);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      await _repo.create(
        memberId: _member!.id,
        trainerId: widget.trainerId,
        slots: _body,
      );
      if (mounted) {
        showToast(context, 'Booking confirmed');
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        showError(context, e);
        _review();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTrainer = getIt<SessionCubit>().state.role == 'trainer';
    return Scaffold(
      appBar: AppBar(title: const Text('Add Booking')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Member',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const Gap(8),
                AppCard(
                  onTap: () async {
                    final m = await pickMember(
                      context,
                      title: 'Select Member',
                      status: 'active',
                      where: (m) =>
                          m.membership?.sessionsTotal != null &&
                          (isTrainer ||
                              widget.trainerId == null ||
                              m.trainerId == widget.trainerId),
                    );
                    if (m != null) {
                      setState(() {
                        _member = m;
                        _preview = null;
                      });
                    }
                  },
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _member == null
                            ? Text(
                                'Choose member',
                                style: TextStyle(color: AppColors.textMuted),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _member!.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${_member!.membership?.planName} · ${_member!.membership?.sessionsLeft ?? 0} sessions left',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      const Icon(Icons.keyboard_arrow_down),
                    ],
                  ),
                ),
                const Gap(6),
                Text(
                  'Only members with a session-based plan can be booked. They must be assigned to this trainer.',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
                const Gap(20),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Slots',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _member == null ? null : _addSlot,
                      icon: const Icon(Icons.add),
                      label: const Text('Add slot'),
                    ),
                  ],
                ),
                if (_slots.isEmpty)
                  AppCard(
                    child: Text(
                      'Add one or more slots. Each uses one session from the member\'s plan.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                for (final (i, s) in _slots.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      color: _preview == null
                          ? null
                          : (_preview!.slots[i].ok
                                ? AppColors.successTint
                                : AppColors.dangerTint),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  Fmt.dateLong(s.date),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  '${Fmt.hhmm(s.start)} – ${Fmt.hhmm(s.end)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                if (_preview != null && !_preview!.slots[i].ok)
                                  Text(
                                    _preview!.slots[i].reason ?? '',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.danger,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.edit_calendar_outlined,
                              size: 20,
                            ),
                            onPressed: () async {
                              final t = await showTimePicker(
                                context: context,
                                helpText: 'End time',
                                initialTime: TimeOfDay(
                                  hour: int.parse(s.end.substring(0, 2)),
                                  minute: int.parse(s.end.substring(3)),
                                ),
                              );
                              if (t != null) {
                                setState(() {
                                  s.end =
                                      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                                  _preview = null;
                                });
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => setState(() {
                              _slots.removeAt(i);
                              _preview = null;
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_preview != null) ...[
                  const Gap(8),
                  InfoBanner(
                    _preview!.valid
                        ? 'All slots are available. Session budget: ${_preview!.budget}.'
                        : (_preview!.message ??
                              'Fix the highlighted slots to continue.'),
                    icon: _preview!.valid
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    warning: !_preview!.valid,
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LoadingButton(
                label: _preview?.valid == true
                    ? 'Confirm ${_slots.length} booking${_slots.length == 1 ? '' : 's'}'
                    : 'Review Bookings',
                loading: _busy,
                onPressed: (_member == null || _slots.isEmpty)
                    ? null
                    : (_preview?.valid == true ? _confirm : _review),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
