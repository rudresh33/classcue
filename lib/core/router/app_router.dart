import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_provider.dart';
import '../../features/auth/login_screen.dart';
import '../../features/shell/role_shell_screen.dart';
import '../widgets/mobile_shell_frame.dart';

/// Creates the application `GoRouter` listening to `AuthProvider` for automatic
/// sign-in/sign-out redirection and role-specific home routes.
GoRouter createAppRouter(AuthProvider authProvider) {
  String homePathForRole(String role) {
    switch (role) {
      case 'student':
        return '/student';
      case 'cr':
        return '/cr';
      case 'faculty':
        return '/faculty';
      case 'admin':
        return '/admin';
      default:
        return '/student';
    }
  }

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: authProvider,
    redirect: (context, state) {
      final loc = state.matchedLocation;

      if (authProvider.isInitializing) {
        return loc == '/splash' ? null : '/splash';
      }

      if (!authProvider.isAuthenticated) {
        return loc == '/login' ? null : '/login';
      }

      final targetHome = homePathForRole(authProvider.profile!.role);
      if (loc == '/login' || loc == '/splash' || loc != targetHome) {
        return targetHome;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const MobileShellFrame(
          child: Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text('Loading ClassCue...'),
                ],
              ),
            ),
          ),
        ),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/student',
        builder: (context, state) => const RoleShellScreen(roleKey: 'student'),
      ),
      GoRoute(
        path: '/cr',
        builder: (context, state) => const RoleShellScreen(roleKey: 'cr'),
      ),
      GoRoute(
        path: '/faculty',
        builder: (context, state) => const RoleShellScreen(roleKey: 'faculty'),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const RoleShellScreen(roleKey: 'admin'),
      ),
    ],
  );
}
