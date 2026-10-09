import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/di.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../data/models/members.dart';
import '../../data/repositories/members_repository.dart';
import 'member_widgets.dart';

/// Bottom-sheet member search ("Select Member"). Returns the chosen member or null.
Future<MemberSummary?> pickMember(
  BuildContext context, {
  String title = 'Select Member',
  String? status,
  bool Function(MemberSummary)? where,
}) {
  return showModalBottomSheet<MemberSummary>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) =>
        _MemberPickerSheet(title: title, status: status, where: where),
  );
}

class _MemberPickerSheet extends StatefulWidget {
  const _MemberPickerSheet({required this.title, this.status, this.where});
  final String title;
  final String? status;
  final bool Function(MemberSummary)? where;
  @override
  State<_MemberPickerSheet> createState() => _MemberPickerSheetState();
}

class _MemberPickerSheetState extends State<_MemberPickerSheet> {
  final _repo = getIt<MembersRepository>();
  List<MemberSummary> _items = [];
  bool _loading = true;
  Object? _error;
  Timer? _t;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _repo.list(1, 40, {
        'sort': 'nameAsc',
        if (_q.isNotEmpty) 'q': _q,
        if (widget.status != null) 'status': widget.status,
      });
      final list = r.list
          .map(MemberSummary.fromJson)
          .where(widget.where ?? (_) => true)
          .toList();
      if (mounted) setState(() => _items = list);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.title,
                  style: Theme.of(ctx).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search for name or phone',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) {
                  _t?.cancel();
                  _t = Timer(const Duration(milliseconds: 300), () {
                    _q = v.trim();
                    _load();
                  });
                },
              ),
            ),
            Expanded(
              child: _loading
                  ? const LoadingBox()
                  : (_error != null
                        ? const EmptyState(
                            icon: Icons.error_outline,
                            title: 'Failed to load members',
                          )
                        : (_items.isEmpty
                              ? const EmptyState(
                                  icon: Icons.person_search_outlined,
                                  title: 'No members found',
                                )
                              : ListView.separated(
                                  controller: scroll,
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    4,
                                    16,
                                    24,
                                  ),
                                  itemCount: _items.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (ctx, i) {
                                    final m = _items[i];
                                    final tag = membershipTag(m.membership);
                                    return AppCard(
                                      onTap: () => Navigator.pop(ctx, m),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      child: Row(
                                        children: [
                                          UserAvatar(
                                            name: m.name,
                                            url: m.photoUrl,
                                            radius: 20,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  m.name,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                Text(
                                                  '#${m.admissionNo} · ${m.phone}',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color:
                                                        AppColors.textSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Tag(tag.label, tone: tag.tone),
                                        ],
                                      ),
                                    );
                                  },
                                ))),
            ),
          ],
        ),
      ),
    );
  }
}
