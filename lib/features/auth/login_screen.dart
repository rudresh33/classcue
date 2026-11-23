import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import 'auth_provider.dart';

class _DemoAccount {
  const _DemoAccount({
    required this.label,
    required this.roleTag,
    required this.email,
  });

  final String label;
  final String roleTag;
  final String email;
}

const List<_DemoAccount> _demoAccounts = [
  _DemoAccount(
    label: 'Aarav Naik (Sem VII · B1)',
    roleTag: 'Student',
    email: 'student.b1@classcue.app',
  ),
  _DemoAccount(
    label: 'Priya Naik (Sem VII · B2)',
    roleTag: 'Student',
    email: 'student.b2@classcue.app',
  ),
  _DemoAccount(
    label: 'Nisha Kamat (Sem IX · B1)',
    roleTag: 'Student',
    email: 'student.sem9@classcue.app',
  ),
  _DemoAccount(
    label: 'Meera Desai (Sem VII)',
    roleTag: 'CR',
    email: 'cr.sem7@classcue.app',
  ),
  _DemoAccount(
    label: 'Mr. Dnyandev Khadapkar (IMC-703)',
    roleTag: 'Faculty',
    email: 'dnyandev@classcue.app',
  ),
  _DemoAccount(
    label: 'Dr. Teja Khandolkar (IMC-702)',
    roleTag: 'Faculty',
    email: 'teja@classcue.app',
  ),
  _DemoAccount(
    label: 'Mr. Venkatesh Prabhu (IMC-704)',
    roleTag: 'Faculty',
    email: 'venkatesh@classcue.app',
  ),
  _DemoAccount(
    label: 'Dr. Madhusudhan Lanjewar (IMC-716 IoT)',
    roleTag: 'Faculty',
    email: 'madhusudhan@classcue.app',
  ),
  _DemoAccount(
    label: 'GBS Programme Admin',
    roleTag: 'Admin',
    email: 'admin@classcue.app',
  ),
];

/// Login screen with clean email/password fields and collapsible Quick Demo Accounts picker
/// (pre-fills ONLY the email address; never hardcodes passwords).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _showDemoPicker = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    await auth.signIn(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
    );
  }

  void _selectDemoEmail(_DemoAccount account) {
    setState(() {
      _emailCtrl.text = account.email;
      _showDemoPicker = false;
    });
    context.read<AuthProvider>().clearError();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return MobileShellFrame(
      child: Scaffold(
        backgroundColor: AppTheme.surfaceTint,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                // Brand mark
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3730A3), Color(0xFF4F46E5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryIndigo.withValues(alpha: 0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.event_available_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'ClassCue',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.inkPrimary,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'by KYUJUSAN 93 · Goa Business School, Goa University',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.inkMuted,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Verified lecture status, conflict-free rescheduling & classroom alerts in real time.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.secondarySlate,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),

                // Sign-in card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Sign in to your campus account',
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.inkPrimary,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Email Address',
                              hintText: 'name@classcue.app',
                              prefixIcon: Icon(Icons.mail_outline_rounded),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Enter your email address';
                              }
                              if (!v.contains('@')) {
                                return 'Enter a valid email address';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: _obscurePassword,
                            autofillHints: const [AutofillHints.password],
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                              ),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'Show password'
                                    : 'Hide password',
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Enter your password';
                              }
                              return null;
                            },
                          ),
                          if (auth.error != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.cancelledStyle.background,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppTheme.cancelledStyle.border,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    size: 17,
                                    color: AppTheme.cancelledStyle.foreground,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      auth.error!,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color:
                                            AppTheme.cancelledStyle.foreground,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: auth.isBusy ? null : _submit,
                            child: auth.isBusy
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Sign In'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Collapsible Quick Demo Accounts picker (pre-fills ONLY email)
                Card(
                  child: Column(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () =>
                            setState(() => _showDemoPicker = !_showDemoPicker),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 13,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.people_outline_rounded,
                                size: 19,
                                color: AppTheme.primaryIndigo,
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Quick Demo Accounts',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.inkPrimary,
                                      ),
                                    ),
                                    Text(
                                      'Pre-fills email only — enter password manually',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: AppTheme.inkMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                _showDemoPicker
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                                color: AppTheme.inkMuted,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_showDemoPicker) ...[
                        const Divider(height: 1),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _demoAccounts.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final acc = _demoAccounts[index];
                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 2,
                              ),
                              title: Text(
                                acc.label,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.inkPrimary,
                                ),
                              ),
                              subtitle: Text(
                                acc.email,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppTheme.inkMuted,
                                ),
                              ),
                              trailing: InfoPill(label: acc.roleTag),
                              onTap: () => _selectDemoEmail(acc),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                const Text(
                  'IMC-704 · Design Thinking & Data-Driven App Development',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: AppTheme.inkMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
