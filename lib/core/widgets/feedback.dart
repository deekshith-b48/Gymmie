import 'package:flutter/material.dart';

import '../network/api_exception.dart';
import '../state/async_cubit.dart';
import '../theme/app_theme.dart';

void showToast(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.danger : null,
        duration: Duration(seconds: error ? 5 : 3),
      ),
    );
}

void showError(BuildContext context, Object e) =>
    showToast(context, toApiException(e).message, error: true);

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(
            cancelLabel,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            minimumSize: const Size(96, 44),
            backgroundColor: destructive ? AppColors.danger : null,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Runs [action], showing a progress overlay; reports failures as a toast. Returns the result or null on failure.
Future<T?> runWithProgress<T>(
  BuildContext context,
  Future<T> Function() action, {
  String? success,
}) async {
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  );
  try {
    final r = await action();
    nav.pop();
    if (success != null && context.mounted) showToast(context, success);
    return r;
  } catch (e) {
    nav.pop();
    if (context.mounted) showError(context, e);
    return null;
  }
}

/// Dev-OTP / info banner.
class InfoBanner extends StatelessWidget {
  const InfoBanner(
    this.text, {
    super.key,
    this.icon = Icons.info_outline,
    this.warning = false,
  });
  final String text;
  final IconData icon;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final bg = warning ? AppColors.warningTint : AppColors.info.withValues(alpha: 0.16);
    final fg = warning ? AppColors.warning : AppColors.info;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, color: fg, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Like [runWithProgress] for void actions: returns true on success.
Future<bool> runOk(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  final r = await runWithProgress<bool>(context, () async {
    await action();
    return true;
  }, success: success);
  return r ?? false;
}

String friendlyError(Object e) => e is ApiException
    ? e.message
    : 'Something went wrong. Please try again later.';
