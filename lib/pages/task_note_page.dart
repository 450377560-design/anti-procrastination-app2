import 'package:flutter/material.dart';
import '../models/task.dart';

class TaskNotePage extends StatefulWidget {
  final Task task;
  const TaskNotePage({super.key, required this.task});

  @override
  State<TaskNotePage> createState() => _TaskNotePageState();
}

class _TaskNotePageState extends State<TaskNotePage> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.task.note ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('任务笔记'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _ctrl.text),
            child: const Text('保存'),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _ctrl,
          maxLines: null,
          expands: true,
          decoration: InputDecoration(
            hintText: '写下完成心得、关键要点、复盘等……',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }
}
