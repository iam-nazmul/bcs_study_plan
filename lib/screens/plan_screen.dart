import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../data/study_repository.dart';
import 'day_view.dart';

class PlanScreen extends StatelessWidget {
  const PlanScreen({super.key, required this.repo});

  final StudyRepository repo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('120-Day Plan')),
      body: ListenableBuilder(
        listenable: repo,
        builder: (context, _) => FutureBuilder<List<DaySummary>>(
          future: repo.daySummaries(),
          builder: (context, snapshot) {
            final days = snapshot.data;
            if (days == null) return const Center(child: CircularProgressIndicator());
            return _DayList(repo: repo, days: days);
          },
        ),
      ),
    );
  }
}

class _DayList extends StatelessWidget {
  const _DayList({required this.repo, required this.days});

  final StudyRepository repo;
  final List<DaySummary> days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = dateKey(DateTime.now());
    final items = <Widget>[];
    String? month;

    for (final day in days) {
      final date = parseDateKey(day.date);
      final dayMonth = DateFormat('MMMM yyyy').format(date);
      if (dayMonth != month) {
        month = dayMonth;
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(dayMonth, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary)),
        ));
      }
      final isToday = day.date == today;
      final isPast = day.date.compareTo(today) < 0;
      items.add(ListTile(
        selected: isToday,
        leading: CircleAvatar(
          backgroundColor: day.complete ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
          foregroundColor: day.complete ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
          child: day.complete ? const Icon(Icons.check) : Text('${day.dayNumber}'),
        ),
        title: Text(DateFormat('EEE, d MMM').format(date) + (isToday ? '  ·  Today' : '')),
        subtitle: Text(
          '${day.done}/${day.total} hours'
          '${isPast && !day.complete && day.total > 0 ? '  ·  incomplete' : ''}',
        ),
        trailing: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            value: day.progress,
            strokeWidth: 4,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text('Day ${day.dayNumber}')),
            body: DayView(repo: repo, date: day.date),
          ),
        )),
      ));
    }
    return ListView(children: items);
  }
}
