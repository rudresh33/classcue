/// Row from `public.change_history`.
class ChangeHistoryEntry {
  const ChangeHistoryEntry({
    required this.id,
    required this.lectureSessionId,
    required this.changedBy,
    required this.actionType,
    required this.previousState,
    required this.newState,
    this.sideEffects,
    this.reason,
    this.revertsHistoryId,
    this.undoneAt,
    required this.createdAt,
  });

  final String id;
  final String lectureSessionId;
  final String changedBy;

  /// 'cancel' | 'reschedule' | 'room_change' | 'cover_opt_in' | 'permanent_update' | 'status_update' | 'undo'
  final String actionType;
  final Map<String, dynamic> previousState;
  final Map<String, dynamic> newState;
  final Map<String, dynamic>? sideEffects;
  final String? reason;
  final String? revertsHistoryId;
  final DateTime? undoneAt;
  final DateTime createdAt;

  bool get isUndo => actionType == 'undo';
  bool get isUndone => undoneAt != null;

  String get actionLabel {
    switch (actionType) {
      case 'cancel':
        return 'Cancelled';
      case 'reschedule':
        return 'Rescheduled';
      case 'room_change':
        return 'Room Changed';
      case 'cover_opt_in':
        return 'Faculty Coverage';
      case 'permanent_update':
        return 'Permanent Update';
      case 'status_update':
        return 'Status Update';
      case 'undo':
        return 'Reverted (Undo)';
      default:
        return actionType;
    }
  }

  factory ChangeHistoryEntry.fromJson(Map<String, dynamic> json) {
    return ChangeHistoryEntry(
      id: json['id'] as String,
      lectureSessionId: json['lecture_session_id'] as String,
      changedBy: json['changed_by'] as String,
      actionType: json['action_type'] as String,
      previousState: Map<String, dynamic>.from(
        json['previous_state'] as Map? ?? const {},
      ),
      newState: Map<String, dynamic>.from(
        json['new_state'] as Map? ?? const {},
      ),
      sideEffects: json['side_effects'] != null
          ? Map<String, dynamic>.from(json['side_effects'] as Map)
          : null,
      reason: json['reason'] as String?,
      revertsHistoryId: json['reverts_history_id'] as String?,
      undoneAt: json['undone_at'] != null
          ? DateTime.parse(json['undone_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// Row from `public.notifications`.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.userId,
    this.lectureSessionId,
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String? lectureSessionId;
  final String title;
  final String body;

  /// 'cancellation' | 'reschedule' | 'room_change' | 'poll' | 'coverage_open' | 'reminder'
  final String type;
  final bool isRead;
  final DateTime createdAt;

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      userId: userId,
      lectureSessionId: lectureSessionId,
      title: title,
      body: body,
      type: type,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      lectureSessionId: json['lecture_session_id'] as String?,
      title: json['title'] as String,
      body: json['body'] as String,
      type: json['type'] as String,
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
