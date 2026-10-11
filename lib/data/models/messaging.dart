import '../../core/util/json.dart';

class Broadcast {
  const Broadcast({
    required this.id,
    required this.name,
    required this.body,
    required this.status,
    required this.recipientCount,
    required this.creditsReserved,
    this.scheduleAt,
    this.sentAt,
    required this.createdAt,
    this.delivered,
    this.failed,
    this.recipients = const [],
    this.filter = const {},
    this.excludeMemberIds = const [],
  });
  final String id;
  final String name;
  final String body;
  final String status; // scheduled | sent | cancelled
  final int recipientCount;
  final int creditsReserved;
  final String? scheduleAt;
  final String? sentAt;
  final String createdAt;
  final int? delivered;
  final int? failed;
  final List<({String id, String name, String? phone})> recipients;
  final Json filter;
  final List<String> excludeMemberIds;

  factory Broadcast.fromJson(Json j) => Broadcast(
    id: j.s('id'),
    name: j.s('name'),
    body: j.s('body'),
    status: j.s('status'),
    recipientCount: j.i('recipientCount'),
    creditsReserved: j.i('creditsReserved'),
    scheduleAt: j.str('scheduleAt'),
    sentAt: j.str('sentAt'),
    createdAt: j.s('createdAt'),
    delivered: j.intOrNull('delivered'),
    failed: j.intOrNull('failed'),
    recipients: [
      for (final r in j.list('recipients'))
        (id: r.s('id'), name: r.s('name'), phone: r.str('phone')),
    ],
    filter: j.obj('filter') ?? const {},
    excludeMemberIds: j.strings('excludeMemberIds'),
  );
}

class RecipientPreview {
  const RecipientPreview({
    required this.count,
    required this.creditsRequired,
    required this.balance,
    required this.tooMany,
    this.optedOut = 0,
  });
  final int count;
  final int creditsRequired;
  final int balance;
  final bool tooMany;

  /// Members the filter would reach who switched promotions off in the member app (they are not counted).
  final int optedOut;
  factory RecipientPreview.fromJson(Json j) => RecipientPreview(
    count: j.i('count'),
    creditsRequired: j.i('creditsRequired'),
    balance: j.i('balance'),
    tooMany: j.b('tooMany'),
    optedOut: j.i('optedOut'),
  );
}

class NotificationTemplate {
  const NotificationTemplate({
    required this.key,
    required this.title,
    required this.body,
    required this.isCustom,
    required this.auto,
    required this.defaultBody,
  });
  final String key;
  final String title;
  final String body;
  final bool isCustom;
  final bool auto;
  final String defaultBody;
  factory NotificationTemplate.fromJson(Json j) => NotificationTemplate(
    key: j.s('key'),
    title: j.s('title'),
    body: j.s('body'),
    isCustom: j.b('isCustom'),
    auto: j.b('auto'),
    defaultBody: j.s('defaultBody'),
  );
}

class BroadcastTemplate {
  const BroadcastTemplate({
    required this.id,
    required this.title,
    required this.body,
  });
  final String id;
  final String title;
  final String body;
  factory BroadcastTemplate.fromJson(Json j) =>
      BroadcastTemplate(id: j.s('id'), title: j.s('title'), body: j.s('body'));
}

class CreditStats {
  const CreditStats({
    required this.balance,
    required this.costPerMessage,
    required this.usedThisMonth,
    required this.rechargedThisMonth,
    required this.lowBalance,
  });
  final int balance;
  final int costPerMessage;
  final int usedThisMonth;
  final int rechargedThisMonth;
  final bool lowBalance;
  factory CreditStats.fromJson(Json j) => CreditStats(
    balance: j.i('balance'),
    costPerMessage: j.i('costPerMessage', 1),
    usedThisMonth: j.i('usedThisMonth'),
    rechargedThisMonth: j.i('rechargedThisMonth'),
    lowBalance: j.b('lowBalance'),
  );
}

class CreditPack {
  const CreditPack({
    required this.id,
    required this.name,
    required this.credits,
    required this.bonusCredits,
    required this.price,
  });
  final String id;
  final String name;
  final int credits;
  final int bonusCredits;
  final double price;
  factory CreditPack.fromJson(Json j) => CreditPack(
    id: j.s('id'),
    name: j.s('name'),
    credits: j.i('credits'),
    bonusCredits: j.i('bonusCredits'),
    price: j.d('price'),
  );
}

class LedgerEntry {
  const LedgerEntry({
    required this.type,
    required this.credits,
    required this.balanceAfter,
    this.reference,
    required this.createdAt,
  });
  final String type; // recharge | usage | refund
  final int credits;
  final int balanceAfter;
  final String? reference;
  final String createdAt;
  factory LedgerEntry.fromJson(Json j) => LedgerEntry(
    type: j.s('type'),
    credits: j.i('credits'),
    balanceAfter: j.i('balanceAfter'),
    reference: j.str('reference'),
    createdAt: j.s('createdAt'),
  );
}

class OutboxMessage {
  const OutboxMessage({
    required this.id,
    required this.to,
    this.memberName,
    required this.key,
    required this.body,
    required this.status,
    required this.credits,
    required this.createdAt,
  });
  final String id;
  final String to;
  final String? memberName;
  final String key;
  final String body;
  final String status;
  final int credits;
  final String createdAt;
  factory OutboxMessage.fromJson(Json j) => OutboxMessage(
    id: j.s('id'),
    to: j.s('to'),
    memberName: j.str('memberName'),
    key: j.s('key'),
    body: j.s('body'),
    status: j.s('status'),
    credits: j.i('credits'),
    createdAt: j.s('createdAt'),
  );
}

class Integration {
  const Integration({
    required this.key,
    required this.name,
    required this.enabled,
    required this.status,
    required this.provider,
    required this.available,
  });
  final String key;
  final String name;
  final bool enabled;
  final String status;
  final String provider;
  final bool available;
  factory Integration.fromJson(Json j) => Integration(
    key: j.s('key'),
    name: j.s('name'),
    enabled: j.b('enabled'),
    status: j.s('status'),
    provider: j.s('provider'),
    available: j.b('available'),
  );
}
