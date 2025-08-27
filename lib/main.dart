import 'dart:async';
import 'package:flutter/material.dart';

// 你的页面（保持与原工程一致的相对路径）
import 'focus_page.dart';
import 'pages/tasks_page.dart';
import 'pages/stats_page.dart';

// CI 会通过 --dart-define 传入构建号，这里兜底
const String kBuildName =
    String.fromEnvironment('BUILD_NAME', defaultValue: 'dev');

void main() {
  // 关键一步：在使用任何插件/平台通道前，先初始化引擎，避免首帧被卡住
  WidgetsFlutterBinding.ensureInitialized();

  // 兜底，防止未捕获异常影响渲染
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
  };

  runZonedGuarded(() {
    runApp(const MyApp());
  }, (error, stack) {
    // 这里可接日志上报；为稳妥起见不做阻断
  });
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

  // 懒加载：首次访问对应 tab 时再创建页面，避免启动期就构建所有较重页面
  Widget? _focusPage;
  Widget? _tasksPage;
  Widget? _statsPage;

  Widget _currentBody() {
    switch (_index) {
      case 0:
        _focusPage ??= const FocusPage();
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
