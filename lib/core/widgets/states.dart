import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../network/api_exception.dart';
import '../state/async_cubit.dart';
import '../theme/app_theme.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.asset,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final String title;
  final String? message;
  final String? asset; // svg or png under assets/
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    Widget? art;
    if (asset != null) {
      art = asset!.endsWith('.svg')
          ? SvgPicture.asset(asset!, height: compact ? 110 : 160)
          : Image.asset(asset!, height: compact ? 110 : 160);
    } else if (icon != null) {
      art = Icon(icon, size: compact ? 48 : 64, color: AppColors.textMuted);
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (art != null) ...[art, const SizedBox(height: 20)],
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(minimumSize: const Size(180, 48)),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.error,
    this.onRetry,
    this.compact = false,
  });

  final ApiException error;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isNet = error.isNetwork;
    final forbidden = error.status == 403;
    return EmptyState(
      icon: isNet
          ? Icons.wifi_off_rounded
          : (forbidden ? Icons.lock_outline : Icons.error_outline),
      title: isNet
          ? 'No connection'
          : (forbidden ? 'Access denied' : 'Something went wrong'),
      message: error.message,
      actionLabel: onRetry == null ? null : 'Try again',
      onAction: onRetry,
      compact: compact,
    );
  }
}

class LoadingBox extends StatelessWidget {
  const LoadingBox({super.key});
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: CircularProgressIndicator(),
    ),
  );
}

/// Renders an [AsyncCubit] with loading / error / data and pull-to-refresh.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({
    super.key,
    required this.builder,
    this.isEmpty,
    this.empty,
    this.refreshable = true,
    this.cubit,
  });

  final Widget Function(BuildContext context, T data) builder;
  final bool Function(T data)? isEmpty;
  final Widget? empty;
  final bool refreshable;
  final AsyncCubit<T>? cubit;

  @override
  Widget build(BuildContext context) {
    final c = cubit ?? context.read<AsyncCubit<T>>();
    return BlocBuilder<AsyncCubit<T>, AsyncState<T>>(
      bloc: c,
      builder: (context, s) {
        if (s.isLoading) return const LoadingBox();
        if (s.status == LoadStatus.error && !s.hasData) {
          return ErrorState(error: s.error!, onRetry: c.load);
        }
        final data = s.data as T;
        final body = (isEmpty?.call(data) ?? false) && empty != null
            ? empty!
            : builder(context, data);
        if (!refreshable) return body;
        return RefreshIndicator(onRefresh: c.refresh, child: body);
      },
    );
  }
}

/// A scrollable, paginated list bound to a [PagedCubit].
class PagedListBody<T> extends StatefulWidget {
  const PagedListBody({
    super.key,
    required this.cubit,
    required this.itemBuilder,
    this.empty,
    this.header,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 96),
    this.separator = 12,
  });

  final PagedCubit<T> cubit;
  final Widget Function(BuildContext, T) itemBuilder;
  final Widget? empty;
  final Widget Function(BuildContext, PagedState<T>)? header;
  final EdgeInsets padding;
  final double separator;

  @override
  State<PagedListBody<T>> createState() => _PagedListBodyState<T>();
}

class _PagedListBodyState<T> extends State<PagedListBody<T>> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 320) {
        widget.cubit.loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PagedCubit<T>, PagedState<T>>(
      bloc: widget.cubit,
      builder: (context, s) {
        if (s.isLoading && s.items.isEmpty) return const LoadingBox();
        if (s.status == LoadStatus.error && s.items.isEmpty) {
          return ErrorState(error: s.error!, onRetry: widget.cubit.reload);
        }
        final header = widget.header?.call(context, s);
        if (s.items.isEmpty) {
          return RefreshIndicator(
            onRefresh: widget.cubit.reload,
            child: ListView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: widget.padding,
              children: [
                ?header,
                SizedBox(
                  height: 360,
                  child:
                      widget.empty ??
                      const EmptyState(
                        title: 'Nothing here yet',
                        icon: Icons.inbox_outlined,
                      ),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: widget.cubit.reload,
          child: ListView.separated(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: widget.padding,
            itemCount: s.items.length + 1 + (header != null ? 1 : 0),
            separatorBuilder: (_, _) => SizedBox(height: widget.separator),
            itemBuilder: (context, i) {
              if (header != null) {
                if (i == 0) return header;
                i -= 1;
              }
              if (i >= s.items.length) {
                return s.loadingMore
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : (s.hasMore
                          ? const SizedBox(height: 24)
                          : const SizedBox.shrink());
              }
              return widget.itemBuilder(context, s.items[i]);
            },
          ),
        );
      },
    );
  }
}
