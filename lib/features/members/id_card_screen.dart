import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/auth/permissions.dart';
import '../../core/state/async_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/files.dart';
import '../../core/util/format.dart';
import '../../core/widgets/auth_image.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../core/widgets/states.dart';
import '../../data/models/members.dart';
import '../../data/repositories/members_repository.dart';

Color _hex(String s, [Color fallback = AppColors.navy]) {
  final h = s.replaceFirst('#', '');
  final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
  return v == null ? fallback : Color(v);
}

class _CardTheme {
  const _CardTheme(this.name, this.bg, this.fg, this.accent);
  final String name;
  final Color bg;
  final Color fg;
  final Color accent;
}

const _themes = [
  _CardTheme('Navy', Color(0xFF061750), Colors.white, Color(0xFF7C8CF0)),
  _CardTheme('Emerald', Color(0xFF0B6B4F), Colors.white, Color(0xFF8FE3BE)),
  _CardTheme('Light', Color(0xFFF4F6FC), Color(0xFF061750), Color(0xFF4A5BAE)),
];

/// Member ID card: preview, label assignment and share as an image (PNG).
/// The QR uses the same payload as "Show member QR", so a printed card works with "Scan member QR".
class MemberIdCardScreen extends StatefulWidget {
  const MemberIdCardScreen({super.key, required this.memberId});
  final String memberId;
  @override
  State<MemberIdCardScreen> createState() => _MemberIdCardScreenState();
}

class _MemberIdCardScreenState extends State<MemberIdCardScreen> {
  final _repo = getIt<MembersRepository>();
  final _boundary = GlobalKey();
  late final AsyncCubit<(MemberDetail, List<LabelRef>)> _cubit = AsyncCubit(
    () async => (await _repo.detail(widget.memberId), await _repo.labels()),
  );
  int _theme = 0;
  Set<String>? _selected; // label ids shown on the card; null until loaded
  bool _busy = false;

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  Future<void> _assign(
    MemberSummary m,
    List<LabelRef> all,
    Set<String> ids,
  ) async {
    final r = await runWithProgress(
      context,
      () => _repo.setLabels(widget.memberId, ids.toList()),
      success: 'Labels assigned successfully',
    );
    if (r != null && mounted) {
      setState(() => _selected = r.labels.map((l) => l.id).toSet());
      await _cubit.refresh(); // reload so the saved labels become the baseline
      if (mounted) setState(() => _selected = null);
    }
  }

  Future<void> _newLabel(
    MemberSummary m,
    List<LabelRef> all,
    Set<String> ids,
  ) async {
    final name = await promptText(
      context,
      title: 'New label',
      label: 'Label name',
      hint: 'e.g. VIP, Student, Corporate',
      maxLength: 30,
      required: true,
    );
    if (name == null || !mounted) return;
    final l = await runWithProgress(context, () => _repo.createLabel(name));
    if (l != null && mounted) {
      await _cubit.refresh();
      if (mounted) await _assign(m, [...all, l], {...ids, l.id});
    }
  }

  Future<void> _share(MemberSummary m) async {
    setState(() => _busy = true);
    try {
      final b =
          _boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 4);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted) return;
      await shareBytes(
        context,
        data!.buffer.asUint8List(),
        'id_card_${m.admissionNo}.png',
        'image/png',
        text: '${m.name} - member ID card',
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = getIt<SessionCubit>().state;
    final gym = s.profile!;
    final canAssign = s.can(Perm.membersWrite);
    return Scaffold(
      appBar: AppBar(title: const Text('Member ID Card')),
      body: AsyncBody<(MemberDetail, List<LabelRef>)>(
        cubit: _cubit,
        builder: (context, d) {
          final m = d.$1.summary;
          final all = d.$2;
          final ids = _selected ?? m.labels.map((l) => l.id).toSet();
          final shown = [
            for (final l in all)
              if (ids.contains(l.id)) l,
          ];
          final t = _themes[_theme];
          final dirty =
              !(ids.length == m.labels.length &&
                  m.labels.every((l) => ids.contains(l.id)));
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    RepaintBoundary(
                      key: _boundary,
                      child: AspectRatio(
                        aspectRatio: 1.586,
                        child: Container(
                          decoration: BoxDecoration(
                            color: t.bg,
                            borderRadius: BorderRadius.circular(16),
                            border: t.bg.computeLuminance() > .8
                                ? Border.all(color: AppColors.border)
                                : null,
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      gym.name.toUpperCase(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: t.accent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    'MEMBER',
                                    style: TextStyle(
                                      color: t.fg.withValues(alpha: .6),
                                      fontSize: 10,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Expanded(
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: SizedBox(
                                        width: 78,
                                        height: 96,
                                        child: m.photoUrl == null
                                            ? Container(
                                                color: t.accent.withValues(
                                                  alpha: .25,
                                                ),
                                                alignment: Alignment.center,
                                                child: Text(
                                                  Fmt.initials(m.name),
                                                  style: TextStyle(
                                                    color: t.fg,
                                                    fontSize: 26,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              )
                                            : AuthImage(
                                                url: m.photoUrl!,
                                                width: 78,
                                                height: 96,
                                                fit: BoxFit.cover,
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            m.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: t.fg,
                                              fontSize: 17,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'ID #${m.admissionNo}',
                                            style: TextStyle(
                                              color: t.accent,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            m.phone,
                                            style: TextStyle(
                                              color: t.fg.withValues(alpha: .8),
                                              fontSize: 12,
                                            ),
                                          ),
                                          if (m.membership != null)
                                            Text(
                                              '${m.membership!.planName} · valid till ${Fmt.dateShort(m.membership!.endDate)}',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: t.fg.withValues(
                                                  alpha: .8,
                                                ),
                                                fontSize: 11,
                                              ),
                                            ),
                                          if (shown.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 6,
                                              ),
                                              child: Wrap(
                                                spacing: 4,
                                                runSpacing: 4,
                                                children: [
                                                  for (final l in shown)
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 2,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: _hex(l.color),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              20,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        l.name,
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      color: Colors.white,
                                      padding: const EdgeInsets.all(4),
                                      child: QrImageView(
                                        data:
                                            'dgymbook://member/${gym.code}/${m.id}',
                                        size: 72,
                                        padding: EdgeInsets.zero,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final (i, th) in _themes.indexed)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: GestureDetector(
                              onTap: () => setState(() => _theme = i),
                              child: Tooltip(
                                message: th.name,
                                child: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: i == _theme
                                      ? AppColors.info
                                      : AppColors.border,
                                  child: CircleAvatar(
                                    radius: 13,
                                    backgroundColor: th.bg,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Labels on this card',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (canAssign)
                          TextButton.icon(
                            onPressed: () => _newLabel(m, all, ids),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('New label'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (all.isEmpty)
                      const Text(
                        'No labels yet. Create one to tag this member (for example VIP or Student).',
                        style: TextStyle(color: AppColors.textSecondary),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final l in all)
                            PillChip(
                              label: l.name,
                              selected: ids.contains(l.id),
                              onTap: !canAssign
                                  ? () {}
                                  : () => setState(() {
                                      final next = {...ids};
                                      next.contains(l.id)
                                          ? next.remove(l.id)
                                          : next.add(l.id);
                                      _selected = next;
                                    }),
                            ),
                        ],
                      ),
                    if (canAssign && dirty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: OutlinedButton.icon(
                          onPressed: () => _assign(m, all, ids),
                          icon: const Icon(Icons.label_outline),
                          label: const Text('Assign labels to member'),
                        ),
                      ),
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: InfoBanner(
                        'The QR on the card works with "Scan member QR" for check-in.',
                        icon: Icons.qr_code_2,
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: LoadingButton(
                    label: 'Share ID Card (image)',
                    icon: Icons.share,
                    loading: _busy,
                    onPressed: () => _share(m),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
