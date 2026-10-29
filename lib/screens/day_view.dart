import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../data/study_repository.dart';

/// Sessions checklist plus notes for a single plan day.
class DayView extends StatefulWidget {
  const DayView({super.key, required this.repo, required this.date});

  final StudyRepository repo;
  final String date;

  @override
  State<DayView> createState() => _DayViewState();
}

class _DayViewState extends State<DayView> {
  final _noteController = TextEditingController();
  Timer? _saveTimer;
  late Future<List<StudySession>> _sessions;

  StudyRepository get repo => widget.repo;

  @override
  void initState() {
    super.initState();
    _load();
    repo.addListener(_reloadSessions);
  }

  @override
  void didUpdateWidget(DayView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.date != widget.date) {
      _flushNote(oldWidget.date);
      _load();
    }
  }

  @override
  void dispose() {
    repo.removeListener(_reloadSessions);
    _flushNote(widget.date);
    _noteController.dispose();
    super.dispose();
  }

  void _load() {
    _sessions = repo.sessionsFor(widget.date);
    repo.noteFor(widget.date).then((note) {
      if (mounted) _noteController.text = note;
    });
  }

  void _reloadSessions() => setState(() => _sessions = repo.sessionsFor(widget.date));

  void _onNoteChanged(String text) {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () => repo.saveNote(widget.date, text));
  }

  void _flushNote(String date) {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      repo.saveNote(date, _noteController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = parseDateKey(widget.date);
    final now = DateTime.now();
    final isToday = widget.date == dateKey(now);
    final dayNumber = repo.dayNumber(widget.date);

    return FutureBuilder<List<StudySession>>(
      future: _sessions,
      builder: (context, snapshot) {
        final sessions = snapshot.data;
        if (sessions == null) return const Center(child: CircularProgressIndicator());
        final done = sessions.where((s) => s.done).length;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _Header(
              title: DateFormat('EEEE, d MMMM yyyy').format(date),
              subtitle: dayNumber == null ? null : 'Day $dayNumber of ${repo.planDates.length}',
              done: done,
              total: sessions.length,
            ),
            const SizedBox(height: 12),
            if (sessions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No sessions planned for this day.')),
              ),
            for (final session in sessions)
              _SessionTile(
                session: session,
                subject: repo.subject(session.subject),
                isNow: isToday && session.hour == now.hour,
                onToggle: (value) => repo.setDone(session.id, value),
                onEdit: () => _editSession(session),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _addSession(sessions),
                icon: const Icon(Icons.add),
                label: const Text('Add session'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              onChanged: _onNoteChanged,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Notes',
                hintText: 'Topics covered, weak areas, revision to-dos…',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editSession(StudySession session) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(slotLabel(session.hour), style: Theme.of(context).textTheme.titleMedium),
            for (final s in repo.subjects)
              ListTile(
                leading: CircleAvatar(backgroundColor: s.color, radius: 8),
                title: Text(s.name),
                trailing: s.code == session.subject ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, s.code),
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove session'),
              onTap: () => Navigator.pop(context, ''),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    if (result.isEmpty) {
      await repo.deleteSession(session.id);
    } else if (result != session.subject) {
      await repo.changeSubject(session.id, result);
    }
  }

  Future<void> _addSession(List<StudySession> existing) async {
    final taken = existing.map((s) => s.hour).toSet();
    final freeHours = [for (var h = 5; h <= 23; h++) if (!taken.contains(h)) h];
    if (freeHours.isEmpty) return;
    var hour = freeHours.first;
    var code = repo.subjects.first.code;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add session'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<int>(
                initialValue: hour,
                decoration: const InputDecoration(labelText: 'Time'),
                items: [
                  for (final h in freeHours) DropdownMenuItem(value: h, child: Text(slotLabel(h))),
                ],
                onChanged: (value) => setDialogState(() => hour = value!),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in repo.subjects)
                    ChoiceChip(
                      label: Text(s.name),
                      selected: code == s.code,
                      selectedColor: s.color.withValues(alpha: 0.25),
                      onSelected: (_) => setDialogState(() => code = s.code),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (confirmed == true) await repo.addSession(widget.date, hour, code);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.subtitle, required this.done, required this.total});

  final String title;
  final String? subtitle;
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitle != null)
              Text(subtitle!, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: total == 0 ? 0 : done / total, minHeight: 8),
            ),
            const SizedBox(height: 6),
            Text('$done of $total hours done', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.subject,
    required this.isNow,
    required this.onToggle,
    required this.onEdit,
  });

  final StudySession session;
  final Subject subject;
  final bool isNow;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: isNow ? subject.color.withValues(alpha: 0.12) : theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isNow ? BorderSide(color: subject.color, width: 2) : BorderSide.none,
      ),
      child: ListTile(
        onTap: () => onToggle(!session.done),
        onLongPress: onEdit,
        leading: Container(
          width: 6,
          height: 40,
          decoration: BoxDecoration(color: subject.color, borderRadius: BorderRadius.circular(3)),
        ),
        title: Text(
          subject.name,
          style: TextStyle(decoration: session.done ? TextDecoration.lineThrough : null),
        ),
        subtitle: Text(isNow ? '${slotLabel(session.hour)} · now' : slotLabel(session.hour)),
        trailing: Checkbox(value: session.done, onChanged: (v) => onToggle(v ?? false)),
      ),
    );
  }
}
