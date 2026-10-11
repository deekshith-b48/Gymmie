import 'dart:typed_data';

import '../../../data/models/user_gym.dart' show OtpChallenge;
import '../member_models.dart';

/// The member's gym-side data (membership, visits, assigned plans). `MemberRepository` implements it;
/// tests use a fake. Each call falls back to the last answer when the phone is offline.
abstract class MemberGymApi {
  Future<MemberProfile> profile();
  Future<AttendanceSummary> attendance({int days = 90});
  Future<AssignedPlans> plans();

  /// Whether this gym takes online payments (it connected its own payment account).
  Future<bool> paymentsOnline();

  /// A secure link to pay the member's own balance (or [amount] of it). Needs the network.
  Future<String> paymentLink({double? amount});

  // ---- account (reads fall back to the last answer offline; every write needs the network and throws when offline) ----

  Future<MemberAccount> account();

  /// Sends only what changed; a `null` value clears the field. Returns the saved account.
  Future<MemberAccount> updateAccount(Map<String, dynamic> changes);
  Future<Uint8List?> photo();
  Future<MemberAccount> setPhoto(Uint8List bytes, String contentType);
  Future<MemberAccount> removePhoto();

  /// Step 1 of a phone change: a code is sent to the NEW number.
  Future<OtpChallenge> requestPhoneChange(String phone);

  /// Step 2: the number changes and this member's other phones are signed out.
  Future<String> verifyPhoneChange(String requestId, String otp);

  Future<List<DeviceSession>> sessions();
  Future<void> endSession(String id);
  Future<void> endOtherSessions();

  Future<OtpChallenge> requestDeleteCode();
  Future<void> deleteAccount({required String requestId, required String otp});

  Future<List<MembershipRequest>> requests();
  Future<MembershipRequest> createRequest({required String type, String? planId, String? note});
  Future<void> withdrawRequest(String id);

  Future<PrivacySettings> privacy();
  Future<PrivacySettings> setPrivacy({Map<String, bool>? trainerCanSee, String? shareTraining});
  Future<NotificationSettings> notifications();
  Future<NotificationSettings> setNotifications({bool? announcements, bool? expiryOn, int? expiryDaysBefore});
}
