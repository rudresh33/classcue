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
  });

  DateTime date;
  TimeOfDay startTime;
  TimeOfDay endTime;
  String? roomId;
  SlotConflictResult? conflict;
  bool checking = false;
  String? error;
}

/// Modal Bottom Sheet for CR / Faculty / Admin to open a new reschedule poll
/// with 2–4 conflict-checked proposed slots and an IST closing deadline.
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

  SupabaseService get _service => context.read<AuthProvider>().service;
  UserProfile get _profile => context.read<AuthProvider>().profile!;

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

    if (widget.initialSession != null) {
      _selectedSession = widget.initialSession;
      _eligibleSessions = [widget.initialSession!];
      _loadingSessions = false;
      _seedDefaultOptions(widget.initialSession!);
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
          return s.facultyId == _profile.id ||
              s.coveringFacultyId == _profile.id;
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
        _seedDefaultOptions(_selectedSession!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingSessions = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(DateTimeUtils.prettifyError(e))));
    }
  }

  void _seedDefaultOptions(LectureSession session) {
    final today = DateTimeUtils.todayIst();
    final baseDate = session.sessionDate.isBefore(today)
        ? today
        : session.sessionDate;
    final nextDay1 = _nextWorkingDay(baseDate.add(const Duration(days: 1)));
    final nextDay2 = _nextWorkingDay(nextDay1.add(const Duration(days: 1)));

    _options
      ..clear()
      ..addAll([
        _EditablePollOption(
          date: nextDay1,
          startTime: DateTimeUtils.parseSqlTime(session.startTime),
          endTime: DateTimeUtils.parseSqlTime(session.endTime),
          roomId: session.roomId,
        ),
        _EditablePollOption(
          date: nextDay2,
          startTime: DateTimeUtils.parseSqlTime(session.startTime),
          endTime: DateTimeUtils.parseSqlTime(session.endTime),
          roomId: session.roomId,
        ),
      ]);
    for (int i = 0; i < _options.length; i++) {
      _checkOptionConflict(i);
    }
  }

  DateTime _nextWorkingDay(DateTime d) {
    return d.weekday == DateTime.sunday ? d.add(const Duration(days: 1)) : d;
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
      // Anti-probing rules:
      // - Faculty -> MUST pass auth.uid()
      // - CR -> MUST pass target session's faculty_id
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

  void _addOption() {
    if (_options.length >= 4 || _selectedSession == null) return;
    final last = _options.last;
    final nextDate = _nextWorkingDay(last.date.add(const Duration(days: 1)));
    setState(() {
      _options.add(
        _EditablePollOption(
          date: nextDate,
          startTime: last.startTime,
          endTime: last.endTime,
          roomId: last.roomId,
        ),
      );
    });
    _checkOptionConflict(_options.length - 1);
  }

  void _removeOption(int index) {
    if (_options.length <= 2) return;
    setState(() => _options.removeAt(index));
  }

  Future<void> _submit() async {
    final session = _selectedSession;
    if (session == null) return;

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
        initialChildSize: 0.85,
        minChildSize: 0.55,
        maxChildSize: 0.95,
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
                'Add 2–4 conflict-checked replacement slots. Students vote anonymously; assigned faculty confirms the winning slot.',
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
                          setState(() => _selectedSession = s);
                          _seedDefaultOptions(s);
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
                const SizedBox(height: 16),

                // Options header
                Row(
                  children: [
                    Text(
                      'Proposed Slots (${_options.length}/4)',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    if (_options.length < 4)
                      TextButton.icon(
                        onPressed: _addOption,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add Option'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),

                for (int i = 0; i < _options.length; i++)
                  _buildOptionCard(i, rooms),

                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
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
                  label: const Text('Publish Reschedule Poll'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildOptionCard(int index, List<Room> rooms) {
    final opt = _options[index];
    final today = DateTimeUtils.todayIst();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Option ${index + 1}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryIndigo,
                  ),
                ),
                const Spacer(),
                if (_options.length > 2)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Remove option',
                    onPressed: () => _removeOption(index),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: opt.date.isBefore(today)
                            ? today
                            : opt.date,
                        firstDate: today,
                        lastDate: today.add(const Duration(days: 120)),
                      );
                      if (picked != null) {
                        setState(() => opt.date = picked);
                        _checkOptionConflict(index);
                      }
                    },
                    icon: const Icon(Icons.calendar_today_rounded, size: 14),
                    label: Text(DateTimeUtils.formatCampusDate(opt.date)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: opt.startTime,
                      );
                      if (picked != null) {
                        setState(() => opt.startTime = picked);
                        _checkOptionConflict(index);
                      }
                    },
                    child: Text(
                      'Start ${DateTimeUtils.formatTimeOfDay(opt.startTime)}',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: opt.endTime,
                      );
                      if (picked != null) {
                        setState(() => opt.endTime = picked);
                        _checkOptionConflict(index);
                      }
                    },
                    child: Text(
                      'End ${DateTimeUtils.formatTimeOfDay(opt.endTime)}',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              initialValue: opt.roomId,
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
                setState(() => opt.roomId = val);
                _checkOptionConflict(index);
              },
            ),
            const SizedBox(height: 8),
            if (opt.checking)
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
                    style: TextStyle(fontSize: 11.5, color: AppTheme.inkMuted),
                  ),
                ],
              )
            else if (opt.error != null)
              Text(
                opt.error!,
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.cancelledStyle.foreground,
                ),
              )
            else if (opt.conflict != null) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  InfoPill(
                    label: opt.conflict!.hasConflict
                        ? 'Conflict Detected'
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
                  if (opt.conflict!.cohortConflict)
                    const InfoPill(label: 'Cohort busy'),
                  if (opt.conflict!.facultyConflict)
                    const InfoPill(label: 'Faculty busy'),
                  if (opt.conflict!.roomConflict)
                    const InfoPill(label: 'Room busy'),
                ],
              ),
              if (opt.conflict!.roomConflict &&
                  opt.conflict!.suggestedRooms.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: opt.conflict!.suggestedRooms.take(4).map((r) {
                    return ActionChip(
                      label: Text(
                        'Use ${r.roomNumber}',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      onPressed: () {
                        setState(() => opt.roomId = r.id);
                        _checkOptionConflict(index);
                      },
                    );
                  }).toList(),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
