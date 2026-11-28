import '../utils/date_time_utils.dart';
import 'conflict_result.dart';

/// Conflict-free replacement slot row returned by `public.get_available_slots`.
class AvailableSlot {
  const AvailableSlot({
    required this.slotDate,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    required this.recommendedRoomId,
    required this.recommendedRoomNumber,
    required this.recommendedRoomIsLab,
    required this.availableRooms,
    required this.slotSource,
    required this.slotLabel,
    required this.priorityScore,
  });

  final DateTime slotDate;
  final int dayOfWeek; // 1=Mon..6=Sat
  final String startTime; // HH:MM:SS
  final String endTime; // HH:MM:SS
  final int durationMinutes;
  final String recommendedRoomId;
  final String recommendedRoomNumber;
  final bool recommendedRoomIsLab;
  final List<SuggestedRoom> availableRooms;

  /// 'freed_by_cancellation' | 'open_gap' | 'saturday_makeup'
  final String slotSource;
  final String slotLabel;
  final int priorityScore;

  bool get isFreedByCancellation => slotSource == 'freed_by_cancellation';
  bool get isOpenGap => slotSource == 'open_gap';
  bool get isSaturdayMakeup => slotSource == 'saturday_makeup';

  String get slotKey =>
      '${DateTimeUtils.toSqlDate(slotDate)}|$startTime|$endTime';

  String get recommendedRoomDisplay => recommendedRoomIsLab
      ? '$recommendedRoomNumber (Lab)'
      : recommendedRoomNumber;

  factory AvailableSlot.fromJson(Map<String, dynamic> json) {
    final rawRooms = json['available_rooms'] as List<dynamic>? ?? const [];
    return AvailableSlot(
      slotDate: DateTimeUtils.parseSqlDate(json['slot_date'] as String),
      dayOfWeek: (json['day_of_week'] as num).toInt(),
      startTime: json['start_time'] as String,
      endTime: json['end_time'] as String,
      durationMinutes: (json['duration_minutes'] as num).toInt(),
      recommendedRoomId: json['recommended_room_id'] as String,
      recommendedRoomNumber: json['recommended_room_number'] as String,
      recommendedRoomIsLab: json['recommended_room_is_lab'] as bool? ?? false,
      availableRooms: rawRooms
          .map(
            (e) => SuggestedRoom.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      slotSource: json['slot_source'] as String? ?? 'open_gap',
      slotLabel: json['slot_label'] as String? ?? '',
      priorityScore: (json['priority_score'] as num?)?.toInt() ?? 20,
    );
  }
}
