import 'dart:async';
import 'package:flutter/material.dart';

import 'focus_page.dart';
import 'pages/tasks_page.dart';
import 'pages/stats_page.dart';

const String kBuildName =
    String.fromEnvironment('BUILD_NAME', defaultValue: 'dev');

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
  };

  runZonedGuarded(() {
    runApp(const MyApp());
  }, (error, stack) {});
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  ThemeData _theme() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: Colors.indigo,
        secondary: Colors.indigoAccent,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '专注 v$kBuildName',
      debugShowCheckedModeBanner: false,
      theme: _theme(),
      home: const _MainShell(),
    );
  }
}

class _MainShell extends StatefulWidget {
  const _MainShell({super.key});

  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> {
  int _index = 0;

  Widget? _focusPage;
  Widget? _tasksPage;
  Widget? _statsPage;

  Widget _currentBody() {
    switch (_index) {
      case 0:
        // 关键修改：为 FocusPage 传入必填的 minutes
        _focusPage ??= const FocusPage(minutes: 25);
        return _focusPage!;
      case 1:
        _tasksPage ??= const TasksPage();
        return _tasksPage!;
      default:
        _statsPage ??= const StatsPage();
        return _statsPage!;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(['专注', '任务清单', '统计'][_index]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                'v$kBuildName',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(child: _currentBody()),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.timer_outlined), label: '专注'),
          NavigationDestination(icon: Icon(Icons.checklist_rtl), label: '任务'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), label: '统计'),
        ],
      ),
    );
  }
}
