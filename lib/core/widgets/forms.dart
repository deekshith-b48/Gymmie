import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../util/format.dart';

/// Reusable validators. Messages reuse the original app's copy where it was recovered.
class V {
  V._();

  static String? required(String? v, [String msg = 'This field is required']) =>
      (v == null || v.trim().isEmpty) ? msg : null;

  static String? name(String? v, {String label = 'name'}) {
    if (v == null || v.trim().isEmpty) return 'Please enter a $label';
    if (v.trim().length < 2) return 'Name must be at least 2 characters';
    if (!RegExp(r"^[\p{L}\p{M} .'-]+$", unicode: true).hasMatch(v.trim())) {
      return 'Name cannot contain special characters';
    }
    return null;
  }

  static String? email(String? v, {bool optional = true}) {
    if (v == null || v.trim().isEmpty) {
      return optional ? null : 'Please enter email';
    }
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(v.trim())
        ? null
        : 'Please enter a valid email address';
  }

  static String? phone(
    String? v, {
    String dial = '+91',
    bool optional = false,
  }) {
    if (v == null || v.trim().isEmpty) {
      return optional ? null : 'Please enter a valid phone number';
    }
    final d = v.replaceAll(RegExp(r'\D'), '');
    if (dial == '+91') {
      return RegExp(r'^[6-9]\d{9}$').hasMatch(d)
          ? null
          : 'Mobile number not valid.';
    }
    return d.length >= 6 && d.length <= 14 ? null : 'Mobile number not valid.';
  }

  static String? amount(String? v, {bool allowZero = false, double? max}) {
    if (v == null || v.trim().isEmpty) return 'Enter amount';
    final n = double.tryParse(v.trim());
    if (n == null || n < 0 || (!allowZero && n == 0)) {
      return 'Please enter a valid amount';
    }
    if (max != null && n > max) return 'Amount cannot exceed ${Fmt.money(max)}';
    return null;
  }

  static String? integer(
    String? v, {
    int min = 0,
    int? max,
    String label = 'a valid number',
  }) {
    final n = int.tryParse((v ?? '').trim());
    if (n == null || n < min || (max != null && n > max)) {
      return 'Please enter $label';
    }
    return null;
  }

  static String? url(String? v) {
    if (v == null || v.trim().isEmpty) return 'URL cannot be empty';
    final u = Uri.tryParse(v.trim());
    return (u != null &&
            (u.scheme == 'http' || u.scheme == 'https') &&
            u.host.contains('.'))
        ? null
        : 'Please enter a valid URL';
  }

  static String? otp(String? v) => RegExp(r'^\d{6}$').hasMatch((v ?? '').trim())
      ? null
      : 'OTP not valid. Enter 6 digit OTP';
}

/// Text field with the label above it, matching the original form layout.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.validator,
    this.keyboardType,
    this.inputFormatters,
    this.maxLines = 1,
    this.maxLength,
    this.obscure = false,
    this.prefix,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.readOnly = false,
    this.onTap,
    this.textInputAction,
    this.enabled = true,
    this.initialValue,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.errorText,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;
  final int? maxLength;
  final bool obscure;
  final Widget? prefix;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool readOnly;
  final VoidCallback? onTap;
  final TextInputAction? textInputAction;
  final bool enabled;
  final String? initialValue;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              label!,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        TextFormField(
          controller: controller,
          initialValue: controller == null ? initialValue : null,
          validator: validator,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          maxLines: maxLines,
          maxLength: maxLength,
          obscureText: obscure,
          readOnly: readOnly,
          enabled: enabled,
          onTap: onTap,
          autofocus: autofocus,
          textCapitalization: textCapitalization,
          textInputAction: textInputAction,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: prefix,
            suffixIcon: suffix,
            counterText: '',
            errorText: errorText,
          ),
        ),
      ],
    );
  }
}

class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    this.label = 'Amount',
    this.hint,
    this.validator,
    this.onChanged,
    this.symbol,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final String? symbol;

  @override
  Widget build(BuildContext context) => AppTextField(
    controller: controller,
    label: label,
    hint: hint ?? 'Enter amount',
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [
      FilteringTextInputFormatter.allow(RegExp(r'^\d{0,9}(\.\d{0,2})?')),
    ],
    prefix: Padding(
      padding: const EdgeInsets.only(left: 16, right: 8),
      child: Center(
        widthFactor: 1,
        child: Text(
          symbol ?? Fmt.currencySymbol,
          style: const TextStyle(fontSize: 16),
        ),
      ),
    ),
    validator: validator ?? V.amount,
    onChanged: onChanged,
  );
}

class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.hint = 'Select date',
    this.required = false,
    this.clearable = false,
  });

  final String label;
  final String? value; // yyyy-MM-dd
  final ValueChanged<String?> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String hint;
  final bool required;
  final bool clearable;

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: value,
      validator: (_) => required && (value == null || value!.isEmpty)
          ? 'Please select a date'
          : null,
      builder: (state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final init = Fmt.parseDate(value) ?? DateTime.now();
                final first = firstDate ?? DateTime(1940);
                final last = lastDate ?? DateTime(2100);
                final d = await showDatePicker(
                  context: context,
                  initialDate: init.isBefore(first)
                      ? first
                      : (init.isAfter(last) ? last : init),
                  firstDate: first,
                  lastDate: last,
                );
                if (d != null) {
                  onChanged(Fmt.ymd(d));
                  state.didChange(Fmt.ymd(d));
                }
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  errorText: state.errorText,
                  suffixIcon: clearable && value != null
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => onChanged(null),
                        )
                      : const Icon(Icons.calendar_today_outlined, size: 18),
                ),
                child: Text(
                  value == null || value!.isEmpty ? hint : Fmt.date(value),
                  style: TextStyle(
                    color: value == null ? AppColors.textMuted : null,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class DropdownField<T> extends StatelessWidget {
  const DropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint = 'Please Select',
    this.validator,
    this.labelOf,
  });

  final String label;
  final T? value;
  final List<T> items;
  final ValueChanged<T?> onChanged;
  final String hint;
  final FormFieldValidator<T>? validator;
  final String Function(T)? labelOf;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
        DropdownButtonFormField<T>(
          initialValue: items.contains(value) ? value : null,
          isExpanded: true,
          items: [
            for (final i in items)
              DropdownMenuItem<T>(
                value: i,
                child: Text(
                  labelOf?.call(i) ?? '$i',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: onChanged,
          validator: validator,
          hint: Text(hint, style: const TextStyle(color: AppColors.textMuted)),
          decoration: const InputDecoration(),
          borderRadius: BorderRadius.circular(12),
        ),
      ],
    );
  }
}

/// Primary button with an inline progress indicator.
class LoadingButton extends StatelessWidget {
  const LoadingButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.outlined = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final bool outlined;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: outlined ? null : Theme.of(context).colorScheme.onPrimary,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: 8),
              ],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          );
    final cb = loading ? null : onPressed;
    if (outlined) {
      return OutlinedButton(
        onPressed: cb,
        style: destructive
            ? OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
              )
            : null,
        child: child,
      );
    }
    return FilledButton(
      onPressed: cb,
      style: destructive
          ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
          : null,
      child: child,
    );
  }
}

/// Bottom action bar for form screens.
class FormScaffold extends StatelessWidget {
  const FormScaffold({
    super.key,
    required this.title,
    required this.formKey,
    required this.child,
    required this.submitLabel,
    required this.onSubmit,
    this.saving = false,
    this.actions,
    this.secondary,
  });

  final String title;
  final GlobalKey<FormState> formKey;
  final Widget child;
  final String submitLabel;
  final VoidCallback onSubmit;
  final bool saving;
  final List<Widget>? actions;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Form(
                key: formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [child],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Row(
                children: [
                  if (secondary != null) ...[
                    Expanded(child: secondary!),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex: 2,
                    child: LoadingButton(
                      label: submitLabel,
                      onPressed: onSubmit,
                      loading: saving,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vertical gap helper.
class Gap extends StatelessWidget {
  const Gap(this.h, {super.key});
  final double h;
  @override
  Widget build(BuildContext context) => SizedBox(height: h);
}
