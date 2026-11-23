import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/models.dart';
import '../../core/services/supabase_service.dart';
import '../../core/utils/date_time_utils.dart';

/// Manages Supabase Auth state, current `UserProfile`, and reference metadata cache.
class AuthProvider extends ChangeNotifier {
  AuthProvider(this._service) {
    _authSub = _service.client.auth.onAuthStateChange.listen(_onAuthChange);
    _bootstrap();
  }

  final SupabaseService _service;
  StreamSubscription<AuthState>? _authSub;

  UserProfile? _profile;
  bool _isInitializing = true;
  bool _isBusy = false;
  String? _error;

  UserProfile? get profile => _profile;
  bool get isAuthenticated => _profile != null;
  bool get isInitializing => _isInitializing;
  bool get isBusy => _isBusy;
  String? get error => _error;
  SupabaseService get service => _service;

  Cohort? get userCohort => _service.cohortById(_profile?.cohortId);

  Future<void> _bootstrap() async {
    try {
      if (_service.currentAuthUser != null) {
        await _loadAuthenticatedState();
      }
    } catch (e) {
      _error = DateTimeUtils.prettifyError(e);
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  void _onAuthChange(AuthState state) {
    if (state.event == AuthChangeEvent.signedOut) {
      _profile = null;
      _service.clearCaches();
      notifyListeners();
    } else if (state.event == AuthChangeEvent.signedIn ||
        state.event == AuthChangeEvent.tokenRefreshed) {
      if (_profile == null && !_isBusy) {
        _loadAuthenticatedState().then((_) => notifyListeners());
      }
    }
  }

  Future<void> _loadAuthenticatedState() async {
    final profile = await _service.fetchCurrentProfile();
    if (profile == null) {
      await _service.signOut();
      throw Exception(
        'No ClassCue profile was found for this account. Contact the GBS programme admin.',
      );
    }
    await _service.loadReferenceData(force: true);
    _profile = profile;
    _error = null;
  }

  Future<bool> signIn({required String email, required String password}) async {
    _isBusy = true;
    _error = null;
    notifyListeners();
    try {
      await _service.signInWithPassword(email: email, password: password);
      await _loadAuthenticatedState();
      return true;
    } catch (e) {
      _error = DateTimeUtils.prettifyError(e);
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<bool> updateFullName(String newName) async {
    _isBusy = true;
    _error = null;
    notifyListeners();
    try {
      await _service.updateOwnFullName(newName);
      _profile = _profile?.copyWith(fullName: newName.trim());
      if (_profile?.isFaculty ?? false) {
        await _service.loadReferenceData(force: true);
      }
      return true;
    } catch (e) {
      _error = DateTimeUtils.prettifyError(e);
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    _isBusy = true;
    notifyListeners();
    try {
      await _service.signOut();
      _profile = null;
      _error = null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
