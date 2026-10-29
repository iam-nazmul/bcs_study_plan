import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final _isoDate = DateFormat('yyyy-MM-dd');

String dateKey(DateTime date) => _isoDate.format(date);

DateTime parseDateKey(String key) => _isoDate.parse(key);

String slotLabel(int hour) {
  String two(int h) => h.toString().padLeft(2, '0');
  return '${two(hour)}:00 – ${two(hour + 1)}:00';
}

class Subject {
  const Subject(this.code, this.name, this.color);

  final String code;
  final String name;
  final Color color;

  static const _palette = {
    'GK': Color(0xFF3F51B5),
    'M': Color(0xFF00897B),
    'E': Color(0xFFEF6C00),
    'B': Color(0xFFC2185B),
  };

  static Color colorFor(String code) => _palette[code] ?? Colors.blueGrey;
}

class StudySession {
  const StudySession({
    required this.id,
    required this.date,
    required this.hour,
    required this.subject,
    required this.done,
    this.eventId,
    this.eventSignature,
  });

  factory StudySession.fromRow(Map<String, Object?> row) => StudySession(
        id: row['id'] as int,
        date: row['date'] as String,
        hour: row['hour'] as int,
        subject: row['subject'] as String,
        done: (row['done'] as int) == 1,
        eventId: row['event_id'] as String?,
        eventSignature: row['event_sig'] as String?,
      );

  final int id;
  final String date;
  final int hour;
  final String subject;
  final bool done;

  /// Id of the matching event in the phone calendar, once synced.
  final String? eventId;

  /// Fingerprint of the event content last written to the calendar.
  final String? eventSignature;
}

class DaySummary {
  const DaySummary({
    required this.date,
    required this.dayNumber,
    required this.total,
    required this.done,
  });

  final String date;
  final int dayNumber;
  final int total;
  final int done;

  bool get complete => total > 0 && done == total;
  double get progress => total == 0 ? 0 : done / total;
}

class SubjectStat {
  const SubjectStat(this.subject, this.total, this.done);

  final Subject subject;
  final int total;
  final int done;

  double get progress => total == 0 ? 0 : done / total;
}
