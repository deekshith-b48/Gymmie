import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Filter / sort bottom sheet chrome as in the original: "Filter"  [Reset]  [Save].
Future<T?> showFilterSheet<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext, StateSetter) body,
  required T Function() onSave,
  required VoidCallback onReset,
  bool Function()? canSave,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(ctx).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      onReset();
                      setState(() {});
                    },
                    child: const Text(
                      'Reset',
                      style: TextStyle(color: AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: (canSave?.call() ?? true)
                        ? () => Navigator.pop(ctx, onSave())
                        : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(96, 44),
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                children: [body(ctx, setState)],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Pick one item from a (searchable) list in a bottom sheet.
Future<T?> showPickerSheet<T>(
  BuildContext context, {
  required String title,
  required List<T> items,
  required String Function(T) labelOf,
  String Function(T)? subtitleOf,
  T? selected,
  bool searchable = false,
  Widget Function(T)? leadingOf,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      var q = '';
      return StatefulBuilder(
        builder: (ctx, setState) {
          final filtered = [
            for (final i in items)
              if (q.isEmpty ||
                  labelOf(i).toLowerCase().contains(q.toLowerCase()))
                i,
          ];
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            maxChildSize: 0.95,
            builder: (ctx, scroll) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      style: Theme.of(ctx).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                if (searchable)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: TextField(
                      onChanged: (v) => setState(() => q = v),
                      decoration: const InputDecoration(
                        hintText: 'Search',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(
                          child: Text(
                            'No results',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : ListView.builder(
                          controller: scroll,
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) {
                            final it = filtered[i];
                            return ListTile(
                              leading: leadingOf?.call(it),
                              title: Text(labelOf(it)),
                              subtitle: subtitleOf == null
                                  ? null
                                  : Text(subtitleOf(it)),
                              trailing: it == selected
                                  ? const Icon(
                                      Icons.check_circle,
                                      color: AppColors.success,
                                    )
                                  : null,
                              onTap: () => Navigator.pop(ctx, it),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

/// Simple sheet with a title and arbitrary content (+ optional primary action).
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext) builder,
  bool scroll = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: scroll,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.of(ctx).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(ctx).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            builder(ctx),
          ],
        ),
      ),
    ),
  );
}
