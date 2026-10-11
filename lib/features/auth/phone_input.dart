import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/data/countries.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/forms.dart';

/// Phone input: dial-code selector + national number.
class PhoneInput extends StatelessWidget {
  const PhoneInput({
    super.key,
    required this.controller,
    required this.dial,
    required this.onDialChanged,
    this.label = 'Phone number',
    this.optional = false,
    this.autofocus = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String dial;
  final ValueChanged<String> onDialChanged;
  final String label;
  final bool optional;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: controller,
      label: label,
      hint: '10-digit mobile number',
      keyboardType: TextInputType.phone,
      autofocus: autofocus,
      maxLength: 15,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]'))],
      validator: (v) => V.phone(v, dial: dial, optional: optional),
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.done,
      prefix: PopupMenuButton<String>(
        tooltip: 'Country code',
        onSelected: onDialChanged,
        itemBuilder: (_) => [
          for (final c in countries)
            PopupMenuItem(value: c.dial, child: Text('${c.name}  ${c.dial}')),
        ],
        child: Padding(
          padding: const EdgeInsets.only(left: 14, right: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(dial, style: const TextStyle(fontWeight: FontWeight.w500)),
              Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
              Container(
                width: 1,
                height: 22,
                color: AppColors.border,
                margin: const EdgeInsets.only(left: 2, right: 6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
