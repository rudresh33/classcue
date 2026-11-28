import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_time_utils.dart';
import '../../core/widgets/widgets.dart';
import '../auth/auth_provider.dart';

enum _FacultyActionMode {
  cancelOrPending,
  reschedule,
  roomChange,
  restoreScheduled,
}

/// Structured Faculty/Admin Update & Reschedule Bottom Sheet (Nielsen #5 & #3):
/// - Zero accidental toggles: explicit segmented action modes
/// - Smart Free-Slot Picker via `get_available_slots` surfacing freed slots first
/// - Live `check_slot_conflicts` banner (Cohort / Faculty / Room) + tappable Free Room Chips
/// - Temporary vs Permanent toggle (disabled if `baseTimetableId == null` or covering faculty)
/// - Mandatory Pre-Publish `ConfirmActionDialog` before calling `update_lecture_session`
/// - Returns `true` on success so caller displays Immediate Undo Snackbar
class RescheduleSheet extends StatefulWidget {
  const RescheduleSheet({super.key, required this.session});

  final LectureSession session;

  static Future<bool> show(BuildContext context, LectureSession session) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => RescheduleSheet(session: session),
    );
    return result == true;
  }

  @override
  State<RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends State<RescheduleSheet> {
  late _FacultyActionMode _mode;
  late String _cancelStatus; // 'cancelled' | 'rescheduling_pending'
  late bool _openForCoverage;
  late DateTime _selectedDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late String _selectedRoomId;
  String _changeScope = 'temporary';
  final _reasonCtrl = TextEditingController();

  // Smart Free-Slot Finder state
  List<AvailableSlot> _smartSlots = [];
  bool _loadingSmartSlots = false;
  String? _smartSlotsError;
  late int _smartDurationMinutes;
  bool _includeSaturday = true;
  bool _allowLunch = false;
  int _daysAhead = 7;
  int _maxPerDay = 3;
  String? _selectedSmartSlotKey;

  SlotConflictResult? _conflictResult;
  bool _checkingConflict = false;
  String? _conflictError;
  bool _submitting = false;

  SupabaseService get _service => context.read<AuthProvider>().service;
  UserProfile get _profile => context.read<AuthProvider>().profile!;

  bool get _canRestore =>
      widget.session.isCancelled || widget.session.isPending;

  int get _originalDurationMinutes =>
      widget.session.baselineDurationMinutes.clamp(30, 240);

  bool get _canMakePermanent {
    if (widget.session.baseTimetableId == null) return false;
    if (_profile.isAdmin) return true;
    // Covering faculty cannot permanently alter the primary instructor's weekly timetable
    return _profile.isFaculty &&
        widget.session.facultyId == _profile.id &&
        _service.isFacultyAssignedToCourse(
          widget.session.courseId,
          _profile.id,
        );
  }

  @override
  void initState() {
    super.initState();
    _mode = _canRestore
        ? _FacultyActionMode.restoreScheduled
        : _FacultyActionMode.cancelOrPending;
    _cancelStatus = widget.session.isPending
        ? 'rescheduling_pending'
        : 'cancelled';
    _openForCoverage = widget.session.isOpenForCoverage;
    _selectedDate = widget.session.sessionDate;
    final baseStart =
        widget.session.preCoverageStartTime ?? widget.session.startTime;
    final baseEnd = widget.session.preCoverageEndTime ?? widget.session.endTime;
    _startTime = DateTimeUtils.parseSqlTime(baseStart);
    _endTime = DateTimeUtils.parseSqlTime(baseEnd);
    _selectedRoomId = widget.session.roomId;
    _reasonCtrl.text = widget.session.reason ?? '';
    _smartDurationMinutes = _originalDurationMinutes;
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  bool get _needsConflictCheck =>
      _mode == _FacultyActionMode.reschedule ||
      _mode == _FacultyActionMode.roomChange ||
      _mode == _FacultyActionMode.restoreScheduled;

  bool get _slotActuallyChanged {
    final startSql = DateTimeUtils.toSqlTime(_startTime);
    final endSql = DateTimeUtils.toSqlTime(_endTime);
    final baseStart =
        widget.session.preCoverageStartTime ?? widget.session.startTime;
    final baseEnd = widget.session.preCoverageEndTime ?? widget.session.endTime;
    return !DateTimeUtils.isSameDay(
          _selectedDate,
          widget.session.sessionDate,
        ) ||
        startSql != baseStart ||
        endSql != baseEnd ||
        _selectedRoomId != widget.session.roomId;
  }

  Future<void> _loadSmartSlots() async {
    if (_mode != _FacultyActionMode.reschedule) return;
    setState(() {
      _loadingSmartSlots = true;
      _smartSlotsError = null;
    });

    try {
      final slots = await _service.getAvailableSlots(
        sessionId: widget.session.id,
        daysAhead: _daysAhead,
        durationMinutes: _smartDurationMinutes,
        includeSaturday: _includeSaturday,
        skipLunch: !_allowLunch,
        limit: 12,
        maxPerDay: _maxPerDay,
        minLeadMinutes: 60,
      );
      if (!mounted) return;
      setState(() {
        _smartSlots = slots;
        _loadingSmartSlots = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _smartSlots = [];
        _smartSlotsError = DateTimeUtils.prettifyError(e);
        _loadingSmartSlots = false;
      });
    }
  }

  void _selectDurationChip(int minutes) {
    final startMins = DateTimeUtils.timeOfDayToMinutes(_startTime);
    final newEnd = DateTimeUtils.minutesToTimeOfDay(
      (startMins + minutes).clamp(startMins + 30, 23 * 60 + 45),
    );
    setState(() {
      _smartDurationMinutes = minutes;
      _endTime = newEnd;
      _selectedSmartSlotKey = null;
    });
    _loadSmartSlots();
    _runConflictCheck();
  }

  void _applySmartSlot(AvailableSlot slot) {
    setState(() {
      _selectedDate = slot.slotDate;
      _startTime = DateTimeUtils.parseSqlTime(slot.startTime);
      _endTime = DateTimeUtils.parseSqlTime(slot.endTime);
      _selectedRoomId = slot.recommendedRoomId;
      _selectedSmartSlotKey = slot.slotKey;
    });
    _runConflictCheck();
  }

  Future<void> _runConflictCheck() async {
    if (!_needsConflictCheck) return;
    if (DateTimeUtils.timeOfDayToMinutes(_endTime) <=
        DateTimeUtils.timeOfDayToMinutes(_startTime)) {
      setState(() {
        _conflictResult = null;
        _conflictError = 'End time must be strictly after start time.';
      });
      return;
    }

    setState(() {
      _checkingConflict = true;
      _conflictError = null;
    });

    try {
      // Anti-probing rule: if caller is faculty, p_faculty_id MUST be auth.uid()
      final facultyIdToCheck = _profile.isFaculty
          ? _profile.id
          : widget.session.effectiveFacultyId;

      final res = await _service.checkSlotConflicts(
        courseId: widget.session.courseId,
        sessionDate: _mode == _FacultyActionMode.reschedule
            ? _selectedDate
            : widget.session.sessionDate,
        startTime: _mode == _FacultyActionMode.reschedule
            ? DateTimeUtils.toSqlTime(_startTime)
            : widget.session.startTime,
        endTime: _mode == _FacultyActionMode.reschedule
            ? DateTimeUtils.toSqlTime(_endTime)
            : widget.session.endTime,
        roomId: _mode == _FacultyActionMode.restoreScheduled
            ? widget.session.roomId
            : _selectedRoomId,
        facultyId: facultyIdToCheck,
        batch: widget.session.batch,
        excludeSessionId: widget.session.id,
      );

      if (!mounted) return;
      setState(() {
        _conflictResult = res;
        _checkingConflict = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _conflictResult = null;
        _conflictError = DateTimeUtils.prettifyError(e);
        _checkingConflict = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final today = DateTimeUtils.todayIst();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isBefore(today) ? today : _selectedDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 120)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _selectedSmartSlotKey = null;
      });
      await _runConflictCheck();
    }
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
        _selectedSmartSlotKey = null;
      });
      await _runConflictCheck();
    }
  }

  Future<void> _confirmAndSubmit() async {
    final course = _service.courseById(widget.session.courseId);
    final oldRoom = _service.roomById(widget.session.roomId);
    final newRoom = _service.roomById(_selectedRoomId);
    final oldSlotText =
        '${DateTimeUtils.formatSlotSummary(widget.session.sessionDate, widget.session.startTime, widget.session.endTime)} · ${oldRoom?.roomNumber ?? 'Room'}';

    String targetStatus;
    DateTime? pDate;
    String? pStart;
    String? pEnd;
    String? pRoomId;
    String scope = 'temporary';
    bool openCoverage = false;
    Color accentColor = AppTheme.primaryIndigo;
    String confirmLabel = 'Publish Update';

    if (_mode == _FacultyActionMode.cancelOrPending) {
      targetStatus = _cancelStatus;
      // DB enforces null slot fields for cancelled / rescheduling_pending
      pDate = null;
      pStart = null;
      pEnd = null;
      pRoomId = null;
      scope = 'temporary';
      openCoverage = _openForCoverage;
      accentColor = targetStatus == 'cancelled'
          ? AppTheme.cancelledStyle.foreground
          : AppTheme.pendingStyle.foreground;
      confirmLabel = targetStatus == 'cancelled'
          ? 'Confirm Cancellation'
          : 'Mark Rescheduling Pending';
    } else if (_mode == _FacultyActionMode.reschedule) {
      if (DateTimeUtils.timeOfDayToMinutes(_endTime) <=
          DateTimeUtils.timeOfDayToMinutes(_startTime)) {
        _showSnack('End time must be after start time.');
        return;
      }
      if (!_slotActuallyChanged) {
        _showSnack(
          'Change the date, time, or room to reschedule this lecture.',
        );
        return;
      }
      targetStatus = 'rescheduled';
      pDate = _selectedDate;
      pStart = DateTimeUtils.toSqlTime(_startTime);
      pEnd = DateTimeUtils.toSqlTime(_endTime);
      pRoomId = _selectedRoomId;
      scope = _canMakePermanent ? _changeScope : 'temporary';
      accentColor = AppTheme.rescheduledStyle.foreground;
      confirmLabel = scope == 'permanent'
          ? 'Publish Permanent Change'
          : 'Confirm Reschedule';
    } else if (_mode == _FacultyActionMode.roomChange) {
      if (_selectedRoomId == widget.session.roomId) {
        _showSnack('Select a different room to publish a room change.');
        return;
      }
      targetStatus = widget.session.isRescheduled ? 'rescheduled' : 'scheduled';
      pDate = widget.session.sessionDate;
      pStart = widget.session.startTime;
      pEnd = widget.session.endTime;
      pRoomId = _selectedRoomId;
      scope = _canMakePermanent ? _changeScope : 'temporary';
      accentColor = AppTheme.pendingStyle.foreground;
      confirmLabel = 'Confirm Room Change';
    } else {
      // Restore scheduled
      targetStatus = 'scheduled';
      pDate = widget.session.sessionDate;
      pStart = widget.session.startTime;
      pEnd = widget.session.endTime;
      pRoomId = widget.session.roomId;
      scope = 'temporary';
      accentColor = AppTheme.scheduledStyle.foreground;
      confirmLabel = 'Restore Lecture';
    }

    final newSlotText = _mode == _FacultyActionMode.cancelOrPending
        ? oldSlotText
        : '${DateTimeUtils.formatSlotSummary(pDate ?? widget.session.sessionDate, pStart ?? widget.session.startTime, pEnd ?? widget.session.endTime)} · ${newRoom?.displayLabel ?? oldRoom?.roomNumber ?? 'Room'}';

    final rows = <ConfirmationDetailRow>[
      ConfirmationDetailRow(
        label: 'Course & Batch',
        value:
            '${course?.code ?? ''} — ${course?.name ?? 'Lecture'} (${widget.session.batch == 'ALL' ? 'All Students' : 'Batch ${widget.session.batch}'})',
      ),
      ConfirmationDetailRow(
        label: 'New Status',
        value: AppTheme.statusStyleFor(targetStatus).label,
        highlightColor: accentColor,
      ),
      ConfirmationDetailRow(
        label: _mode == _FacultyActionMode.cancelOrPending
            ? 'Affected Slot'
            : 'Slot Comparison',
        strikethroughOldValue:
            _mode == _FacultyActionMode.cancelOrPending ||
                _mode == _FacultyActionMode.restoreScheduled
            ? null
            : oldSlotText,
        value: newSlotText,
      ),
      ConfirmationDetailRow(
        label: 'Change Scope',
        value: scope == 'permanent'
            ? 'Permanent (updates recurring weekly timetable & future sessions)'
            : 'Temporary (only this dated session)',
      ),
      if (_mode == _FacultyActionMode.cancelOrPending)
        ConfirmationDetailRow(
          label: 'Faculty Coverage',
          value: openCoverage
              ? 'Open for other faculty to opt in'
              : 'Not open for coverage',
        ),
      if (_reasonCtrl.text.trim().isNotEmpty)
        ConfirmationDetailRow(
          label: 'Reason / Note',
          value: _reasonCtrl.text.trim(),
        ),
    ];

    final confirmed = await ConfirmActionDialog.show(
      context,
      title: 'Review & Publish Change',
      subtitle: 'Affected students, CRs, and faculty will be notified immediately. You can still Undo right after publishing.',
      rows: rows,
      confirmLabel: confirmLabel,
      confirmColor: accentColor,
      warningText: scope == 'permanent'
          ? 'Permanent changes update the recurring weekly base timetable and automatically shift future untouched scheduled sessions.'
          : null,
    );

    if (!confirmed || !mounted) return;

    setState(() => _submitting = true);
    try {
      await _service.updateLectureSession(
        sessionId: widget.session.id,
        status: targetStatus,
        sessionDate: pDate,
        startTime: pStart,
        endTime: pEnd,
        roomId: pRoomId,
        changeScope: scope,
        reason: _reasonCtrl.text,
        isOpenForCoverage: openCoverage,
      );
      if (scope == 'permanent') {
        await _service.refreshBaseTimetable();
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _showSnack(DateTimeUtils.prettifyError(e));
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildSmartFreeSlotsSection() {
    final standardDurations = <int>[60, 90, 120];
    final showOriginalChip = !standardDurations.contains(
      _originalDurationMinutes,
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: AppTheme.primaryIndigo,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Smart Free Slots',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.inkPrimary,
                  ),
                ),
              ),
              if (!_loadingSmartSlots)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Refresh smart slots',
                  onPressed: _loadSmartSlots,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 17,
                    color: AppTheme.primaryIndigo,
                  ),
                ),
            ],
          ),
          const Text(
            'Conflict-free slots for cohort, instructor & room — freed cancellation windows shown first.',
            style: TextStyle(fontSize: 11.5, color: AppTheme.inkMuted),
          ),
          const SizedBox(height: 10),

          // Duration chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final mins in standardDurations)
                ChoiceChip(
                  label: Text(
                    DateTimeUtils.formatMinutesShort(mins),
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: _smartDurationMinutes == mins,
                  onSelected: (_) => _selectDurationChip(mins),
                ),
              if (showOriginalChip)
                ChoiceChip(
                  label: Text(
                    'Original (${DateTimeUtils.formatMinutesShort(_originalDurationMinutes)})',
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: _smartDurationMinutes == _originalDurationMinutes,
                  onSelected: (_) =>
                      _selectDurationChip(_originalDurationMinutes),
                ),
            ],
          ),
          const SizedBox(height: 6),

          // Filter chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              FilterChip(
                label: const Text(
                  'Include Sat',
                  style: TextStyle(fontSize: 11.5),
                ),
                selected: _includeSaturday,
                onSelected: (v) {
                  setState(() => _includeSaturday = v);
                  _loadSmartSlots();
                },
              ),
              FilterChip(
                label: const Text(
                  'Allow Lunch',
                  style: TextStyle(fontSize: 11.5),
                ),
                selected: _allowLunch,
                onSelected: (v) {
                  setState(() => _allowLunch = v);
                  _loadSmartSlots();
                },
              ),
              ActionChip(
                avatar: Icon(
                  _daysAhead >= 14
                      ? Icons.check_rounded
                      : Icons.date_range_rounded,
                  size: 15,
                  color: AppTheme.primaryIndigo,
                ),
                label: Text(
                  _daysAhead >= 14 ? 'Showing 14 days' : 'Show more · 14 days',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: () {
                  setState(() {
                    if (_daysAhead < 14) {
                      _daysAhead = 14;
                      _maxPerDay = 5;
                    } else {
                      _daysAhead = 7;
                      _maxPerDay = 3;
                    }
                  });
                  _loadSmartSlots();
                },
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (_loadingSmartSlots)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Finding conflict-free slots...',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.secondarySlate,
                    ),
                  ),
                ],
              ),
            )
          else if (_smartSlotsError != null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.cancelledStyle.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.cancelledStyle.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _smartSlotsError!,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.cancelledStyle.foreground,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _loadSmartSlots,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          else if (_smartSlots.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No conflict-free ${DateTimeUtils.formatMinutesShort(_smartDurationMinutes)} slots found in the next $_daysAhead days.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.inkPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (_daysAhead < 14)
                        FilledButton.tonalIcon(
                          onPressed: () {
                            setState(() {
                              _daysAhead = 14;
                              _maxPerDay = 5;
                            });
                            _loadSmartSlots();
                          },
                          icon: const Icon(Icons.date_range_rounded, size: 16),
                          label: const Text('Search next 14 days'),
                        ),
                      if (!_includeSaturday)
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() => _includeSaturday = true);
                            _loadSmartSlots();
                          },
                          icon: const Icon(Icons.weekend_outlined, size: 16),
                          label: const Text('Include Saturday'),
                        ),
                    ],
                  ),
                ],
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _smartSlots.length,
                itemBuilder: (_, idx) {
                  final slot = _smartSlots[idx];
                  return SmartSlotCard(
                    slot: slot,
                    isSelected: _selectedSmartSlotKey == slot.slotKey,
                    onTap: () => _applySmartSlot(slot),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final course = _service.courseById(widget.session.courseId);
    final rooms = _service.rooms;

    final segments = <ButtonSegment<_FacultyActionMode>>[
      const ButtonSegment(
        value: _FacultyActionMode.cancelOrPending,
        label: Text('Cancel'),
        icon: Icon(Icons.cancel_outlined, size: 16),
      ),
      const ButtonSegment(
        value: _FacultyActionMode.reschedule,
        label: Text('Move'),
        icon: Icon(Icons.event_repeat_rounded, size: 16),
      ),
      const ButtonSegment(
        value: _FacultyActionMode.roomChange,
        label: Text('Room'),
        icon: Icon(Icons.meeting_room_outlined, size: 16),
      ),
      if (_canRestore)
        const ButtonSegment(
          value: _FacultyActionMode.restoreScheduled,
          label: Text('Restore'),
          icon: Icon(Icons.restore_rounded, size: 16),
        ),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
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
            const SizedBox(height: 14),
            Text(
              'Update ${course?.code ?? 'Lecture'}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.inkPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${course?.name ?? ''} · ${DateTimeUtils.formatSlotSummary(widget.session.sessionDate, widget.session.startTime, widget.session.endTime)}',
              style: const TextStyle(fontSize: 12.5, color: AppTheme.inkMuted),
            ),
            const SizedBox(height: 14),

            // Segmented action selector
            SegmentedButton<_FacultyActionMode>(
              segments: segments,
              selected: {_mode},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                setState(() {
                  _mode = selection.first;
                  _conflictResult = null;
                  _conflictError = null;
                  if (_mode == _FacultyActionMode.cancelOrPending ||
                      _mode == _FacultyActionMode.restoreScheduled) {
                    _changeScope = 'temporary';
                  }
                });
                if (_mode == _FacultyActionMode.reschedule) {
                  _loadSmartSlots();
                }
                if (_needsConflictCheck) {
                  _runConflictCheck();
                }
              },
            ),
            const SizedBox(height: 16),

            // Mode 1: Cancel / Pending
            if (_mode == _FacultyActionMode.cancelOrPending) ...[
              const Text(
                'Status to Publish',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Cancelled'),
                    selected: _cancelStatus == 'cancelled',
                    onSelected: (_) =>
                        setState(() => _cancelStatus = 'cancelled'),
                  ),
                  ChoiceChip(
                    label: const Text('Rescheduling Pending'),
                    selected: _cancelStatus == 'rescheduling_pending',
                    onSelected: (_) =>
                        setState(() => _cancelStatus = 'rescheduling_pending'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SwitchListTile.adaptive(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppTheme.cardBorder),
                ),
                title: const Text(
                  'Open for faculty coverage',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Allows another faculty member to volunteer to cover this slot.',
                  style: TextStyle(fontSize: 12),
                ),
                value: _openForCoverage,
                onChanged: (v) => setState(() => _openForCoverage = v),
              ),
            ],

            // Mode 2: Reschedule Slot (Smart Free Slots + Manual Fine-Tuning)
            if (_mode == _FacultyActionMode.reschedule) ...[
              _buildSmartFreeSlotsSection(),
              const SizedBox(height: 14),
              const Text(
                'Selected / Manual Slot',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_rounded, size: 16),
                      label: Text(
                        DateTimeUtils.formatCampusDate(_selectedDate),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickTime(isStart: true),
                      icon: const Icon(Icons.schedule_rounded, size: 16),
                      label: Text(
                        'Start ${DateTimeUtils.formatTimeOfDay(_startTime)}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickTime(isStart: false),
                      icon: const Icon(Icons.schedule_rounded, size: 16),
                      label: Text(
                        'End ${DateTimeUtils.formatTimeOfDay(_endTime)}',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Room selector for Reschedule or Room Change
            if (_mode == _FacultyActionMode.reschedule ||
                _mode == _FacultyActionMode.roomChange) ...[
              DropdownButtonFormField<String>(
                key: ValueKey('room_$_selectedRoomId'),
                initialValue: _selectedRoomId,
                decoration: const InputDecoration(
                  labelText: 'Classroom / Lab',
                  prefixIcon: Icon(Icons.meeting_room_outlined),
                ),
                items: rooms
                    .map(
                      (r) => DropdownMenuItem(
                        value: r.id,
                        child: Text('${r.displayLabel} · Cap ${r.capacity}'),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val == null) return;
                  setState(() => _selectedRoomId = val);
                  _runConflictCheck();
                },
              ),
              const SizedBox(height: 12),

              // Temporary vs Permanent scope selector
              const Text(
                'Change Scope',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('Temporary (This date)')),
                      selected: _changeScope == 'temporary',
                      onSelected: (_) =>
                          setState(() => _changeScope = 'temporary'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('Permanent (Weekly)')),
                      selected: _changeScope == 'permanent',
                      onSelected: _canMakePermanent
                          ? (_) => setState(() => _changeScope = 'permanent')
                          : null,
                    ),
                  ),
                ],
              ),
              if (!_canMakePermanent) ...[
                const SizedBox(height: 4),
                Text(
                  widget.session.baseTimetableId == null
                      ? 'Permanent updates require a lecture linked to the recurring weekly timetable.'
                      : 'Only the primary assigned faculty or admin can make permanent timetable changes.',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.inkMuted,
                  ),
                ),
              ],
            ],

            // Mode 4: Restore Scheduled info
            if (_mode == _FacultyActionMode.restoreScheduled) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.scheduledStyle.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.scheduledStyle.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.restore_rounded,
                      color: AppTheme.scheduledStyle.foreground,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Restores this session to Scheduled at its current date, time, and room (conflict-checked below).',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.inkPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Live Conflict Check Banner + Free Room Suggestions
            if (_needsConflictCheck) ...[
              const SizedBox(height: 14),
              _ConflictCheckBanner(
                checking: _checkingConflict,
                error: _conflictError,
                result: _conflictResult,
                selectedRoomId: _selectedRoomId,
                onRefresh: _runConflictCheck,
                onSelectRoom: _mode == _FacultyActionMode.restoreScheduled
                    ? null
                    : (roomId) {
                        setState(() => _selectedRoomId = roomId);
                        _runConflictCheck();
                      },
              ),
            ],

            const SizedBox(height: 14),
            TextField(
              controller: _reasonCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason / Note (optional)',
                hintText: 'e.g., Faculty travel, lab equipment maintenance, exam prep',
              ),
            ),
            const SizedBox(height: 16),

            FilledButton.icon(
              onPressed:
                  _submitting ||
                      (_needsConflictCheck &&
                          (_conflictResult?.hasConflict ?? false))
                  ? null
                  : _confirmAndSubmit,
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.fact_check_outlined, size: 18),
              label: Text(
                (_needsConflictCheck && (_conflictResult?.hasConflict ?? false))
                    ? 'Resolve Slot Conflict First'
                    : 'Review & Confirm Update',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConflictCheckBanner extends StatelessWidget {
  const _ConflictCheckBanner({
    required this.checking,
    required this.error,
    required this.result,
    required this.selectedRoomId,
    required this.onRefresh,
    required this.onSelectRoom,
  });

  final bool checking;
  final String? error;
  final SlotConflictResult? result;
  final String selectedRoomId;
  final VoidCallback onRefresh;
  final ValueChanged<String>? onSelectRoom;

  @override
  Widget build(BuildContext context) {
    if (checking) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceTint,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text(
              'Checking cohort, faculty & room conflicts...',
              style: TextStyle(fontSize: 12.5, color: AppTheme.secondarySlate),
            ),
          ],
        ),
      );
    }

    if (error != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.cancelledStyle.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.cancelledStyle.border),
        ),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: AppTheme.cancelledStyle.foreground,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                error!,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.cancelledStyle.foreground,
                ),
              ),
            ),
            TextButton(onPressed: onRefresh, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (result == null) {
      return OutlinedButton.icon(
        onPressed: onRefresh,
        icon: const Icon(Icons.verified_user_outlined, size: 17),
        label: const Text('Check Slot Conflicts'),
      );
    }

    final hasConflict = result!.hasConflict;
    final bg = hasConflict
        ? AppTheme.cancelledStyle.background
        : AppTheme.scheduledStyle.background;
    final border = hasConflict
        ? AppTheme.cancelledStyle.border
        : AppTheme.scheduledStyle.border;
    final fg = hasConflict
        ? AppTheme.cancelledStyle.foreground
        : AppTheme.scheduledStyle.foreground;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasConflict
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                size: 18,
                color: fg,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasConflict
                      ? 'Slot conflict detected'
                      : 'No conflicts — slot is clear!',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Re-check conflicts',
                onPressed: onRefresh,
                icon: Icon(Icons.refresh_rounded, size: 18, color: fg),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _ConflictChip(label: 'Cohort', conflict: result!.cohortConflict),
              _ConflictChip(
                label: 'Faculty',
                conflict: result!.facultyConflict,
              ),
              _ConflictChip(label: 'Room', conflict: result!.roomConflict),
            ],
          ),
          if (result!.suggestedRooms.isNotEmpty && onSelectRoom != null) ...[
            const SizedBox(height: 10),
            const Text(
              'Free rooms for this slot (tap to select):',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.inkPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: result!.suggestedRooms.map((r) {
                final isSelected = r.id == selectedRoomId;
                return ActionChip(
                  avatar: Icon(
                    r.isLab
                        ? Icons.computer_rounded
                        : Icons.meeting_room_outlined,
                    size: 14,
                    color: isSelected ? Colors.white : AppTheme.primaryIndigo,
                  ),
                  label: Text(
                    r.isLab ? '${r.roomNumber} (Lab)' : r.roomNumber,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : AppTheme.inkPrimary,
                    ),
                  ),
                  backgroundColor: isSelected
                      ? AppTheme.primaryIndigo
                      : Colors.white,
                  onPressed: () => onSelectRoom!(r.id),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConflictChip extends StatelessWidget {
  const _ConflictChip({required this.label, required this.conflict});

  final String label;
  final bool conflict;

  @override
  Widget build(BuildContext context) {
    final style = conflict ? AppTheme.cancelledStyle : AppTheme.scheduledStyle;
    return InfoPill(
      label: conflict ? '$label Conflict' : '$label Free',
      icon: conflict ? Icons.close_rounded : Icons.check_rounded,
      foreground: style.foreground,
      background: Colors.white,
      border: style.border,
    );
  }
}
