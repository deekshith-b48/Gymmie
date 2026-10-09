import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Search field + navy "+" button + filter button, as on the original Members / Leads screens.
class ListToolbar extends StatefulWidget {
  const ListToolbar({
    super.key,
    required this.hint,
    required this.onSearch,
    this.onAdd,
    this.onFilter,
    this.filterActive = false,
    this.initialQuery = '',
    this.extra,
  });

  final String hint;
  final ValueChanged<String> onSearch;
  final VoidCallback? onAdd;
  final VoidCallback? onFilter;
  final bool filterActive;
  final String initialQuery;
  final List<Widget>? extra;

  @override
  State<ListToolbar> createState() => _ListToolbarState();
}

class _ListToolbarState extends State<ListToolbar> {
  late final _c = TextEditingController(text: widget.initialQuery);
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 52,
            child: TextField(
              controller: _c,
              textInputAction: TextInputAction.search,
              onChanged: (v) {
                _t?.cancel();
                _t = Timer(
                  const Duration(milliseconds: 350),
                  () => widget.onSearch(v.trim()),
                );
              },
              onSubmitted: (v) => widget.onSearch(v.trim()),
              decoration: InputDecoration(
                hintText: widget.hint,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                suffixIcon: _c.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _c.clear();
                          widget.onSearch('');
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),
        ),
        if (widget.onAdd != null) ...[
          const SizedBox(width: 8),
          Material(
            color: primary,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: widget.onAdd,
              child: SizedBox(
                width: 52,
                height: 52,
                child: Icon(
                  Icons.add,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
          ),
        ],
        if (widget.onFilter != null) ...[
          const SizedBox(width: 8),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Material(
                color: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Theme.of(context).dividerColor),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: widget.onFilter,
                  child: const SizedBox(
                    width: 52,
                    height: 52,
                    child: Icon(Icons.tune),
                  ),
                ),
              ),
              if (widget.filterActive)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        ],
        ...?widget.extra,
      ],
    );
  }
}

/// Outlined pills summarising the active sort/filter ("Sort by: Created at - Desc").
class ActiveFilters extends StatelessWidget {
  const ActiveFilters({super.key, required this.labels, this.onTap});
  final List<String> labels;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    final primary = Theme.of(context).colorScheme.primary;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final l in labels)
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: primary),
              ),
              child: Text(l, style: const TextStyle(fontSize: 13)),
            ),
          ),
      ],
    );
  }
}

class CountLine extends StatelessWidget {
  const CountLine(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 12, 0, 4),
    child: Text(
      text,
      style: const TextStyle(color: AppColors.info, fontSize: 14),
    ),
  );
}
