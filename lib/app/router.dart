import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/config/app_config.dart';
import '../core/widgets/states.dart';
import '../features/auth/backend_setup_screen.dart';
import '../features/auth/gym_selection_screen.dart';
import '../features/auth/gym_setup_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/otp_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/attendance/attendance_screen.dart';
import '../features/attendance/scan_screen.dart';
import '../data/models/fitness.dart';
import '../features/engagement/engagement_screens.dart';
import '../features/fitness/diet_screens.dart';
import '../features/health/parq_screens.dart';
import '../features/fitness/exercises_screen.dart';
import '../features/fitness/workout_screens.dart';
import '../features/leads/lead_convert_screen.dart';
import '../features/leads/lead_form_screen.dart';
import '../features/leads/leads_screen.dart';
import '../features/members/at_risk_screen.dart';
import '../features/members/member_detail_screen.dart';
import '../features/members/member_form_screen.dart';
import '../features/members/members_screen.dart';
import '../features/members/renew_screen.dart';
import '../data/models/messaging.dart';
import '../features/messaging/broadcast_screens.dart';
import '../features/messaging/messaging_screens.dart';
import '../features/plans/plans_screen.dart';
import '../features/products/products_screens.dart';
import '../features/products/sales_screens.dart';
import '../features/reports/reports_screen.dart';
import '../features/settings/settings_pages.dart';
import '../features/settings/settings_screen.dart';
import '../features/transactions/balance_screens.dart';
import '../features/transactions/invoice_screen.dart';
import '../features/transactions/transactions_screen.dart';
import '../features/staff/staff_screens.dart';
import '../features/staff/trainer_screens.dart';
import '../features/system/system_screens.dart';
import '../data/models/finance.dart';
import 'di.dart';
import 'routes.dart';
import 'session_cubit.dart';
import 'shell.dart';

/// Bridges a bloc stream to go_router's `refreshListenable`.
class _Refresh extends ChangeNotifier {
  _Refresh(Stream<dynamic> s) {
    _sub = s.listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _sub;
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

const _publicRoutes = {R.login, R.loginOtp, R.register, R.backendSetup};

String? _redirect(SessionCubit session, AppConfig config, GoRouterState st) {
  final loc = st.matchedLocation;
  final s = session.state;
  if (!config.isConfigured) {
    return loc == R.backendSetup ? null : R.backendSetup;
  }
  if (loc == R.backendSetup) return null; // always reachable (developer tools)
  if (s.status == SessionStatus.booting) {
    return loc == R.splash ? null : R.splash;
  }
  if (s.status == SessionStatus.signedOut) {
    return _publicRoutes.contains(loc) ? null : R.login;
  }
  // signed in
  if (s.bootError != null) return loc == R.splash ? null : R.splash;
  if (s.settings.maintenanceMode) {
    return loc == R.maintenance ? null : R.maintenance;
  }
  if (!s.hasGym) {
    // One gym and no error: the profile is still loading, so keep showing the splash instead of the picker.
    if (s.gyms.length == 1 && s.profileError == null) {
      return loc == R.splash ? null : R.splash;
    }
    if (loc == R.gymSetup || loc == R.gymSelection) return null;
    return s.gyms.isEmpty ? R.gymSetup : R.gymSelection;
  }
  if (s.subscriptionExpired) {
    final allowed =
        loc == R.expiredGym ||
        loc == R.gymSelection ||
        loc.startsWith('/settings/subscription') ||
        loc == R.gymSetup;
    return allowed ? null : R.expiredGym;
  }
  if (_publicRoutes.contains(loc) ||
      loc == R.splash ||
      loc == R.maintenance ||
      loc == R.expiredGym) {
    return R.home;
  }
  return null;
}

GoRouter buildRouter() {
  final session = getIt<SessionCubit>();
  final config = getIt<AppConfig>();
  final nav = GlobalKey<NavigatorState>();
  return GoRouter(
    navigatorKey: nav,
    initialLocation: R.splash,
    refreshListenable: _Refresh(session.stream),
    redirect: (context, st) => _redirect(session, config, st),
    errorBuilder: (context, st) => Scaffold(
      appBar: AppBar(),
      body: const EmptyState(
        icon: Icons.explore_off_outlined,
        title: 'Page not found',
        message: 'This screen does not exist.',
      ),
    ),
    routes: [
      GoRoute(path: R.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(
        path: R.backendSetup,
        builder: (_, _) => const BackendSetupScreen(),
      ),
      GoRoute(
        path: R.maintenance,
        builder: (_, _) => const MaintenanceScreen(),
      ),
      GoRoute(
        path: R.updateRequired,
        builder: (_, _) => const UpdateRequiredScreen(),
      ),
      GoRoute(
        path: R.unauthorized,
        builder: (_, _) => const UnauthorizedScreen(),
      ),
      GoRoute(path: R.expiredGym, builder: (_, _) => const ExpiredGymScreen()),
      GoRoute(path: R.login, builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: R.loginOtp,
        redirect: (_, st) => st.extra is OtpArgs ? null : R.login,
        builder: (_, st) => OtpScreen(args: st.extra as OtpArgs),
      ),
      GoRoute(path: R.register, builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: R.gymSetup,
        builder: (_, st) =>
            GymSetupScreen(addAnother: st.uri.queryParameters['add'] == '1'),
      ),
      GoRoute(
        path: R.gymSelection,
        builder: (_, _) => const GymSelectionScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: R.home, builder: (_, _) => const DashboardScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: R.members,
                builder: (_, st) => MembersScreen(
                  initialStatus: st.uri.queryParameters['status'],
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: R.reports,
                builder: (_, _) => const ReportsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: R.transactions,
                builder: (_, st) => TransactionsScreen(
                  memberId: st.uri.queryParameters['memberId'],
                ),
                routes: [
                  GoRoute(
                    path: 'balance',
                    builder: (_, _) => const BalanceScreen(),
                  ),
                  GoRoute(
                    path: 'reminders',
                    builder: (_, _) => const RemindersScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: R.settings,
                builder: (_, _) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(path: '/feedback', builder: (_, _) => const FeedbackScreen()),
      GoRoute(
        path: '/video-links',
        builder: (_, _) => const VideoLinksScreen(),
      ),
      GoRoute(path: '/biometrics', builder: (_, _) => const BiometricsScreen()),
      GoRoute(path: '/poster', builder: (_, _) => const PosterScreen()),
      GoRoute(
        path: '/parq-form-builder',
        builder: (_, _) => const ParqBuilderScreen(),
      ),
      GoRoute(
        path: '/members/:id/parq',
        builder: (_, st) =>
            MemberParqScreen(memberId: st.pathParameters['id']!),
      ),
      // ---- workout / diet / exercises ----
      GoRoute(
        path: '/workout-plans',
        builder: (_, _) => const WorkoutPlansScreen(),
      ),
      GoRoute(
        path: '/workout-plans/new',
        builder: (_, _) => const WorkoutEditorScreen(),
      ),
      GoRoute(
        path: '/workout-plans/generate',
        builder: (_, st) =>
            GenerateWorkoutScreen(memberId: st.uri.queryParameters['memberId']),
      ),
      GoRoute(
        path: '/workout-plans/review',
        redirect: (_, st) => st.extra is WorkoutPlan ? null : '/workout-plans',
        builder: (_, st) => WorkoutEditorScreen(
          draft: st.extra as WorkoutPlan,
          memberId: st.uri.queryParameters['memberId'],
        ),
      ),
      GoRoute(
        path: '/workout-plans/:id',
        builder: (_, st) =>
            WorkoutEditorScreen(planId: st.pathParameters['id']),
      ),
      GoRoute(path: '/diet-plans', builder: (_, _) => const DietPlansScreen()),
      GoRoute(
        path: '/diet-plans/new',
        builder: (_, _) => const DietEditorScreen(),
      ),
      GoRoute(
        path: '/diet-plans/generate',
        builder: (_, st) =>
            GenerateDietScreen(memberId: st.uri.queryParameters['memberId']),
      ),
      GoRoute(
        path: '/diet-plans/review',
        redirect: (_, st) => st.extra is DietPlan ? null : '/diet-plans',
        builder: (_, st) => DietEditorScreen(
          draft: st.extra as DietPlan,
          memberId: st.uri.queryParameters['memberId'],
        ),
      ),
      GoRoute(
        path: '/diet-plans/:id',
        builder: (_, st) => DietEditorScreen(planId: st.pathParameters['id']),
      ),
      GoRoute(path: '/exercises', builder: (_, _) => const ExercisesScreen()),
      GoRoute(
        path: '/exercises/select',
        builder: (_, _) => const ExercisesScreen(selectMode: true),
      ),
      GoRoute(
        path: '/members/:id/workout',
        builder: (_, st) =>
            WorkoutEditorScreen(memberId: st.pathParameters['id']),
      ),
      GoRoute(
        path: '/members/:id/diet',
        builder: (_, st) => DietEditorScreen(memberId: st.pathParameters['id']),
      ),
      // ---- messaging ----
      GoRoute(path: '/broadcasts', builder: (_, _) => const BroadcastsScreen()),
      GoRoute(
        path: '/broadcasts/new',
        builder: (_, _) => const BroadcastFormScreen(),
      ),
      GoRoute(
        path: '/broadcasts/:id',
        builder: (_, st) => BroadcastDetailScreen(id: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/broadcasts/:id/edit',
        redirect: (_, st) => st.extra is Broadcast ? null : '/broadcasts',
        builder: (_, st) =>
            BroadcastFormScreen(existing: st.extra as Broadcast),
      ),
      GoRoute(
        path: '/message-templates',
        builder: (_, _) => const MessageTemplatesScreen(),
      ),
      GoRoute(path: '/credits', builder: (_, _) => const CreditsScreen()),
      GoRoute(
        path: '/messages',
        builder: (_, _) => const MessageHistoryScreen(),
      ),
      GoRoute(
        path: '/whatsapp',
        builder: (_, _) => const WhatsappIntegrationScreen(),
      ),
      // ---- products, sales, expenses ----
      GoRoute(path: '/products', builder: (_, _) => const ProductsScreen()),
      GoRoute(
        path: '/products/select',
        builder: (_, _) => const ProductsScreen(selectMode: true),
      ),
      GoRoute(
        path: '/products/new',
        builder: (_, _) => const ProductFormScreen(),
      ),
      GoRoute(
        path: '/products/:id',
        builder: (_, st) =>
            ProductDetailScreen(productId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/products/:id/edit',
        builder: (_, st) =>
            ProductFormScreen(productId: st.pathParameters['id']),
      ),
      GoRoute(path: '/sales', builder: (_, _) => const SalesScreen()),
      GoRoute(path: '/sales/new', builder: (_, _) => const NewSaleScreen()),
      GoRoute(path: '/expenses', builder: (_, _) => const ExpensesScreen()),
      GoRoute(
        path: '/expenses/new',
        builder: (_, _) => const ExpenseFormScreen(),
      ),
      GoRoute(
        path: '/expenses/:id/edit',
        redirect: (_, st) => st.extra is Expense ? null : '/expenses',
        builder: (_, st) => ExpenseFormScreen(existing: st.extra as Expense),
      ),
      // ---- staff & trainers ----
      GoRoute(path: '/staff', builder: (_, _) => const StaffScreen()),
      GoRoute(path: '/staff/new', builder: (_, _) => const StaffFormScreen()),
      GoRoute(
        path: '/staff/:id/edit',
        redirect: (_, st) => st.extra is StaffMember ? null : '/staff',
        builder: (_, st) => StaffFormScreen(existing: st.extra as StaffMember),
      ),
      GoRoute(
        path: '/trainer/schedule',
        builder: (_, _) => const TrainerScheduleScreen(),
      ),
      GoRoute(
        path: '/trainer/hours',
        builder: (_, _) => const WorkingHoursScreen(),
      ),
      GoRoute(
        path: '/trainer/book',
        builder: (_, st) =>
            AddBookingScreen(trainerId: st.uri.queryParameters['trainerId']),
      ),
      // ---- plans ----
      GoRoute(path: '/plans', builder: (_, _) => const PlansScreen()),
      GoRoute(path: '/plans/new', builder: (_, _) => const PlanFormScreen()),
      GoRoute(
        path: '/plans/groups',
        builder: (_, _) => const PlanGroupsScreen(),
      ),
      GoRoute(
        path: '/plans/:id/edit',
        builder: (_, st) => PlanFormScreen(planId: st.pathParameters['id']),
      ),
      // ---- attendance ----
      GoRoute(path: '/attendance', builder: (_, _) => const AttendanceScreen()),
      GoRoute(
        path: '/attendance/scan',
        builder: (_, _) => const QrAttendanceScreen(),
      ),
      // ---- leads ----
      GoRoute(path: '/leads', builder: (_, _) => const LeadsScreen()),
      GoRoute(path: '/leads/new', builder: (_, _) => const LeadFormScreen()),
      GoRoute(
        path: '/leads/:id/edit',
        builder: (_, st) => LeadFormScreen(leadId: st.pathParameters['id']),
      ),
      GoRoute(
        path: '/leads/:id/convert',
        builder: (_, st) => LeadConvertScreen(leadId: st.pathParameters['id']!),
      ),
      // ---- finance ----
      GoRoute(
        path: '/invoice/:no',
        builder: (_, st) => InvoiceScreen(invoiceNo: st.pathParameters['no']!),
      ),
      // ---- settings & account ----
      GoRoute(
        path: '/settings/gym',
        builder: (_, _) => const GymDetailsScreen(),
      ),
      GoRoute(path: '/settings/tax', builder: (_, _) => const TaxScreen()),
      GoRoute(
        path: '/settings/payment-methods',
        builder: (_, _) => const PaymentMethodsScreen(),
      ),
      GoRoute(
        path: '/settings/features',
        builder: (_, _) => const FeaturesScreen(),
      ),
      GoRoute(
        path: '/settings/preferences',
        builder: (_, _) => const PreferencesScreen(),
      ),
      GoRoute(
        path: '/settings/language',
        builder: (_, _) => const LanguageScreen(),
      ),
      GoRoute(path: '/settings/theme', builder: (_, _) => const ThemeScreen()),
      GoRoute(
        path: '/settings/timezone',
        builder: (_, _) => const TimezoneScreen(),
      ),
      GoRoute(path: '/settings/upi', builder: (_, _) => const UpiScreen()),
      GoRoute(
        path: '/settings/subscription',
        builder: (_, _) => const SubscriptionScreen(),
      ),
      GoRoute(
        path: '/settings/support',
        builder: (_, _) => const SupportScreen(),
      ),
      GoRoute(path: '/settings/dev', builder: (_, _) => const DevToolsScreen()),
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
      // ---- members ----
      GoRoute(
        path: '/members/blood-donors',
        builder: (_, _) => const BloodDonorsScreen(),
      ),
      GoRoute(
        path: '/members/new',
        builder: (_, _) => const MemberFormScreen(),
      ),
      GoRoute(
        path: '/members/at-risk',
        builder: (_, _) => const AtRiskScreen(),
      ),
      GoRoute(
        path: '/members/:id',
        builder: (_, st) =>
            MemberDetailScreen(memberId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/members/:id/edit',
        builder: (_, st) => MemberFormScreen(memberId: st.pathParameters['id']),
      ),
      GoRoute(
        path: '/members/:id/renew',
        builder: (_, st) => RenewScreen(
          memberId: st.pathParameters['id']!,
          kind: st.uri.queryParameters['kind'] ?? 'renewal',
        ),
      ),
      GoRoute(
        path: '/members/:id/upgrade/:membershipId',
        builder: (_, st) => RenewScreen(
          memberId: st.pathParameters['id']!,
          kind: 'new',
          upgradeFromId: st.pathParameters['membershipId'],
        ),
      ),
    ],
  );
}
