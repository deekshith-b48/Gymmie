// The building blocks of the Settings pages, in openGym's grouped-list look: a section is one card of rows
// separated by hairlines; a row has a tinted icon, a title, an optional subtitle and either a value with a
// chevron, or its own control (switch, segmented choice).
import 'package:flutter/cupertino.dart' show CupertinoTimerPicker, CupertinoTimerPickerMode;
import 'package:flutter/material.dart';

import 'theme.dart';

/// Where a search hit lands: the row with this title flashes once and is scrolled into view.
class RowFlash extends InheritedWidget {
  const RowFlash({super.key, required this.title, required super.child});
  final String? title;
  static String? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<RowFlash>()?.title;
  @override
  bool updateShouldNotify(RowFlash old) => old.title != title;
}

class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, this.title, this.footer, required this.children});
  final String? title;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(Divider(height: 1, indent: 58, color: OG.line));
      rows.add(children[i]);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null) Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(title!.toUpperCase(), style: TextStyle(color: OG.dim, fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w600)),
        ),
        Material(color: OG.card, borderRadius: BorderRadius.circular(16), clipBehavior: Clip.antiAlias, child: Column(children: rows)),
        if (footer != null) Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
          child: Text(footer!, style: TextStyle(color: OG.dim, fontSize: 12, height: 1.35)),
        ),
      ]),
    );
  }
}

class SettingsRow extends StatefulWidget {
  const SettingsRow({
    super.key, required this.icon, required this.title, this.tint, this.subtitle, this.value,
    this.onTap, this.chevron = false, this.trailing, this.danger = false, this.enabled = true,
  });
  final IconData icon;
  final String title;
  final Color? tint;
  final String? subtitle;

  /// Shown at the right, dim, before the chevron.
  final String? value;
  final VoidCallback? onTap;
  final bool chevron;

  /// A control at the right (a switch, a segmented choice).
  final Widget? trailing;
  final bool danger;
  final bool enabled;

  @override
  State<SettingsRow> createState() => _SettingsRowState();
}

class _SettingsRowState extends State<SettingsRow> with SingleTickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  bool _done = false;

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_done && RowFlash.of(context) == widget.title) {
      _done = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(context, alignment: 0.4, duration: const Duration(milliseconds: 250));
        _flash.forward(from: 0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.danger ? OG.red : (widget.tint ?? OG.blue);
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(children: [
        Container(
          width: 30, height: 30, alignment: Alignment.center,
          decoration: BoxDecoration(color: tint.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8)),
          child: Icon(widget.icon, size: 18, color: tint),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title, style: TextStyle(fontSize: 16, color: widget.danger ? OG.red : OG.text, fontWeight: FontWeight.w500)),
          if (widget.subtitle != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(widget.subtitle!, style: TextStyle(color: OG.dim, fontSize: 12.5, height: 1.3))),
        ])),
        if (widget.value != null) Flexible(child: Padding(padding: const EdgeInsets.only(left: 8), child: Text(widget.value!, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end, style: TextStyle(color: OG.dim, fontSize: 15)))),
        if (widget.trailing != null) Padding(padding: const EdgeInsets.only(left: 10), child: widget.trailing),
        if (widget.chevron) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.chevron_right, color: OG.dim, size: 22)),
      ]),
    );
    final row = Opacity(
      opacity: widget.enabled ? 1 : 0.45,
      child: widget.onTap == null || !widget.enabled ? body : InkWell(onTap: widget.onTap, child: body),
    );
    return AnimatedBuilder(
      animation: _flash,
      builder: (context, child) {
        final a = _flash.isAnimating || _flash.value > 0 ? (1 - _flash.value) * 0.28 : 0.0;
        return ColoredBox(color: OG.acc.withValues(alpha: a), child: child);
      },
      child: row,
    );
  }
}

/// A row with an on/off switch.
class SwitchRow extends StatelessWidget {
  const SwitchRow({super.key, required this.icon, required this.title, required this.value, required this.onChanged, this.tint, this.subtitle, this.enabled = true});
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? tint;
  final String? subtitle;
  final bool enabled;

  @override
  Widget build(BuildContext context) => SettingsRow(
    icon: icon, title: title, tint: tint, subtitle: subtitle, enabled: enabled,
    onTap: () => onChanged(!value),
    trailing: Switch(value: value, onChanged: enabled ? onChanged : null),
  );
}

/// A row whose choices sit inline as a compact segmented control.
class SegmentedRow<T> extends StatelessWidget {
  const SegmentedRow({super.key, required this.icon, required this.title, required this.value, required this.options, required this.onChanged, this.tint, this.subtitle});
  final IconData icon;
  final String title;
  final T value;
  final List<(T value, String label)> options;
  final ValueChanged<T> onChanged;
  final Color? tint;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => SettingsRow(
    icon: icon, title: title, tint: tint, subtitle: subtitle,
    trailing: SegmentedButton<T>(
      showSelectedIcon: false,
      style: ButtonStyle(visualDensity: VisualDensity.compact, padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      segments: [for (final o in options) ButtonSegment(value: o.$1, label: Text(o.$2, style: const TextStyle(fontSize: 13)))],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    ),
  );
}

/// One choice in a [SelectRow] sheet.
class SelectOption<T> {
  const SelectOption(this.value, this.label, {this.subtitle});
  final T value;
  final String label;
  final String? subtitle;
}

/// A row that shows the current choice and opens a sheet to pick another.
class SelectRow<T> extends StatelessWidget {
  const SelectRow({super.key, required this.icon, required this.title, required this.value, required this.options, required this.onChanged, this.tint, this.sheetTitle});
  final IconData icon;
  final String title;
  final T value;
  final List<SelectOption<T>> options;
  final ValueChanged<T> onChanged;
  final Color? tint;
  final String? sheetTitle;

  @override
  Widget build(BuildContext context) {
    final current = options.where((o) => o.value == value).firstOrNull ?? options.first;
    return SettingsRow(
      icon: icon, title: title, tint: tint, value: current.label, chevron: true,
      onTap: () async {
        final r = await showSheet<T>(context, title: sheetTitle ?? title, builder: (ctx) => [
          for (final o in options) ListTile(
            title: Text(o.label, style: TextStyle(fontWeight: o.value == value ? FontWeight.w700 : FontWeight.w500)),
            subtitle: o.subtitle == null ? null : Text(o.subtitle!, style: TextStyle(color: OG.dim, fontSize: 12.5)),
            trailing: o.value == value ? Icon(Icons.check, color: OG.acc) : null,
            onTap: () => Navigator.pop(ctx, o.value),
          ),
        ]);
        if (r != null && r != value) onChanged(r);
      },
    );
  }
}

/// A bottom sheet with a title and a scrollable list of [builder]'s widgets.
Future<T?> showSheet<T>(BuildContext context, {required String title, String? subtitle, required List<Widget> Function(BuildContext ctx) builder}) =>
    showModalBottomSheet<T>(
      context: context, isScrollControlled: true, showDragHandle: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Align(alignment: Alignment.centerLeft, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle, style: TextStyle(color: OG.dim, fontSize: 13, height: 1.35))),
          ])),
        ),
        Flexible(child: ListView(shrinkWrap: true, children: builder(ctx))),
      ])),
    );

/// A time (minutes and seconds) in a wheel, like openGym's duration wheel. 0:00 means "off" when [off] is set.
Future<int?> pickDuration(BuildContext context, {required String title, required int seconds, required int maxSeconds, String? footer}) {
  var value = seconds.clamp(0, maxSeconds);
  return showModalBottomSheet<int>(
    context: context, showDragHandle: true,
    builder: (ctx) => SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        SizedBox(height: 190, child: CupertinoTimerPicker(
          mode: CupertinoTimerPickerMode.ms,
          initialTimerDuration: Duration(seconds: value),
          onTimerDurationChanged: (d) => value = d.inSeconds.clamp(0, maxSeconds),
        )),
        if (footer != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(footer, textAlign: TextAlign.center, style: TextStyle(color: OG.dim, fontSize: 12.5))),
        FilledButton(onPressed: () => Navigator.pop(ctx, value), child: const Text('Done')),
      ]),
    )),
  );
}

String fmtRest(int sec) => sec <= 0 ? 'Off' : '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';

/// The standard page chrome for a Settings screen.
class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({super.key, required this.title, required this.children, this.flash});
  final String title;
  final List<Widget> children;
  final String? flash;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: RowFlash(title: flash, child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: children)),
  );
}
