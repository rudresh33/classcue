/// Suggested free room item returned inside `check_slot_conflicts`.
class SuggestedRoom {
  const SuggestedRoom({
    required this.id,
    required this.roomNumber,
    required this.isLab,
  });

  final String id;
  final String roomNumber;
  final bool isLab;

  factory SuggestedRoom.fromJson(Map<String, dynamic> json) {
    return SuggestedRoom(
      id: json['id'] as String,
      roomNumber: json['room_number'] as String,
      isLab: json['is_lab'] as bool? ?? false,
    );
  }
}

/// Result returned by `public.check_slot_conflicts`.
class SlotConflictResult {
  const SlotConflictResult({
    required this.hasConflict,
    required this.cohortConflict,
    required this.facultyConflict,
    required this.roomConflict,
    required this.suggestedRooms,
  });

  final bool hasConflict;
  final bool cohortConflict;
  final bool facultyConflict;
  final bool roomConflict;
  final List<SuggestedRoom> suggestedRooms;

  factory SlotConflictResult.fromJson(Map<String, dynamic> json) {
    final rawRooms = json['suggested_rooms'] as List<dynamic>? ?? const [];
    return SlotConflictResult(
      hasConflict: json['has_conflict'] as bool? ?? false,
      cohortConflict: json['cohort_conflict'] as bool? ?? false,
      facultyConflict: json['faculty_conflict'] as bool? ?? false,
      roomConflict: json['room_conflict'] as bool? ?? false,
      suggestedRooms: rawRooms
          .map(
            (e) => SuggestedRoom.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
    );
  }
}
