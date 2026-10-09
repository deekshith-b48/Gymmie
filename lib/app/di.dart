import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/storage/token_store.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/dashboard_repository.dart';
import '../data/repositories/finance_repository.dart';
import '../data/repositories/extras_repository.dart';
import '../data/repositories/fitness_repository.dart';
import '../data/repositories/gym_repository.dart';
import '../data/repositories/leads_repository.dart';
import '../data/repositories/members_repository.dart';
import '../data/repositories/messaging_repository.dart';
import '../data/repositories/products_repository.dart';
import '../data/repositories/trainer_repository.dart';
import 'session_cubit.dart';
import 'settings_cubit.dart';

final getIt = GetIt.instance;

/// Registers singletons. Safe to call once at start-up; tests may call [resetDependencies] first.
Future<void> configureDependencies() async {
  final prefs = await SharedPreferences.getInstance();
  final config = AppConfig(prefs);
  final tokens = TokenStore(const FlutterSecureStorage(), prefs);
  final api = ApiClient(config: config, tokens: tokens);

  getIt
    ..registerSingleton<SharedPreferences>(prefs)
    ..registerSingleton<AppConfig>(config)
    ..registerSingleton<TokenStore>(tokens)
    ..registerSingleton<ApiClient>(api)
    ..registerSingleton<AuthRepository>(AuthRepository(api, tokens))
    ..registerSingleton<DashboardRepository>(DashboardRepository(api))
    ..registerSingleton<MembersRepository>(MembersRepository(api))
    ..registerSingleton<MembershipsRepository>(MembershipsRepository(api))
    ..registerSingleton<PlansRepository>(PlansRepository(api))
    ..registerSingleton<FinanceRepository>(FinanceRepository(api))
    ..registerSingleton<AttendanceRepository>(AttendanceRepository(api))
    ..registerSingleton<StaffRepository>(StaffRepository(api))
    ..registerSingleton<GymRepository>(GymRepository(api))
    ..registerSingleton<LeadsRepository>(LeadsRepository(api))
    ..registerSingleton<FitnessRepository>(FitnessRepository(api))
    ..registerSingleton<ExtrasRepository>(ExtrasRepository(api))
    ..registerSingleton<MessagingRepository>(MessagingRepository(api))
    ..registerSingleton<ProductsRepository>(ProductsRepository(api))
    ..registerSingleton<TrainerRepository>(TrainerRepository(api))
    ..registerSingleton<SettingsCubit>(SettingsCubit(prefs))
    ..registerSingleton<SessionCubit>(
      SessionCubit(getIt<AuthRepository>(), tokens, api),
    );
}

Future<void> resetDependencies() => getIt.reset();
