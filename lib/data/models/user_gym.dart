import 'dart:convert';

import 'package:flutter/services.dart';

import '../../core/util/json.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.language = 'en',
    this.timezone,
    this.phoneVerified = false,
    this.emailVerified = false,
    this.photoUrl,
  });

  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String language;
  final String? timezone;
  final bool phoneVerified;
  final bool emailVerified;
  final String? photoUrl;

  factory AppUser.fromJson(Json j) => AppUser(
    id: j.s('id'),
    name: j.s('name'),
    phone: j.str('phone'),
    email: j.str('email'),
    language: j.s('language', 'en'),
    timezone: j.str('timezone'),
    phoneVerified: j.b('phoneVerified'),
    emailVerified: j.b('emailVerified'),
    photoUrl: j.str('photoUrl'),
  );
}

class GymBrief {
  const GymBrief({
    required this.id,
    required this.code,
    required this.name,
    this.city,
    this.logoUrl,
    this.timezone = 'Asia/Kolkata',
    this.currencySymbol = '₹',
    required this.role,
    this.subscriptionPlan,
    this.subscriptionStatus,
    this.subscriptionEndsAt,
  });

  final String id;
  final String code;
  final String name;
  final String? city;
  final String? logoUrl;
  final String timezone;
  final String currencySymbol;
  final String role;
  final String? subscriptionPlan;
  final String? subscriptionStatus;
  final String? subscriptionEndsAt;

  factory GymBrief.fromJson(Json j) {
    final sub = j.obj('subscription');
    return GymBrief(
      id: j.s('id'),
      code: j.s('code'),
      name: j.s('name'),
      city: j.str('city'),
      logoUrl: j.str('logoUrl'),
      timezone: j.s('timezone', 'Asia/Kolkata'),
      currencySymbol: j.s('currencySymbol', '₹'),
      role: j.s('role', 'staff'),
      subscriptionPlan: sub?.str('plan'),
      subscriptionStatus: sub?.str('status'),
      subscriptionEndsAt: sub?.str('endsAt'),
    );
  }
}

class Subscription {
  const Subscription({
    required this.plan,
    required this.status,
    this.startsAt,
    this.endsAt,
    this.limits = const {},
  });

  final String plan;
  final String status; // active | expired | none
  final String? startsAt;
  final String? endsAt;
  final Map<String, int> limits;

  bool get expired => status == 'expired';

  factory Subscription.fromJson(Json j) => Subscription(
    plan: j.s('plan'),
    status: j.s('status', 'active'),
    startsAt: j.str('startsAt'),
    endsAt: j.str('endsAt'),
    limits: {
      for (final e in (j.obj('limits') ?? {}).entries)
        e.key: (e.value as num).toInt(),
    },
  );
}

class FeatureDef {
  const FeatureDef({
    required this.key,
    required this.name,
    required this.description,
    required this.visible,
    required this.adminEnabled,
    required this.defaultEnabled,
    required this.category,
  });

  final String key;
  final String name;
  final String description;
  final bool visible;
  final bool adminEnabled;
  final bool defaultEnabled;
  final String category;

  factory FeatureDef.fromJson(Json j) => FeatureDef(
    key: j.s('key'),
    name: j.s('name'),
    description: j.s('description'),
    visible: j.b('visible'),
    adminEnabled: j.b('adminEnabled'),
    defaultEnabled: j.b('defaultEnabled'),
    category: j.s('category'),
  );
}

/// Feature switches recovered from the original app (`assets/feature_flags_data.json`).
class FeatureCatalog {
  FeatureCatalog(this.defs);

  final List<FeatureDef> defs;

  static Future<FeatureCatalog> load() async {
    final raw = await rootBundle.loadString('assets/feature_flags_data.json');
    return FeatureCatalog([
      for (final e in jsonDecode(raw) as List)
        FeatureDef.fromJson((e as Map).cast<String, dynamic>()),
    ]);
  }

  FeatureDef? byKey(String key) {
    for (final d in defs) {
      if (d.key == key) return d;
    }
    return null;
  }
}

abstract final class Feat {
  static const memberHealth = 'MEMBER_HEALTH';
  static const whatsapp = 'WHATSAPP_INTEGRATION';
  static const tax = 'TAX_INFORMATION';
  static const localization = 'LOCALIZATION';
  static const aiInsights = 'AI_INSIGHTS';
  static const quickReports = 'QUICK_REPORTS';
  static const poster = 'POSTER_TEMPLATE';
  static const aiWorkouts = 'AI_WORKOUTS';
  static const riskMembers = 'RISK_MEMBERS';
  static const sales = 'SALES';
  static const renewalSound = 'RENEWAL_SOUND';
  static const simpleCard = 'SIMPLE_MEMBER_CARD';
  static const upiQr = 'GYM_UPI_QR';
  static const diet = 'DIET_PLANS';
  static const workout = 'WORKOUT_PLANS';
}

class GymProfile {
  const GymProfile({
    required this.id,
    required this.code,
    required this.name,
    this.address = '',
    this.city,
    this.state,
    this.pincode,
    this.country = 'IN',
    this.phone,
    this.email,
    this.timezone = 'Asia/Kolkata',
    this.currencyCode = 'INR',
    this.currencySymbol = '₹',
    this.upiId,
    this.logoUrl,
    this.simpleMemberCard = false,
    this.renewalSound = false,
    this.activePaymentTypes = const ['cash'],
    this.defaultPaymentType = 'cash',
    this.features = const {},
    required this.role,
    this.onboardingCompleted = false,
    this.subscription,
    this.whatsappEnabled = false,
    this.whatsappStatus = 'disconnected',
    this.creditBalance = 0,
  });

  final String id;
  final String code;
  final String name;
  final String address;
  final String? city;
  final String? state;
  final String? pincode;
  final String country;
  final String? phone;
  final String? email;
  final String timezone;
  final String currencyCode;
  final String currencySymbol;
  final String? upiId;
  final String? logoUrl;
  final bool simpleMemberCard;
  final bool renewalSound;
  final List<String> activePaymentTypes;
  final String defaultPaymentType;
  final Map<String, bool> features;
  final String role;
  final bool onboardingCompleted;
  final Subscription? subscription;
  final bool whatsappEnabled;
  final String whatsappStatus;
  final int creditBalance;

  bool feature(String key, [FeatureCatalog? catalog]) =>
      features[key] ?? catalog?.byKey(key)?.defaultEnabled ?? false;

  factory GymProfile.fromJson(Json j) {
    final prefs = j.obj('preferences') ?? const {};
    final pm = j.obj('paymentMethods') ?? const {};
    final feats = j.obj('features') ?? const {};
    final wa = j.obj('whatsapp') ?? const {};
    final sub = j.obj('subscription');
    return GymProfile(
      id: j.s('id'),
      code: j.s('code'),
      name: j.s('name'),
      address: j.s('address'),
      city: j.str('city'),
      state: j.str('state'),
      pincode: j.str('pincode'),
      country: j.s('country', 'IN'),
      phone: j.str('phone'),
      email: j.str('email'),
      timezone: j.s('timezone', 'Asia/Kolkata'),
      currencyCode: j.s('currencyCode', 'INR'),
      currencySymbol: j.s('currencySymbol', '₹'),
      upiId: j.str('upiId'),
      logoUrl: j.str('logoUrl'),
      simpleMemberCard: prefs.b('simpleMemberCard'),
      renewalSound: prefs.b('renewalSound'),
      activePaymentTypes: pm.strings('active').isEmpty
          ? const ['cash']
          : pm.strings('active'),
      defaultPaymentType: pm.s('default', 'cash'),
      features: {for (final e in feats.entries) e.key: e.value == true},
      role: j.s('role', 'staff'),
      onboardingCompleted: j.b('onboardingCompleted'),
      subscription: sub == null ? null : Subscription.fromJson(sub),
      whatsappEnabled: wa.b('enabled'),
      whatsappStatus: wa.s('status', 'disconnected'),
      creditBalance: j.i('creditBalance'),
    );
  }
}

class OtpChallenge {
  const OtpChallenge({
    required this.requestId,
    required this.expiresIn,
    required this.resendIn,
    this.maskedTarget,
    this.devOtp,
    this.channel = 'sms',
  });

  final String requestId;
  final int expiresIn;
  final int resendIn;
  final String? maskedTarget;
  final String? devOtp;
  final String channel;

  factory OtpChallenge.fromJson(Json j) => OtpChallenge(
    requestId: j.s('requestId'),
    expiresIn: j.i('expiresIn', 600),
    resendIn: j.i('resendIn', 30),
    maskedTarget: j.str('maskedTarget'),
    devOtp: j.str('devOtp'),
    channel: j.s('channel', 'sms'),
  );
}

class AuthResult {
  const AuthResult({
    required this.user,
    required this.gyms,
    this.isNewUser = false,
    this.nextStep,
  });

  final AppUser user;
  final List<GymBrief> gyms;
  final bool isNewUser;
  final String? nextStep;
}

class AppSettings {
  const AppSettings({
    this.maintenanceMode = false,
    this.minimumAppVersion = '0.0.0',
    this.minimumSuggestedAppVersion = '0.0.0',
    this.helpCenterUrl,
    this.companyWhatsappNumber,
    this.devOtpEnabled = false,
    this.environment,
  });

  final bool maintenanceMode;
  final String minimumAppVersion;
  final String minimumSuggestedAppVersion;
  final String? helpCenterUrl;
  final String? companyWhatsappNumber;
  final bool devOtpEnabled;
  final String? environment;

  factory AppSettings.fromJson(Json j) {
    final be = j.obj('backend') ?? const {};
    return AppSettings(
      maintenanceMode: j.b('maintenanceMode'),
      minimumAppVersion: j.s('minimumAppVersion', '0.0.0'),
      minimumSuggestedAppVersion: j.s('minimumSuggestedAppVersion', '0.0.0'),
      helpCenterUrl: j.str('helpCenterUrl'),
      companyWhatsappNumber: j.str('companyWhatsappNumber'),
      devOtpEnabled: be.b('devOtpEnabled'),
      environment: be.str('environment'),
    );
  }
}

/// Compares dotted version strings (`1.9.4` vs `1.10.0`).
int compareVersions(String a, String b) {
  List<int> p(String s) => s
      .split('.')
      .map((e) => int.tryParse(e.replaceAll(RegExp(r'\D'), '')) ?? 0)
      .toList();
  final x = p(a), y = p(b);
  for (var i = 0; i < 3; i++) {
    final c = (i < x.length ? x[i] : 0).compareTo(i < y.length ? y[i] : 0);
    if (c != 0) return c;
  }
  return 0;
}
