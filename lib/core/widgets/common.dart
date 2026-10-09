import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../util/format.dart';
import 'auth_image.dart';

/// Outlined white card with the original app's 12px radius.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      color: color,
      margin: margin,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              child: Padding(padding: padding, child: child),
            ),
    );
    return card;
  }
}

enum Tone { neutral, success, warning, danger, info, navy }

({Color bg, Color fg}) toneColors(BuildContext context, Tone t) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (t) {
    Tone.success => (
      bg: dark ? const Color(0xFF123A28) : AppColors.successTint,
      fg: dark ? const Color(0xFF7BE0A8) : AppColors.success,
    ),
    Tone.warning => (
      bg: dark ? const Color(0xFF44300F) : AppColors.warningTint,
      fg: dark ? const Color(0xFFFFC27A) : AppColors.warning,
    ),
    Tone.danger => (
      bg: dark ? const Color(0xFF4A1A1C) : AppColors.dangerTint,
      fg: dark ? const Color(0xFFFF9A9D) : AppColors.danger,
    ),
    Tone.info => (
      bg: dark ? const Color(0xFF1D2A5A) : const Color(0xFFE8ECFB),
      fg: dark ? const Color(0xFFA9B8FF) : AppColors.info,
    ),
    Tone.navy => (bg: AppColors.navy, fg: Colors.white),
    Tone.neutral => (
      bg: dark ? AppColors.darkChip : AppColors.neutralTint,
      fg: dark ? const Color(0xFFC9D2F0) : AppColors.textSecondary,
    ),
  };
}

/// Small coloured label ("Medium", "Walk-in", "Follow up on: 03 Jan 2025").
class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.tone = Tone.neutral, this.icon});

  final String label;
  final Tone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = toneColors(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: c.fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: c.fg,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Selectable pill used in filter sheets: unselected light-grey, selected navy with white text.
class PillChip extends StatelessWidget {
  const PillChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = selected
        ? Theme.of(context).colorScheme.primary
        : (dark ? AppColors.darkChip : AppColors.chip);
    final fg = selected
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSurface;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled group of single-select pills (one section of the filter sheet).
class ChoiceGroup<T> extends StatelessWidget {
  const ChoiceGroup({
    super.key,
    required this.title,
    required this.options,
    required this.value,
    required this.onChanged,
    this.labelOf,
  });

  final String title;
  final List<T> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final String Function(T)? labelOf;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final o in options)
                PillChip(
                  label: labelOf?.call(o) ?? '$o',
                  selected: o == value,
                  onTap: () => onChanged(o),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(
    this.text, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 20, 16, 8),
  });

  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class InfoRow extends StatelessWidget {
  const InfoRow(
    this.label,
    this.value, {
    super.key,
    this.valueWidget,
    this.bold = false,
  });

  final String label;
  final String? value;
  final Widget? valueWidget;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          flex: 6,
          child:
              valueWidget ??
              Text(
                value == null || value!.isEmpty ? '—' : value!,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
        ),
      ],
    ),
  );
}

/// Circular avatar: photo when available (authenticated fetch), otherwise initials.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.name, this.url, this.radius = 24});

  final String name;
  final String? url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initials = Text(
      Fmt.initials(name),
      style: TextStyle(
        fontSize: radius * 0.7,
        fontWeight: FontWeight.w600,
        color: AppColors.navy,
      ),
    );
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFDDE3F7),
      child: url == null
          ? initials
          : ClipOval(
              child: AuthImage(
                url: url!,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                placeholder: initials,
              ),
            ),
    );
  }
}

/// Dashboard-style KPI tile.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.onTap,
    this.tone = Tone.navy,
    this.caption,
  });

  final String label;
  final String value;
  final IconData? icon;
  final VoidCallback? onTap;
  final Tone tone;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final c = toneColors(context, tone == Tone.navy ? Tone.info : tone);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (icon != null)
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: c.bg,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 18, color: c.fg),
                ),
              const Spacer(),
              if (onTap != null)
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.textMuted,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          if (caption != null)
            Text(
              caption!,
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }
}

/// Tappable list row inside cards (settings menus etc.).
class MenuTile extends StatelessWidget {
  const MenuTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : null;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w500, color: color),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: const TextStyle(fontSize: 12)),
      trailing:
          trailing ??
          (onTap == null
              ? null
              : const Icon(Icons.chevron_right, color: AppColors.textMuted)),
      onTap: onTap,
    );
  }
}

/// Wraps tiles in one outlined card with dividers.
class MenuGroup extends StatelessWidget {
  const MenuGroup({super.key, required this.children, this.title});

  final List<Widget> children;
  final String? title;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (title != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
          child: Text(
            title!,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Card(
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(indent: 56),
                children[i],
              ],
            ],
          ),
        ),
      ),
    ],
  );
}
