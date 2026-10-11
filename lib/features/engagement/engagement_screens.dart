import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/auth/permissions.dart';
import '../../core/state/async_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/files.dart';
import '../../core/util/format.dart';
import '../../core/util/json.dart';
import '../../core/util/launch.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../../data/repositories/extras_repository.dart';

// ---------------------------------------------------------------- Feedback

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});
  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _repo = getIt<ExtrasRepository>();
  bool _favOnly = false;
  late final AsyncCubit<(Json, List<Json>)> _cubit = AsyncCubit(
    () async => (
      await _repo.feedbackStats(),
      await _repo.feedbacks(favoriteOnly: _favOnly),
    ),
  );

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  Widget _stars(int n) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 1; i <= 5; i++)
        Icon(
          i <= n ? Icons.star_rounded : Icons.star_border_rounded,
          size: 18,
          color: const Color(0xFFF5A623),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final code = getIt<SessionCubit>().state.profile?.code;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feedback'),
        actions: [
          IconButton(
            tooltip: 'Favourites',
            icon: Icon(_favOnly ? Icons.favorite : Icons.favorite_border),
            onPressed: () {
              setState(() => _favOnly = !_favOnly);
              _cubit.load();
            },
          ),
        ],
      ),
      body: AsyncBody<(Json, List<Json>)>(
        cubit: _cubit,
        builder: (context, d) {
          final stats = d.$1;
          final list = d.$2;
          final avg = stats['average'];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            avg == null ? '–' : '$avg',
                            style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          _stars(avg is num ? avg.round() : 0),
                          const SizedBox(height: 4),
                          Text(
                            '${stats.i('total')} reviews · ${stats.i('unseen')} new',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        for (final r
                            in (stats['distribution'] as List? ?? []).reversed)
                          Text(
                            '${(r as Map)['rating']}★  ${r['count']}',
                            style: const TextStyle(fontSize: 12),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (code != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: InfoBanner(
                    'Members can leave feedback from the gym portal using your gym code $code.',
                    icon: Icons.qr_code_2,
                  ),
                ),
              const SizedBox(height: 8),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: EmptyState(
                    icon: Icons.rate_review_outlined,
                    title: 'No feedback yet',
                    message:
                        'Feedback submitted by your members will appear here.',
                    compact: true,
                  ),
                ),
              for (final f in list)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: AppCard(
                    onTap: () async {
                      if (f['seen'] != true) {
                        await _repo
                            .markSeen(f.s('id'))
                            .catchError((Object _) {});
                        _cubit.refresh();
                      }
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _stars(f.i('rating')),
                            const SizedBox(width: 8),
                            if (f['seen'] != true)
                              const Tag('New', tone: Tone.info),
                            const Spacer(),
                            Text(
                              Fmt.date(f.str('createdAt')),
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                f['isFavorite'] == true
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: f['isFavorite'] == true
                                    ? AppColors.danger
                                    : null,
                                size: 20,
                              ),
                              onPressed: () async {
                                await runOk(
                                  context,
                                  () => _repo.setFavorite(
                                    f.s('id'),
                                    f['isFavorite'] != true,
                                  ),
                                );
                                _cubit.refresh();
                              },
                            ),
                          ],
                        ),
                        if ((f.str('comment') ?? '').isNotEmpty)
                          Text(f.s('comment')),
                        if (f.str('memberName') != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '— ${f.s('memberName')}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                      ],
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

// ------------------------------------------------------------- Video links

class VideoLinksScreen extends StatefulWidget {
  const VideoLinksScreen({super.key});
  @override
  State<VideoLinksScreen> createState() => _VideoLinksScreenState();
}

class _VideoLinksScreenState extends State<VideoLinksScreen> {
  final _repo = getIt<ExtrasRepository>();
  late final AsyncCubit<List<Json>> _cubit = AsyncCubit(_repo.videos);

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  Future<void> _edit([Json? v]) async {
    final title = TextEditingController(text: v?.str('title'));
    final url = TextEditingController(text: v?.str('url'));
    final key = GlobalKey<FormState>();
    final ok = await showAppSheet<bool>(
      context,
      title: v == null ? 'Add Video Link' : 'Edit Video Link',
      builder: (ctx) => Form(
        key: key,
        child: Column(
          children: [
            AppTextField(
              controller: title,
              label: 'Title',
              maxLength: 100,
              validator: (x) => V.required(x, 'Please enter a title'),
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: url,
              label: 'Video URL',
              hint: 'https://…',
              keyboardType: TextInputType.url,
              validator: (x) =>
                  RegExp(r'^https?://\S+\.\S+$').hasMatch((x ?? '').trim())
                  ? null
                  : 'Please enter a valid URL',
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (key.currentState!.validate()) Navigator.pop(ctx, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      final body = {'title': title.text.trim(), 'url': url.text.trim()};
      if (await runOk(
        context,
        () => v == null
            ? _repo.createVideo(body)
            : _repo.updateVideo(v.s('id'), body),
        success: v == null
            ? 'Video link added successfully'
            : 'Video link updated successfully',
      )) {
        _cubit.refresh();
      }
    }
    title.dispose();
    url.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = getIt<SessionCubit>().state.can(Perm.videosWrite);
    return Scaffold(
      appBar: AppBar(title: const Text('Video Links')),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('Add Video'),
            )
          : null,
      body: AsyncBody<List<Json>>(
        cubit: _cubit,
        isEmpty: (d) => d.isEmpty,
        empty: const EmptyState(
          icon: Icons.ondemand_video,
          title: 'No video links yet',
          message: 'Share workout or gym tour videos with your members.',
        ),
        builder: (context, list) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final v = list[i];
            return AppCard(
              onTap: () => Launch.url(context, v.s('url')),
              child: Row(
                children: [
                  Icon(
                    Icons.play_circle_fill,
                    color: AppColors.navy,
                    size: 36,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          v.s('title'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          v.s('url'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (canWrite)
                    PopupMenuButton<String>(
                      onSelected: (a) async {
                        if (a == 'edit') return _edit(v);
                        if (await confirmDialog(
                              context,
                              title: 'Delete Video Link',
                              message: 'Do you want to delete this video link? This action cannot be undone.',
                              confirmLabel: 'Delete',
                              destructive: true,
                            ) &&
                            context.mounted &&
                            await runOk(
                              context,
                              () => _repo.deleteVideo(v.s('id')),
                              success: 'Video link deleted successfully',
                            )) {
                          _cubit.refresh();
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// -------------------------------------------------------- Biometric devices

class BiometricsScreen extends StatefulWidget {
  const BiometricsScreen({super.key});
  @override
  State<BiometricsScreen> createState() => _BiometricsScreenState();
}

class _BiometricsScreenState extends State<BiometricsScreen> {
  final _repo = getIt<ExtrasRepository>();
  late final AsyncCubit<List<Json>> _cubit = AsyncCubit(_repo.devices);

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  Future<void> _showKey(String key) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Device key'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Configure this key on the device (sent as the x-device-key header). It is shown only once.',
          ),
          const SizedBox(height: 12),
          SelectableText(
            key,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: key));
            showToast(ctx, 'Copied');
          },
          child: const Text('Copy'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Done'),
        ),
      ],
    ),
  );

  Future<void> _add() async {
    final name = TextEditingController();
    final serial = TextEditingController();
    final ip = TextEditingController();
    final loc = TextEditingController();
    var type = 'both';
    final key = GlobalKey<FormState>();
    final ok = await showAppSheet<bool>(
      context,
      title: 'Add Device',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Form(
          key: key,
          child: Column(
            children: [
              AppTextField(
                controller: name,
                label: 'Device Name',
                maxLength: 60,
                validator: (v) => V.required(v, 'Please enter a device name'),
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: serial,
                label: 'Serial Number',
                maxLength: 60,
                validator: (v) => (v ?? '').trim().length < 3
                    ? 'Please enter a valid serial number'
                    : null,
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: ip,
                label: 'IP Address (optional)',
                keyboardType: TextInputType.number,
                validator: (v) =>
                    (v ?? '').trim().isEmpty ||
                        RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(v!.trim())
                    ? null
                    : 'Enter IP address',
              ),
              const SizedBox(height: 12),
              DropdownField<String>(
                label: 'Type',
                value: type,
                items: const ['face', 'fingerprint', 'both'],
                onChanged: (v) => set(() => type = v ?? type),
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: loc,
                label: 'Location (optional)',
                maxLength: 80,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (key.currentState!.validate()) Navigator.pop(ctx, true);
                },
                child: const Text('Add Device'),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true && mounted) {
      final r = await runWithProgress<Json>(
        context,
        () => _repo.createDevice({
          'name': name.text.trim(),
          'serialNumber': serial.text.trim(),
          if (ip.text.trim().isNotEmpty) 'ip': ip.text.trim(),
          'type': type,
          if (loc.text.trim().isNotEmpty) 'location': loc.text.trim(),
        }),
      );
      if (r != null && mounted) {
        _cubit.refresh();
        await _showKey(r.s('deviceKey'));
      }
    }
    for (final c in [name, serial, ip, loc]) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = getIt<SessionCubit>().state.can(Perm.devicesWrite);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Biometric Devices'),
        actions: [
          if (canWrite)
            IconButton(
              tooltip: 'Sync now',
              icon: const Icon(Icons.sync),
              onPressed: () async {
                await runOk(
                  context,
                  _repo.forceSync,
                  success: 'Sync requested',
                );
                _cubit.refresh();
              },
            ),
        ],
      ),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('Add Device'),
            )
          : null,
      body: AsyncBody<List<Json>>(
        cubit: _cubit,
        isEmpty: (d) => d.isEmpty,
        empty: const EmptyState(
          icon: Icons.fingerprint,
          title: 'No devices connected',
          message: 'Register a face or fingerprint device to log member attendance automatically.',
        ),
        builder: (context, list) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final d = list[i];
            final status = d.s('status');
            return AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.fingerprint, color: AppColors.navy),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          d.s('name'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Tag(
                        status == 'connected'
                            ? 'Connected'
                            : status == 'offline'
                            ? 'Offline'
                            : 'Not connected',
                        tone: status == 'connected'
                            ? Tone.success
                            : status == 'offline'
                            ? Tone.danger
                            : Tone.neutral,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'S/N ${d.s('serialNumber')}${d.str('ip') == null ? '' : ' · ${d.s('ip')}'}${d.str('location') == null ? '' : ' · ${d.s('location')}'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (d.str('lastPingAt') != null)
                    Text(
                      'Last seen ${Fmt.dateTime(d.str('lastPingAt'))}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  if (canWrite)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () async {
                            if (!await confirmDialog(
                                  context,
                                  title: 'Rotate key',
                                  message: 'The current device key will stop working. Continue?',
                                  confirmLabel: 'Rotate',
                                ) ||
                                !context.mounted) {
                              return;
                            }
                            final k = await runWithProgress<String>(
                              context,
                              () => _repo.rotateKey(d.s('id')),
                            );
                            if (k != null && mounted) await _showKey(k);
                          },
                          child: const Text('Rotate key'),
                        ),
                        TextButton(
                          onPressed: () async {
                            if (!await confirmDialog(
                                  context,
                                  title: 'Remove device',
                                  message: 'Do you want to remove this device?',
                                  confirmLabel: 'Remove',
                                  destructive: true,
                                ) ||
                                !context.mounted) {
                              return;
                            }
                            if (await runOk(
                              context,
                              () => _repo.deleteDevice(d.s('id')),
                              success: 'Device removed successfully',
                            )) {
                              _cubit.refresh();
                            }
                          },
                          child: Text(
                            'Remove',
                            style: TextStyle(color: AppColors.danger),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ Poster

class PosterScreen extends StatefulWidget {
  const PosterScreen({super.key});
  @override
  State<PosterScreen> createState() => _PosterScreenState();
}

class _PosterScreenState extends State<PosterScreen> {
  final _key = GlobalKey();
  int _theme = 0;
  bool _busy = false;
  static const _themes = [
    (Color(0xFF061750), Colors.white),
    (Color(0xFF0E7C5A), Colors.white),
    (Color(0xFFF5F7FC), Color(0xFF061750)),
  ];

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final b =
          _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 3);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted) return;
      await shareBytes(
        context,
        data!.buffer.asUint8List(),
        'gym_poster.png',
        'image/png',
        text: 'Join us!',
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = getIt<SessionCubit>().state.profile!;
    final (bg, fg) = _themes[_theme];
    return Scaffold(
      appBar: AppBar(title: const Text('Gym Poster')),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: RepaintBoundary(
                    key: _key,
                    child: Container(
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'JOIN',
                            style: TextStyle(
                              color: fg.withValues(alpha: .7),
                              letterSpacing: 6,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            g.name,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: fg,
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Container(
                            color: Colors.white,
                            padding: const EdgeInsets.all(10),
                            child: QrImageView(
                              data: 'gym:${g.code}',
                              size: 150,
                            ),
                          ),
                          Column(
                            children: [
                              Text(
                                'Gym code ${g.code}',
                                style: TextStyle(
                                  color: fg,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if ((g.phone ?? '').isNotEmpty)
                                Text(
                                  g.phone!,
                                  style: TextStyle(
                                    color: fg.withValues(alpha: .8),
                                  ),
                                ),
                              if ((g.address).isNotEmpty)
                                Text(
                                  g.address,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: fg.withValues(alpha: .8),
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _themes.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _theme = i),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: i == _theme
                          ? AppColors.navy
                          : Colors.transparent,
                      child: CircleAvatar(
                        radius: 13,
                        backgroundColor: _themes[i].$1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LoadingButton(
                label: 'Share Poster',
                icon: Icons.share,
                loading: _busy,
                onPressed: _share,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
