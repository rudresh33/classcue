import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_time_utils.dart';
import '../../core/widgets/widgets.dart';
import '../auth/auth_provider.dart';

class _EditablePollOption {
  _EditablePollOption({
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.roomId,
    this.verifiedBySmartFinder = false,
    this.sourceLabel,
  });

  DateTime date;
  TimeOfDay startTime;
  TimeOfDay endTime;
  String? roomId;
  bool verifiedBySmartFinder;
  String? sourceLabel;
  SlotConflictResult? conflict;
  bool checking = false;
  String? error;

  String get slotKey =>
      '${DateTimeUtils.toSqlDate(date)}|${DateTimeUtils.toSqlTime(startTime)}|${DateTimeUtils.toSqlTime(endTime)}';
}

/// Modal Bottom Sheet for CR / Faculty / Admin to open a new reschedule poll
/// powered by `get_available_slots` for 1-tap conflict-free option picking,
/// plus a collapsible manual slot builder validated via `check_slot_conflicts`.
class CreatePollSheet extends StatefulWidget {
  const CreatePollSheet({super.key, this.initialSession});

  final LectureSession? initialSession;

  static Future<bool> show(
    BuildContext context, {
    LectureSession? initialSession,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => CreatePollSheet(initialSession: initialSession),
    );
    return result == true;
  }

  @override
  State<CreatePollSheet> createState() => _CreatePollSheetState();
}

class _CreatePollSheetState extends State<CreatePollSheet> {
  List<LectureSession> _eligibleSessions = [];
  LectureSession? _selectedSession;
  bool _loadingSessions = true;
  bool _submitting = false;

  late DateTime _closesAtIstDate;
  late TimeOfDay _closesAtIstTime;

  final List<_EditablePollOption> _options = [];

  // Smart Free-Slot Picker state
  List<AvailableSlot> _smartSlots = [];
  bool _loadingSmartSlots = false;
  String? _smartSlotsError;
  int _smartDurationMinutes = 120;
  bool _includeSaturday = true;
  bool _allowLunch = false;
  int _daysAhead = 7;
  int _maxPerDay = 3;

  // Collapsible manual custom slot builder
  bool _showManualBuilder = false;
  late DateTime _manualDate;
  TimeOfDay _manualStart = const TimeOfDay(hour: 10, minute: 30);
  TimeOfDay _manualEnd = const TimeOfDay(hour: 12, minute: 30);
  String? _manualRoomId;
  SlotConflictResult? _manualConflict;
  bool _checkingManual = false;
  String? _manualError;

  SupabaseService get _service => context.read<AuthProvider>().service;
  UserProfile get _profile => context.read<AuthProvider>().profile!;

  int get _originalDurationMinutes =>
      (_selectedSession?.baselineDurationMinutes ?? 120).clamp(30, 240);

  @override
  void initState() {
    super.initState();
    final defaultCloseIst = DateTimeUtils.nowIst().add(
      const Duration(hours: 6),
    );
    _closesAtIstDate = DateTime(
      defaultCloseIst.year,
      defaultCloseIst.month,
      defaultCloseIst.day,
    );
    _closesAtIstTime = TimeOfDay(
      hour: defaultCloseIst.hour,
      minute: (defaultCloseIst.minute ~/ 15) * 15,
    );
    _manualDate = DateTimeUtils.todayIst().add(const Duration(days: 1));

    if (widget.initialSession != null) {
      _selectedSession = widget.initialSession;
      _eligibleSessions = [widget.initialSession!];
      _loadingSessions = false;
      _onSessionSelected(widget.initialSession!);
    } else {
      _loadEligibleSessions();
    }
  }

  Future<void> _loadEligibleSessions() async {
    try {
      final today = DateTimeUtils.todayIst();
      final sessions = await _service.fetchSessionsInRange(
        startDate: today,
        endDate: today.add(const Duration(days: 21)),
      );
      final filtered = sessions.where((s) {
        if (_profile.isAdmin || _profile.isCr) return true;
        if (_profile.isFaculty) {
          return s.facultyId == _profile.id;
        }
        return false;
      }).toList();

      if (!mounted) return;
      setState(() {
        _eligibleSessions = filtered;
        _selectedSession = filtered.isNotEmpty ? filtered.first : null;
        _loadingSessions = false;
      });
      if (_selectedSession != null) {
        _onSessionSelected(_selectedSession!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingSessions = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(DateTimeUtils.prettifyError(e))));
    }
  }

  void _onSessionSelected(LectureSession session) {
    final today = DateTimeUtils.todayIst();
    final baseDate = session.sessionDate.isBefore(today)
        ? today
        : session.sessionDate;
    var nextDay = baseDate.add(const Duration(days: 1));
    if (nextDay.weekday == DateTime.sunday) {
      nextDay = nextDay.add(const Duration(days: 1));
    }

    final baseStart = session.preCoverageStartTime ?? session.startTime;
    final baseEnd = session.preCoverageEndTime ?? session.endTime;

    setState(() {
      _selectedSession = session;
      _options.clear();
      _smartDurationMinutes = session.baselineDurationMinutes.clamp(30, 240);
      _daysAhead = 7;
      _maxPerDay = 3;
      _manualDate = nextDay;
      _manualStart = DateTimeUtils.parseSqlTime(baseStart);
      _manualEnd = DateTimeUtils.parseSqlTime(baseEnd);
      _manualRoomId = session.roomId;
      _manualConflict = null;
      _manualError = null;
    });
    _loadSmartSlots();
  }

  Future<void> _loadSmartSlots() async {
    final session = _selectedSession;
    if (session == null) return;

    setState(() {
      _loadingSmartSlots = true;
      _smartSlotsError = null;
    });

    try {
      final slots = await _service.getAvailableSlots(
        sessionId: session.id,
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

  bool _isSlotAlreadyAdded(AvailableSlot slot) {
    return _options.any((o) => o.slotKey == slot.slotKey);
  }

  void _addSmartSlot(AvailableSlot slot) {
    if (_options.length >= 4 || _isSlotAlreadyAdded(slot)) return;
    setState(() {
      _options.add(
        _EditablePollOption(
          date: slot.slotDate,
          startTime: DateTimeUtils.parseSqlTime(slot.startTime),
          endTime: DateTimeUtils.parseSqlTime(slot.endTime),
          roomId: slot.recommendedRoomId,
          verifiedBySmartFinder: true,
          sourceLabel: slot.slotLabel,
        ),
      );
    });
  }

  Future<void> _checkManualSlotConflict() async {
    final session = _selectedSession;
    if (session == null) return;
    if (DateTimeUtils.timeOfDayToMinutes(_manualEnd) <=
        DateTimeUtils.timeOfDayToMinutes(_manualStart)) {
      setState(() {
        _manualConflict = null;
        _manualError = 'End time must be after start time.';
      });
      return;
    }

    setState(() {
      _checkingManual = true;
      _manualError = null;
    });

    try {
      // Anti-probing rules: Faculty -> auth.uid(), CR -> session.facultyId
      final facultyId = _profile.isFaculty ? _profile.id : session.facultyId;
      final res = await _service.checkSlotConflicts(
        courseId: session.courseId,
        sessionDate: _manualDate,
        startTime: DateTimeUtils.toSqlTime(_manualStart),
        endTime: DateTimeUtils.toSqlTime(_manualEnd),
        roomId: _manualRoomId,
        facultyId: facultyId,
        batch: session.batch,
        excludeSessionId: session.id,
      );
      if (!mounted) return;
      setState(() {
        _manualConflict = res;
        _checkingManual = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _manualConflict = null;
        _manualError = DateTimeUtils.prettifyError(e);
        _checkingManual = false;
      });
    }
  }

  void _addManualOption() {
    if (_options.length >= 4) {
      _showSnack('Maximum 4 options allowed per poll.');
      return;
    }
    if (DateTimeUtils.timeOfDayToMinutes(_manualEnd) <=
        DateTimeUtils.timeOfDayToMinutes(_manualStart)) {
      _showSnack('End time must be after start time.');
      return;
    }
    final todayIst = DateTimeUtils.todayIst();
    if (_manualDate.isBefore(todayIst)) {
      _showSnack('Proposed date cannot be in the past (IST).');
      return;
    }
    final newOpt = _EditablePollOption(
      date: _manualDate,
      startTime: _manualStart,
      endTime: _manualEnd,
      roomId: _manualRoomId,
      verifiedBySmartFinder: false,
    )..conflict = _manualConflict;

    if (_options.any((o) => o.slotKey == newOpt.slotKey)) {
      _showSnack('This exact date and time window is already in your options.');
      return;
    }

    setState(() {
      _options.add(newOpt);
      _showManualBuilder = false;
    });
    if (newOpt.conflict == null) {
      _checkOptionConflict(_options.length - 1);
    }
  }

  Future<void> _checkOptionConflict(int index) async {
    final session = _selectedSession;
    if (session == null || index < 0 || index >= _options.length) return;
    final opt = _options[index];

    if (DateTimeUtils.timeOfDayToMinutes(opt.endTime) <=
        DateTimeUtils.timeOfDayToMinutes(opt.startTime)) {
      setState(() {
        opt.conflict = null;
        opt.error = 'End time must be after start time.';
      });
      return;
    }

    setState(() {
      opt.checking = true;
      opt.error = null;
    });

    try {
      final facultyId = _profile.isFaculty ? _profile.id : session.facultyId;
      final res = await _service.checkSlotConflicts(
        courseId: session.courseId,
        sessionDate: opt.date,
        startTime: DateTimeUtils.toSqlTime(opt.startTime),
        endTime: DateTimeUtils.toSqlTime(opt.endTime),
        roomId: opt.roomId,
        facultyId: facultyId,
        batch: session.batch,
        excludeSessionId: session.id,
      );
      if (!mounted) return;
      setState(() {
        opt.conflict = res;
        opt.checking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        opt.conflict = null;
        opt.error = DateTimeUtils.prettifyError(e);
        opt.checking = false;
      });
    }
  }

  void _removeOption(int index) {
    setState(() => _options.removeAt(index));
  }

  Future<void> _submit() async {
    final session = _selectedSession;
    if (session == null) return;

    if (_options.length < 2) {
      _showSnack('Add at least 2 proposed slots before publishing the poll.');
      return;
    }

    final todayIst = DateTimeUtils.todayIst();
    for (int i = 0; i < _options.length; i++) {
      final opt = _options[i];
      if (opt.date.isBefore(todayIst)) {
        _showSnack('Option ${i + 1} date cannot be in the past (IST).');
        return;
      }
      if (DateTimeUtils.timeOfDayToMinutes(opt.endTime) <=
          DateTimeUtils.timeOfDayToMinutes(opt.startTime)) {
        _showSnack('Option ${i + 1}: end time must be after start time.');
        return;
      }
    }

    final closesAtUtc = DateTimeUtils.istWallToUtc(
      DateTime(
        _closesAtIstDate.year,
        _closesAtIstDate.month,
        _closesAtIstDate.day,
        _closesAtIstTime.hour,
        _closesAtIstTime.minute,
      ),
    );
    if (!closesAtUtc.isAfter(DateTime.now().toUtc())) {
      _showSnack('Poll closing time must be in the future (IST).');
      return;
    }

    setState(() => _submitting = true);
    try {
      await _service.createPollWithOptions(
        lectureSessionId: session.id,
        closesAtUtc: closesAtUtc,
        options: _options
            .map(
              (o) => PollOptionDraft(
                proposedDate: o.date,
                proposedStartTime: DateTimeUtils.toSqlTime(o.startTime),
                proposedEndTime: DateTimeUtils.toSqlTime(o.endTime),
                proposedRoomId: o.roomId,
              ),
            )
            .toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _showSnack(DateTimeUtils.prettifyError(e));
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _buildSmartSlotPicker() {
    final standardDurations = <int>[60, 90, 120];
    final showOriginalChip = !standardDurations.contains(
      _originalDurationMinutes,
    );
    final atMax = _options.length >= 4;

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
                  'Conflict-Free Suggested Slots',
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
                  tooltip: 'Refresh suggestions',
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
            'Tap "+ Add" to include up to 4 verified conflict-free slots in the poll.',
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
                  onSelected: (_) {
                    setState(() => _smartDurationMinutes = mins);
                    _loadSmartSlots();
                  },
                ),
              if (showOriginalChip)
                ChoiceChip(
                  label: Text(
                    'Original (${DateTimeUtils.formatMinutesShort(_originalDurationMinutes)})',
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: _smartDurationMinutes == _originalDurationMinutes,
                  onSelected: (_) {
                    setState(
                      () => _smartDurationMinutes = _originalDurationMinutes,
                    );
                    _loadSmartSlots();
                  },
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
                  _daysAhead >= 14 ? 'Showing 14 days' : 'Search 14 days',
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
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _smartSlots.length,
                itemBuilder: (_, idx) {
                  final slot = _smartSlots[idx];
                  final added = _isSlotAlreadyAdded(slot);
                  return SmartSlotCard(
                    slot: slot,
                    isSelected: added,
                    onTap: (!added && !atMax)
                        ? () => _addSmartSlot(slot)
                        : null,
                    trailing: added
                        ? InfoPill(
                            label: 'Added',
                            icon: Icons.check_rounded,
                            foreground: AppTheme.scheduledStyle.foreground,
                            background: AppTheme.scheduledStyle.background,
                            border: AppTheme.scheduledStyle.border,
                          )
                        : FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: atMax ? null : () => _addSmartSlot(slot),
                            child: const Text(
                              '+ Add',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildManualCustomBuilder(List<Room> rooms) {
    final today = DateTimeUtils.todayIst();
    return Card(
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              setState(() => _showManualBuilder = !_showManualBuilder);
              if (_showManualBuilder) {
                _checkManualSlotConflict();
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: AppTheme.secondarySlate,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Add custom slot manually',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.inkPrimary,
                      ),
                    ),
                  ),
                  Icon(
                    _showManualBuilder
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.inkMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_showManualBuilder) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _manualDate.isBefore(today)
                            ? today
                            : _manualDate,
                        firstDate: today,
                        lastDate: today.add(const Duration(days: 120)),
                      );
                      if (picked != null) {
                        setState(() => _manualDate = picked);
                        _checkManualSlotConflict();
                      }
                    },
                    icon: const Icon(Icons.calendar_today_rounded, size: 15),
                    label: Text(DateTimeUtils.formatCampusDate(_manualDate)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: _manualStart,
                            );
                            if (picked != null) {
                              setState(() => _manualStart = picked);
                              _checkManualSlotConflict();
                            }
                          },
                          child: Text(
                            'Start ${DateTimeUtils.formatTimeOfDay(_manualStart)}',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: _manualEnd,
                            );
                            if (picked != null) {
                              setState(() => _manualEnd = picked);
                              _checkManualSlotConflict();
                            }
                          },
                          child: Text(
                            'End ${DateTimeUtils.formatTimeOfDay(_manualEnd)}',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    key: ValueKey('manual_room_$_manualRoomId'),
                    initialValue: _manualRoomId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Proposed Room',
                      isDense: true,
                    ),
                    items: rooms
                        .map(
                          (r) => DropdownMenuItem<String?>(
                            value: r.id,
                            child: Text(r.displayLabel),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      setState(() => _manualRoomId = val);
                      _checkManualSlotConflict();
                    },
                  ),
                  const SizedBox(height: 8),
                  if (_checkingManual)
                    const Row(
                      children: [
                        SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Checking conflicts...',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.inkMuted,
                          ),
                        ),
                      ],
                    )
                  else if (_manualError != null)
                    Text(
                      _manualError!,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.cancelledStyle.foreground,
                      ),
                    )
                  else if (_manualConflict != null) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        InfoPill(
                          label: _manualConflict!.hasConflict
                              ? 'Conflict Detected'
                              : 'Slot Clear',
                          icon: _manualConflict!.hasConflict
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle_outline_rounded,
                          foreground: _manualConflict!.hasConflict
                              ? AppTheme.cancelledStyle.foreground
                              : AppTheme.scheduledStyle.foreground,
                          background: _manualConflict!.hasConflict
                              ? AppTheme.cancelledStyle.background
                              : AppTheme.scheduledStyle.background,
                          border: _manualConflict!.hasConflict
                              ? AppTheme.cancelledStyle.border
                              : AppTheme.scheduledStyle.border,
                        ),
                        if (_manualConflict!.cohortConflict)
                          const InfoPill(label: 'Cohort busy'),
                        if (_manualConflict!.facultyConflict)
                          const InfoPill(label: 'Faculty busy'),
                        if (_manualConflict!.roomConflict)
                          const InfoPill(label: 'Room busy'),
                      ],
                    ),
                    if (_manualConflict!.roomConflict &&
                        _manualConflict!.suggestedRooms.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: _manualConflict!.suggestedRooms.take(4).map((
                          r,
                        ) {
                          return ActionChip(
                            label: Text(
                              'Use ${r.roomNumber}',
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            onPressed: () {
                              setState(() => _manualRoomId = r.id);
                              _checkManualSlotConflict();
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: _options.length >= 4 ? null : _addManualOption,
                    icon: const Icon(Icons.add_rounded, size: 17),
                    label: const Text('Add Custom Slot to Poll'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _service.rooms;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.88,
        minChildSize: 0.55,
        maxChildSize: 0.96,
        expand: false,
        builder: (context, scrollCtrl) {
          return ListView(
            controller: scrollCtrl,
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
              const Text(
                'Create Reschedule Poll',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.inkPrimary,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'Pick 2–4 conflict-free replacement slots. Students vote anonymously; assigned faculty confirms the winning slot.',
                style: TextStyle(fontSize: 12.5, color: AppTheme.inkMuted),
              ),
              const SizedBox(height: 14),

              if (_loadingSessions)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_eligibleSessions.isEmpty)
                const EmptyStateView(
                  icon: Icons.event_busy_outlined,
                  title: 'No upcoming sessions found',
                  subtitle: 'There are no upcoming lecture sessions in the next 3 weeks eligible for a reschedule poll.',
                )
              else ...[
                // Target session dropdown
                DropdownButtonFormField<String>(
                  initialValue: _selectedSession?.id,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Target Lecture Session',
                    prefixIcon: Icon(Icons.class_outlined),
                  ),
                  items: _eligibleSessions.map((s) {
                    final course = _service.courseById(s.courseId);
                    return DropdownMenuItem(
                      value: s.id,
                      child: Text(
                        '${course?.code ?? ''} · ${DateTimeUtils.formatSlotSummary(s.sessionDate, s.startTime, s.endTime)}${s.batch != 'ALL' ? ' (${s.batch})' : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: widget.initialSession != null
                      ? null
                      : (id) {
                          if (id == null) return;
                          final s = _eligibleSessions.firstWhere(
                            (e) => e.id == id,
                          );
                          _onSessionSelected(s);
                        },
                ),
                const SizedBox(height: 14),

                // Voting deadline (IST)
                const Text(
                  'Voting Closes (IST)',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final today = DateTimeUtils.todayIst();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _closesAtIstDate.isBefore(today)
                                ? today
                                : _closesAtIstDate,
                            firstDate: today,
                            lastDate: today.add(const Duration(days: 30)),
                          );
                          if (picked != null) {
                            setState(() => _closesAtIstDate = picked);
                          }
                        },
                        icon: const Icon(
                          Icons.calendar_today_rounded,
                          size: 15,
                        ),
                        label: Text(
                          DateTimeUtils.formatCampusDate(_closesAtIstDate),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: _closesAtIstTime,
                          );
                          if (picked != null) {
                            setState(() => _closesAtIstTime = picked);
                          }
                        },
                        icon: const Icon(Icons.timer_outlined, size: 16),
                        label: Text(
                          '${DateTimeUtils.formatTimeOfDay(_closesAtIstTime)} IST',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Smart Free-Slot Picker
                _buildSmartSlotPicker(),
                const SizedBox(height: 16),

                // Selected poll options list
                Row(
                  children: [
                    Text(
                      'Selected Poll Options (${_options.length}/4)',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    if (_options.length < 2)
                      const Text(
                        'Add at least 2',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.inkMuted,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                if (_options.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceTint,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.cardBorder),
                    ),
                    child: const Text(
                      'Tap "+ Add" on 2–4 conflict-free suggestions above, or expand "Add custom slot manually" below.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.inkMuted,
                      ),
                    ),
                  )
                else
                  for (int i = 0; i < _options.length; i++)
                    _buildSelectedOptionCard(i, rooms),

                const SizedBox(height: 10),
                _buildManualCustomBuilder(rooms),

                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: (_submitting || _options.length < 2)
                      ? null
                      : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.how_to_vote_rounded, size: 18),
                  label: Text(
                    _options.length < 2
                        ? 'Select at Least 2 Slots to Publish'
                        : 'Publish Reschedule Poll (${_options.length} Options)',
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildSelectedOptionCard(int index, List<Room> rooms) {
    final opt = _options[index];
    final room = _service.roomById(opt.roomId);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Option ${index + 1}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryIndigo,
                  ),
                ),
                const SizedBox(width: 8),
                if (opt.verifiedBySmartFinder && opt.conflict == null)
                  InfoPill(
                    label: 'Conflict-Free',
                    icon: Icons.verified_outlined,
                    foreground: AppTheme.scheduledStyle.foreground,
                    background: AppTheme.scheduledStyle.background,
                    border: AppTheme.scheduledStyle.border,
                  )
                else if (opt.conflict != null)
                  InfoPill(
                    label: opt.conflict!.hasConflict
                        ? 'Conflict'
                        : 'Slot Clear',
                    icon: opt.conflict!.hasConflict
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline_rounded,
                    foreground: opt.conflict!.hasConflict
                        ? AppTheme.cancelledStyle.foreground
                        : AppTheme.scheduledStyle.foreground,
                    background: opt.conflict!.hasConflict
                        ? AppTheme.cancelledStyle.background
                        : AppTheme.scheduledStyle.background,
                    border: opt.conflict!.hasConflict
                        ? AppTheme.cancelledStyle.border
                        : AppTheme.scheduledStyle.border,
                  ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Remove option',
                  onPressed: () => _removeOption(index),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${DateTimeUtils.formatSlotSummary(opt.date, DateTimeUtils.toSqlTime(opt.startTime), DateTimeUtils.toSqlTime(opt.endTime))} · ${room?.displayLabel ?? 'Room TBD'}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.inkPrimary,
              ),
            ),
            if (opt.sourceLabel != null &&
                opt.sourceLabel!.trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                opt.sourceLabel!,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.inkMuted,
                ),
              ),
            ],
            if (opt.checking)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Verifying slot...',
                      style: TextStyle(fontSize: 11, color: AppTheme.inkMuted),
                    ),
                  ],
                ),
              )
            else if (opt.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  opt.error!,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.cancelledStyle.foreground,
                  ),
                ),
              ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String?>(
              key: ValueKey('opt_${index}_${opt.roomId}'),
              initialValue: opt.roomId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Room',
                isDense: true,
              ),
              items: rooms
                  .map(
                    (r) => DropdownMenuItem<String?>(
                      value: r.id,
                      child: Text(r.displayLabel),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                setState(() {
                  opt.roomId = val;
                  opt.verifiedBySmartFinder = false;
                });
                _checkOptionConflict(index);
              },
            ),
          ],
        ),
      ),
    );
  }
}
