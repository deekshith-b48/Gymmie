import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/auth/permissions.dart';
import '../../core/state/async_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/files.dart';
import '../../core/util/format.dart';
import '../../core/util/launch.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../core/widgets/period_filter.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../../data/models/messaging.dart';
import '../../data/repositories/messaging_repository.dart';

/// Automated messages (per-event templates with an on/off switch) + custom broadcast templates.
class MessageTemplatesScreen extends StatefulWidget {
  const MessageTemplatesScreen({super.key});
  @override
  State<MessageTemplatesScreen> createState() => _MessageTemplatesScreenState();
}

class _MessageTemplatesScreenState extends State<MessageTemplatesScreen>
    with SingleTickerProviderStateMixin {
  final _repo = getIt<MessagingRepository>();
  late final AsyncCubit<List<NotificationTemplate>> _auto = AsyncCubit(
    _repo.notificationTemplates,
  );
  late final AsyncCubit<List<BroadcastTemplate>> _custom = AsyncCubit(
    _repo.broadcastTemplates,
  );
  late final TabController _tabs = TabController(length: 2, vsync: this);
  List<String> _vars = const [];

  @override
  void initState() {
    super.initState();
    _repo
        .variables('member')
        .then(
          (v) => mounted
              ? setState(() => _vars = [...v.common, ...v.member])
              : null,
        )
        .catchError((Object _) {});
  }

  @override
  void dispose() {
    _auto.close();
    _custom.close();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _editAuto(NotificationTemplate t) async {
    final c = TextEditingController(text: t.body);
    final key = GlobalKey<FormState>();
    final res = await showAppSheet<String>(
      context,
      title: 'Edit message template',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Form(
          key: key,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.title,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const Gap(8),
              AppTextField(
                controller: c,
                maxLines: 5,
                maxLength: 1000,
                validator: (v) =>
                    (v ?? '').trim().length < 5 ? 'Message is too short' : null,
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final v in _vars)
                    ActionChip(
                      label: Text('#$v', style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        c.text = '${c.text}{{$v}}';
                        c.selection = TextSelection.collapsed(
                          offset: c.text.length,
                        );
                      },
                    ),
                ],
              ),
              const Gap(12),
              FilledButton(
                onPressed: () {
                  if (key.currentState!.validate()) {
                    Navigator.pop(ctx, c.text.trim());
                  }
                },
                child: const Text('Save'),
              ),
              if (t.isCustom)
                TextButton(
                  onPressed: () => Navigator.pop(ctx, '__reset__'),
                  child: const Text('Reset to Default'),
                ),
            ],
          ),
        ),
      ),
    );
    c.dispose();
    if (res == null || !mounted) return;
    final ok = await runOk(
      context,
      () => res == '__reset__'
          ? _repo.resetNotificationTemplate(t.key).then((_) {})
          : _repo.updateNotificationTemplate(t.key, body: res).then((_) {}),
      success: res == '__reset__'
          ? 'Your message template has been reset to default.'
          : 'Your message template has been saved.',
    );
    if (ok) _auto.refresh();
  }

  Future<void> _editCustom([BroadcastTemplate? t]) async {
    final title = TextEditingController(text: t?.title);
    final body = TextEditingController(text: t?.body);
    final key = GlobalKey<FormState>();
    final res = await showAppSheet<(String, String)>(
      context,
      title: t == null ? 'Create Template' : 'Edit your template',
      builder: (ctx) => Form(
        key: key,
        child: Column(
          children: [
            AppTextField(
              controller: title,
              label: 'Template name',
              hint: 'Enter name',
              maxLength: 60,
              validator: (v) => V.required(v, 'Please enter the title'),
            ),
            const Gap(12),
            AppTextField(
              controller: body,
              label: 'Message',
              hint: 'Use {{memberName}}, {{gymName}} …',
              maxLines: 5,
              maxLength: 1000,
              validator: (v) =>
                  (v ?? '').trim().length < 5 ? 'Message is too short' : null,
            ),
            const Gap(12),
            FilledButton(
              onPressed: () {
                if (key.currentState!.validate()) {
                  Navigator.pop(ctx, (title.text.trim(), body.text.trim()));
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    title.dispose();
    body.dispose();
    if (res == null || !mounted) return;
    final ok = await runOk(
      context,
      () => t == null
          ? _repo.createBroadcastTemplate(res.$1, res.$2)
          : _repo.updateBroadcastTemplate(t.id, res.$1, res.$2),
      success: 'Your message template has been saved.',
    );
    if (ok) _custom.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = getIt<SessionCubit>().state.can(Perm.broadcastsWrite);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Message Templates'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Automated Messages'),
            Tab(text: 'Your Templates'),
          ],
        ),
      ),
      floatingActionButton: canWrite
          ? ListenableBuilder(
              listenable: _tabs,
              builder: (_, _) => _tabs.index == 1
                  ? FloatingActionButton.extended(
                      onPressed: _editCustom,
                      icon: const Icon(Icons.add),
                      label: const Text('Create Template'),
                    )
                  : const SizedBox.shrink(),
            )
          : null,
      body: TabBarView(
        controller: _tabs,
        children: [
          AsyncBody<List<NotificationTemplate>>(
            cubit: _auto,
            builder: (context, list) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              children: [
                const InfoBanner(
                  'Automated messages are sent through WhatsApp when the integration is on and use credits. Turn off the ones you do not want.',
                ),
                const Gap(12),
                for (final t in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      onTap: canWrite ? () => _editAuto(t) : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  t.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (t.isCustom)
                                const Tag('Edited', tone: Tone.info),
                              if (canWrite)
                                Switch(
                                  value: t.auto,
                                  onChanged: (v) async {
                                    if (await runOk(
                                      context,
                                      () => _repo
                                          .updateNotificationTemplate(
                                            t.key,
                                            auto: v,
                                          )
                                          .then((_) {}),
                                    )) {
                                      _auto.refresh();
                                    }
                                  },
                                ),
                            ],
                          ),
                          Text(
                            t.body,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          AsyncBody<List<BroadcastTemplate>>(
            cubit: _custom,
            isEmpty: (d) => d.isEmpty,
            empty: const EmptyState(
              icon: Icons.chat_bubble_outline,
              title: "Looks like you haven't created any templates.",
              message: 'Create reusable messages for your broadcasts.',
            ),
            builder: (context, list) => ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final t = list[i];
                return AppCard(
                  onTap: canWrite ? () => _editCustom(t) : null,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              t.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (canWrite)
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            color: AppColors.danger,
                          ),
                          onPressed: () async {
                            if (await confirmDialog(
                                  context,
                                  title: 'Delete',
                                  message: 'This action cannot be undone',
                                  confirmLabel: 'Delete',
                                  destructive: true,
                                ) &&
                                context.mounted &&
                                await runOk(
                                  context,
                                  () => _repo.deleteBroadcastTemplate(t.id),
                                  success: 'Deleted',
                                )) {
                              _custom.refresh();
                            }
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
class CreditsScreen extends StatefulWidget {
  const CreditsScreen({super.key});
  @override
  State<CreditsScreen> createState() => _CreditsScreenState();
}

class _CreditsScreenState extends State<CreditsScreen>
    with WidgetsBindingObserver {
  final _repo = getIt<MessagingRepository>();
  late final AsyncCubit<CreditStats> _stats = AsyncCubit(_repo.creditStats);
  late final AsyncCubit<List<CreditPack>> _packs = AsyncCubit(
    _repo.creditPacks,
  );
  late final PagedCubit<LedgerEntry> _ledger = PagedCubit<LedgerEntry>(
    fetch: _repo.ledger,
    parse: LedgerEntry.fromJson,
    pageSize: 30,
  );
  String? _pendingOrder;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stats.close();
    _packs.close();
    _ledger.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingOrder != null) {
      _checkOrder();
    }
  }

  int _polls = 0;

  Future<void> _checkOrder() async {
    final id = _pendingOrder;
    if (id == null) return;
    try {
      final o = await _repo.order(id);
      if (o.status == 'created') {
        // paid at the bank but the provider has not confirmed yet: look again in a few seconds
        if (_polls++ < 6) Future<void>.delayed(const Duration(seconds: 3), () { if (mounted) _checkOrder(); });
        return;
      }
      _pendingOrder = null;
      if (!mounted) return;
      if (o.status == 'paid') {
        showToast(context, 'Credits recharged!');
        await getIt<SessionCubit>().refreshProfile();
        _stats.refresh();
        _ledger.reload();
      } else {
        showToast(
          context,
          "We couldn't complete your credit purchase. Please try again from the app or contact support if the problem persists.",
          error: true,
        );
      }
    } catch (_) {}
  }

  Future<void> _buy(CreditPack p) async {
    final o = await runWithProgress(context, () => _repo.orderCredits(p.id));
    if (o?.paymentUrl == null || !mounted) return;
    _pendingOrder = o!.id;
    _polls = 0;
    await Launch.url(context, o.paymentUrl!);
  }

  @override
  Widget build(BuildContext context) {
    final canBuy = getIt<SessionCubit>().state.can(Perm.broadcastsWrite);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Credits'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Export Credit Transaction History',
            onPressed: () async {
              final p = await showPeriodSheet(
                context,
                PeriodSel.thisMonth,
                only: const {
                  'thisMonth',
                  'lastMonth',
                  'last30Days',
                  'thisYear',
                  'custom',
                  'all',
                },
              );
              if (p == null || !context.mounted) return;
              final b = await runWithProgress(
                context,
                () => _repo.exportLedger({...p.query}),
              );
              if (b != null && context.mounted) {
                await shareBytes(context, b, 'credits.csv', 'text/csv');
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([_stats.refresh(), _ledger.reload()]);
          await getIt<SessionCubit>().refreshProfile();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            BlocBuilder<AsyncCubit<CreditStats>, AsyncState<CreditStats>>(
              bloc: _stats,
              builder: (context, st) {
                final s = st.data;
                if (s == null) {
                  return const AppCard(child: LinearProgressIndicator());
                }
                return AppCard(
                  color: s.lowBalance ? AppColors.dangerTint : null,
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.lowBalance
                            ? 'Credits left - low balance'
                            : 'Credits left',
                        style: TextStyle(
                          color: s.lowBalance
                              ? AppColors.danger
                              : AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${s.balance}',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w600,
                          color: s.lowBalance ? AppColors.danger : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Credits work across WhatsApp messages, bulk SMS, and more. 1 credit / message.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Divider(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: _Mini(
                              'Used this month',
                              '${s.usedThisMonth}',
                            ),
                          ),
                          Expanded(
                            child: _Mini(
                              'Recharged this month',
                              '${s.rechargedThisMonth}',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            if (canBuy) ...[
              const SectionTitle(
                'Recharge your credits',
                padding: EdgeInsets.fromLTRB(2, 20, 2, 4),
              ),
              Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Development catalogue + simulated payment page. No real money moves.',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ),
              BlocBuilder<
                AsyncCubit<List<CreditPack>>,
                AsyncState<List<CreditPack>>
              >(
                bloc: _packs,
                builder: (context, st) => Column(
                  children: [
                    for (final p in st.data ?? const <CreditPack>[])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: AppCard(
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${p.credits}${p.bonusCredits > 0 ? ' + ${p.bonusCredits} bonus' : ''} credits',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      p.name,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(100, 42),
                                ),
                                onPressed: () => _buy(p),
                                child: Text(Fmt.money(p.price)),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SectionTitle(
              'Recent Transactions',
              padding: EdgeInsets.fromLTRB(2, 12, 2, 8),
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final (k, l) in [
                  ('all', 'All'),
                  ('recharge', 'Credit Recharge History'),
                  ('usage', 'Credit Usage History'),
                ])
                  PillChip(
                    label: l,
                    selected: _filter == k,
                    onTap: () {
                      setState(() => _filter = k);
                      _ledger.setQuery({if (k != 'all') 'type': k});
                    },
                  ),
              ],
            ),
            const Gap(12),
            BlocBuilder<PagedCubit<LedgerEntry>, PagedState<LedgerEntry>>(
              bloc: _ledger,
              builder: (context, st) {
                if (st.items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        st.isLoading ? 'Loading…' : 'No credit activity yet',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final e in st.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AppCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      switch (e.type) {
                                        'recharge' => 'Credits recharged',
                                        'refund' => 'Credits refunded',
                                        _ => 'Credits used',
                                      },
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      '${Fmt.dateTime(e.createdAt)}${e.reference == null ? '' : ' · ${e.reference}'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${e.credits > 0 ? '+' : ''}${e.credits}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: e.credits > 0
                                      ? AppColors.success
                                      : AppColors.danger,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '${e.balanceAfter}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (st.hasMore)
                      TextButton(
                        onPressed: _ledger.loadMore,
                        child: const Text('Load more'),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      Text(
        label,
        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------------------------
class MessageHistoryScreen extends StatefulWidget {
  const MessageHistoryScreen({super.key});
  @override
  State<MessageHistoryScreen> createState() => _MessageHistoryScreenState();
}

class _MessageHistoryScreenState extends State<MessageHistoryScreen> {
  final _repo = getIt<MessagingRepository>();
  PeriodSel _period = PeriodSel.thisMonth;
  late final PagedCubit<OutboxMessage> _cubit = PagedCubit<OutboxMessage>(
    fetch: _repo.messages,
    parse: OutboxMessage.fromJson,
    pageSize: 30,
    query: {..._period.query},
  );

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Message history'),
      actions: [
        IconButton(
          icon: const Icon(Icons.file_download_outlined),
          onPressed: () async {
            final b = await runWithProgress(
              context,
              () => _repo.exportMessages({..._period.query}),
            );
            if (b != null && context.mounted) {
              await shareBytes(context, b, 'messages.csv', 'text/csv');
            }
          },
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                PeriodButton(
                  value: _period,
                  onChanged: (p) {
                    setState(() => _period = p);
                    _cubit.setQuery({...p.query});
                  },
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: InfoBanner(
              'Development outbox: messages are recorded and metered but not delivered to WhatsApp/SMS.',
              icon: Icons.developer_mode,
              warning: true,
            ),
          ),
          Expanded(
            child: PagedListBody<OutboxMessage>(
              cubit: _cubit,
              separator: 8,
              empty: const EmptyState(
                icon: Icons.mark_chat_read_outlined,
                title: 'No messages yet',
              ),
              itemBuilder: (context, m) => AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            m.memberName ?? m.to,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Tag(
                          m.status,
                          tone: m.status == 'failed'
                              ? Tone.danger
                              : Tone.neutral,
                        ),
                      ],
                    ),
                    Text(
                      m.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${Fmt.dateTime(m.createdAt)} · ${m.key} · ${m.credits} credit',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------------------------
class WhatsappIntegrationScreen extends StatefulWidget {
  const WhatsappIntegrationScreen({super.key});
  @override
  State<WhatsappIntegrationScreen> createState() =>
      _WhatsappIntegrationScreenState();
}

class _WhatsappIntegrationScreenState extends State<WhatsappIntegrationScreen> {
  final _repo = getIt<MessagingRepository>();
  late final AsyncCubit<List<Integration>> _cubit = AsyncCubit(
    _repo.integrations,
  );

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = getIt<SessionCubit>().state.can(Perm.settingsWrite);
    return Scaffold(
      appBar: AppBar(title: const Text('WhatsApp Integration')),
      body: AsyncBody<List<Integration>>(
        cubit: _cubit,
        builder: (context, list) {
          final w = list.firstWhere((i) => i.key == 'whatsapp');
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.chat,
                          color: AppColors.success,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Automated Messages',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Tag(
                          w.enabled ? 'On' : 'Off',
                          tone: w.enabled ? Tone.success : Tone.neutral,
                        ),
                      ],
                    ),
                    const Gap(8),
                    Text(
                      'Send smart automated WhatsApp messages to your members for renewals, reminders, and important updates.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const Gap(12),
                    if (canWrite)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Do you want to turn on whatsapp integration?',
                          style: TextStyle(fontSize: 14),
                        ),
                        value: w.enabled,
                        onChanged: !w.available
                            ? null
                            : (v) async {
                                final ok = await confirmDialog(
                                  context,
                                  title: v ? 'Turn on' : 'Turn off',
                                  message: v
                                      ? 'Do you want to turn on whatsapp integration?'
                                      : 'Automated messages and broadcasts will stop.',
                                  confirmLabel: v ? 'Turn on now' : 'Turn off',
                                );
                                if (ok &&
                                    context.mounted &&
                                    await runOk(
                                      context,
                                      () => _repo.setWhatsapp(v),
                                      success: v
                                          ? 'Your whatsapp account is successfully connected'
                                          : 'Integration turned off',
                                    )) {
                                  await getIt<SessionCubit>().refreshProfile();
                                  _cubit.refresh();
                                }
                              },
                      ),
                    if (!w.available)
                      Text(
                        'Not available for this gym yet.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.warning,
                        ),
                      ),
                  ],
                ),
              ),
              const Gap(12),
              if (w.provider == 'dev-outbox') ...[
                const InfoBanner(
                  'No WhatsApp provider is set up on this server, so messages are recorded in an outbox and not sent. Set the WhatsApp variables on the backend to deliver them (docs/DEPLOY.md).',
                  icon: Icons.developer_mode,
                  warning: true,
                ),
                const Gap(12),
              ],
              MenuGroup(
                children: [
                  MenuTile(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Credits',
                    onTap: () => context.push('/credits'),
                  ),
                  MenuTile(
                    icon: Icons.chat_outlined,
                    title: 'Message Templates',
                    onTap: () => context.push('/message-templates'),
                  ),
                  MenuTile(
                    icon: Icons.campaign_outlined,
                    title: 'Broadcasts',
                    onTap: () => context.push('/broadcasts'),
                  ),
                  MenuTile(
                    icon: Icons.history,
                    title: 'Message history',
                    onTap: () => context.push('/messages'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
