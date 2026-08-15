import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'google_drive_backup_service.dart';
import 'mysql_service.dart';

const int _backupAlarmIdBase = 700100;
const String _enabledKey = 'backup_schedule_enabled';
const String _hourKey = 'backup_schedule_hour';
const String _minuteKey = 'backup_schedule_minute';
const String _timesKey = 'backup_schedule_times';
const String _lastRunAtKey = 'backup_schedule_last_run_at';
const String _lastStatusKey = 'backup_schedule_last_status';
const String _lastErrorKey = 'backup_schedule_last_error';
const String _lastBackupPathKey = 'backup_schedule_last_backup_path';
const String _nextRunAtListKey = 'backup_schedule_next_run_at_list';
const String _scheduledAlarmCountKey = 'backup_schedule_alarm_count';
const String _pendingUploadPathsKey = 'backup_schedule_pending_upload_paths';
const String _backupStatusChannelId = 'backup_status_channel';
const String _backupStatusChannelName = 'Backup Status Notifications';
const String _backupStatusChannelDescription =
  'Shows backup start, completion, or failure.';
const int _backupInProgressNotificationId = 700200;
const int _backupCompletionNotificationId = 700201;
const int _scheduledWindowDays = 7;
const int _maxScheduledAlarmSlots = 512;

@pragma('vm:entry-point')
Future<void> backupAlarmCallback() async {
  DartPluginRegistrant.ensureInitialized();
  try {
    await BackupSchedulerService.instance.handleBackgroundAlarm();
  } catch (error, stackTrace) {
    await BackupSchedulerService.instance.handleSchedulingFailure(
      phase: 'background alarm callback',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

class BackupScheduleSnapshot {
  const BackupScheduleSnapshot({
    required this.enabled,
    required this.times,
    required this.nextRunAts,
    required this.lastStatus,
    required this.lastError,
    required this.lastBackupPath,
    required this.lastRunAt,
  });

  final bool enabled;
  final List<TimeOfDay> times;
  final List<DateTime> nextRunAts;
  final String? lastStatus;
  final String? lastError;
  final String? lastBackupPath;
  final DateTime? lastRunAt;

  DateTime? get nextRunAt => nextRunAts.isEmpty ? null : nextRunAts.first;
}

class BackupSchedulerService {
  BackupSchedulerService._();

  static final BackupSchedulerService instance = BackupSchedulerService._();
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _notificationsInitialized = false;
  Future<void>? _initializing;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    final existingInitialization = _initializing;
    if (existingInitialization != null) {
      return existingInitialization;
    }

    final initializing = _initialize();
    _initializing = initializing;
    try {
      await initializing;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _initialize() async {
    _initialized = true;
  }

  Future<BackupScheduleSnapshot> loadSnapshot() async {
    await initialize();
    final prefs = await SharedPreferences.getInstance();
    final times = _readScheduleTimes(prefs);
    return BackupScheduleSnapshot(
      enabled: prefs.getBool(_enabledKey) ?? false,
      times: times,
      nextRunAts: _readDateTimeList(prefs.getStringList(_nextRunAtListKey)),
      lastStatus: prefs.getString(_lastStatusKey),
      lastError: prefs.getString(_lastErrorKey),
      lastBackupPath: prefs.getString(_lastBackupPathKey),
      lastRunAt: _readDateTime(prefs.getString(_lastRunAtKey)),
    );
  }

  Future<void> ensureSchedule() async {
    await initialize();
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_enabledKey) ?? false;
    if (!enabled) {
      await _cancelAllScheduledAlarms();
      return;
    }

    try {
      await _scheduleAllNextRuns(times: _readScheduleTimes(prefs));
    } catch (error, stackTrace) {
      await handleSchedulingFailure(
        phase: 'schedule restore',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> updateSchedule({
    required bool enabled,
    required List<TimeOfDay> times,
  }) async {
    await initialize();
    final prefs = await SharedPreferences.getInstance();
    final normalizedTimes = _normalizeTimes(times);

    await prefs.setBool(_enabledKey, enabled);
    await prefs.setStringList(
        _timesKey, normalizedTimes.map(_encodeTime).toList());

    // Keep legacy keys in sync for backward compatibility with any old reads.
    final firstTime = normalizedTimes.isNotEmpty
        ? normalizedTimes.first
        : const TimeOfDay(hour: 10, minute: 0);
    await prefs.setInt(_hourKey, firstTime.hour);
    await prefs.setInt(_minuteKey, firstTime.minute);

    try {
      if (enabled && normalizedTimes.isNotEmpty) {
        await _scheduleAllNextRuns(times: normalizedTimes);
      } else {
        await _cancelAllScheduledAlarms();
        await prefs.remove(_nextRunAtListKey);
      }
    } catch (error, stackTrace) {
      await handleSchedulingFailure(
        phase: 'schedule update',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> runBackupNow() async {
    await initialize();
    await _runBackup(writeStatus: true);

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_enabledKey) ?? false) {
      try {
        await _scheduleAllNextRuns(times: _readScheduleTimes(prefs));
      } catch (error, stackTrace) {
        await handleSchedulingFailure(
          phase: 'manual backup reschedule',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> handleBackgroundAlarm() async {
    await initialize();
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_enabledKey) ?? false)) {
      return;
    }

    try {
      await _runBackup(writeStatus: true);
      if (prefs.getBool(_enabledKey) ?? false) {
        await _scheduleAllNextRuns(times: _readScheduleTimes(prefs));
      }
    } catch (error, stackTrace) {
      await handleSchedulingFailure(
        phase: 'background backup reschedule',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> handleSchedulingFailure({
    required String phase,
    required Object error,
    StackTrace? stackTrace,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final message = 'Backup scheduling failed during $phase: $error';

    await prefs.setString(_lastStatusKey, 'Backup scheduling failed');
    await prefs.setString(_lastErrorKey, message);

    debugPrint('[BackupSchedulerService] $message');
    if (stackTrace != null) {
      debugPrint(stackTrace.toString());
    }

    await _showBackupCompletionNotification(
      success: false,
      message: message,
    );
  }

  Future<void> _scheduleAllNextRuns({
    required List<TimeOfDay> times,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_enabledKey) ?? false)) {
      return;
    }

    final normalizedTimes = _normalizeTimes(times);
    if (normalizedTimes.isEmpty) {
      await _cancelAllScheduledAlarms();
      await prefs.remove(_nextRunAtListKey);
      return;
    }

    await _cancelAllScheduledAlarms();

    final now = DateTime.now();
    final scheduledRuns = _buildScheduledRunWindow(
      now: now,
      times: normalizedTimes,
    );
    if (scheduledRuns.isEmpty) {
      throw StateError('No upcoming backup runs could be calculated.');
    }

    if (scheduledRuns.length > _maxScheduledAlarmSlots) {
      throw StateError(
        'Too many scheduled backup runs (${scheduledRuns.length}) for available alarm slots.',
      );
    }

    for (var index = 0; index < scheduledRuns.length; index++) {
      final scheduledRun = scheduledRuns[index];
      final scheduled = await AndroidAlarmManager.oneShotAt(
        scheduledRun,
        _alarmIdForIndex(index),
        backupAlarmCallback,
        wakeup: true,
        allowWhileIdle: true,
        rescheduleOnReboot: true,
      );

      if (!scheduled) {
        throw StateError('Failed to schedule one or more daily backup alarms.');
      }
    }

    await prefs.setInt(_scheduledAlarmCountKey, scheduledRuns.length);
    await prefs.setStringList(
      _nextRunAtListKey,
      scheduledRuns
          .take(normalizedTimes.length)
          .map((value) => value.toIso8601String())
          .toList(),
    );
  }

  List<DateTime> _buildScheduledRunWindow({
    required DateTime now,
    required List<TimeOfDay> times,
  }) {
    final startOfToday = DateTime(now.year, now.month, now.day);
    final scheduledRuns = <DateTime>[];

    for (var dayOffset = 0; dayOffset < _scheduledWindowDays; dayOffset++) {
      final day = startOfToday.add(Duration(days: dayOffset));
      for (final time in times) {
        final candidate = DateTime(
          day.year,
          day.month,
          day.day,
          time.hour,
          time.minute,
        );
        if (candidate.isAfter(now)) {
          scheduledRuns.add(candidate);
        }
      }
    }

    scheduledRuns.sort();
    return scheduledRuns;
  }

  Future<bool> _runBackup({required bool writeStatus}) async {
    final prefs = await SharedPreferences.getInstance();
    final startedAt = DateTime.now();

    await _showBackupStartNotification();

    try {
      await dotenv.load();

      final backupPath = await MySqlService()
          .backupDatabaseWithMysqldump()
          .timeout(const Duration(minutes: 15));

      final pendingUploads =
          prefs.getStringList(_pendingUploadPathsKey) ?? const [];
      final uploadQueue = _uniquePaths([...pendingUploads, backupPath]);

      var uploadMessage = 'Backup created locally';
      var uploadedCount = 0;
      String? uploadIssue;
      var remainingQueue = <String>[];

      for (var index = 0; index < uploadQueue.length; index++) {
        final path = uploadQueue[index];
        final file = File(path);
        if (!await file.exists()) {
          continue;
        }

        try {
          await GoogleDriveBackupService.instance.uploadBackupFile(
            filePath: path,
            allowInteractiveSignIn: false,
          ).timeout(const Duration(minutes: 2));
          uploadedCount += 1;
        } catch (uploadError) {
          uploadIssue = _friendlyUploadError(uploadError);
          remainingQueue = uploadQueue.sublist(index);
          break;
        }
      }

      if (uploadIssue == null) {
        await prefs.remove(_pendingUploadPathsKey);
        uploadMessage = uploadedCount > 1
            ? 'Backup created and uploaded to Google Drive ($uploadedCount files synced)'
            : 'Backup created and uploaded to Google Drive';
      } else {
        if (remainingQueue.isNotEmpty) {
          await prefs.setStringList(_pendingUploadPathsKey, remainingQueue);
        } else {
          await prefs.remove(_pendingUploadPathsKey);
        }
        final pendingCount = remainingQueue.length;
        uploadMessage = pendingCount > 0
            ? 'Backup created locally; Google Drive upload deferred ($pendingCount pending). $uploadIssue'
            : 'Backup created locally; Google Drive upload deferred. $uploadIssue';
      }

      if (writeStatus) {
        await prefs.setString(_lastRunAtKey, startedAt.toIso8601String());
        await prefs.setString(_lastStatusKey, uploadMessage);
        await prefs.setString(_lastBackupPathKey, backupPath);
        await prefs.remove(_lastErrorKey);
      }

      await _showBackupCompletionNotification(
        success: true,
        message: uploadMessage,
      );

      return true;
    } catch (error) {
      if (writeStatus) {
        await prefs.setString(_lastRunAtKey, startedAt.toIso8601String());
        await prefs.setString(_lastStatusKey, 'Backup failed');
        await prefs.setString(_lastErrorKey, error.toString());
      }

      await _showBackupCompletionNotification(
        success: false,
        message: error.toString(),
      );

      return false;
    } finally {
      // Safety net: ensure the ongoing notification is always dismissed.
      await _localNotifications
          .cancel(_backupInProgressNotificationId)
          .catchError((_) {});
    }
  }

  Future<void> _ensureNotificationChannel() async {
    if (!_notificationsInitialized) {
      const initializationSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      );
      await _localNotifications
          .initialize(initializationSettings)
          .timeout(const Duration(seconds: 15));
      _notificationsInitialized = true;
    }

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _backupStatusChannelId,
          _backupStatusChannelName,
          description: _backupStatusChannelDescription,
          importance: Importance.high,
        ))
        .timeout(const Duration(seconds: 15));
  }

  Future<void> _showBackupStartNotification() async {
    try {
      await _ensureNotificationChannel();
      await _localNotifications.show(
        _backupInProgressNotificationId,
        'Backup starting',
        'Scheduled backup is in progress…',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _backupStatusChannelId,
            _backupStatusChannelName,
            channelDescription: _backupStatusChannelDescription,
            importance: Importance.low,
            priority: Priority.low,
            icon: '@mipmap/ic_launcher',
            ongoing: true,
            showProgress: true,
            indeterminate: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: false,
            presentBadge: false,
            presentSound: false,
          ),
        ),
      ).timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('Failed to show backup start notification: $e');
    }
  }

  Future<void> _showBackupCompletionNotification({
    required bool success,
    required String message,
  }) async {
    try {
      await _ensureNotificationChannel();

      // Cancel the ongoing in-progress notification before showing the result.
      await _localNotifications
          .cancel(_backupInProgressNotificationId)
          .timeout(const Duration(seconds: 15));

      final title = success ? 'Backup completed' : 'Backup failed';

      await _localNotifications.show(
        _backupCompletionNotificationId,
        title,
        message,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _backupStatusChannelId,
            _backupStatusChannelName,
            channelDescription: _backupStatusChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      ).timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('Failed to show backup completion notification: $e');
    }
  }

  List<String> _uniquePaths(List<String> paths) {
    final seen = <String>{};
    final unique = <String>[];
    for (final path in paths) {
      final trimmed = path.trim();
      if (trimmed.isEmpty || seen.contains(trimmed)) {
        continue;
      }
      seen.add(trimmed);
      unique.add(trimmed);
    }
    return unique;
  }

  String _friendlyUploadError(Object error) {
    if (error is TimeoutException) {
      return 'Google Drive upload timed out; upload will retry automatically.';
    }

    if (error is SocketException) {
      return 'No internet connection right now; upload will retry automatically.';
    }

    final raw = error.toString().toLowerCase();
    if (raw.contains('failed host lookup') ||
        raw.contains('hostlookup') ||
        raw.contains('clientexception')) {
      return 'Google Drive is unreachable right now; upload will retry automatically.';
    }

    return 'Upload failed and will retry automatically: $error';
  }

  List<TimeOfDay> _readScheduleTimes(SharedPreferences prefs) {
    final encodedTimes = prefs.getStringList(_timesKey) ?? const [];
    if (encodedTimes.isNotEmpty) {
      final parsed = encodedTimes
          .map(_decodeTime)
          .whereType<TimeOfDay>()
          .toList(growable: false);
      return _normalizeTimes(parsed);
    }

    // Fallback for older app versions that stored only one schedule time.
    final hour = prefs.getInt(_hourKey) ?? 10;
    final minute = prefs.getInt(_minuteKey) ?? 0;
    return [TimeOfDay(hour: hour, minute: minute)];
  }

  DateTime? _readDateTime(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    return DateTime.tryParse(value);
  }

  List<DateTime> _readDateTimeList(List<String>? values) {
    if (values == null || values.isEmpty) {
      return const [];
    }

    final parsed = values
        .map(_readDateTime)
        .whereType<DateTime>()
        .toList(growable: false)
      ..sort();
    return parsed;
  }

  List<TimeOfDay> _normalizeTimes(List<TimeOfDay> times) {
    final byMinute = <int, TimeOfDay>{};
    for (final time in times) {
      byMinute[time.hour * 60 + time.minute] = time;
    }

    final sortedMinutes = byMinute.keys.toList()..sort();
    return sortedMinutes
        .map((totalMinutes) =>
            TimeOfDay(hour: totalMinutes ~/ 60, minute: totalMinutes % 60))
        .toList(growable: false);
  }

  int _alarmIdForIndex(int index) {
    return _backupAlarmIdBase + index;
  }

  Future<void> _cancelAllScheduledAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    // Fall back to the full range only once, to clear any stale alarms from old installs.
    final count = prefs.getInt(_scheduledAlarmCountKey) ?? _maxScheduledAlarmSlots;
    for (var index = 0; index < count; index++) {
      await AndroidAlarmManager.cancel(_alarmIdForIndex(index));
    }
    await prefs.remove(_scheduledAlarmCountKey);
  }

  String _encodeTime(TimeOfDay time) {
    return jsonEncode({'h': time.hour, 'm': time.minute});
  }

  TimeOfDay? _decodeTime(String value) {
    try {
      final parsed = jsonDecode(value);
      if (parsed is Map<String, dynamic>) {
        final hour = parsed['h'];
        final minute = parsed['m'];
        if (hour is int &&
            minute is int &&
            hour >= 0 &&
            hour <= 23 &&
            minute >= 0 &&
            minute <= 59) {
          return TimeOfDay(hour: hour, minute: minute);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
