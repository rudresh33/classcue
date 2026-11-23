import '../utils/date_time_utils.dart';

/// Row from `public.reschedule_polls`.
class ReschedulePoll {
  const ReschedulePoll({
    required this.id,
    required this.lectureSessionId,
    required this.createdBy,
    required this.expectedSessionVersion,
    required this.status,
    required this.closesAt,
    required this.createdAt,
  });

  final String id;
  final String lectureSessionId;
  final String createdBy;
  final int expectedSessionVersion;

  /// 'open' | 'confirmed' | 'cancelled_fallback' | 'superseded'
  final String status;
  final DateTime closesAt;
  final DateTime createdAt;

  bool get isOpen => status == 'open';
  bool get isConfirmed => status == 'confirmed';
  bool get isCancelledFallback => status == 'cancelled_fallback';
  bool get isSuperseded => status == 'superseded';

  bool get isVotingOpen =>
      isOpen && closesAt.toUtc().isAfter(DateTime.now().toUtc());

  bool get isPastConfirmationWindow => closesAt.toUtc().isBefore(
    DateTime.now().toUtc().subtract(const Duration(hours: 48)),
  );

  factory ReschedulePoll.fromJson(Map<String, dynamic> json) {
    return ReschedulePoll(
      id: json['id'] as String,
      lectureSessionId: json['lecture_session_id'] as String,
      createdBy: json['created_by'] as String,
      expectedSessionVersion:
          (json['expected_session_version'] as num?)?.toInt() ?? 1,
      status: json['status'] as String,
      closesAt: DateTime.parse(json['closes_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// Row returned by `public.get_poll_results(p_poll_id)`.
class PollOptionResult {
  const PollOptionResult({
    required this.optionId,
    required this.proposedDate,
    required this.proposedStartTime,
    required this.proposedEndTime,
    this.proposedRoomId,
    required this.isSelected,
    required this.voteCount,
    required this.votedByMe,
    required this.pollStatus,
    required this.closesAt,
    required this.isVotingOpen,
  });

  final String optionId;
  final DateTime proposedDate;
  final String proposedStartTime;
  final String proposedEndTime;
  final String? proposedRoomId;
  final bool isSelected;
  final int voteCount;
  final bool votedByMe;
  final String pollStatus;
  final DateTime closesAt;
  final bool isVotingOpen;

  factory PollOptionResult.fromJson(Map<String, dynamic> json) {
    return PollOptionResult(
      optionId: json['option_id'] as String,
      proposedDate: DateTimeUtils.parseSqlDate(json['proposed_date'] as String),
      proposedStartTime: json['proposed_start_time'] as String,
      proposedEndTime: json['proposed_end_time'] as String,
      proposedRoomId: json['proposed_room_id'] as String?,
      isSelected: json['is_selected'] as bool? ?? false,
      voteCount: (json['vote_count'] as num?)?.toInt() ?? 0,
      votedByMe: json['voted_by_me'] as bool? ?? false,
      pollStatus: json['poll_status'] as String,
      closesAt: DateTime.parse(json['closes_at'] as String),
      isVotingOpen: json['is_voting_open'] as bool? ?? false,
    );
  }
}

/// Draft option when creating a new poll before inserting into `poll_options`.
class PollOptionDraft {
  PollOptionDraft({
    required this.proposedDate,
    required this.proposedStartTime,
    required this.proposedEndTime,
    this.proposedRoomId,
  });

  DateTime proposedDate;
  String proposedStartTime;
  String proposedEndTime;
  String? proposedRoomId;
}
