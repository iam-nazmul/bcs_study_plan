import 'package:flutter/material.dart';

import '../data/calendar_sync.dart';

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key, required this.sync});

  final CalendarSync sync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Google Calendar')),
      body: ListenableBuilder(
        listenable: sync,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: Icon(
                  sync.connected ? Icons.event_available : Icons.event_busy,
                  color: sync.connected ? theme.colorScheme.primary : null,
                ),
                title: Text(sync.connected ? 'Connected' : 'Not connected'),
                subtitle: Text(sync.connected
                    ? sync.calendarName ?? ''
                    : 'Add every study session to your calendar as a 1-hour event.'),
              ),
            ),
            const SizedBox(height: 8),
            if (!sync.connected)
              FilledButton.icon(
                onPressed: () => _connect(context),
                icon: const Icon(Icons.link),
                label: const Text('Connect calendar'),
              )
            else ...[
              ListTile(
                title: const Text('Reminder'),
                trailing: DropdownButton<int>(
                  value: sync.reminderMinutes,
                  items: [
                    for (final m in CalendarSync.reminderChoices)
                      DropdownMenuItem(value: m, child: Text(m == 0 ? 'None' : '$m min before')),
                  ],
                  onChanged: (m) {
                    if (m != null && m != sync.reminderMinutes) {
                      _runWithProgress(context, 'Updating reminders',
                          (p) => sync.setReminder(m, onProgress: p));
                    }
                  },
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () => _syncNow(context),
                icon: const Icon(Icons.sync),
                label: const Text('Sync now'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () => _connect(context),
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Change calendar'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _disconnect(context),
                icon: const Icon(Icons.link_off),
                label: const Text('Disconnect'),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              'Sessions are written to a calendar on this phone. Pick a calendar under your '
              'Google account and Android syncs the events to Google Calendar on the web and '
              'your other devices. Ticking a session off, editing or removing it updates the '
              'event automatically.\n\n'
              'If events do not show up in Google Calendar, check that calendar sync is on in '
              'Android Settings › Accounts › Google.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _connect(BuildContext context) async {
    final calendars = await sync.writableCalendars();
    if (!context.mounted) return;
    if (calendars.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No writable calendar found. Allow calendar access and add a Google account.'),
      ));
      return;
    }
    final chosen = await showDialog<DeviceCalendar>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose a calendar'),
        children: [
          for (final c in calendars)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, c),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 8,
                  backgroundColor: c.color != null ? Color(c.color!) : Colors.grey,
                ),
                title: Text(c.name),
                subtitle: Text(c.isGoogle ? '${c.accountName} · Google' : c.accountName),
                trailing: c.id == sync.calendarId ? const Icon(Icons.check) : null,
              ),
            ),
        ],
      ),
    );
    if (chosen == null || !context.mounted) return;
    await _runWithProgress(context, 'Adding sessions to calendar',
        (p) => sync.connect(chosen, onProgress: p));
  }

  Future<void> _syncNow(BuildContext context) async {
    var failures = 0;
    await _runWithProgress(context, 'Syncing',
        (p) async => failures = await sync.syncAll(onProgress: p));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(failures == 0
          ? 'Calendar is up to date.'
          : '$failures sessions could not be synced. Check calendar permission.'),
    ));
  }

  Future<void> _disconnect(BuildContext context) async {
    final deleteEvents = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect calendar?'),
        content: const Text('Remove the study events this app added to your calendar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep events')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove events')),
        ],
      ),
    );
    if (deleteEvents == null || !context.mounted) return;
    await _runWithProgress(context, 'Removing events',
        (p) => sync.disconnect(deleteEvents: deleteEvents, onProgress: p));
  }

  Future<void> _runWithProgress(
    BuildContext context,
    String title,
    Future<void> Function(SyncProgress onProgress) job,
  ) async {
    final progress = ValueNotifier<(int, int)>((0, 0));
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(title),
          content: ValueListenableBuilder(
            valueListenable: progress,
            builder: (context, value, _) {
              final (done, total) = value;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: total == 0 ? null : done / total),
                  const SizedBox(height: 12),
                  Text(total == 0 ? 'Starting…' : '$done of $total'),
                ],
              );
            },
          ),
        ),
      ),
    );
    try {
      await job((done, total) => progress.value = (done, total));
    } finally {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      progress.dispose();
    }
  }
}
