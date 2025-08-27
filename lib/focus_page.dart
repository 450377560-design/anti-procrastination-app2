import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'db/dao_focus.dart';
import 'models/task.dart';

class FocusPage extends StatefulWidget {
  final int minutes;
  final Task? task; // 关联任务（可空）
  const FocusPage({super.key, required this.minutes, this.task});

  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> {
  late int _remaining;
  Timer? _timer;

  bool _paused = false;
  bool _ended = false;
  int? _sessionId;

  // 休息计时
  int _restAccum = 0; // 当前会话累计休息秒
  Timer? _restTimer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.minutes * 60;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    _startSession();
    _ping();
  }

  Future<void> _startSession() async {
    _sessionId = await FocusDao.startSession(
      plannedMinutes: minutesValue,
      taskId: widget.task?.id,
    );

    _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (_paused || _ended) return;
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0 && !_ended) {
        _ended = true;
        _timer?.cancel();
        await FocusDao.finishSession(_sessionId!, completed: true, restSeconds: _restAccum);
        if (!mounted) return;
        await _celebrate();
        if (!mounted) return;
        Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _restTimer?.cancel();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _stop() async {
    if (_ended) {
      if (mounted) Navigator.pop(context);
      return;
    }
    await _maybeRecordInterruption('手动停止');
    _ended = true;
    _timer?.cancel();
    _restTimer?.cancel();
    if (_sessionId != null) {
      await FocusDao.finishSession(_sessionId!, completed: false, restSeconds: _restAccum);
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _togglePause() async {
    setState(() => _paused = !_paused);
    _ping();
    if (_paused) {
      await _maybeRecordInterruption('暂停');
      _restTimer?.cancel();
      _restTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _restAccum++);
      });
    } else {
      _restTimer?.cancel();
    }
  }

  Future<void> _maybeRecordInterruption(String defaultReason) async {
    if (_sessionId == null) return;
    final r = await _pickReason(defaultReason);
    if (r != null && r.trim().isNotEmpty) {
      await FocusDao.addInterruption(_sessionId!, r.trim());
    }
  }

  Future<String?> _pickReason(String fallback) async {
    final ctrl = TextEditingController();
    final reasons = ['消息', '刷短视频', '临时事项', '疲劳', '生理需求', '其它'];
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('是什么打断了你？', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: reasons.map((e) {
                  return ChoiceChip(
                    label: Text(e),
                    selected: false,
                    onSelected: (_) => Navigator.pop(c, e == '其它' ? null : e),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  labelText: '自定义原因（可选）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(onPressed: () => Navigator.pop(c, null), child: const Text('跳过')),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(c, ctrl.text.trim().isEmpty ? fallback : ctrl.text.trim()),
                    child: const Text('确定'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _ping() async {
    await SystemSound.play(SystemSoundType.click);
    try { await HapticFeedback.mediumImpact(); } catch (_) {}
  }

  String _fmt(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  Future<void> _celebrate() async {
    await _ping();
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (c) => AlertDialog(
        title: const Text('🎉 太棒了！'),
        content: const Text('本次专注完成，奖励 +10 积分'),
        actions: [FilledButton(onPressed: () => Navigator.of(c).pop(), child: const Text('确定'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final taskTitle = widget.task?.title;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (taskTitle != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('任务：$taskTitle', style: const TextStyle(color: Colors.white70)),
                  ),
                Text(_fmt(_remaining),
                    style: const TextStyle(color: Colors.white, fontSize: 96, fontWeight: FontWeight.w600, letterSpacing: 2)),
                const SizedBox(height: 24),
                if (_paused)
                  Column(
                    children: [
                      const Text('休息时间', style: TextStyle(color: Colors.white70)),
                      Text(_fmt(_restAccum),
                          style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                    ],
                  ),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  FilledButton(onPressed: _togglePause, child: Text(_paused ? '继续' : '暂停')),
                  const SizedBox(width: 12),
                  FilledButton.tonal(onPressed: _stop, child: const Text('停止')),
                ]),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
