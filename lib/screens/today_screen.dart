import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/calendar_sync.dart';
import '../data/models.dart';
import '../data/study_repository.dart';
import 'calendar_screen.dart';
import 'day_view.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, required this.repo, required this.sync});

  final StudyRepository repo;
  final CalendarSync sync;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  late Timer _ticker;

  @override
  void initState() {
    super.initState();
    // Re-render each minute so the "now" highlight and the date roll over.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final today = dateKey(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          ListenableBuilder(
            listenable: widget.sync,
            builder: (context, _) => IconButton(
              tooltip: 'Google Calendar',
              icon: Icon(widget.sync.connected ? Icons.event_available : Icons.edit_calendar_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CalendarScreen(sync: widget.sync),
              )),
            ),
          ),
        ],
      ),
      body: repo.dayNumber(today) != null
          ? DayView(repo: repo, date: today)
          : _OutsidePlan(repo: repo, today: today),
    );
  }
}

class _OutsidePlan extends StatelessWidget {
  const _OutsidePlan({required this.repo, required this.today});

  final StudyRepository repo;
  final String today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notStarted = today.compareTo(repo.firstDate) < 0;
    final start = parseDateKey(repo.firstDate);
    final daysLeft = start.difference(parseDateKey(today)).inDays;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(notStarted ? Icons.hourglass_top : Icons.emoji_events,
                size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              notStarted
                  ? '$daysLeft day${daysLeft == 1 ? '' : 's'} until the plan starts'
                  : 'The 120-day plan is finished',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              notStarted
                  ? 'Day 1 is ${DateFormat('EEEE, d MMMM yyyy').format(start)}.'
                  : 'Check the Progress tab to see how it went.',
              textAlign: TextAlign.center,
            ),
            if (notStarted) ...[
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Day 1')),
                    body: DayView(repo: repo, date: repo.firstDate),
                  ),
                )),
                child: const Text('Preview Day 1'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
