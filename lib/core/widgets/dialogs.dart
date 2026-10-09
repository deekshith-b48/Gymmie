import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'forms.dart';

/// Text-input dialog. Returns the trimmed value or null when cancelled.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? message,
  String? label,
  String? hint,
  String? initial,
  String confirmLabel = 'Save',
  int maxLines = 1,
  int? maxLength,
  bool required = false,
  TextInputType? keyboardType,
  List<TextInputFormatter>? formatters,
  String? Function(String?)? validator,
}) {
  final c = TextEditingController(text: initial);
  final key = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Form(
        key: key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            AppTextField(
              controller: c,
              label: label,
              hint: hint,
              maxLines: maxLines,
              maxLength: maxLength,
              keyboardType: keyboardType,
              inputFormatters: formatters,
              autofocus: true,
              validator: validator ?? (required ? (v) => V.required(v) : null),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text(
            'Cancel',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
          onPressed: () {
            if (key.currentState!.validate()) Navigator.pop(ctx, c.text.trim());
          },
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

Future<int?> promptNumber(
  BuildContext context, {
  required String title,
  String? label,
  String? hint,
  int min = 1,
  int max = 100000,
  String confirmLabel = 'Save',
  int? initial,
}) async {
  final v = await promptText(
    context,
    title: title,
    label: label,
    hint: hint,
    initial: initial?.toString(),
    confirmLabel: confirmLabel,
    keyboardType: TextInputType.number,
    formatters: [FilteringTextInputFormatter.digitsOnly],
    validator: (v) => V.integer(
      v,
      min: min,
      max: max,
      label: 'a number between $min and $max',
    ),
  );
  return v == null ? null : int.tryParse(v);
}

/// Single-choice dialog. Returns the chosen item or null.
Future<T?> chooseOne<T>(
  BuildContext context, {
  required String title,
  required List<T> items,
  required String Function(T) labelOf,
  T? selected,
}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title),
      children: [
        for (final i in items)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, i),
            child: Row(
              children: [
                Expanded(child: Text(labelOf(i))),
                if (i == selected)
                  const Icon(Icons.check, color: AppColors.success, size: 18),
              ],
            ),
          ),
      ],
    ),
  );
}
