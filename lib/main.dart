import 'package:flutter/material.dart';
import 'build_info.dart';
import 'focus_page.dart';
import 'pages/tasks_page.dart';
import 'pages/stats_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, // 去掉右上角 DEBUG
      title: 'Anti Procrastination App 2',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const Root(),
    );
  }
}

class Root extends StatefulWidget {
  const Root({super.key});
  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const FocusHome(),
      const TasksPage(),
      const StatsPage(),
    ];
    return Scaffold(
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.timer), label: '专注'),
          NavigationDestination(icon: Icon(Icons.checklist), label: '任务'),
          NavigationDestination(icon: Icon(Icons.insights), label: '统计'),
        ],
      ),
    );
  }
}

class FocusHome extends StatelessWidget {
  const FocusHome({super.key});

  Future<void> _start(BuildContext context, int minutes) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FocusPage(minutes: minutes)),
    );
  }

  Future<void> _startCustom(BuildContext context) async {
    final ctrl = TextEditingController(text: '25');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('自定义专注时长'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: '分钟', hintText: '5–180'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('开始')),
        ],
      ),
    );
    if (ok == true) {
      final m = int.tryParse(ctrl.text) ?? 25;
      if (m >= 1 && m <= 180) _start(context, m);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('专注 · v$kBuildName')),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          FilledButton(onPressed: () => _start(context, 25), child: const Text('开始 25 分钟')),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: () => _start(context, 50), child: const Text('开始 50 分钟')),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: () => _start(context, 90), child: const Text('开始 90 分钟')),
          const SizedBox(height: 20),
          TextButton.icon(onPressed: () => _startCustom(context), icon: const Icon(Icons.tune), label: const Text('自定义时长')),
        ]),
      ),
    );
  }
}
