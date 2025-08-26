import 'package:flutter/material.dart';
import 'services/native_bridge.dart';
import 'db/dao_focus.dart';
import 'focus_page.dart';
import 'build_info.dart';

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
    _ensureNotificationPermission();

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

  Future<void> _ensureNotificationPermission() async {
    final ok = await NativeBridge.requestNotificationPermission();
    if (!ok && mounted) {
      _showSnack('未授予通知权限，专注与提醒可能无法工作');
    }
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

  Future<void> _startFocus({required int minutes}) async {
    final ok = await NativeBridge.requestNotificationPermission();
    if (!ok) {
      _showSnack('请先在系统设置中允许通知权限');
      return;
    }
    // lock=false：不再尝试原生锁屏 Activity
    final started = await NativeBridge.startFocus(minutes: minutes, lock: false);
    if (started) {
      _currentSessionId = await FocusDao.startSession(minutes);
      if (!mounted) return;
      _showSnack('已开始专注 $minutes 分钟');

      // 进入 Flutter 全屏专注页（不被系统拦截）
      // 倒计时来自 NativeBridge.onTick
      // 结束/停止后会自动返回
      // ignore: use_build_context_synchronously
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => FocusPage(minutes: minutes)),
      );
    } else {
      _showSnack('启动失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('专注 · v$kBuildName')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: () => _startFocus(minutes: 25),
              child: const Text('开始 25 分钟（全屏）'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => NativeBridge.stopFocus(),
              child: const Text('停止'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () async {
                final ok = await NativeBridge.plannerEnable(21, 30);
                if (ok && mounted) _showSnack('已开启夜间规划 21:30');
              },
              child: const Text('开启夜间规划 21:30'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                final ok = await NativeBridge.plannerDisable();
                if (ok && mounted) _showSnack('已关闭夜间规划');
              },
              child: const Text('关闭夜间规划'),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () async {
                final now = DateTime.now();
                final minute = (now.minute + 1) % 60;
                final hour = (minute == 0) ? (now.hour + 1) % 24 : now.hour;
                final ok = await NativeBridge.plannerEnable(hour, minute);
                if (ok && mounted) _showSnack('将于 ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} 推送夜间提醒（测试）');
              },
              child: const Text('测试夜间提醒（+1 分钟）'),
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
