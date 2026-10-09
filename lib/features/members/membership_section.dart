import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/format.dart';
import '../../core/util/json.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../core/widgets/sheets.dart';
import '../../data/models/finance.dart';
import '../../data/models/plans.dart';
import '../../data/repositories/members_repository.dart';

class _PayLine {
  _PayLine(this.type);
  String type;
  final amount = TextEditingController();
}

/// Plan + discount + payment inputs with a live server-side price quote.
/// Read the result with `key.currentState!.buildBody()` after `validate()`.
class MembershipSection extends StatefulWidget {
  const MembershipSection({
    super.key,
    this.memberId,
    this.kind,
    this.excludePlanId,
    this.initialPlanId,
  });

  final String? memberId;
  final String? kind; // new | renewal | upcoming
  final String? excludePlanId;
  final String? initialPlanId;

  @override
  State<MembershipSection> createState() => MembershipSectionState();
}

class MembershipSectionState extends State<MembershipSection> {
  final _plans = getIt<PlansRepository>();
  final _memberships = getIt<MembershipsRepository>();
  List<Plan>? _list;
  Object? _loadError;
  Plan? _plan;
  String? _startDate;
  String _discountType = 'amount';
  final _discount = TextEditingController();
  final _notes = TextEditingController();
  final List<_PayLine> _lines = [];
  Quote? _quote;
  String? _quoteError;
  bool _quoting = false;
  Timer? _debounce;
  String? _planError;

  @override
  void initState() {
    super.initState();
    final gym = getIt<SessionCubit>().state.profile!;
    _lines.add(
      _PayLine(
        gym.activePaymentTypes.contains(gym.defaultPaymentType)
            ? gym.defaultPaymentType
            : gym.activePaymentTypes.first,
      ),
    );
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await _plans.plans();
      if (!mounted) return;
      setState(() {
        _list = l.where((p) => p.id != widget.excludePlanId).toList();
        if (widget.initialPlanId != null) {
          _plan = _list!.where((p) => p.id == widget.initialPlanId).firstOrNull;
        }
      });
      if (_plan != null) _requote();
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _discount.dispose();
    _notes.dispose();
    for (final l in _lines) {
      l.amount.dispose();
    }
    super.dispose();
  }

  void _requote() {
    _debounce?.cancel();
    if (_plan == null) return;
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() {
        _quoting = true;
        _quoteError = null;
      });
      try {
        final v = double.tryParse(_discount.text.trim());
        final q = await _memberships.quote(
          planId: _plan!.id,
          memberId: widget.memberId,
          startDate: _startDate,
          discount: v == null || v <= 0
              ? null
              : {'type': _discountType, 'value': v},
        );
        if (mounted) setState(() => _quote = q);
      } on ApiException catch (e) {
        if (mounted) {
          setState(() {
            _quote = null;
            _quoteError = e.message;
          });
        }
      } finally {
        if (mounted) setState(() => _quoting = false);
      }
    });
  }

  double get _received => _lines.fold(
    0,
    (s, l) => s + (double.tryParse(l.amount.text.trim()) ?? 0),
  );

  /// Validates the section; shows inline errors. Returns true when the body can be built.
  bool validate() {
    var ok = true;
    if (_plan == null) {
      setState(() => _planError = 'Please select a plan');
      return false;
    }
    if (_quote == null) {
      setState(
        () => _quoteError ??= 'Waiting for the price. Please try again.',
      );
      return false;
    }
    if (_received > _quote!.total + 0.001) {
      setState(
        () => _quoteError =
            'Payment received cannot exceed total (${Fmt.money(_quote!.total)})',
      );
      ok = false;
    }
    return ok;
  }

  Json buildBody() {
    final disc = double.tryParse(_discount.text.trim());
    final pays = [
      for (final l in _lines)
        if ((double.tryParse(l.amount.text.trim()) ?? 0) > 0)
          {'paymentType': l.type, 'amount': double.parse(l.amount.text.trim())},
    ];
    return compact({
      'planId': _plan!.id,
      'startDate': _startDate,
      'discount': disc == null || disc <= 0
          ? null
          : {'type': _discountType, 'value': disc},
      'payments': pays.isEmpty ? null : pays,
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      'kind': widget.kind,
    });
  }

  Future<void> _pickPlan() async {
    final p = await showPickerSheet<Plan>(
      context,
      title: 'Select Plan',
      items: _list ?? const [],
      selected: _plan,
      labelOf: (p) => p.name,
      subtitleOf: (p) =>
          '${Fmt.money(p.price)} · ${p.durationLabel}${p.hasSessions ? ' · ${p.sessionCount} sessions' : ''}',
    );
    if (p != null) {
      setState(() {
        _plan = p;
        _planError = null;
      });
      _requote();
    }
  }

  @override
  Widget build(BuildContext context) {
    final gym = getIt<SessionCubit>().state.profile!;
    final symbol = gym.currencySymbol;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Select Plan',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
        if (_loadError != null)
          Text(
            'Failed to load plans',
            style: const TextStyle(color: AppColors.danger),
          )
        else if (_list == null)
          const LinearProgressIndicator()
        else if (_list!.isEmpty)
          const InfoBanner(
            'Create a plan first. Plans hold your price and duration.',
            warning: true,
          )
        else
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _pickPlan,
            child: InputDecorator(
              decoration: InputDecoration(
                errorText: _planError,
                suffixIcon: const Icon(Icons.keyboard_arrow_down),
              ),
              child: _plan == null
                  ? const Text(
                      'Select the plan you created.',
                      style: TextStyle(color: AppColors.textMuted),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Text(
                            _plan!.name,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        Text(
                          Fmt.money(_plan!.price),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        const Gap(16),
        DateField(
          label: 'Select Start Date',
          value: _startDate,
          hint: 'Starts after the current membership (default)',
          clearable: true,
          onChanged: (v) {
            setState(() => _startDate = v);
            _requote();
          },
        ),
        const Gap(16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: AppTextField(
                controller: _discount,
                label: 'Discount',
                hint: _discountType == 'percent'
                    ? 'Enter percentage between 1-100'
                    : 'Add a discount if needed.',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d{0,9}(\.\d{0,2})?'),
                  ),
                ],
                onChanged: (_) => _requote(),
              ),
            ),
            const SizedBox(width: 10),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'amount', label: Text(symbol)),
                const ButtonSegment(value: 'percent', label: Text('%')),
              ],
              selected: {_discountType},
              onSelectionChanged: (s) {
                setState(() => _discountType = s.first);
                _requote();
              },
            ),
          ],
        ),
        const Gap(16),
        _PriceBreakdown(
          quote: _quote,
          loading: _quoting,
          error: _quoteError,
          symbol: symbol,
        ),
        const Gap(20),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Payment',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
            if (_lines.length < 4 && gym.activePaymentTypes.length > 1)
              TextButton.icon(
                onPressed: () => setState(
                  () => _lines.add(
                    _PayLine(
                      gym.activePaymentTypes.firstWhere(
                        (t) => !_lines.any((l) => l.type == t),
                        orElse: () => gym.activePaymentTypes.first,
                      ),
                    ),
                  ),
                ),
                icon: const Icon(Icons.call_split, size: 18),
                label: const Text('Split payment method'),
              ),
          ],
        ),
        for (final (i, l) in _lines.indexed)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: AmountField(
                    controller: l.amount,
                    label: i == 0 ? 'Amount received' : 'Amount',
                    hint: '0',
                    symbol: symbol,
                    validator: (v) => (v == null || v.isEmpty)
                        ? null
                        : V.amount(v, allowZero: true),
                    onChanged: (_) => setState(() => _quoteError = null),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 4,
                  child: DropdownField<String>(
                    label: 'Payment type',
                    value: l.type,
                    items: gym.activePaymentTypes,
                    labelOf: paymentTypeLabel,
                    onChanged: (v) => setState(() => l.type = v ?? l.type),
                  ),
                ),
                if (_lines.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 28),
                    child: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _lines.removeAt(i)),
                    ),
                  ),
              ],
            ),
          ),
        if (_quote != null) ...[
          const Gap(10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Balance after this payment',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              Text(
                Fmt.money(
                  (_quote!.total - _received).clamp(0, double.infinity),
                ),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _quote!.total - _received > 0
                      ? AppColors.danger
                      : AppColors.success,
                ),
              ),
            ],
          ),
        ],
        const Gap(16),
        AppTextField(
          controller: _notes,
          label: 'Notes (optional)',
          hint: 'Add a short note',
          maxLines: 2,
          maxLength: 500,
        ),
      ],
    );
  }
}

class _PriceBreakdown extends StatelessWidget {
  const _PriceBreakdown({
    required this.quote,
    required this.loading,
    required this.error,
    required this.symbol,
  });
  final Quote? quote;
  final bool loading;
  final String? error;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return InfoBanner(error!, icon: Icons.error_outline, warning: true);
    }
    final q = quote;
    if (q == null) {
      return loading
          ? const LinearProgressIndicator()
          : const SizedBox.shrink();
    }
    Widget row(String l, String v, {bool bold = false, Color? color}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              Text(
                v,
                style: TextStyle(
                  fontSize: bold ? 16 : 13,
                  fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        );
    return AppCard(
      color: Theme.of(context).brightness == Brightness.dark
          ? null
          : const Color(0xFFF3F5FC),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Price Breakdown',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          row('Plan price', Fmt.money(q.price, symbol: symbol)),
          if (q.discountAmount > 0)
            row(
              'Discount',
              '- ${Fmt.money(q.discountAmount, symbol: symbol)}',
              color: AppColors.success,
            ),
          if (q.taxRate > 0)
            row(
              '${q.taxName ?? 'Tax'} (${q.taxRate % 1 == 0 ? q.taxRate.toInt() : q.taxRate}%${q.taxIncluded ? ', included' : ''})',
              Fmt.money(q.taxAmount, symbol: symbol),
            ),
          const Divider(height: 16),
          row('Total', Fmt.money(q.total, symbol: symbol), bold: true),
          row('Valid', '${Fmt.date(q.startDate)} → ${Fmt.date(q.endDate)}'),
        ],
      ),
    );
  }
}
