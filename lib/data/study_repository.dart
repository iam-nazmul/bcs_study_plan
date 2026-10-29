import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Receives session changes so they can be mirrored elsewhere (the calendar).
abstract interface class SessionObserver {
  Future<void> sessionChanged(int sessionId);
  Future<void> sessionRemoved(StudySession session);
  Future<void> allProgressReset();
}

/// SQLite-backed store for the study plan. Seeded once from
/// assets/study_plan.json; every change after that lives only in the database.
class StudyRepository extends ChangeNotifier {
  StudyRepository._(this._db, this.subjects, this.planDates);

  final Database _db;
  final List<Subject> subjects;
  final List<String> planDates;

  /// Set once calendar sync is initialised; told about every session change.
  SessionObserver? observer;

  String get firstDate => planDates.first;
  String get lastDate => planDates.last;

  static Future<StudyRepository> open() async {
    final path = p.join(await getDatabasesPath(), 'study_plan.db');
    final db = await openDatabase(
      path,
      version: 3,
      onCreate: _create,
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) await _addCalendarSchema(db);
        if (oldVersion < 3) await _addEventSignature(db);
      },
    );

    final subjectRows = await db.query('subjects', orderBy: 'position');
    final subjects = [
      for (final row in subjectRows)
        Subject(
          row['code'] as String,
          row['name'] as String,
          Subject.colorFor(row['code'] as String),
        ),
    ];
    final dayRows = await db.query('days', columns: ['date'], orderBy: 'date');
    final dates = [for (final row in dayRows) row['date'] as String];
    return StudyRepository._(db, subjects, dates);
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE subjects (
        code TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        position INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE days (
        date TEXT PRIMARY KEY,
        note TEXT NOT NULL DEFAULT ''
      )''');
    await db.execute('''
      CREATE TABLE sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL REFERENCES days(date),
        hour INTEGER NOT NULL,
        subject TEXT NOT NULL REFERENCES subjects(code),
        done INTEGER NOT NULL DEFAULT 0,
        completed_at TEXT,
        UNIQUE(date, hour)
      )''');
    await db.execute('CREATE INDEX sessions_date ON sessions(date)');
    await _addCalendarSchema(db);
    await _addEventSignature(db);

    final seed = jsonDecode(await rootBundle.loadString('assets/study_plan.json'))
        as Map<String, dynamic>;
    final batch = db.batch();
    var position = 0;
    (seed['subjects'] as Map<String, dynamic>).forEach((code, name) {
      batch.insert('subjects', {'code': code, 'name': name, 'position': position++});
    });
    for (final day in seed['days'] as List<dynamic>) {
      batch.insert('days', {'date': day['date'], 'note': day['comment']});
      for (final slot in day['slots'] as List<dynamic>) {
        batch.insert('sessions', {
          'date': day['date'],
          'hour': slot['hour'],
          'subject': slot['subject'],
        });
      }
    }
    await batch.commit(noResult: true);
  }

  static Future<void> _addCalendarSchema(Database db) async {
    await db.execute('ALTER TABLE sessions ADD COLUMN event_id TEXT');
    await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
  }

  /// Fingerprint of what was last written to the calendar, so unchanged
  /// sessions can be skipped on the next sync.
  static Future<void> _addEventSignature(Database db) async {
    await db.execute('ALTER TABLE sessions ADD COLUMN event_sig TEXT');
  }

  Future<String?> setting(String key) async {
    final rows = await _db.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> saveSetting(String key, String? value) async {
    if (value == null) {
      await _db.delete('settings', where: 'key = ?', whereArgs: [key]);
    } else {
      await _db.insert('settings', {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<List<StudySession>> allSessions() async {
    final rows = await _db.query('sessions', orderBy: 'date, hour');
    return rows.map(StudySession.fromRow).toList();
  }

  Future<StudySession?> session(int id) async {
    final rows = await _db.query('sessions', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : StudySession.fromRow(rows.first);
  }

  /// Records calendar links as sessionId -> (eventId, signature); nulls unlink.
  Future<void> setEventLinks(Map<int, (String?, String?)> links) async {
    final batch = _db.batch();
    links.forEach((sessionId, link) {
      final (eventId, signature) = link;
      batch.update('sessions', {'event_id': eventId, 'event_sig': signature},
          where: 'id = ?', whereArgs: [sessionId]);
    });
    await batch.commit(noResult: true);
  }

  Subject subject(String code) => subjects.firstWhere(
        (s) => s.code == code,
        orElse: () => Subject(code, code, Subject.colorFor(code)),
      );

  /// 1-based day number within the plan, or null when [date] is outside it.
  int? dayNumber(String date) {
    final index = planDates.indexOf(date);
    return index < 0 ? null : index + 1;
  }

  Future<List<StudySession>> sessionsFor(String date) async {
    final rows = await _db.query(
      'sessions',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'hour',
    );
    return rows.map(StudySession.fromRow).toList();
  }

  Future<String> noteFor(String date) async {
    final rows = await _db.query('days', columns: ['note'], where: 'date = ?', whereArgs: [date]);
    return rows.isEmpty ? '' : rows.first['note'] as String;
  }

  Future<void> saveNote(String date, String note) async {
    // Notes are typed continuously, so skip notifyListeners to avoid rebuild churn.
    await _db.update('days', {'note': note}, where: 'date = ?', whereArgs: [date]);
  }

  Future<void> setDone(int id, bool done) async {
    await _db.update(
      'sessions',
      {'done': done ? 1 : 0, 'completed_at': done ? DateTime.now().toIso8601String() : null},
      where: 'id = ?',
      whereArgs: [id],
    );
    notifyListeners();
    await observer?.sessionChanged(id);
  }

  Future<void> changeSubject(int id, String code) async {
    await _db.update('sessions', {'subject': code}, where: 'id = ?', whereArgs: [id]);
    notifyListeners();
    await observer?.sessionChanged(id);
  }

  Future<void> addSession(String date, int hour, String code) async {
    final id = await _db.insert(
      'sessions',
      {'date': date, 'hour': hour, 'subject': code},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
    await observer?.sessionChanged(id);
  }

  Future<void> deleteSession(int id) async {
    final removed = await session(id);
    await _db.delete('sessions', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
    if (removed != null) await observer?.sessionRemoved(removed);
  }

  Future<void> resetProgress() async {
    await _db.update('sessions', {'done': 0, 'completed_at': null});
    notifyListeners();
    await observer?.allProgressReset();
  }

  Future<List<DaySummary>> daySummaries() async {
    final rows = await _db.rawQuery('''
      SELECT d.date, COUNT(s.id) AS total, COALESCE(SUM(s.done), 0) AS done
      FROM days d LEFT JOIN sessions s ON s.date = d.date
      GROUP BY d.date ORDER BY d.date''');
    return [
      for (final (i, row) in rows.indexed)
        DaySummary(
          date: row['date'] as String,
          dayNumber: i + 1,
          total: row['total'] as int,
          done: row['done'] as int,
        ),
    ];
  }

  Future<List<SubjectStat>> subjectStats() async {
    final rows = await _db.rawQuery('''
      SELECT subject, COUNT(*) AS total, SUM(done) AS done
      FROM sessions GROUP BY subject''');
    final byCode = {for (final row in rows) row['subject'] as String: row};
    return [
      for (final s in subjects)
        SubjectStat(
          s,
          (byCode[s.code]?['total'] as int?) ?? 0,
          (byCode[s.code]?['done'] as int?) ?? 0,
        ),
    ];
  }
}
