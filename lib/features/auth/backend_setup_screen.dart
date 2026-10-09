import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/routes.dart';
import '../../app/session_cubit.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';

/// Backend URL picker ("Developer tools" > "Backend URL" in the original app).
class BackendSetupScreen extends StatefulWidget {
  const BackendSetupScreen({super.key});

  @override
  State<BackendSetupScreen> createState() => _BackendSetupScreenState();
}

class _BackendSetupScreenState extends State<BackendSetupScreen> {
  final _url = TextEditingController();
  final _cfg = getIt<AppConfig>();
  bool _busy = false;
  String? _result;
  bool? _ok;

  @override
  void initState() {
    super.initState();
    _url.text = _cfg.baseUrl;
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final err = AppConfig.validateBaseUrl(_url.text);
    if (err != null) {
      setState(() {
        _ok = false;
        _result = err;
      });
      return;
    }
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final u = _url.text.trim().replaceAll(RegExp(r'/+$'), '');
      final r = await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 6),
          validateStatus: (_) => true,
        ),
      ).get<dynamic>('$u/healthcheck');
      final ok = r.statusCode == 200;
      setState(() {
        _ok = ok;
        _result = ok
            ? 'Connected: the server responded OK.'
            : 'The server answered with status ${r.statusCode}. Is this a DGymBook API?';
      });
    } catch (_) {
      setState(() {
        _ok = false;
        _result = 'Could not reach the server. Check the address, your network, and that the backend is running.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    try {
      await _cfg.setBaseUrl(_url.text);
      final session = getIt<SessionCubit>();
      if (session.state.signedIn) await session.signOut();
      if (!mounted) return;
      showToast(context, 'Backend URL saved');
      // Session boot depends on the backend: restart it.
      await session.boot();
      if (mounted) context.go(R.splash);
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          e is ArgumentError ? '${e.message}' : '$e',
          error: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backend URL')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            InfoBanner(
              _cfg.isConfigured ? 'Current server: ${_cfg.baseUrl}' : 'No backend is configured. Enter the address of the DGymBook API (or the bundled dev backend) to continue.',
              icon: Icons.dns_outlined,
            ),
            const Gap(20),
            AppTextField(
              controller: _url,
              label: 'Enter backend URL',
              hint: 'https://api.example.com',
              keyboardType: TextInputType.url,
            ),
            const Gap(12),
            if (_result != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _result!,
                  style: TextStyle(
                    color: _ok == true ? AppColors.success : AppColors.danger,
                    fontSize: 13,
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: LoadingButton(
                    label: 'Check and connect',
                    onPressed: _test,
                    loading: _busy,
                    outlined: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LoadingButton(label: 'Save', onPressed: _save),
                ),
              ],
            ),
            const SectionTitle(
              'Presets',
              padding: EdgeInsets.fromLTRB(0, 24, 0, 8),
            ),
            for (final e in AppConfig.presets.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  e.key,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(e.value),
                onTap: () => setState(() => _url.text = e.value),
              ),
            const Gap(8),
            const Text(
              'The "Original" hosts were found in the app binary. This reconstruction implements its own API contract (docs/API_CONTRACT.md); it is only guaranteed to match the bundled development backend.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            if (_cfg.hasOverride)
              TextButton(
                onPressed: () async {
                  await _cfg.resetBaseUrl();
                  setState(() => _url.text = _cfg.baseUrl);
                },
                child: const Text('Reset to default'),
              ),
          ],
        ),
      ),
    );
  }
}
