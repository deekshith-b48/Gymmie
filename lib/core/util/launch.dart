import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/feedback.dart';

/// Opens external apps (dialer, WhatsApp, SMS, browser). Failures are reported, never thrown.
class Launch {
  Launch._();

  static String _digits(String phone) =>
      phone.replaceAll(RegExp(r'[^\d+]'), '');

  static Future<void> call(BuildContext context, String phone) =>
      _go(context, Uri(scheme: 'tel', path: _digits(phone)), 'phone dialer');

  static Future<void> sms(BuildContext context, String phone, {String? body}) =>
      _go(
        context,
        Uri(
          scheme: 'sms',
          path: _digits(phone),
          queryParameters: body == null ? null : {'body': body},
        ),
        'messaging app',
      );

  /// WhatsApp chat via the public wa.me link (the original app uses `https://wa.me/`).
  static Future<void> whatsApp(
    BuildContext context,
    String phone, {
    String? text,
  }) {
    final d = _digits(phone).replaceAll('+', '');
    return _go(
      context,
      Uri.https('wa.me', '/$d', text == null ? null : {'text': text}),
      'WhatsApp',
    );
  }

  static Future<void> url(
    BuildContext context,
    String url, {
    bool external = true,
  }) async {
    if (url.isEmpty) {
      showToast(context, 'This page is not available yet', error: true);
      return;
    }
    final u = Uri.tryParse(url);
    if (u == null || !(u.scheme == 'http' || u.scheme == 'https')) {
      showToast(context, 'Please enter a valid URL', error: true);
      return;
    }
    await _go(
      context,
      u,
      'browser',
      mode: external
          ? LaunchMode.externalApplication
          : LaunchMode.inAppBrowserView,
    );
  }

  static Future<void> _go(
    BuildContext context,
    Uri uri,
    String what, {
    LaunchMode mode = LaunchMode.externalApplication,
  }) async {
    try {
      final ok = await launchUrl(uri, mode: mode);
      if (!ok && context.mounted) {
        showToast(context, 'Could not open the $what', error: true);
      }
    } catch (_) {
      if (context.mounted) {
        showToast(context, 'Could not open the $what', error: true);
      }
    }
  }
}
