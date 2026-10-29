import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/study_repository.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key, required this.repo});

  final StudyRepository repo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Progress'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (_) => _confirmReset(context),
            itemBuilder: (_) => const [PopupMenuItem(value: 'reset', child: Text('Reset all progress'))],
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: repo,
        builder: (context, _) => FutureBuilder(
          future: Future.wait([repo.daySummaries(), repo.subjectStats()]),
          builder: (context, snapshot) {
            final data = snapshot.data;
            if (data == null) return const Center(child: CircularProgressIndicator());
            return _ProgressBody(
              days: data[0] as List<DaySummary>,
              stats: data[1] as List<SubjectStat>,
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset progress?'),
        content: const Text('Every session will be marked as not done. Notes and schedule edits are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok == true) await repo.resetProgress();
  }
}

class _ProgressBody extends StatelessWidget {
  const _ProgressBody({required this.days, required this.stats});

  final List<DaySummary> days;
  final List<SubjectStat> stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = dateKey(DateTime.now());
    final totalHours = days.fold<int>(0, (sum, d) => sum + d.total);
    final doneHours = days.fold<int>(0, (sum, d) => sum + d.done);
    final completeDays = days.where((d) => d.complete).length;
    final elapsed = days.where((d) => d.date.compareTo(today) <= 0).toList();

    // Streak counts back from today; an unfinished today does not break it.
    var streak = 0;
    for (final day in elapsed.reversed) {
      if (day.complete) {
        streak++;
      } else if (day.date != today) {
        break;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                SizedBox(
                  width: 140,
                  height: 140,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: totalHours == 0 ? 0 : doneHours / totalHours,
                        strokeWidth: 12,
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      ),
                      Center(
                        child: Text(
                          '${totalHours == 0 ? 0 : (doneHours * 100 / totalHours).round()}%',
                          style: theme.textTheme.headlineMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text('$doneHours of $totalHours study hours done', style: theme.textTheme.titleMedium),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _StatTile(label: 'Days elapsed', value: '${elapsed.length}/${days.length}'),
            _StatTile(label: 'Days complete', value: '$completeDays'),
            _StatTile(label: 'Streak', value: '$streak'),
          ],
        ),
        const SizedBox(height: 16),
        Text('By subject', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final stat in stats)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(radius: 6, backgroundColor: stat.subject.color),
                    const SizedBox(width: 8),
                    Expanded(child: Text(stat.subject.name)),
                    Text('${stat.done}/${stat.total} h'),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: stat.progress,
                    minHeight: 8,
                    color: stat.subject.color,
                    backgroundColor: stat.subject.color.withValues(alpha: 0.15),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            children: [
              Text(value, style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(label, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
