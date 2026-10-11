/// Route paths. Names follow the route strings recovered from the original app where known
/// (e.g. `/new-member`, `/edit-member`, `/lead-member-list`, `/gym-selection`).
abstract final class R {
  static const splash = '/splash';
  static const backendSetup = '/backend-setup';
  static const maintenance = '/maintenance';
  static const updateRequired = '/update-required';
  static const login = '/login';
  static const loginOtp = '/login/otp';
  static const register = '/register';
  static const gymSetup = '/gym-setup';
  static const gymSelection = '/gym-selection';
  static const expiredGym = '/expired-gym';
  static const unauthorized = '/unauthorized';
  static const walkthrough = '/walkthrough';
  static const paymentIntro = '/payment-intro';
  static const memberLogin = '/member-login';

  static const home = '/home';
  static const members = '/members';
  static const reports = '/reports';
  static const transactions = '/transactions';
  static const settings = '/settings';
}
