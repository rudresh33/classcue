import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/models.dart';
import '../../core/services/supabase_service.dart';
import '../../core/utils/date_time_utils.dart';

/// Manages personal notifications (with live unread count badge) and the
/// scoped Timetable Change History audit trail with Realtime sync.
class NotificationsProvider extends ChangeNotifier {
  NotificationsProvider(this._service);

  final SupabaseService _service;

  UserProfile? _profile;
  List<AppNotification> _notifications = [];
  List<ChangeHistoryEntry> _history = [];
  bool _loading = false;
  String? _error;

  RealtimeChannel? _notifChannel;
  RealtimeChannel? _sessionsChannel;
  Timer? _debounceTimer;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);
  List<ChangeHistoryEntry> get history => List.unmodifiable(_history);
  int get unreadCount => _notifications.where((n) => !n.isRead).length;
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
      _notifications = [];
      _history = [];
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
      final results = await Future.wait([
        _service.fetchNotifications(limit: 60),
        _service.fetchChangeHistory(limit: 60),
      ]);
      _notifications = results[0] as List<AppNotification>;
      _history = results[1] as List<ChangeHistoryEntry>;
      _error = null;
    } catch (e) {
      _error = DateTimeUtils.prettifyError(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> markRead(AppNotification notification) async {
    if (notification.isRead) return;
    final idx = _notifications.indexWhere((n) => n.id == notification.id);
    if (idx != -1) {
      _notifications[idx] = notification.copyWith(isRead: true);
      notifyListeners();
    }
    try {
      await _service.markNotificationRead(notification.id);
    } catch (_) {
      await refreshAll(silent: true);
    }
  }

  Future<void> markAllRead() async {
    if (unreadCount == 0) return;
    _notifications = _notifications
        .map((n) => n.copyWith(isRead: true))
        .toList();
    notifyListeners();
    try {
      await _service.markAllNotificationsRead();
    } catch (_) {
      await refreshAll(silent: true);
    }
  }

  void _subscribeRealtime() {
    final uid = _profile?.id ?? 'anon';
    _notifChannel = _service.subscribeToTable(
      channelName: 'classcue_notifs_$uid',
      table: 'notifications',
      onChange: _scheduleRefresh,
    );
    _sessionsChannel = _service.subscribeToTable(
      channelName: 'classcue_history_sync_$uid',
      table: 'lecture_sessions',
      onChange: _scheduleRefresh,
    );
  }

  void _scheduleRefresh() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      refreshAll(silent: true);
    });
  }

  void _unsubscribe() {
    _debounceTimer?.cancel();
    _service.removeChannel(_notifChannel);
    _service.removeChannel(_sessionsChannel);
    _notifChannel = null;
    _sessionsChannel = null;
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }
}
