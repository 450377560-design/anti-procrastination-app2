import 'dart:async';
import 'package:flutter/material.dart';
import 'db/dao_focus.dart';
import 'db/dao_task.dart';
import 'models/task.dart';

class FocusPage extends StatefulWidget {
  final int minutes;   // 必填：专注分钟
  final Task? task;    // 可选：来自任务页的任务

  const FocusPage({super.key, required this.minutes, this.task});

  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> {
  int? _sessionId;
  bool _running = false;
  bool _paused  = false;
  int  _remainingSec = 0;

  int  _restAccum = 0;            // 已累计的休息秒数
  DateTime? _pauseStart;          // 暂停起点（用于累计休息）
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _remainingSec = widget.minutes * 60; // 不自动开始，等用户点击
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _start() async {
    if (_running) return;
    final id = await FocusDao.startSession(
      plannedMinutes: widget.minutes,
      taskId: widget.task?.id,
    );
    setState(() {
      _sessionId = id;
      _running = true;
      _paused  = false;
      _remainingSec = widget.minutes * 60;
    });
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!_paused) {
        if (_remainingSec > 0) {
          setState(() => _remainingSec--);
        } else {
          _onAutoFinish();
        }
      }
    });
  }

  Future<void> _onAutoFinish() async {
    if (_sessionId == null) return;
    // 自动结束视为完成
    // 若此时处于暂停，补齐休息时间
    if (_paused && _pauseStart != null) {
      _restAccum += DateTime.now().difference(_pauseStart!).inSeconds;
    }
    await FocusDao.finishSession(_sessionId!, completed: true, restSeconds: _restAccum);
    _cleanup();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('太棒了，本次专注完成！(+10 积分)')),
    );
  }

  Future<void> _togglePause() async {
    if (!_running) return;
    if (_paused) {
      // 继续：把这段暂停时间计入休息
      if (_pauseStart != null) {
        _restAccum += DateTime.now().difference(_pauseStart!).inSeconds;
      }
      setState(() {
        _paused = false;
        _pauseStart = null;
      });
    } else {
      // 开始暂停
      setState(() {
        _paused = true;
        _pauseStart = DateTime.now();
      });
    }
  }

  Future<void> _stop() async {
    if (_sessionId == null) {
      _cleanup();
      return;
    }
    // 先选“完成 / 被打断”
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('结束专注'),
        content: const Text('请选择本次结果'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'interrupt'), child: const Text('被打断')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'complete'),  child: const Text('完成')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'),    child: const Text('取消')),
        ],
      ),
    );
    if (!mounted || action == null || action == 'cancel') return;

    bool completed = action == 'complete';
    // 若被打断，采集原因
    if (!completed) {
      final reason = await _askInterruptionReason();
      if (reason != null && reason.trim().isNotEmpty) {
        await FocusDao.addInterruption(_sessionId!, reason.trim());
      }
    }
    // 若仍在暂停，补齐休息时间
    if (_paused && _pauseStart != null) {
      _restAccum += DateTime.now().difference(_pauseStart!).inSeconds;
    }
    await FocusDao.finishSession(_sessionId!, completed: completed, restSeconds: _restAccum);
    _cleanup(); // 重置当前页 UI（不 pop，避免黑屏）
  }

  Future<String?> _askInterruptionReason() async {
    final reasons = ['消息/来电', '想刷手机', '被人打断', '去做别的事', '身体不适', '其他'];
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('打断原因'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: reasons
                  .map((r) => ActionChip(label: Text(r), onPressed: () => Navigator.pop(ctx, r)))
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextField(controller: controller, decoration: const InputDecoration(hintText: '自定义原因')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim().isEmpty ? null : controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _cleanup() {
    _tick?.cancel();
    _tick = null;
    setState(() {
      _running = false;
      _paused = false;
      _pauseStart = null;
      _sessionId = null;
      _restAccum = 0;
      _remainingSec = widget.minutes * 60;
    });
  }

  String _fmt() {
    final m = _remainingSec ~/ 60;
    final s = _remainingSec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _running
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_fmt(), style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_paused)
                    Text('休息中… 已休息 ${(_restAccum / 60).floor()} 分 ${_restAccum % 60} 秒',
                        style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _togglePause,
                        icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                        label: Text(_paused ? '继续' : '暂停'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _stop,
                        icon: const Icon(Icons.stop),
                        label: const Text('停止'),
                      ),
                    ],
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timer_outlined, size: 72),
                  const SizedBox(height: 12),
                  Text('准备开始 ${widget.minutes} 分钟专注', style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('开始专注'),
                  ),
                ],
              ),
      ),
    );
  }
}
