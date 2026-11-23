import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/models.dart';
import '../../core/services/supabase_service.dart';
import '../../core/utils/date_time_utils.dart';

/// Bundled poll view model combining `ReschedulePoll`, its target `LectureSession`,
/// and privacy-preserving aggregated rows from `get_poll_results`.
class PollViewData {
  const PollViewData({required this.poll, this.session, required this.options});

  final ReschedulePoll poll;
  final LectureSession? session;
  final List<PollOptionResult> options;

  int get totalVotes => options.fold<int>(0, (sum, o) => sum + o.voteCount);

  PollOptionResult? get myVotedOption {
    for (final o in options) {
      if (o.votedByMe) return o;
    }
    return null;
  }

  bool get hasUserVoted => myVotedOption != null;

  bool get isVotingOpen =>
      options.isNotEmpty ? options.first.isVotingOpen : poll.isVotingOpen;

  bool get isStale =>
      session != null && session!.version != poll.expectedSessionVersion;
}

/// Manages reschedule polls, anonymous vote aggregation via `get_poll_results`,
/// safe insert/update voting, faculty confirmation, and Realtime sync.
class PollsProvider extends ChangeNotifier {
  PollsProvider(this._service);

  final SupabaseService _service;

  UserProfile? _profile;
  List<PollViewData> _polls = [];
  bool _loading = false;
  String? _error;

  RealtimeChannel? _pollsChannel;
  Timer? _debounceTimer;

  List<PollViewData> get polls => List.unmodifiable(_polls);
  List<PollViewData> get openPolls =>
      _polls.where((p) => p.poll.isOpen).toList();
  List<PollViewData> get closedPolls =>
      _polls.where((p) => !p.poll.isOpen).toList();

  bool get isLoading => _loading;
  String? get error => _error;

  void bindProfile(UserProfile? profile) {
    if (_profile?.id == profile?.id && _profile?.role == profile?.role) {
      _profile = profile;
      return;
    }
    _profile = profile;
    _unsubscribe();
    if (profile == null) {
      _polls = [];
      notifyListeners();
      return;
    }
    _subscribeRealtime();
    refreshAll();
  }

  Future<void> refreshAll({bool silent = false}) async {
    if (_profile == null) return;
    if (!silent) {
      _loading = true;
      _error = null;
      notifyListeners();
    }

    try {
      final rawPolls = await _service.fetchPolls();
      final items = await Future.wait(
        rawPolls.map((poll) async {
          final results = await Future.wait([
            _service.fetchSessionById(poll.lectureSessionId),
            _service.getPollResults(poll.id),
          ]);
          return PollViewData(
            poll: poll,
            session: results[0] as LectureSession?,
            options: results[1] as List<PollOptionResult>,
          );
        }),
      );
      _polls = items;
      _error = null;
    } catch (e) {
      _error = DateTimeUtils.prettifyError(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> vote({
    required PollViewData pollData,
    required String optionId,
  }) async {
    await _service.submitPollVote(
      pollId: pollData.poll.id,
      optionId: optionId,
      hasExistingVote: pollData.hasUserVoted,
    );
    await refreshAll(silent: true);
  }

  Future<void> confirmOption({
    required String pollId,
    required String optionId,
    String? reason,
    bool allowEarlyClose = false,
  }) async {
    await _service.confirmPollOption(
      pollId: pollId,
      optionId: optionId,
      reason: reason,
      allowEarlyClose: allowEarlyClose,
    );
    await refreshAll(silent: true);
  }

  Future<void> closeAsFallback(String pollId) async {
    await _service.closePollAsCancelledFallback(pollId);
    await refreshAll(silent: true);
  }

  void _subscribeRealtime() {
    final uid = _profile?.id ?? 'anon';
    _pollsChannel = _service.subscribeToTable(
      channelName: 'classcue_polls_$uid',
      table: 'reschedule_polls',
      onChange: () {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 350), () {
          refreshAll(silent: true);
        });
      },
    );
  }

  void _unsubscribe() {
    _debounceTimer?.cancel();
    _service.removeChannel(_pollsChannel);
    _pollsChannel = null;
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }
}
