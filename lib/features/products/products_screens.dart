import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/auth/permissions.dart';
import '../../core/state/async_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/format.dart';
import '../../core/util/images.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../core/widgets/list_toolbar.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../../data/models/products.dart';
import '../../data/repositories/products_repository.dart';

/// Scans a barcode and returns its value.
Future<String?> scanBarcode(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.of(ctx).size.height * 0.7,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Scan Barcode',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: MobileScanner(
                onDetect: (c) {
                  final v = c.barcodes
                      .map((b) => b.rawValue)
                      .whereType<String>()
                      .firstOrNull;
                  if (v != null) Navigator.pop(ctx, v);
                },
                errorBuilder: (context, e) => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'The camera is unavailable. Enter or scan barcode manually.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Align barcode within the frame to scan',
              style: TextStyle(color: Theme.of(ctx).hintColor),
            ),
          ),
        ],
      ),
    ),
  );
}

String stockLabel(Product p) => !p.trackStock
    ? 'Not tracked'
    : (p.outOfStock
          ? 'Out of stock'
          : (p.lowStock
                ? 'Low stock: ${p.quantity}'
                : 'In stock: ${p.quantity}'));
Tone stockTone(Product p) => !p.trackStock
    ? Tone.neutral
    : (p.outOfStock ? Tone.danger : (p.lowStock ? Tone.warning : Tone.success));

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key, this.selectMode = false});
  final bool selectMode; // used by the sale screen to pick a product
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _repo = getIt<ProductsRepository>();
  String _q = '';
  String? _category;
  bool _low = false;
  String _sort = 'nameAsc';
  late final AsyncCubit<List<Product>> _cubit = AsyncCubit(_load);

  Future<List<Product>> _load() => _repo.list(
    q: _q.isEmpty ? null : _q,
    category: _category,
    lowStock: _low,
    sort: _sort,
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
      appBar: AppBar(
        title: Text(widget.selectMode ? 'Select Product' : 'Manage Products'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: ListToolbar(
                hint: 'Search for product name',
                onSearch: (v) {
                  _q = v;
                  _cubit.load();
                },
                onAdd: canWrite && !widget.selectMode
                    ? () async {
                        await context.push('/products/new');
                        _cubit.refresh();
                      }
                    : null,
                extra: [
                  const SizedBox(width: 8),
                  Material(
                    color: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final code = await scanBarcode(context);
                        if (code == null || !mounted) return;
                        final found = await _repo.list(barcode: code);
                        if (!context.mounted) return;
                        if (found.isEmpty) {
                          showToast(
                            context,
                            'No product has this barcode',
                            error: true,
                          );
                        } else if (widget.selectMode) {
                          context.pop(found.first);
                        } else {
                          await context.push('/products/${found.first.id}');
                          _cubit.refresh();
                        }
                      },
                      child: const SizedBox(
                        width: 52,
                        height: 52,
                        child: Icon(Icons.qr_code_scanner),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  PillChip(
                    label: 'All products',
                    selected: _category == null && !_low,
                    onTap: () {
                      _category = null;
                      _low = false;
                      _cubit.load();
                      setState(() {});
                    },
                  ),
                  for (final c in [
                    'Supplements',
                    'Beverages',
                    'Merchandise',
                    'Accessories',
                    'Other',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: PillChip(
                        label: c,
                        selected: _category == c,
                        onTap: () {
                          _category = c;
                          _low = false;
                          _cubit.load();
                          setState(() {});
                        },
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: PillChip(
                      label: 'Low stock',
                      selected: _low,
                      icon: Icons.warning_amber_rounded,
                      onTap: () {
                        _low = !_low;
                        _cubit.load();
                        setState(() {});
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: PillChip(
                      label: 'Most sold',
                      selected: _sort == 'mostSold',
                      onTap: () {
                        _sort = _sort == 'mostSold' ? 'nameAsc' : 'mostSold';
                        _cubit.load();
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AsyncBody<List<Product>>(
                cubit: _cubit,
                isEmpty: (d) => d.isEmpty,
                empty: EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'Add your first product to start tracking sales and stock',
                  actionLabel: canWrite && !widget.selectMode
                      ? 'Create Product'
                      : null,
                  onAction: () async {
                    await context.push('/products/new');
                    _cubit.refresh();
                  },
                ),
                builder: (context, list) => ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final p = list[i];
                    return AppCard(
                      padding: const EdgeInsets.all(12),
                      onTap: () async {
                        if (widget.selectMode) {
                          context.pop(p);
                        } else {
                          await context.push('/products/${p.id}');
                          _cubit.refresh();
                        }
                      },
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 56,
                              height: 56,
                              child: p.photoUrl == null
                                  ? Container(
                                      color: AppColors.chip,
                                      child: Icon(
                                        Icons.inventory_2_outlined,
                                        color: AppColors.textMuted,
                                      ),
                                    )
                                  : UserAvatarSquare(url: p.photoUrl!),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${p.category} · ${p.unitsSold} sold',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Tag(stockLabel(p), tone: stockTone(p)),
                              ],
                            ),
                          ),
                          Text(
                            Fmt.money(p.price),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UserAvatarSquare extends StatelessWidget {
  const UserAvatarSquare({super.key, required this.url});
  final String url;
  @override
  Widget build(BuildContext context) =>
      UserAvatar(name: '', url: url, radius: 28);
}

// ---------------------------------------------------------------------------------------------
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, this.productId});
  final String? productId;
  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _form = GlobalKey<FormState>();
  final _repo = getIt<ProductsRepository>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _cost = TextEditingController();
  final _barcode = TextEditingController();
  final _desc = TextEditingController();
  final _opening = TextEditingController(text: '0');
  final _threshold = TextEditingController(text: '0');
  String _category = 'Supplements';
  bool _track = false;
  PickedImage? _photo;
  bool _saving = false;
  bool _loading = false;
  late final bool _isEdit = widget.productId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final p = await _repo.get(widget.productId!);
      if (!mounted) return;
      setState(() {
        _name.text = p.name;
        _price.text = '${p.price}';
        _cost.text = p.costPrice?.toString() ?? '';
        _barcode.text = p.barcode ?? '';
        _desc.text = p.description ?? '';
        _category = p.category;
        _track = p.trackStock;
        _threshold.text = '${p.lowStockThreshold}';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _price,
      _cost,
      _barcode,
      _desc,
      _opening,
      _threshold,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        'name': _name.text.trim(),
        'category': _category,
        'price': double.parse(_price.text.trim()),
        if (_cost.text.trim().isNotEmpty)
          'costPrice': double.parse(_cost.text.trim()),
        if (_barcode.text.trim().isNotEmpty) 'barcode': _barcode.text.trim(),
        if (_desc.text.trim().isNotEmpty) 'description': _desc.text.trim(),
        'lowStockThreshold': int.tryParse(_threshold.text.trim()) ?? 0,
        if (_photo != null) 'photo': _photo!.toJson(),
      };
      if (_isEdit) {
        await _repo.update(widget.productId!, body);
      } else {
        await _repo.create({
          ...body,
          'trackStock': _track,
          if (_track) 'openingStock': int.tryParse(_opening.text.trim()) ?? 0,
        });
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
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Product')),
        body: const LoadingBox(),
      );
    }
    return FormScaffold(
      title: _isEdit ? 'Edit Product' : 'Create Product',
      formKey: _form,
      submitLabel: _isEdit ? 'Save' : 'Create Product',
      saving: _saving,
      onSubmit: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: GestureDetector(
              onTap: () async {
                final p = await pickImage(context, maxSide: 800);
                if (p != null) setState(() => _photo = p);
              },
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  color: AppColors.chip,
                  borderRadius: BorderRadius.circular(16),
                  image: _photo == null
                      ? null
                      : DecorationImage(
                          image: MemoryImage(Uint8List.fromList(_photo!.bytes)),
                          fit: BoxFit.cover,
                        ),
                ),
                child: _photo == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_a_photo_outlined,
                            color: AppColors.textMuted,
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Add product photo',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      )
                    : null,
              ),
            ),
          ),
          const Gap(20),
          AppTextField(
            controller: _name,
            label: 'Product name',
            hint: 'Enter name',
            textCapitalization: TextCapitalization.words,
            validator: (v) => V.required(v, 'Please enter a name'),
            maxLength: 100,
          ),
          const Gap(16),
          DropdownField<String>(
            label: 'Category',
            value: _category,
            items: const [
              'Supplements',
              'Beverages',
              'Merchandise',
              'Accessories',
              'Other',
            ],
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          const Gap(16),
          AmountField(
            controller: _price,
            label: 'Sale price',
            hint: 'Enter sale price',
            validator: (v) => V.amount(v, allowZero: true),
          ),
          const Gap(16),
          AmountField(
            controller: _cost,
            label: 'Cost price (optional)',
            hint: 'Enter total cost',
            validator: (v) =>
                (v == null || v.isEmpty) ? null : V.amount(v, allowZero: true),
          ),
          const Gap(16),
          AppTextField(
            controller: _barcode,
            label: 'Barcode (optional)',
            hint: 'Enter or scan barcode',
            suffix: IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () async {
                final c = await scanBarcode(context);
                if (c != null) setState(() => _barcode.text = c);
              },
            ),
          ),
          const Gap(16),
          AppTextField(
            controller: _desc,
            label: 'Description (optional)',
            hint: 'Enter a short description',
            maxLines: 2,
            maxLength: 300,
          ),
          const Gap(8),
          if (!_isEdit)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Start Stock Tracking',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Sales will check and deduct stock.',
                style: TextStyle(fontSize: 12),
              ),
              value: _track,
              onChanged: (v) => setState(() => _track = v),
            ),
          if (!_isEdit && _track)
            AppTextField(
              controller: _opening,
              label: 'Opening Stock Count',
              hint: '0',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) => V.integer(
                v,
                min: 0,
                label: 'a valid opening count (0 or more)',
              ),
            ),
          if (_track || _isEdit) ...[
            const Gap(16),
            AppTextField(
              controller: _threshold,
              label: 'Low Stock Threshold',
              hint: 'Enter minimum stock quantity',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) => V.integer(v, min: 0, label: 'a valid number'),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.productId});
  final String productId;
  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final _repo = getIt<ProductsRepository>();
  late final AsyncCubit<Product> _cubit = AsyncCubit(
    () => _repo.get(widget.productId),
  );
  late final AsyncCubit<List<StockEntry>> _history = AsyncCubit(
    () => _repo.history(widget.productId),
  );

  @override
  void dispose() {
    _cubit.close();
    _history.close();
    super.dispose();
  }

  Future<void> _act(Future<Product> Function() f, String ok) async {
    final p = await runWithProgress(context, f, success: ok);
    if (p != null) {
      _cubit.set(p);
      _history.refresh();
    }
  }

  Future<void> _receive(Product p) async {
    final qty = TextEditingController();
    final cost = TextEditingController();
    var asExpense = false;
    final key = GlobalKey<FormState>();
    final res = await showAppSheet<Map<String, dynamic>>(
      context,
      title: 'Add Stock',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Form(
          key: key,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTextField(
                controller: qty,
                label: 'Quantity',
                hint: 'Please enter a valid quantity',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) =>
                    V.integer(v, min: 1, label: 'a valid quantity'),
              ),
              const Gap(12),
              AmountField(
                controller: cost,
                label: 'Total Cost (optional)',
                hint: 'Enter total cost',
                validator: (v) => (v == null || v.isEmpty)
                    ? null
                    : V.amount(v, allowZero: true),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Log the stocking cost as an expense'),
                value: asExpense,
                onChanged: (v) => set(() => asExpense = v),
              ),
              const Gap(8),
              FilledButton(
                onPressed: () {
                  if (!key.currentState!.validate()) return;
                  final c = double.tryParse(cost.text.trim());
                  if (asExpense && (c == null || c <= 0)) {
                    showToast(
                      ctx,
                      'Stock cannot be 0 when logging as expense',
                      error: true,
                    );
                    return;
                  }
                  Navigator.pop(ctx, {
                    'q': int.parse(qty.text.trim()),
                    'c': c,
                    'e': asExpense,
                  });
                },
                child: const Text('Add Stock'),
              ),
            ],
          ),
        ),
      ),
    );
    if (res == null || !mounted) return;
    await _act(
      () => _repo.receive(
        p.id,
        res['q'] as int,
        totalCost: res['c'] as double?,
        logAsExpense: res['e'] as bool,
      ),
      'Stock added successfully',
    );
  }

  Future<void> _damage(Product p) async {
    final reasons = await _repo.damageReasons().catchError(
      (Object _) => <String>['Other'],
    );
    if (!mounted) return;
    final reason = await showPickerSheet<String>(
      context,
      title: 'Reason for damage',
      items: reasons,
      labelOf: (s) => s,
    );
    if (reason == null || !mounted) return;
    final q = await promptNumber(
      context,
      title: 'Add Damage',
      label: 'Quantity damaged',
      min: 1,
      max: p.quantity,
      confirmLabel: 'Report',
    );
    if (q == null || !mounted) return;
    await _act(
      () => _repo.damage(p.id, q, reason),
      'Damage reported successfully',
    );
  }

  Future<void> _correct(Product p) async {
    final n = await promptNumber(
      context,
      title: 'Stock correction',
      label: 'New count',
      min: 0,
      initial: p.quantity,
      confirmLabel: 'Next',
    );
    if (n == null || !mounted) return;
    final reason = await promptText(
      context,
      title: 'Reason for Stock Edit',
      hint: 'Enter reason for editing stock',
      required: true,
      maxLength: 200,
    );
    if (reason == null || !mounted) return;
    await _act(() => _repo.correct(p.id, n, reason), 'Stock corrected');
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = getIt<SessionCubit>().state.can(Perm.productsWrite);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Details'),
        actions: [
          if (canWrite)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                await context.push('/products/${widget.productId}/edit');
                _cubit.refresh();
                _history.refresh();
              },
            ),
          if (canWrite)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (!await confirmDialog(
                      context,
                      title: 'Delete Product',
                      message: 'Do you want to delete this product? This action cannot be undone.',
                      confirmLabel: 'Delete',
                      destructive: true,
                    ) ||
                    !context.mounted) {
                  return;
                }
                if (await runOk(
                      context,
                      () => _repo.delete(widget.productId),
                      success: 'Deleted',
                    ) &&
                    context.mounted) {
                  context.pop();
                }
              },
            ),
        ],
      ),
      body: AsyncBody<Product>(
        cubit: _cubit,
        builder: (context, p) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        Fmt.money(p.price),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      Tag(p.category),
                      Tag(stockLabel(p), tone: stockTone(p)),
                      Tag('${p.unitsSold} sold'),
                    ],
                  ),
                  const Divider(height: 24),
                  InfoRow(
                    'Cost price',
                    p.costPrice == null ? null : Fmt.money(p.costPrice),
                  ),
                  InfoRow('Barcode', p.barcode),
                  InfoRow(
                    'Low stock threshold',
                    p.trackStock ? '${p.lowStockThreshold}' : null,
                  ),
                  InfoRow('Description', p.description),
                ],
              ),
            ),
            if (canWrite) ...[
              const SectionTitle(
                'Stock',
                padding: EdgeInsets.fromLTRB(2, 20, 2, 8),
              ),
              if (!p.trackStock)
                FilledButton.icon(
                  onPressed: () async {
                    final n = await promptNumber(
                      context,
                      title: 'Start Stock Tracking',
                      label: 'Opening Stock Count',
                      min: 0,
                      confirmLabel: 'Start Tracking',
                    );
                    if (n != null && context.mounted) {
                      await _act(
                        () => _repo.startTracking(p.id, n),
                        'Stock tracking started',
                      );
                    }
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Stock Tracking'),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: () => _receive(p),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Stock'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: p.quantity > 0 ? () => _damage(p) : null,
                      icon: const Icon(Icons.broken_image_outlined),
                      label: const Text('Add Damage'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: () => _correct(p),
                      icon: const Icon(Icons.tune),
                      label: const Text('Correct'),
                    ),
                    TextButton(
                      onPressed: () async {
                        if (await confirmDialog(
                              context,
                              title: 'Stop Stock Tracking',
                              message: 'This will switch the product to no quantity. Sales will no longer check or deduct stock. Past stock history will be preserved.',
                              confirmLabel: 'Stop Tracking',
                            ) &&
                            context.mounted) {
                          await _act(
                            () => _repo.stopTracking(p.id),
                            'Stock tracking stopped',
                          );
                        }
                      },
                      child: const Text('Stop Tracking'),
                    ),
                  ],
                ),
            ],
            const SectionTitle(
              'Product History',
              padding: EdgeInsets.fromLTRB(2, 20, 2, 8),
            ),
            AsyncBody<List<StockEntry>>(
              cubit: _history,
              refreshable: false,
              isEmpty: (d) => d.isEmpty,
              empty: Text(
                'No stock activity yet.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              builder: (context, h) => Column(
                children: [
                  for (final e in h)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: AppCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    switch (e.type) {
                                      'opening' => 'Opening stock',
                                      'receive' => 'Stock added',
                                      'sale' => 'Sold',
                                      'sale-reversal' => 'Sale reversed',
                                      'damage' => 'Damage reported',
                                      'correction' => 'Stock corrected',
                                      'untracked' => 'Tracking stopped',
                                      _ => e.type,
                                    },
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    '${Fmt.dateTime(e.createdAt)}${e.reason == null ? '' : ' · ${e.reason}'}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${e.quantity > 0 ? '+' : ''}${e.quantity}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: e.quantity >= 0
                                    ? AppColors.success
                                    : AppColors.danger,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '→ ${e.balanceAfter}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
