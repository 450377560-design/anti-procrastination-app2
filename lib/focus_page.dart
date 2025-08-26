import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'db/dao_focus.dart';

class FocusPage extends StatefulWidget {
  final int minutes;
  const FocusPage({super.key, required this.minutes});

  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> {
  late int _remaining;
  Timer? _timer;
  bool _paused = false;
  int? _sessionId;

  @override
  void initState() {
    super.initState();
    _remaining = widget.minutes * 60;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    _startSession();
  }

  Future<void> _startSession() async {
    _sessionId = await FocusDao.startSession(widget.minutes);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (_paused) return;
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) {
        await FocusDao.finishSession(_sessionId!, completed: true);
        if (!mounted) return;
        await _showReward();
        Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _stop() async {
    if (_sessionId != null) {
      await FocusDao.finishSession(_sessionId!, completed: false);
    }
    if (!mounted) return;
    Navigator.pop(context); // 返回上一页，不退出应用
  }

  String _fmt(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  Future<void> _showReward() async {
    // 简单积分：完成一次 +10
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('🎉 太棒了！'),
        content: const Text('本次专注完成，奖励 +10 积分'),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('确定'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_fmt(_remaining),
              style: const TextStyle(color: Colors.white, fontSize: 96, fontWeight: FontWeight.w600, letterSpacing: 2)),
          const SizedBox(height: 24),
          Row(mainAxisSize: MainAxisSize.min, children: [
            FilledButton(
              onPressed: () => setState(() => _paused = !_paused),
              child: Text(_paused ? '继续' : '暂停'),
            ),
            const SizedBox(width: 12),
            FilledButton.tonal(onPressed: _stop, child: const Text('停止')),
          ]),
        ]),
      ),
    );
  }
}
