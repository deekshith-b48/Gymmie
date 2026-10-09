import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/auth/permissions.dart';
import '../../core/state/async_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/format.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../core/widgets/period_filter.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/dialogs.dart';
import '../../data/models/finance.dart';
import '../../data/models/members.dart';
import '../../data/models/plans.dart';
import '../../data/models/products.dart';
import '../../data/repositories/finance_repository.dart';
import '../../data/repositories/members_repository.dart';
import '../../data/repositories/products_repository.dart';
import '../members/member_picker.dart';

class _Line {
  _Line(this.product, this.qty);
  final Product product;
  int qty;
}

/// Create Sale: cart + optional member + discount + payment. Totals shown are an estimate; the
/// server computes the authoritative tax and total.
class NewSaleScreen extends StatefulWidget {
  const NewSaleScreen({super.key});
  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  final _repo = getIt<ProductsRepository>();
  final _form = GlobalKey<FormState>();
  final _lines = <_Line>[];
  final _discount = TextEditingController();
  final _received = TextEditingController();
  final _guest = TextEditingController();
  MemberSummary? _member;
  String _discType = 'amount';
  late String _payType;
  TaxConfig? _tax;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final g = getIt<SessionCubit>().state.profile!;
    _payType = g.activePaymentTypes.contains(g.defaultPaymentType)
        ? g.defaultPaymentType
        : g.activePaymentTypes.first;
    getIt<PlansRepository>()
        .taxes()
        .then(
          (t) => mounted
              ? setState(() => _tax = t.where((x) => x.isDefault).firstOrNull)
              : null,
        )
        .catchError((Object _) {});
  }

  @override
  void dispose() {
    _discount.dispose();
    _received.dispose();
    _guest.dispose();
    super.dispose();
  }

  double get _subtotal => _lines.fold(0, (s, l) => s + l.product.price * l.qty);
  double get _discountAmount {
    final v = double.tryParse(_discount.text.trim()) ?? 0;
    return _discType == 'percent' ? _subtotal * v / 100 : v;
  }

  double get _net => (_subtotal - _discountAmount).clamp(0, double.infinity);
  double get _taxAmount => _tax == null
      ? 0
      : (_tax!.isIncluded
            ? _net - _net / (1 + _tax!.rate / 100)
            : _net * _tax!.rate / 100);
  double get _total =>
      _tax == null || _tax!.isIncluded ? _net : _net + _taxAmount;

  Future<void> _addProduct() async {
    final p = await context.push<Product>('/products/select');
    if (p == null) return;
    if (p.trackStock && p.quantity <= 0) {
      if (mounted) showToast(context, 'Product is out of stock', error: true);
      return;
    }
    setState(() {
      final ex = _lines.where((l) => l.product.id == p.id).firstOrNull;
      if (ex != null) {
        ex.qty++;
      } else {
        _lines.add(_Line(p, 1));
      }
    });
  }

  Future<void> _save() async {
    if (_lines.isEmpty) {
      return showToast(context, 'Please select a product', error: true);
    }
    if (!_form.currentState!.validate()) return;
    final received = double.tryParse(_received.text.trim()) ?? 0;
    if (received > _total + 0.01) {
      return showToast(
        context,
        'Payment received cannot exceed total (${Fmt.money(_total)})',
        error: true,
      );
    }
    setState(() => _saving = true);
    try {
      final sale = await _repo.createSale({
        if (_member != null)
          'memberId': _member!.id
        else if (_guest.text.trim().isNotEmpty)
          'guestName': _guest.text.trim(),
        'items': [
          for (final l in _lines)
            {'productId': l.product.id, 'quantity': l.qty},
        ],
        if ((double.tryParse(_discount.text.trim()) ?? 0) > 0)
          'discount': {
            'type': _discType,
            'value': double.parse(_discount.text.trim()),
          },
        if (received > 0)
          'payments': [
            {'paymentType': _payType, 'amount': received},
          ],
      });
      if (!mounted) return;
      showToast(context, 'Sale created successfully');
      context.pushReplacement('/invoice/${sale.invoiceNo}');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = getIt<SessionCubit>().state.profile!;
    return FormScaffold(
      title: 'Create Sale',
      formKey: _form,
      submitLabel: 'Create Sale',
      saving: _saving,
      onSubmit: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Customer',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const Gap(8),
          AppCard(
            onTap: () async {
              final m = await pickMember(context);
              if (m != null) setState(() => _member = m);
            },
            child: Row(
              children: [
                const Icon(Icons.person_outline),
                const SizedBox(width: 12),
                Expanded(
                  child: _member == null
                      ? const Text(
                          'Walk-in customer (tap to choose a member)',
                          style: TextStyle(color: AppColors.textMuted),
                        )
                      : Text(
                          _member!.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                ),
                if (_member != null)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _member = null),
                  ),
              ],
            ),
          ),
          if (_member == null) ...[
            const Gap(12),
            AppTextField(
              controller: _guest,
              label: 'Guest name (optional)',
              hint: 'Guest name',
              maxLength: 80,
            ),
          ],
          const Gap(20),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Items',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
              TextButton.icon(
                onPressed: _addProduct,
                icon: const Icon(Icons.add),
                label: const Text('Select Product'),
              ),
            ],
          ),
          if (_lines.isEmpty)
            const AppCard(
              child: Text(
                'Add at least one product.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          for (final l in _lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.product.name,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            '${Fmt.money(l.product.price)} each${l.product.trackStock ? ' · ${l.product.quantity} in stock' : ''}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => setState(
                        () => l.qty > 1 ? l.qty-- : _lines.remove(l),
                      ),
                    ),
                    Text(
                      '${l.qty}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => setState(() {
                        if (l.product.trackStock &&
                            l.qty >= l.product.quantity) {
                          showToast(
                            context,
                            'Stock limit exceeded for ${l.product.name}',
                            error: true,
                          );
                        } else {
                          l.qty++;
                        }
                      }),
                    ),
                  ],
                ),
              ),
            ),
          const Gap(12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AppTextField(
                  controller: _discount,
                  label: 'Discount',
                  hint: 'Add a discount if needed.',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d{0,9}(\.\d{0,2})?'),
                    ),
                  ],
                  onChanged: (_) => setState(() {}),
                  validator: (_) => _discountAmount > _subtotal
                      ? 'Discount cannot be greater than total price'
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'amount', label: Text(g.currencySymbol)),
                  const ButtonSegment(value: 'percent', label: Text('%')),
                ],
                selected: {_discType},
                onSelectionChanged: (s) => setState(() => _discType = s.first),
              ),
            ],
          ),
          const Gap(16),
          AppCard(
            child: Column(
              children: [
                InfoRow('Subtotal', Fmt.money(_subtotal)),
                if (_discountAmount > 0)
                  InfoRow('Discount', '- ${Fmt.money(_discountAmount)}'),
                if (_tax != null)
                  InfoRow(
                    '${_tax!.name} (${_tax!.rate}%${_tax!.isIncluded ? ', included' : ''}) — estimate',
                    Fmt.money(_taxAmount),
                  ),
                InfoRow('Total', Fmt.money(_total), bold: true),
              ],
            ),
          ),
          const Gap(16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: AmountField(
                  controller: _received,
                  label: 'Amount Received',
                  hint: Fmt.money(_total),
                  validator: (v) => (v == null || v.isEmpty)
                      ? null
                      : V.amount(v, allowZero: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 4,
                child: DropdownField<String>(
                  label: 'Payment type',
                  value: _payType,
                  items: g.activePaymentTypes,
                  labelOf: paymentTypeLabel,
                  onChanged: (v) => setState(() => _payType = v ?? _payType),
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () =>
                    setState(() => _received.text = _total.toStringAsFixed(2)),
                child: const Text('Fill full amount'),
              ),
              if (_member == null &&
                  (double.tryParse(_received.text) ?? 0) < _total - 0.01)
                const Text(
                  'Walk-in sales must be paid in full',
                  style: TextStyle(fontSize: 11, color: AppColors.warning),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  PeriodSel _period = PeriodSel.thisMonth;
  final _repo = getIt<ProductsRepository>();
  late final PagedCubit<Sale> _cubit = PagedCubit<Sale>(
    fetch: _repo.sales,
    parse: Sale.fromJson,
    query: {..._period.query},
  );

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = getIt<SessionCubit>().state.can(Perm.productsWrite);
    return Scaffold(
      appBar: AppBar(title: const Text('Sales History')),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: () async {
                await context.push('/sales/new');
                _cubit.reload();
              },
              icon: const Icon(Icons.add),
              label: const Text('Create Sale'),
            )
          : null,
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
                      _cubit.setQuery(p.query.cast<String, dynamic>());
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: PagedListBody<Sale>(
                cubit: _cubit,
                separator: 10,
                empty: const EmptyState(
                  icon: Icons.point_of_sale,
                  title: 'No sales yet',
                  message: 'Sales you create appear here.',
                ),
                itemBuilder: (context, s) => AppCard(
                  onTap: () => _open(s),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.memberName ?? s.guestName ?? 'Walk-in customer',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            Fmt.money(s.total),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.items
                            .map((i) => '${i.name} x${i.quantity}')
                            .join(', '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: [
                          Tag(Fmt.date(s.date)),
                          Tag(s.invoiceNo),
                          if (s.balance > 0)
                            Tag(
                              'Due ${Fmt.money(s.balance)}',
                              tone: Tone.danger,
                            ),
                        ],
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

  void _open(Sale s) {
    final canWrite = getIt<SessionCubit>().state.can(Perm.productsWrite);
    showAppSheet<void>(
      context,
      title: s.invoiceNo,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final i in s.items)
            InfoRow(
              '${i.name} × ${i.quantity}',
              Fmt.money(i.price * i.quantity),
            ),
          const Divider(),
          InfoRow('Total', Fmt.money(s.total), bold: true),
          InfoRow('Received', Fmt.money(s.amountReceived)),
          if (s.balance > 0) InfoRow('Balance', Fmt.money(s.balance)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              context.push('/invoice/${s.invoiceNo}');
            },
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('View Invoice'),
          ),
          if (canWrite)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: () async {
                if (!await confirmDialog(
                      ctx,
                      title: 'Delete Sale',
                      message: 'Stock is restored and the payments are removed. This action cannot be undone.',
                      confirmLabel: 'Delete',
                      destructive: true,
                    ) ||
                    !ctx.mounted) {
                  return;
                }
                if (await runOk(
                  ctx,
                  () => _repo.deleteSale(s.id),
                  success: 'Sale deleted successfully',
                )) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  _cubit.reload();
                }
              },
              child: const Text('Delete Sale'),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final _repo = getIt<FinanceRepository>();
  PeriodSel _period = PeriodSel.thisMonth;
  String? _category;
  late final PagedCubit<Expense> _cubit = PagedCubit<Expense>(
    fetch: _repo.expenses,
    parse: Expense.fromJson,
    query: {..._period.query},
  );

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  Map<String, dynamic> get _q => {
    ..._period.query,
    if (_category != null) 'category': _category,
  };

  @override
  Widget build(BuildContext context) {
    final canWrite = getIt<SessionCubit>().state.can(Perm.expensesWrite);
    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: () async {
                await context.push('/expenses/new');
                _cubit.reload();
              },
              icon: const Icon(Icons.add),
              label: const Text('Create Expense'),
            )
          : null,
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
                      _cubit.setQuery(_q);
                    },
                  ),
                  const SizedBox(width: 8),
                  FutureBuilder<List<String>>(
                    future: _repo.expenseCategories(),
                    builder: (c, s) => OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 42),
                        side: BorderSide(color: Theme.of(context).dividerColor),
                        foregroundColor: Theme.of(context)
                            .colorScheme
                            .onSurface,
                      ),
                      onPressed: s.hasData
                          ? () async {
                              final pick = await showPickerSheet<String?>(
                                context,
                                title: 'Select category',
                                items: [null, ...s.data!],
                                labelOf: (c) => c ?? 'All categories',
                                selected: _category,
                              );
                              if (pick != null || _category != null) {
                                setState(() => _category = pick);
                                _cubit.setQuery(_q);
                              }
                            }
                          : null,
                      icon: const Icon(Icons.filter_list, size: 18),
                      label: Text(
                        _category ?? 'Category',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: BlocBuilder<PagedCubit<Expense>, PagedState<Expense>>(
                bloc: _cubit,
                builder: (context, st) => Column(
                  children: [
                    if (st.meta['totalAmount'] != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: AppCard(
                          color: AppColors.dangerTint,
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Total expenses',
                                  style: TextStyle(color: AppColors.danger),
                                ),
                              ),
                              Text(
                                Fmt.money(st.meta['totalAmount'] as num),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.danger,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Expanded(
                      child: PagedListBody<Expense>(
                        cubit: _cubit,
                        separator: 10,
                        empty: const EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'No expenses',
                          message: 'Track rent, salaries, equipment and more.',
                        ),
                        itemBuilder: (context, e) => AppCard(
                          onTap: canWrite
                              ? () async {
                                  await context.push(
                                    '/expenses/${e.id}/edit',
                                    extra: e,
                                  );
                                  _cubit.reload();
                                }
                              : null,
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppColors.dangerTint,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.north_east,
                                  color: AppColors.danger,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e.title ?? e.category,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '${e.category} · ${Fmt.date(e.date)} · ${paymentTypeLabel(e.paymentType)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                Fmt.money(e.amount),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.danger,
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
            ),
          ],
        ),
      ),
    );
  }
}

class ExpenseFormScreen extends StatefulWidget {
  const ExpenseFormScreen({super.key, this.existing});
  final Expense? existing;
  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final _form = GlobalKey<FormState>();
  final _repo = getIt<FinanceRepository>();
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _amount = TextEditingController(
    text: widget.existing?.amount.toString(),
  );
  late final _notes = TextEditingController(text: widget.existing?.notes);
  late final _vendor = TextEditingController(text: widget.existing?.vendor);
  late String? _category = widget.existing?.category;
  late String? _date = widget.existing?.date ?? Fmt.ymd(DateTime.now());
  late String _pay =
      widget.existing?.paymentType ??
      getIt<SessionCubit>().state.profile!.defaultPaymentType;
  List<String> _categories = const [];
  bool _saving = false;
  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _repo
        .expenseCategories()
        .then((c) => mounted ? setState(() => _categories = c) : null)
        .catchError((Object _) {});
  }

  @override
  void dispose() {
    for (final c in [_title, _amount, _notes, _vendor]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_category == null) {
      return showToast(context, 'Please select a category', error: true);
    }
    if (!_form.currentState!.validate()) return;
    final ok = await confirmDialog(
      context,
      title: _isEdit ? 'Edit Expense' : 'Create Expense',
      message: _isEdit
          ? 'Would you like to update this expense?'
          : 'Would you like to create this expense?',
      confirmLabel: 'Confirm',
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      final body = {
        'category': _category,
        'amount': double.parse(_amount.text.trim()),
        'date': _date,
        'paymentType': _pay,
        if (_title.text.trim().isNotEmpty) 'title': _title.text.trim(),
        if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
        if (_vendor.text.trim().isNotEmpty) 'vendor': _vendor.text.trim(),
      };
      if (_isEdit) {
        await _repo.updateExpense(widget.existing!.id, body);
      } else {
        await _repo.createExpense(body);
      }
      if (!mounted) return;
      showToast(
        context,
        _isEdit ? 'Edited successfully' : 'Added successfully',
      );
      context.pop(true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = getIt<SessionCubit>().state.profile!;
    return FormScaffold(
      title: _isEdit ? 'Edit Expense' : 'Create Expense',
      formKey: _form,
      submitLabel: _isEdit ? 'Save' : 'Create expense',
      saving: _saving,
      onSubmit: _save,
      secondary: _isEdit
          ? OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
              ),
              onPressed: () async {
                if (!await confirmDialog(
                      context,
                      title: 'Delete Expense',
                      message: 'This action cannot be undone',
                      confirmLabel: 'Delete',
                      destructive: true,
                    ) ||
                    !context.mounted) {
                  return;
                }
                if (await runOk(
                      context,
                      () => _repo.deleteExpense(widget.existing!.id),
                      success: 'Expense deleted successfully',
                    ) &&
                    context.mounted) {
                  context.pop(true);
                }
              },
              child: const Text('Delete'),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownField<String>(
            label: 'Category name',
            value: _category,
            items: {..._categories, ?_category}.toList(),
            hint: 'Select category',
            onChanged: (v) => setState(() => _category = v),
          ),
          TextButton.icon(
            onPressed: () async {
              final c = await promptText(
                context,
                title: 'New category',
                label: 'Category name',
                hint: 'Enter category',
                required: true,
                maxLength: 60,
              );
              if (c != null) {
                setState(() {
                  _categories = [..._categories, c];
                  _category = c;
                });
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('Add category'),
          ),
          const Gap(8),
          AppTextField(
            controller: _title,
            label: 'Title (optional)',
            hint: 'Enter your title',
            maxLength: 100,
          ),
          const Gap(16),
          AmountField(
            controller: _amount,
            label: 'Amount',
            hint: 'Enter amount',
            symbol: g.currencySymbol,
          ),
          const Gap(16),
          DateField(
            label: 'Date',
            value: _date,
            lastDate: DateTime.now(),
            required: true,
            onChanged: (v) => setState(() => _date = v),
          ),
          const Gap(16),
          DropdownField<String>(
            label: 'Payment type',
            value: _pay,
            items: g.activePaymentTypes.contains(_pay)
                ? g.activePaymentTypes
                : [...g.activePaymentTypes, _pay],
            labelOf: paymentTypeLabel,
            onChanged: (v) => setState(() => _pay = v ?? _pay),
          ),
          const Gap(16),
          AppTextField(
            controller: _vendor,
            label: 'Vendor (optional)',
            hint: 'Who was paid',
            maxLength: 100,
          ),
          const Gap(16),
          AppTextField(
            controller: _notes,
            label: 'Notes (optional)',
            hint: 'Add a short note',
            maxLines: 2,
            maxLength: 500,
          ),
        ],
      ),
    );
  }
}
