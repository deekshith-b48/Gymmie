import 'package:flutter/material.dart';

import '../../../../core/network/api_exception.dart';
import 'theme.dart';

/// Loads something once and shows it, with a spinner, a retry on failure, and pull-to-refresh by [reload].
class AsyncSection<T> extends StatefulWidget {
  const AsyncSection({super.key, required this.load, required this.builder, this.compact = false});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;
  final bool compact;

  @override
  State<AsyncSection<T>> createState() => _AsyncSectionState<T>();
}

class _AsyncSectionState<T> extends State<AsyncSection<T>> {
  T? _data;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await widget.load();
      if (mounted) setState(() { _data = d; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d != null) return widget.builder(context, d);
    if (_loading) return Padding(padding: EdgeInsets.all(widget.compact ? 12 : 32), child: const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))));
    final msg = _error is ApiException ? (_error as ApiException).message : 'Could not load this.';
    return Padding(padding: const EdgeInsets.all(16), child: Row(children: [
      Icon(Icons.cloud_off, color: OG.orange), const SizedBox(width: 10),
      Expanded(child: Text(msg, style: TextStyle(color: OG.dim))),
      TextButton(onPressed: _run, child: const Text('Retry')),
    ]));
  }
}
