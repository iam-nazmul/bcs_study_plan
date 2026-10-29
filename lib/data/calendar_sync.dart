import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'study_repository.dart';

typedef SyncProgress = void Function(int done, int total);

class DeviceCalendar {
  const DeviceCalendar({
    required this.id,
    required this.name,
    required this.accountName,
    required this.accountType,
    required this.color,
  });

  factory DeviceCalendar.fromMap(Map<Object?, Object?> map) => DeviceCalendar(
        id: '${map['id']}',
        name: map['name'] as String? ?? 'Calendar',
        accountName: map['accountName'] as String? ?? '',
        accountType: map['accountType'] as String? ?? '',
        color: map['color'] as int?,
      );

  final String id;
  final String name;
  final String accountName;
  final String accountType;
  final int? color;

  bool get isGoogle => accountType == 'com.google';
}

/// Mirrors study sessions into a calendar on the phone. When that calendar
/// belongs to a Google account, Android syncs the events to Google Calendar.
///
/// Writes go through a native channel (CalendarChannel.kt) that applies each
/// chunk of events in a single calendar-provider transaction.
class CalendarSync extends ChangeNotifier implements SessionObserver {
  CalendarSync._(this._repo);

  static const _channel = MethodChannel('bcs_study_plan/calendar');
  static const _calendarIdKey = 'calendar_id';
  static const _calendarNameKey = 'calendar_name';
  static const _reminderKey = 'calendar_reminder_minutes';
  static const _chunkSize = 100;
  static const reminderChoices = [0, 5, 10, 15, 30];

  final StudyRepository _repo;

  String? calendarId;
  String? calendarName;
  int reminderMinutes = 5;

  bool get connected => calendarId != null;

  static Future<CalendarSync> init(StudyRepository repo) async {
    final sync = CalendarSync._(repo);
    sync.calendarId = await repo.setting(_calendarIdKey);
    sync.calendarName = await repo.setting(_calendarNameKey);
    sync.reminderMinutes = int.tryParse(await repo.setting(_reminderKey) ?? '') ?? 5;
    repo.observer = sync;
    return sync;
  }

  /// Writable calendars, Google accounts first. Empty if permission is denied.
  Future<List<DeviceCalendar>> writableCalendars() async {
    final granted = await _channel.invokeMethod<bool>('requestPermission');
    if (granted != true) return [];
    final rows = await _channel.invokeListMethod<Map<Object?, Object?>>('listCalendars') ?? [];
    final calendars = rows.map(DeviceCalendar.fromMap).toList();
    int rank(DeviceCalendar c) => c.isGoogle ? 0 : 1;
    calendars.sort((a, b) =>
        rank(a) != rank(b) ? rank(a) - rank(b) : a.accountName.compareTo(b.accountName));
    return calendars;
  }

  Future<void> connect(DeviceCalendar calendar, {SyncProgress? onProgress}) async {
    if (connected && calendar.id != calendarId) await removeEvents();
    calendarId = calendar.id;
    calendarName = '${calendar.name} (${calendar.accountName})';
    await _repo.saveSetting(_calendarIdKey, calendarId);
    await _repo.saveSetting(_calendarNameKey, calendarName);
    notifyListeners();
    await syncAll(onProgress: onProgress);
  }

  Future<void> disconnect({bool deleteEvents = true, SyncProgress? onProgress}) async {
    if (deleteEvents) await removeEvents(onProgress: onProgress);
    calendarId = null;
    calendarName = null;
    await _repo.saveSetting(_calendarIdKey, null);
    await _repo.saveSetting(_calendarNameKey, null);
    notifyListeners();
  }

  Future<void> setReminder(int minutes, {SyncProgress? onProgress}) async {
    reminderMinutes = minutes;
    await _repo.saveSetting(_reminderKey, '$minutes');
    notifyListeners();
    if (connected) await syncAll(onProgress: onProgress);
  }

  /// Writes every session whose event is missing or out of date.
  /// Returns the number of sessions that could not be written.
  Future<int> syncAll({SyncProgress? onProgress}) async {
    final sessions = await _repo.allSessions();
    final linked = [for (final s in sessions) if (s.eventId != null) int.parse(s.eventId!)];
    final alive = (await _invoke<List<Object?>>('aliveEvents', {'eventIds': linked}) ?? [])
        .map((id) => '$id')
        .toSet();
    final stale = [
      for (final s in sessions)
        if (!alive.contains(s.eventId) || s.eventSignature != _signature(s)) s,
    ];

    var failures = 0;
    onProgress?.call(0, stale.length);
    for (var i = 0; i < stale.length; i += _chunkSize) {
      final chunk = stale.sublist(i, (i + _chunkSize).clamp(0, stale.length));
      if (!await _push(chunk)) failures += chunk.length;
      onProgress?.call(i + chunk.length, stale.length);
    }
    return failures;
  }

  Future<void> removeEvents({SyncProgress? onProgress}) async {
    final linked = (await _repo.allSessions()).where((s) => s.eventId != null).toList();
    onProgress?.call(0, linked.length);
    for (var i = 0; i < linked.length; i += _chunkSize * 2) {
      final chunk = linked.sublist(i, (i + _chunkSize * 2).clamp(0, linked.length));
      await _invoke('deleteEvents', {'eventIds': [for (final s in chunk) int.parse(s.eventId!)]});
      await _repo.setEventLinks({for (final s in chunk) s.id: (null, null)});
      onProgress?.call(i + chunk.length, linked.length);
    }
  }

  @override
  Future<void> sessionChanged(int sessionId) async {
    if (!connected) return;
    final session = await _repo.session(sessionId);
    if (session != null) await _push([session]);
  }

  @override
  Future<void> sessionRemoved(StudySession session) async {
    if (connected && session.eventId != null) {
      await _invoke('deleteEvents', {'eventIds': [int.parse(session.eventId!)]});
    }
  }

  @override
  Future<void> allProgressReset() async {
    if (connected) await syncAll();
  }

  String _title(StudySession s) =>
      '${s.done ? '✓ ' : ''}${_repo.subject(s.subject).name} · BCS study';

  String _description(StudySession s) => 'Day ${_repo.dayNumber(s.date) ?? '-'} of '
      '${_repo.planDates.length} · BCS Foreign Affairs cadre study plan.';

  String _signature(StudySession s) =>
      [calendarId, _title(s), _description(s), s.date, s.hour, reminderMinutes].join('|');

  Future<bool> _push(List<StudySession> sessions) async {
    final ids = await _invoke<Map<Object?, Object?>>('upsertEvents', {
      'calendarId': int.parse(calendarId!),
      'events': [
        for (final s in sessions)
          {
            'key': '${s.id}',
            'eventId': s.eventId == null ? null : int.parse(s.eventId!),
            'title': _title(s),
            'description': _description(s),
            'date': s.date,
            'hour': s.hour,
            'reminder': reminderMinutes,
          },
      ],
    });
    if (ids == null) return false;
    await _repo.setEventLinks({
      for (final s in sessions)
        if (ids['${s.id}'] != null) s.id: ('${ids['${s.id}']}', _signature(s)),
    });
    return true;
  }

  /// Calendar failures (revoked permission, deleted calendar) must never
  /// break ticking off a session, so they are logged and swallowed.
  Future<T?> _invoke<T>(String method, Map<String, Object?> args) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      debugPrint('Calendar $method failed: ${e.message}');
      return null;
    }
  }
}
