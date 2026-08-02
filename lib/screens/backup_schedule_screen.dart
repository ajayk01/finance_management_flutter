import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/backup_scheduler_service.dart';

class BackupScheduleScreen extends StatefulWidget {
  const BackupScheduleScreen({super.key});

  @override
  State<BackupScheduleScreen> createState() => _BackupScheduleScreenState();
}

class _BackupScheduleScreenState extends State<BackupScheduleScreen> {
  final _service = BackupSchedulerService.instance;

  bool _loading = true;
  bool _saving = false;
  bool _runningNow = false;
  bool _enabled = false;
  List<TimeOfDay> _times = const [TimeOfDay(hour: 10, minute: 0)];
  DateTime? _lastRunAt;
  List<DateTime> _nextRunAts = const [];
  String? _lastStatus;
  String? _lastError;
  String? _lastBackupPath;

  @override
  void initState() {
    super.initState();
    _loadSnapshot();
  }

  Future<void> _loadSnapshot() async {
    setState(() => _loading = true);
    final snapshot = await _service.loadSnapshot();
    if (!mounted) {
      return;
    }

    setState(() {
      _enabled = snapshot.enabled;
      _times = List<TimeOfDay>.from(snapshot.times);
      _lastRunAt = snapshot.lastRunAt;
      _nextRunAts = List<DateTime>.from(snapshot.nextRunAts);
      _lastStatus = snapshot.lastStatus;
      _lastError = snapshot.lastError;
      _lastBackupPath = snapshot.lastBackupPath;
      _loading = false;
    });
  }

  Future<void> _saveSchedule() async {
    setState(() => _saving = true);
    await _service.updateSchedule(enabled: _enabled, times: _times);
    final snapshot = await _service.loadSnapshot();
    if (!mounted) {
      return;
    }

    setState(() {
      _enabled = snapshot.enabled;
      _times = List<TimeOfDay>.from(snapshot.times);
      _lastRunAt = snapshot.lastRunAt;
      _nextRunAts = List<DateTime>.from(snapshot.nextRunAts);
      _lastStatus = snapshot.lastStatus;
      _lastError = snapshot.lastError;
      _lastBackupPath = snapshot.lastBackupPath;
      _saving = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Backup schedule updated')),
    );
  }

  Future<void> _pickTime({int? editIndex}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: editIndex == null
          ? const TimeOfDay(hour: 10, minute: 0)
          : _times[editIndex],
    );

    if (picked == null) {
      return;
    }

    final existingAtOtherIndex = _times
        .asMap()
        .entries
        .where(
          (entry) =>
              entry.value.hour == picked.hour &&
              entry.value.minute == picked.minute,
        )
        .map((entry) => entry.key)
        .firstWhere(
          (index) => editIndex == null || index != editIndex,
          orElse: () => -1,
        );
    if (existingAtOtherIndex != -1) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That time is already in your schedule.')),
      );
      return;
    }

    setState(() {
      final updated = List<TimeOfDay>.from(_times);
      if (editIndex == null) {
        updated.add(picked);
      } else {
        updated[editIndex] = picked;
      }
      _times = _sortTimes(updated);
    });
    await _saveSchedule();
  }

  Future<void> _toggleEnabled(bool value) async {
    setState(() {
      if (value && _times.isEmpty) {
        _times = const [TimeOfDay(hour: 10, minute: 0)];
      }
      _enabled = value;
    });
    await _saveSchedule();
  }

  Future<void> _removeTime(int index) async {
    final updated = List<TimeOfDay>.from(_times)..removeAt(index);
    setState(() {
      _times = _sortTimes(updated);
      if (_times.isEmpty) {
        _enabled = false;
      }
    });
    await _saveSchedule();
  }

  Future<void> _runNow() async {
    setState(() => _runningNow = true);
    final snapshotBefore = await _service.loadSnapshot();
    await _service.runBackupNow();
    final snapshot = await _service.loadSnapshot();
    if (!mounted) {
      return;
    }

    setState(() {
      _enabled = snapshot.enabled;
      _times = List<TimeOfDay>.from(snapshot.times);
      _lastRunAt = snapshot.lastRunAt;
      _nextRunAts = List<DateTime>.from(snapshot.nextRunAts);
      _lastStatus = snapshot.lastStatus;
      _lastError = snapshot.lastError;
      _lastBackupPath = snapshot.lastBackupPath;
      _runningNow = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          snapshot.lastError == null &&
                  snapshot.lastRunAt != snapshotBefore.lastRunAt
              ? 'Backup completed'
              : 'Backup finished with errors',
        ),
      ),
    );
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) {
      return 'Not yet run';
    }

    return DateFormat('EEE, dd MMM yyyy • hh:mm a').format(dateTime);
  }

  List<TimeOfDay> _sortTimes(List<TimeOfDay> times) {
    final sorted = List<TimeOfDay>.from(times)
      ..sort(
        (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute),
      );
    return sorted;
  }

  String _formatNextRuns(List<DateTime> nextRuns) {
    if (nextRuns.isEmpty) {
      return 'Not scheduled';
    }

    return nextRuns
        .map((run) => DateFormat('EEE, dd MMM yyyy • hh:mm a').format(run))
        .join('\n');
  }

  String _formatTime(TimeOfDay timeOfDay) {
    final now = DateTime.now();
    final dateTime = DateTime(
        now.year, now.month, now.day, timeOfDay.hour, timeOfDay.minute);
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(dateTime),
      alwaysUse24HourFormat: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup Schedule'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildSummaryCard(),
                const SizedBox(height: 16),
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: _enabled,
                        onChanged: _saving ? null : _toggleEnabled,
                        title: const Text('Enable scheduled backups'),
                        subtitle: const Text(
                            'Runs MySQL backup automatically at one or more times each day.'),
                      ),
                      const Divider(height: 1),
                      if (_times.isEmpty)
                        const ListTile(
                          title: Text('No times added'),
                          subtitle: Text(
                              'Add at least one time to enable scheduling.'),
                        )
                      else
                        ..._times.asMap().entries.expand(
                              (entry) => [
                                ListTile(
                                  enabled: !_saving,
                                  title: Text('Backup time ${entry.key + 1}'),
                                  subtitle: Text(_formatTime(entry.value)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Edit time',
                                        onPressed: _saving
                                            ? null
                                            : () =>
                                                _pickTime(editIndex: entry.key),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        tooltip: 'Remove time',
                                        onPressed: _saving
                                            ? null
                                            : () => _removeTime(entry.key),
                                        icon: const Icon(
                                            Icons.delete_outline_rounded),
                                      ),
                                    ],
                                  ),
                                ),
                                const Divider(height: 1),
                              ],
                            ),
                      ListTile(
                        enabled: !_saving,
                        title: const Text('Add backup time'),
                        trailing: const Icon(Icons.add_rounded),
                        onTap: _saving ? null : () => _pickTime(),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: const Text('Next run'),
                        subtitle: Text(_formatNextRuns(_nextRunAts)),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: const Text('Last run'),
                        subtitle: Text(_formatDateTime(_lastRunAt)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Latest status',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _lastStatus ?? 'No backup has been executed yet.',
                          style: const TextStyle(color: Color(0xFF4B5563)),
                        ),
                        if ((_lastError ?? '').isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            _lastError!,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ],
                        if ((_lastBackupPath ?? '').isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            _lastBackupPath!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _runningNow ? null : _runNow,
                  icon: _runningNow
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(
                      _runningNow ? 'Running backup...' : 'Run backup now'),
                ),
              ],
            ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF111827), Color(0xFF1D4ED8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Daily MySQL backup',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _enabled
                ? 'Scheduled ${_times.length} time(s) daily.'
                : 'Scheduling is currently off.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
