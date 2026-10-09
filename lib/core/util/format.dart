import 'package:intl/intl.dart';

/// Display formatting. Dates travel as `YYYY-MM-DD` (gym-local calendar dates) or ISO timestamps.
class Fmt {
  Fmt._();

  static String currencySymbol = '₹';

  static String money(num? v, {String? symbol, bool compact = false}) {
    final n = v ?? 0;
    final sym = symbol ?? currencySymbol;
    final isWhole = n == n.roundToDouble();
    final f = compact
        ? NumberFormat.compactCurrency(
            locale: 'en_IN',
            symbol: sym,
            decimalDigits: isWhole ? 0 : 1,
          )
        : NumberFormat.currency(
            locale: 'en_IN',
            symbol: sym,
            decimalDigits: isWhole ? 0 : 2,
          );
    return f.format(n);
  }

  static String number(num? v) =>
      NumberFormat.decimalPattern('en_IN').format(v ?? 0);

  static DateTime? parseDate(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  /// `03 Jan 2025`
  static String date(String? s) {
    final d = parseDate(s);
    return d == null
        ? '—'
        : DateFormat('dd MMM yyyy').format(d.toLocal().copyWith(isUtc: false));
  }

  static String dateShort(String? s) {
    final d = parseDate(s);
    return d == null ? '—' : DateFormat('dd MMM').format(d);
  }

  /// `EEE, d MMM yyyy` — pattern recovered from the app's string table.
  static String dateLong(String? s) {
    final d = parseDate(s);
    return d == null ? '—' : DateFormat('EEE, d MMM yyyy').format(d);
  }

  static String time(String? iso) {
    final d = parseDate(iso);
    return d == null ? '—' : DateFormat('h:mm a').format(d.toLocal());
  }

  static String dateTime(String? iso) {
    final d = parseDate(iso);
    return d == null
        ? '—'
        : DateFormat('dd MMM yyyy, h:mm a').format(d.toLocal());
  }

  static String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  /// `HH:MM` -> `6:00 AM`
  static String hhmm(String? t) {
    if (t == null || t.length < 5) return '—';
    final h = int.tryParse(t.substring(0, 2)) ?? 0;
    final m = t.substring(3, 5);
    final suffix = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:$m $suffix';
  }

  static String daysLeft(int? d) {
    if (d == null) return '';
    if (d < 0) return 'Expired ${-d} day${-d == 1 ? '' : 's'} ago';
    if (d == 0) return 'Expires today';
    return '$d day${d == 1 ? '' : 's'} left';
  }

  static String initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  static String plural(int n, String one, [String? many]) =>
      '$n ${n == 1 ? one : (many ?? '${one}s')}';
}
