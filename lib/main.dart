import 'package:flutter/material.dart';

import 'data/calendar_sync.dart';
import 'data/study_repository.dart';
import 'screens/plan_screen.dart';
import 'screens/progress_screen.dart';
import 'screens/today_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = await StudyRepository.open();
  final sync = await CalendarSync.init(repo);
  runApp(StudyPlanApp(repo: repo, sync: sync));
}

class StudyPlanApp extends StatelessWidget {
  const StudyPlanApp({super.key, required this.repo, required this.sync});

  final StudyRepository repo;
  final CalendarSync sync;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1B5E20);
    return MaterialApp(
      title: 'BCS Study Plan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark),
      home: HomeShell(repo: repo, sync: sync),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.repo, required this.sync});

  final StudyRepository repo;
  final CalendarSync sync;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          TodayScreen(repo: widget.repo, sync: widget.sync),
          PlanScreen(repo: widget.repo),
          ProgressScreen(repo: widget.repo),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Today'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Plan'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Progress'),
        ],
      ),
    );
  }
}
