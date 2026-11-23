import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import 'mobile_shell_frame.dart';

/// Developer setup fallback rendered whenever `SUPABASE_URL` or `SUPABASE_ANON_KEY`
/// was not supplied via `--dart-define-from-file=env.json`.
class EnvSetupErrorScreen extends StatelessWidget {
  const EnvSetupErrorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ClassCue — Setup Required',
      theme: AppTheme.lightTheme(),
      home: MobileShellFrame(
        child: Scaffold(
          backgroundColor: AppTheme.surfaceTint,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Center(
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: AppTheme.pendingStyle.background,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.pendingStyle.border),
                      ),
                      child: Icon(
                        Icons.settings_suggest_rounded,
                        size: 32,
                        color: AppTheme.pendingStyle.foreground,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Supabase Environment Required',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.inkPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'ClassCue could not read SUPABASE_URL and SUPABASE_ANON_KEY from compile-time defines.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: AppTheme.secondarySlate,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Developer Setup Steps',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.inkPrimary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            '1. Copy env.json.example to env.json in the project root (env.json is git-ignored and must never be committed).',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.inkPrimary,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '2. Fill in your Supabase project SUPABASE_URL and SUPABASE_ANON_KEY.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.inkPrimary,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '3. Launch locally in Chrome with:',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.inkPrimary,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const SelectableText(
                              'flutter run -d chrome --dart-define-from-file=env.json',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: Color(0xFFE2E8F0),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'ClassCue — by KYUJUSAN 93 · Goa Business School, Goa University',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: AppTheme.inkMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
