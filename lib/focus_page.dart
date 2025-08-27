// lib/focus_page.dart
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
  late int _remaining; // 秒
  Timer? _timer;

  bool _paused = false;
  bool _ended = false;
  int? _sessionId;

  // 休息计时
  int _restAccum = 0; // 秒
  Timer? _restTimer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.minutes * 60;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    _startSession();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _restTimer?.cancel();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _startSession() async {
    // 关键修复：写入真实计划分钟（不再硬编码 25）
    _sessionId = await FocusDao.startSession(
      plannedMinutes: widget.minutes,
      taskId: widget.task?.id,
    );

    // 主计时
    _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (_paused || _ended) return;
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0 && !_ended) {
        _ended = true;
        _timer?.cancel();
        await FocusDao.finishSession(
          _sessionId!,
          completed: true,
          restSeconds: _restAccum,
        );
        if (!mounted) return;
        await _celebrate();
        if (!mounted) return;
        Navigator.pop(context);
      }
    });
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
      await FocusDao.finishSession(
        _sessionId!,
        completed: false,
        restSeconds: _restAccum,
      );
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _togglePause() async {
    setState(() => _paused = !_paused);
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
                minLines: 1,
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(c, fallback),
                      child: Text('直接记录：$fallback'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final v = ctrl.text.trim();
                        Navigator.pop(c, v.isEmpty ? fallback : v);
                      },
                      child: const Text('确定'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _celebrate() async {
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

  String _fmt(int s) {
    final m = s ~/ 60;
    final ss = s % 60;
    return '${m.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final taskTitle = widget.task?.title;
    return Scaffold(
      appBar: AppBar(
        title: Text(taskTitle == null ? '专注' : '专注：$taskTitle'),
        actions: [
          IconButton(
            icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
            onPressed: _togglePause,
          ),
          IconButton(
            icon: const Icon(Icons.stop),
            onPressed: _stop,
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_fmt(_remaining), style: const TextStyle(fontSize: 64, fontFeatures: [FontFeature.tabularFigures()])),
            const SizedBox(height: 16),
            if (_restAccum > 0)
              Text('休息累计：${(_restAccum ~/ 60).toString().padLeft(2, '0')}:${(_restAccum % 60).toString().padLeft(2, '0')}'),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _togglePause,
              icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
              label: Text(_paused ? '继续' : '暂停'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _stop,
              icon: const Icon(Icons.stop),
              label: const Text('停止'),
            ),
          ],
        ),
      ),
    );
  }
}
