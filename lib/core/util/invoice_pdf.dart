import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/models/finance.dart';
import '../util/format.dart';

/// Renders an invoice as a PDF. Poppins is embedded because the built-in PDF fonts have no ₹ glyph.
Future<Uint8List> buildInvoicePdf(InvoiceData inv) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Poppins-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Poppins-SemiBold.ttf'),
  );
  final doc = pw.Document(
    title: 'Invoice ${inv.invoiceNo}',
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );
  final sym = inv.gym['currencySymbol'] as String? ?? '₹';
  String m(num v) => Fmt.money(v, symbol: sym);
  final navy = PdfColor.fromInt(0xFF061750);
  final grey = PdfColor.fromInt(0xFF5B6478);

  pw.Widget kv(String k, String v, {bool strong = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(k, style: pw.TextStyle(color: grey, fontSize: 10)),
        pw.Text(
          v,
          style: pw.TextStyle(
            fontSize: strong ? 13 : 10,
            fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ],
    ),
  );

  final tax = inv.tax;
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  inv.gym['name'] as String? ?? '',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: navy,
                  ),
                ),
                if (inv.gym['address'] != null)
                  pw.SizedBox(
                    width: 260,
                    child: pw.Text(
                      '${inv.gym['address']}',
                      style: pw.TextStyle(fontSize: 9, color: grey),
                    ),
                  ),
                if (inv.gym['phone'] != null)
                  pw.Text(
                    '${inv.gym['phone']}',
                    style: pw.TextStyle(fontSize: 9, color: grey),
                  ),
                if (inv.gym['taxNumber'] != null)
                  pw.Text(
                    'Tax No: ${inv.gym['taxNumber']}',
                    style: pw.TextStyle(fontSize: 9, color: grey),
                  ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'INVOICE',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: navy,
                  ),
                ),
                pw.Text(
                  'Invoice No: ${inv.invoiceNo}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
                pw.Text(
                  'Date: ${Fmt.date(inv.date)}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Billed to',
                style: pw.TextStyle(fontSize: 9, color: grey),
              ),
              pw.Text(
                inv.member?['name'] as String? ?? 'Walk-in customer',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (inv.member?['phone'] != null)
                pw.Text(
                  '${inv.member!['phone']}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              if (inv.member?['admissionNo'] != null)
                pw.Text(
                  'Member ID #${inv.member!['admissionNo']}',
                  style: pw.TextStyle(fontSize: 9, color: grey),
                ),
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: ['Item', 'Qty', 'Price', 'Amount'],
          data: [
            for (final i in inv.items)
              [
                '${i['name']}${i['detail'] != null ? '\n${i['detail']}' : ''}',
                '${i['quantity']}',
                m((i['unitPrice'] as num?) ?? 0),
                m((i['amount'] as num?) ?? 0),
              ],
          ],
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
            fontSize: 10,
          ),
          headerDecoration: pw.BoxDecoration(color: navy),
          cellStyle: const pw.TextStyle(fontSize: 10),
          cellAlignments: {
            1: pw.Alignment.centerRight,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
          },
          columnWidths: {
            0: const pw.FlexColumnWidth(5),
            1: const pw.FlexColumnWidth(1),
            2: const pw.FlexColumnWidth(2),
            3: const pw.FlexColumnWidth(2),
          },
        ),
        pw.SizedBox(height: 12),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(
            width: 230,
            child: pw.Column(
              children: [
                kv('Subtotal', m(inv.subtotal)),
                if (inv.discount > 0) kv('Discount', '- ${m(inv.discount)}'),
                if (tax != null && ((tax['rate'] as num?) ?? 0) > 0)
                  kv(
                    '${tax['name'] ?? 'Tax'} (${tax['rate']}%${tax['included'] == true ? ' incl.' : ''})',
                    m((tax['amount'] as num?) ?? 0),
                  ),
                pw.Divider(color: PdfColors.grey400),
                kv('Total', m(inv.total), strong: true),
                kv('Received', m(inv.received)),
                if (inv.writtenOff > 0) kv('Written off', m(inv.writtenOff)),
                kv('Balance due', m(inv.balance), strong: inv.balance > 0),
              ],
            ),
          ),
        ),
        if (inv.payments.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          pw.Text(
            'Payments',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
          ),
          for (final p in inv.payments)
            pw.Text(
              '${Fmt.date(p['date'] as String?)}  ·  ${paymentTypeLabel('${p['paymentType']}')}  ·  ${m((p['amount'] as num?) ?? 0)}',
              style: const pw.TextStyle(fontSize: 10),
            ),
        ],
        pw.Spacer(),
        pw.Center(
          child: pw.Text(
            'Thank you for choosing ${inv.gym['name']}. Powered by Gymmie.',
            style: pw.TextStyle(fontSize: 9, color: grey),
          ),
        ),
      ],
    ),
  );
  return doc.save();
}
