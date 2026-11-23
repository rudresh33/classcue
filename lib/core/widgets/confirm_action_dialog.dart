import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Key/value summary line for the mandatory Pre-Publish Confirmation Dialog.
class ConfirmationDetailRow {
  const ConfirmationDetailRow({
    required this.label,
    required this.value,
    this.strikethroughOldValue,
    this.highlightColor,
  });

  final String label;
  final String value;
  final String? strikethroughOldValue;
  final Color? highlightColor;
}

/// Mandatory Error-Prevention confirmation dialog (Nielsen #5).
class ConfirmActionDialog extends StatelessWidget {
  const ConfirmActionDialog({
    super.key,
    required this.title,
    required this.subtitle,
    required this.rows,
    required this.confirmLabel,
    this.confirmColor,
    this.warningText,
  });

  final String title;
  final String subtitle;
  final List<ConfirmationDetailRow> rows;
  final String confirmLabel;
  final Color? confirmColor;
  final String? warningText;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<ConfirmationDetailRow> rows,
    required String confirmLabel,
    Color? confirmColor,
    String? warningText,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ConfirmActionDialog(
        title: title,
        subtitle: subtitle,
        rows: rows,
        confirmLabel: confirmLabel,
        confirmColor: confirmColor,
        warningText: warningText,
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (confirmColor ?? AppTheme.primaryIndigo).withValues(
                alpha: 0.12,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.fact_check_outlined,
              size: 20,
              color: confirmColor ?? AppTheme.primaryIndigo,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.inkMuted,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceTint,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < rows.length; i++) ...[
                    if (i > 0) const Divider(height: 14),
                    Text(
                      rows[i].label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (rows[i].strikethroughOldValue != null) ...[
                      Text(
                        rows[i].strikethroughOldValue!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.inkMuted,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                    Text(
                      rows[i].value,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: rows[i].highlightColor ?? AppTheme.inkPrimary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (warningText != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFCD34D)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: Color(0xFFB45309),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        warningText!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF92400E),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: confirmColor != null
              ? FilledButton.styleFrom(backgroundColor: confirmColor)
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
