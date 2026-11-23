import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/router/app_router.dart';
import 'core/services/supabase_service.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/env_setup_error_screen.dart';
import 'features/auth/auth_provider.dart';
import 'features/notifications/notifications_provider.dart';
import 'features/polls/polls_provider.dart';
import 'features/timetable/timetable_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Env.isConfigured) {
    runApp(const EnvSetupErrorScreen());
    return;
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
  );

  runApp(ClassCueApp(supabaseClient: Supabase.instance.client));
}

/// Root widget for ClassCue (by KYUJUSAN 93).
class ClassCueApp extends StatefulWidget {
  const ClassCueApp({super.key, this.supabaseClient});

  final SupabaseClient? supabaseClient;

  @override
  State<ClassCueApp> createState() => _ClassCueAppState();
}

class _ClassCueAppState extends State<ClassCueApp> {
  SupabaseService? _service;
  AuthProvider? _authProvider;
  GoRouter? _router;

  @override
  void initState() {
    super.initState();
    final client = widget.supabaseClient;
    if (client != null) {
      _service = SupabaseService(client);
      _authProvider = AuthProvider(_service!);
      _router = createAppRouter(_authProvider!);
    }
  }

  @override
  void dispose() {
    _router?.dispose();
    _authProvider?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_service == null || _authProvider == null || _router == null) {
      return const EnvSetupErrorScreen();
    }

    return MultiProvider(
      providers: [
        Provider<SupabaseService>.value(value: _service!),
        ChangeNotifierProvider<AuthProvider>.value(value: _authProvider!),
        ChangeNotifierProxyProvider<AuthProvider, TimetableProvider>(
          create: (_) => TimetableProvider(_service!),
          update: (_, auth, prev) {
            final provider = prev ?? TimetableProvider(_service!);
            provider.bindProfile(auth.profile);
            return provider;
          },
        ),
        ChangeNotifierProxyProvider<AuthProvider, PollsProvider>(
          create: (_) => PollsProvider(_service!),
          update: (_, auth, prev) {
            final provider = prev ?? PollsProvider(_service!);
            provider.bindProfile(auth.profile);
            return provider;
          },
        ),
        ChangeNotifierProxyProvider<AuthProvider, NotificationsProvider>(
          create: (_) => NotificationsProvider(_service!),
          update: (_, auth, prev) {
            final provider = prev ?? NotificationsProvider(_service!);
            provider.bindProfile(auth.profile);
            return provider;
          },
        ),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'ClassCue — by KYUJUSAN 93',
        theme: AppTheme.lightTheme(),
        routerConfig: _router!,
      ),
    );
  }
}
