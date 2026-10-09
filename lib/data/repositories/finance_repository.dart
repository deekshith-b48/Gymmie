import 'dart:typed_data';

import '../../core/network/api_client.dart';
import '../../core/util/json.dart';
import '../models/finance.dart';

class FinanceRepository {
  FinanceRepository(this._api);
  final ApiClient _api;

  Future<ApiResponse> transactions(int page, int limit, Json q) => _api.get(
    '/v5/members/transactions',
    query: {...q, 'page': page, 'limit': limit},
  );
  Future<Uint8List> exportTransactions(Json q) =>
      _api.bytes('/v5/members/transactions/export', query: q);
  Future<void> deleteTransaction(String id) async =>
      _api.delete('/v5/members/transactions/$id');
  Future<BalanceSummary> balance() async => BalanceSummary.fromJson(
    (await _api.get('/v5/members/transactions/balance')).map,
  );

  Future<({double settled, double remaining})> settle(
    String memberId, {
    double? amount,
    String? paymentType,
    List<Json>? payments,
    String? notes,
  }) async {
    final r = (await _api.post(
      '/v5/members/transactions/settle',
      body: compact({
        'memberId': memberId,
        'amount': amount,
        'paymentType': paymentType,
        'payments': payments,
        'notes': notes,
      }),
    )).map;
    return (settled: r.d('settled'), remaining: r.d('remainingBalance'));
  }

  Future<double> writeOff(String memberId, {String? reason}) async =>
      (await _api.post(
        '/v5/members/transactions/write-off',
        body: compact({'memberId': memberId, 'reason': reason}),
      )).map.d('writtenOff');

  Future<InvoiceData> invoice(String invoiceNo) async =>
      InvoiceData((await _api.get('/v5/invoices/$invoiceNo')).map);

  // ---- balance reminders ----
  Future<List<BalanceReminder>> reminders({bool done = false}) async =>
      (await _api.get(
        '/v5/balance-reminder',
        query: {'done': done ? 'true' : null},
      )).list.map(BalanceReminder.fromJson).toList();
  Future<void> createReminder(
    String memberId,
    String date, {
    String? notes,
  }) async => _api.post(
    '/v5/balance-reminder',
    body: compact({'memberId': memberId, 'reminderDate': date, 'notes': notes}),
  );
  Future<void> updateReminder(String id, {String? date, String? notes}) async =>
      _api.patch(
        '/v5/balance-reminder/$id',
        body: compact({'reminderDate': date, 'notes': notes}),
      );
  Future<void> markReminderDone(String id) async =>
      _api.post('/v5/balance-reminder/$id/done');
  Future<void> deleteReminder(String id) async =>
      _api.delete('/v5/balance-reminder/$id');

  // ---- expenses ----
  Future<ApiResponse> expenses(int page, int limit, Json q) =>
      _api.get('/v5/expenses', query: {...q, 'page': page, 'limit': limit});
  Future<List<String>> expenseCategories() async =>
      (await _api.get('/v5/expenses/categories')).stringList;
  Future<Expense> createExpense(Json body) async =>
      Expense.fromJson((await _api.post('/v5/expenses', body: body)).map);
  Future<Expense> updateExpense(String id, Json body) async =>
      Expense.fromJson((await _api.patch('/v5/expenses/$id', body: body)).map);
  Future<void> deleteExpense(String id) async =>
      _api.delete('/v5/expenses/$id');
}

class AttendanceRepository {
  AttendanceRepository(this._api);
  final ApiClient _api;

  Future<ApiResponse> logs(int page, int limit, Json q) =>
      _api.get('/v5/attendance', query: {...q, 'page': page, 'limit': limit});
  Future<AttendanceLog> mark(
    String memberId, {
    String? at,
    bool allowExpired = false,
  }) async => AttendanceLog.fromJson(
    (await _api.post(
      '/v5/attendance/mark',
      body: compact({
        'memberId': memberId,
        'at': at,
        'allowExpired': allowExpired ? true : null,
      }),
    )).map,
  );
  Future<AttendanceLog> markByQr(String payload) async =>
      AttendanceLog.fromJson(
        (await _api.post(
          '/v5/attendance/mark-by-qr',
          body: {'payload': payload},
        )).map,
      );
  Future<void> addGuest(String name, {String? phone}) async => _api.post(
    '/v5/attendance/guest',
    body: compact({'guestName': name, 'guestPhone': phone}),
  );
  Future<void> checkout(String id) async =>
      _api.post('/v5/attendance/$id/checkout');
  Future<void> delete(String id) async => _api.delete('/v5/attendance/$id');
  Future<Uint8List> export(Json q) =>
      _api.bytes('/v5/attendance/export', query: q);
}

class StaffRepository {
  StaffRepository(this._api);
  final ApiClient _api;

  Future<List<StaffMember>> staff({String? role}) async => (await _api.get(
    '/v5/gyms/staffs',
    query: {'role': role},
  )).list.map(StaffMember.fromJson).toList();
  Future<StaffMember> create({
    required String name,
    required String phone,
    required String role,
    String? email,
  }) async => StaffMember.fromJson(
    (await _api.post(
      '/v5/gyms/staffs',
      body: compact({
        'name': name,
        'phone': phone,
        'role': role,
        'email': email,
      }),
    )).map,
  );
  Future<StaffMember> update(String userId, Json body) async =>
      StaffMember.fromJson(
        (await _api.patch('/v5/gyms/staffs/$userId', body: body)).map,
      );
  Future<void> delete(String userId) async =>
      _api.delete('/v5/gyms/staffs/$userId');
  Future<void> resendInvite(String userId) async =>
      _api.post('/v5/gyms/staffs/$userId/resend-invite');
  Future<List<StaffMember>> trainers() async =>
      (await _api.get('/v5/trainers')).list.map(StaffMember.fromJson).toList();
}
