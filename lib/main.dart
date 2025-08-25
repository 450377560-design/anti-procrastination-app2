import 'package:flutter/material.dart';
import 'services/native_bridge.dart';
import 'db/dao_focus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  NativeBridge.initCallbacks();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anti Procrastination App 2',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int? _currentSessionId;

  @override
  void initState() {
    super.initState();
    NativeBridge.onInterruption.listen((_) async {
      final reason = await _pickReason(context);
      if (reason != null && _currentSessionId != null) {
        await FocusDao.addInterruption(_currentSessionId!, reason);
      }
      if (mounted) _showSnack('已记录打断：${reason ?? "（未选择）"}');
    });

    NativeBridge.onFinish.listen((_) async {
      if (_currentSessionId != null) {
        await FocusDao.finishSession(_currentSessionId!, completed: true);
        _currentSessionId = null;
        if (mounted) _showSnack('专注完成');
      }
    });

    NativeBridge.onStop.listen((_) async {
      if (_currentSessionId != null) {
        await FocusDao.finishSession(_currentSessionId!, completed: false);
        _currentSessionId = null;
        if (mounted) _showSnack('专注已停止');
      }
    });
  }

  Future<String?> _pickReason(BuildContext ctx) async {
    const common = ['查看手机', '被他人打断', '通知/消息', '生理需求', '其他'];
    return showDialog<String>(
      context: ctx,
      builder: (c) {
        String custom = '';
        return AlertDialog(
          title: const Text('选择打断原因'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...common.map((e) => ListTile(
                    title: Text(e),
                    onTap: () => Navigator.pop(c, e),
                  )),
              TextField(
                decoration: const InputDecoration(hintText: '自定义原因…'),
                onChanged: (v) => custom = v,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(c, custom.isEmpty ? null : custom), child: const Text('确定')),
          ],
        );
      },
    );
  }

  Future<void> _startFocus({required int minutes, required bool lock}) async {
    final ok = await NativeBridge.startFocus(minutes: minutes, lock: lock);
    if (ok) {
      _currentSessionId = await FocusDao.startSession(minutes);
      if (mounted) _showSnack('已开始专注 $minutes 分钟');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Anti Procrastination App 2')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: () => _startFocus(minutes: 25, lock: true),
              child: const Text('开始 25 分钟（锁屏）'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => NativeBridge.stopFocus(),
              child: const Text('停止'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => NativeBridge.plannerEnable(21, 30),
              child: const Text('开启夜间规划 21:30'),
            ),
            TextButton(
              onPressed: () => NativeBridge.plannerDisable(),
              child: const Text('关闭夜间规划'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
