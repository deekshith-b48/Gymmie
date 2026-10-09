import 'package:flutter/material.dart';

import '../util/format.dart';
import 'common.dart';
import 'sheets.dart';

/// A reporting period as used by transactions / reports / expenses / attendance filters.
class PeriodSel {
  const PeriodSel(this.key, {this.from, this.to});
  final String key; // server period key, or 'custom' / 'all'
  final String? from;
  final String? to;

  static const thisMonth = PeriodSel('thisMonth');
  static const all = PeriodSel('all');

  static const options = <String, String>{
    'today': 'Today',
    'thisWeek': 'This Week',
    'last7Days': 'Last 7 days',
    'last30Days': 'Last 30 days',
    'thisMonth': 'This Month',
    'lastMonth': 'Last Month',
    'last6Months': 'Last 6 Months',
    'thisYear': 'This Year',
    'lastYear': 'Last Year',
    'firstHalfThisYear': '1st half this year',
    'secondHalfThisYear': '2nd half this year',
    'custom': 'Custom date range',
    'all': 'All Time',
  };

  String get label => key == 'custom'
      ? '${Fmt.dateShort(from)} – ${Fmt.date(to)}'
      : (options[key] ?? key);

  /// Query parameters understood by the API (`period` + `from`/`to`).
  Map<String, dynamic> get query => key == 'all'
      ? const {}
      : {
          'period': key,
          if (key == 'custom') ...{'from': from, 'to': to},
        };

  @override
  bool operator ==(Object other) =>
      other is PeriodSel &&
      other.key == key &&
      other.from == from &&
      other.to == to;
  @override
  int get hashCode => Object.hash(key, from, to);
}

/// Lets the user pick a period (chips + a date-range picker for "Custom").
Future<PeriodSel?> showPeriodSheet(
  BuildContext context,
  PeriodSel current, {
  bool allowAll = true,
  Set<String>? only,
}) async {
  final keys = [
    for (final k in PeriodSel.options.keys)
      if ((allowAll || k != 'all') && (only == null || only.contains(k))) k,
  ];
  return showAppSheet<PeriodSel>(
    context,
    title: 'Time Filter',
    builder: (ctx) => Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final k in keys)
          PillChip(
            label: PeriodSel.options[k]!,
            selected: current.key == k,
            onTap: () async {
              if (k != 'custom') {
                Navigator.pop(ctx, PeriodSel(k));
                return;
              }
              final now = DateTime.now();
              final r = await showDateRangePicker(
                context: ctx,
                firstDate: DateTime(now.year - 5),
                lastDate: DateTime(now.year + 1),
                initialDateRange:
                    current.key == 'custom' && current.from != null
                    ? DateTimeRange(
                        start: DateTime.parse(current.from!),
                        end: DateTime.parse(current.to!),
                      )
                    : null,
                helpText: 'Select date range',
              );
              if (r != null && ctx.mounted) {
                Navigator.pop(
                  ctx,
                  PeriodSel(
                    'custom',
                    from: Fmt.ymd(r.start),
                    to: Fmt.ymd(r.end),
                  ),
                );
              }
            },
          ),
      ],
    ),
  );
}

/// The compact "This Month ▾" button shown above lists.
class PeriodButton extends StatelessWidget {
  const PeriodButton({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowAll = true,
    this.only,
  });
  final PeriodSel value;
  final ValueChanged<PeriodSel> onChanged;
  final bool allowAll;
  final Set<String>? only;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 42),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      side: BorderSide(color: Theme.of(context).dividerColor),
      foregroundColor: Theme.of(context).colorScheme.onSurface,
    ),
    onPressed: () async {
      final r = await showPeriodSheet(
        context,
        value,
        allowAll: allowAll,
        only: only,
      );
      if (r != null) onChanged(r);
    },
    icon: const Icon(Icons.calendar_month_outlined, size: 18),
    label: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value.label, style: const TextStyle(fontSize: 13)),
        const Icon(Icons.arrow_drop_down),
      ],
    ),
  );
}
