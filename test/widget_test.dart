import 'dart:convert';
import 'dart:io';

import 'package:bcs_study_plan/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('slotLabel formats an hour range', () {
    expect(slotLabel(6), '06:00 – 07:00');
    expect(slotLabel(22), '22:00 – 23:00');
  });

  test('date keys round-trip', () {
    final date = DateTime(2026, 11, 1);
    expect(dateKey(date), '2026-11-01');
    expect(parseDateKey('2026-11-01'), date);
  });

  test('seed asset covers the 120-day plan', () {
    final seed = jsonDecode(File('assets/study_plan.json').readAsStringSync()) as Map<String, dynamic>;
    final days = seed['days'] as List<dynamic>;
    expect(days, hasLength(120));
    expect(days.first['date'], '2026-11-01');
    expect(days.last['date'], '2027-02-28');
    expect((seed['subjects'] as Map).keys, containsAll(['GK', 'M', 'E', 'B']));
  });
}
