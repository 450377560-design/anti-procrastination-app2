import 'dart:async';
import 'package:flutter/material.dart';

// 你的页面：保持路径一致
import 'focus_page.dart';
import 'pages/tasks_page.dart';
import 'pages/stats_page.dart';

// 版本号（CI 里传入 --dart-define=BUILD_NAME=...，这里做兜底）
const String kBuildName =
    String.fromEnvironment('BUILD_NAME', defaultValue: 'dev');

void main() {
  // 确保引擎初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 全局兜底，防止未捕获异常导致白屏/停留在启动页
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
    // 忽略掉让 UI 继续运行
  };
  runZonedGuarded(() {
    runApp(const MyApp());
  }, (e, s) {
    // 生产环境可上报，先打印即可
    // debugPrint('Uncaught in zone: $e\n$s');
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

  // 提前构建 3 个页，避免切换时再次触发耗时 init
  late final List<Widget> _pages = <Widget>[
    const FocusPage(), // 你的专注页
    const TasksPage(), // 你的任务页
    const StatsPage(), // 你的统计页
  ];

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
      body: SafeArea(
        // 用 IndexedStack 保持页状态，避免每次切页重新加载导致“看似卡住”
        child: IndexedStack(
          index: _index,
          children: _pages,
        ),
      ),
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
