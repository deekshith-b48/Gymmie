import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../app/di.dart';
import '../../core/state/async_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/files.dart';
import '../../core/util/format.dart';
import '../../core/util/invoice_pdf.dart';
import '../../core/util/launch.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/states.dart';
import '../../data/models/finance.dart';
import '../../data/repositories/finance_repository.dart';

/// Invoice view (route /invoice/:no) with PDF share and print.
class InvoiceScreen extends StatelessWidget {
  const InvoiceScreen({super.key, required this.invoiceNo});
  final String invoiceNo;

  @override
  Widget build(BuildContext context) {
    final cubit = AsyncCubit<InvoiceData>(
      () => getIt<FinanceRepository>().invoice(invoiceNo),
    );
    return Scaffold(
      appBar: AppBar(title: Text('Invoice $invoiceNo')),
      body: AsyncBody<InvoiceData>(
        cubit: cubit,
        refreshable: false,
        builder: (context, inv) {
          final sym = inv.gym['currencySymbol'] as String? ?? '₹';
          String m(num v) => Fmt.money(v, symbol: sym);
          final tax = inv.tax;
          return Column(
            children: [
              Expanded(
                child: ListView(
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
                                  '${inv.gym['name']}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const Tag('INVOICE', tone: Tone.navy),
                            ],
                          ),
                          if (inv.gym['address'] != null)
                            Text(
                              '${inv.gym['address']}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          if (inv.gym['taxNumber'] != null)
                            Text(
                              'Tax No: ${inv.gym['taxNumber']}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          const Divider(height: 24),
                          InfoRow('Invoice No', inv.invoiceNo),
                          InfoRow('Date', Fmt.date(inv.date)),
                          InfoRow(
                            'Billed to',
                            inv.member?['name'] as String? ??
                                'Walk-in customer',
                          ),
                          if (inv.member?['phone'] != null)
                            InfoRow('Phone', '${inv.member!['phone']}'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    AppCard(
                      child: Column(
                        children: [
                          for (final i in inv.items)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${i['name']}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        if (i['detail'] != null)
                                          Text(
                                            '${i['detail']}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        Text(
                                          '${i['quantity']} × ${m((i['unitPrice'] as num?) ?? 0)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    m((i['amount'] as num?) ?? 0),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const Divider(),
                          InfoRow('Subtotal', m(inv.subtotal)),
                          if (inv.discount > 0)
                            InfoRow('Discount', '- ${m(inv.discount)}'),
                          if (tax != null && ((tax['rate'] as num?) ?? 0) > 0)
                            InfoRow(
                              '${tax['name'] ?? 'Tax'} (${tax['rate']}%${tax['included'] == true ? ', included' : ''})',
                              m((tax['amount'] as num?) ?? 0),
                            ),
                          InfoRow('Total', m(inv.total), bold: true),
                          InfoRow('Received', m(inv.received)),
                          if (inv.writtenOff > 0)
                            InfoRow('Written off', m(inv.writtenOff)),
                          InfoRow(
                            'Balance due',
                            m(inv.balance),
                            bold: inv.balance > 0,
                          ),
                        ],
                      ),
                    ),
                    if (inv.payments.isNotEmpty) ...[
                      const SectionTitle(
                        'Payments',
                        padding: EdgeInsets.fromLTRB(2, 20, 2, 8),
                      ),
                      for (final p in inv.payments)
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
                                  child: Text(
                                    '${Fmt.date(p['date'] as String?)} · ${paymentTypeLabel('${p['paymentType']}')}',
                                  ),
                                ),
                                Text(
                                  m((p['amount'] as num?) ?? 0),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.success,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final bytes = await runWithProgress(
                              context,
                              () => buildInvoicePdf(inv),
                            );
                            if (bytes != null && context.mounted) {
                              await Printing.layoutPdf(
                                name: 'Invoice ${inv.invoiceNo}',
                                onLayout: (_) async => bytes,
                              );
                            }
                          },
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('Print'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            final bytes = await runWithProgress(
                              context,
                              () => buildInvoicePdf(inv),
                            );
                            if (bytes != null && context.mounted) {
                              await shareBytes(
                                context,
                                bytes,
                                'invoice-${inv.invoiceNo}.pdf',
                                'application/pdf',
                              );
                            }
                          },
                          icon: const Icon(Icons.share_outlined),
                          label: const Text('Share Invoice'),
                        ),
                      ),
                      if (inv.member?['phone'] != null) ...[
                        const SizedBox(width: 10),
                        IconButton.filledTonal(
                          onPressed: () => Launch.whatsApp(
                            context,
                            '${inv.member!['phone']}',
                            text:
                                'Invoice ${inv.invoiceNo} from ${inv.gym['name']}: total ${m(inv.total)}, received ${m(inv.received)}, balance ${m(inv.balance)}.',
                          ),
                          icon: const Icon(Icons.chat_outlined),
                          tooltip: 'Send Invoice',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
