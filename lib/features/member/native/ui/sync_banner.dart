import 'package:flutter/material.dart';

import '../../../../core/network/api_exception.dart';
import '../log_store.dart';
import 'scope.dart';
import 'theme.dart';

/// Tells the member, in plain words, when their log could not be saved to their account. Their changes
/// are always kept on the phone. A refused session (401/403) is also handed to the app, which re-checks
/// whether the gym still allows this member and signs them out if not.
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final sc = NativeScope.of(context);
    final st = sc.store;
    return ListenableBuilder(listenable: st, builder: (context, _) {
      if (!sc.prefs.connectionBar) return const SizedBox.shrink(); // the member switched it off; Home shows a dot instead
      if (st.status != SyncStatus.error && !(st.status == SyncStatus.offline && st.dirty)) return const SizedBox.shrink();
      final offline = st.status == SyncStatus.offline;
      final e = st.lastError;
      final text = offline
          ? 'You are offline. Your changes are saved on this phone and will sync later.'
          : e is ApiException && e.status > 0
              ? 'Your server answered with an error (HTTP ${e.status}). Your changes are kept here.'
              : 'Your log could not be saved to your account. Your changes are kept here.';
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(color: (offline ? OG.orange : OG.red).withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(offline ? Icons.cloud_off : Icons.warning_amber_rounded, color: offline ? OG.orange : OG.red),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          TextButton(onPressed: st.status == SyncStatus.syncing ? null : st.sync, child: const Text('Try again')),
        ]),
      );
    });
  }
}
