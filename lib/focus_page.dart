import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'services/native_bridge.dart';

class FocusPage extends StatefulWidget {
  final int minutes;
  const FocusPage({super.key, required this.minutes});

  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> {
  int _remaining = 0;
  late final StreamSubscription<int> _tickSub;
  late final StreamSubscription<void> _finishSub;
  late final StreamSubscription<void> _stopSub;

  String _fmt(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    // 全屏沉浸 + 常亮
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();

    _tickSub = NativeBridge.onTick.listen((sec) {
      if (mounted) setState(() => _remaining = sec);
    });
    _finishSub = NativeBridge.onFinish.listen((_) {
      if (mounted) Navigator.pop(context); // 计时自然结束
    });
    _stopSub = NativeBridge.onStop.listen((_) {
      if (mounted) Navigator.pop(context); // 被停止/打断
    });
  }

  @override
  void dispose() {
    _tickSub.cancel();
    _finishSub.cancel();
    _stopSub.cancel();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _fmt(_remaining),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 96,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => NativeBridge.stopFocus(),
              child: const Text('停止'),
            ),
          ],
        ),
      ),
    );
  }
}
