import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import 'auth_provider.dart';

/// Account & Profile bottom sheet allowing safe least-privilege `full_name` update + Sign Out.
class ProfileSheet extends StatefulWidget {
  const ProfileSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => const ProfileSheet(),
    );
  }

  @override
  State<ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<ProfileSheet> {
  late final TextEditingController _nameCtrl;
  bool _saving = false;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    final profile = context.read<AuthProvider>().profile;
    _nameCtrl = TextEditingController(text: profile?.fullName ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final trimmed = _nameCtrl.text.trim();
    if (trimmed.isEmpty) {
      setState(() => _feedback = 'Display name cannot be empty.');
      return;
    }
    setState(() {
      _saving = true;
      _feedback = null;
    });
    final auth = context.read<AuthProvider>();
    final ok = await auth.updateFullName(trimmed);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _feedback = ok
          ? 'Display name updated.'
          : (auth.error ?? 'Could not update name.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final profile = auth.profile;
    final cohort = auth.userCohort;
    if (profile == null) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.cardBorder,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppTheme.primaryIndigo.withValues(alpha: 0.12),
                child: Text(
                  profile.fullName.isNotEmpty
                      ? profile.fullName[0].toUpperCase()
                      : 'U',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: AppTheme.primaryIndigo,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.fullName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.inkPrimary,
                      ),
                    ),
                    Text(
                      profile.email,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              RoleBadge(profile: profile, cohort: cohort),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              InfoPill(label: 'Role: ${profile.roleDisplayLabel}'),
              if (cohort != null) InfoPill(label: cohort.name),
              if (profile.isStudent)
                InfoPill(label: 'Lab Batch: ${profile.labBatch}'),
              if (profile.facultyType != null)
                InfoPill(label: 'Faculty: ${profile.facultyType}'),
              if (profile.facultyCode != null)
                InfoPill(label: 'Code: ${profile.facultyCode}'),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Display Name',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.inkPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Your display name',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _saving ? null : _saveName,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Protected fields (role, cohort, lab batch) are managed by the programme admin via database RLS.',
            style: TextStyle(fontSize: 11.5, color: AppTheme.inkMuted),
          ),
          if (_feedback != null) ...[
            const SizedBox(height: 8),
            Text(
              _feedback!,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: _feedback == 'Display name updated.'
                    ? AppTheme.scheduledStyle.foreground
                    : AppTheme.cancelledStyle.foreground,
              ),
            ),
          ],
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              Navigator.of(context).pop();
              await auth.signOut();
            },
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Sign Out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.cancelledStyle.foreground,
              side: BorderSide(color: AppTheme.cancelledStyle.border),
            ),
          ),
        ],
      ),
    );
  }
}
