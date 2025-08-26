import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db/dao_task.dart';
import '../db/dao_template.dart';
import '../models/task.dart';
import '../utils/color_hash.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});
  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  String _date = DateFormat('yyyy-MM-dd').format(DateTime.now());
  String _sort = 'priority';
  final Set<int> _selected = {}; // 批量选择

  String _fmt(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _pickDate() async {
    final now = DateTime.tryParse(_date) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) setState(() => _date = _fmt(picked));
  }

  void _shiftDay(int delta) {
    final d = DateTime.tryParse(_date) ?? DateTime.now();
    setState(() => _date = _fmt(d.add(Duration(days: delta))));
  }

  Future<void> _moveToTomorrow() async {
    final n = await TaskDao.moveUnfinishedToTomorrow(_date);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已将 $_date 的 $n 个未完成任务移到明天')));
    setState(() {});
  }

  Future<void> _editTask([Task? t]) async {
    final ctrlTitle = TextEditingController(text: t?.title ?? '');
    final ctrlDesc = TextEditingController(text: t?.description ?? '');
    final ctrlStart = TextEditingController(text: t?.startTime ?? '');
    final ctrlEnd = TextEditingController(text: t?.endTime ?? '');
    final ctrlExp = TextEditingController(text: (t?.expectedMinutes ?? 25).toString());
    final ctrlLabels = TextEditingController(text: t?.labels ?? '');
    final ctrlProject = TextEditingController(text: t?.project ?? '');
    int priority = t?.priority ?? 2;

    Future<void> applyTemplate() async {
      final list = await TemplateDao.list();
      if (!mounted) return;
      final id = await showModalBottomSheet<int>(
        context: context,
        builder: (c) => ListView(
          children: list
              .map((e) => ListTile(
                    title: Text(e['name'] as String),
                    onTap: () => Navigator.pop(c, e['id'] as int),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await TemplateDao.delete(e['id'] as int);
                        if (mounted) Navigator.pop(c);
                      },
                    ),
                  ))
              .toList(),
        ),
      );
      if (id != null) {
        final tmp = await TemplateDao.apply(id, _date);
        ctrlTitle.text = tmp.title;
        ctrlDesc.text = tmp.description ?? '';
        priority = tmp.priority;
        ctrlStart.text = tmp.startTime ?? '';
        ctrlEnd.text = tmp.endTime ?? '';
        ctrlExp.text = (tmp.expectedMinutes ?? 25).toString();
        ctrlLabels.text = tmp.labels ?? '';
        ctrlProject.text = tmp.project ?? '';
        setState(() {});
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t == null ? '新建任务' : '编辑任务'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: ctrlTitle, decoration: const InputDecoration(labelText: '标题')),
            TextField(controller: ctrlDesc, decoration: const InputDecoration(labelText: '描述')),
            Row(children: [
              const Text('优先级：'), const SizedBox(width: 8),
              DropdownButton<int>(
                value: priority,
                items: const [
                  DropdownMenuItem(value: 1, child: Text('P1')),
                  DropdownMenuItem(value: 2, child: Text('P2')),
                  DropdownMenuItem(value: 3, child: Text('P3')),
                ],
                onChanged: (v) => priority = v ?? 2,
              ),
            ]),
            Row(children: [
              Expanded(child: TextField(controller: ctrlStart, decoration: const InputDecoration(labelText: '开始(09:30)'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: ctrlEnd, decoration: const InputDecoration(labelText: '结束(10:15)'))),
            ]),
            Row(children: [
              Expanded(child: TextField(controller: ctrlExp, decoration: const InputDecoration(labelText: '预计分钟'), keyboardType: TextInputType.number)),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: ctrlProject, decoration: const InputDecoration(labelText: '项目'))),
            ]),
            TextField(controller: ctrlLabels, decoration: const InputDecoration(labelText: '标签(逗号分隔)')),
            const SizedBox(height: 8),
            Row(children: [
              OutlinedButton(onPressed: applyTemplate, child: const Text('应用模板')),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () async {
                  final nameCtrl = TextEditingController(text: ctrlTitle.text.isEmpty ? '我的模板' : ctrlTitle.text);
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c2) => AlertDialog(
                      title: const Text('保存为模板'),
                      content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '模板名')),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('取消')),
                        FilledButton(onPressed: () => Navigator.pop(c2, true), child: const Text('保存')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    final tmpTask = Task(
                      title: ctrlTitle.text,
                      description: ctrlDesc.text,
                      priority: priority,
                      startTime: ctrlStart.text,
                      endTime: ctrlEnd.text,
                      expectedMinutes: int.tryParse(ctrlExp.text),
                      labels: ctrlLabels.text,
                      project: ctrlProject.text,
                      date: _date,
                    );
                    await TemplateDao.saveTemplate(nameCtrl.text, tmpTask);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存为模板')));
                  }
                },
                child: const Text('保存为模板'),
              ),
            ]),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('保存')),
        ],
      ),
    );

    if (ok == true) {
      final task = Task(
        id: t?.id,
        title: ctrlTitle.text,
        description: ctrlDesc.text.isEmpty ? null : ctrlDesc.text,
        priority: priority,
        startTime: ctrlStart.text.isEmpty ? null : ctrlStart.text,
        endTime: ctrlEnd.text.isEmpty ? null : ctrlEnd.text,
        expectedMinutes: int.tryParse(ctrlExp.text),
        labels: ctrlLabels.text.isEmpty ? null : ctrlLabels.text,
        project: ctrlProject.text.isEmpty ? null : ctrlProject.text,
        date: _date,
        done: t?.done ?? false,
      );
      if (t == null) {
        await TaskDao.insert(task);
      } else {
        await TaskDao.update(task);
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> _batchSetDone(bool done) async {
    await TaskDao.setDoneMany(_selected.toList(), done);
    setState(() => _selected.clear());
  }

  Future<void> _batchDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除所选任务？'),
        content: Text('共 ${_selected.length} 个任务将被删除，不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      await TaskDao.deleteMany(_selected.toList());
      setState(() => _selected.clear());
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: TaskDao.listByDate(_date, sort: _sort),
      builder: (context, snap) {
        final list = snap.data ?? <Task>[];
        final groups = groupBy(list, (Task t) => (t.project?.isNotEmpty == true) ? t.project! : '未分组');
        final titleDate = DateTime.tryParse(_date) ?? DateTime.now();
        final titleStr = DateFormat('yyyy-MM-dd (EEE)', 'zh_CN').format(titleDate);

        return Scaffold(
          appBar: AppBar(
            title: Text(_selected.isEmpty ? '任务清单 · $titleStr' : '已选择 ${_selected.length} 项'),
            actions: _selected.isEmpty
                ? [
                    IconButton(onPressed: () => _shiftDay(-1), icon: const Icon(Icons.chevron_left), tooltip: '前一天'),
                    IconButton(onPressed: _pickDate, icon: const Icon(Icons.event), tooltip: '选择日期'),
                    IconButton(onPressed: () => _shiftDay(1), icon: const Icon(Icons.chevron_right), tooltip: '后一天'),
                    IconButton(onPressed: _moveToTomorrow, icon: const Icon(Icons.redo), tooltip: '未完成移到明天'),
                    PopupMenuButton<String>(
                      onSelected: (v) => setState(() => _sort = v),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'priority', child: Text('按优先级')),
                        PopupMenuItem(value: 'time', child: Text('按时间段')),
                      ],
                    ),
                  ]
                : [
                    IconButton(onPressed: () => _batchSetDone(true), icon: const Icon(Icons.check_circle_outline)),
                    IconButton(onPressed: () => _batchSetDone(false), icon: const Icon(Icons.radio_button_unchecked)),
                    IconButton(onPressed: _batchDelete, icon: const Icon(Icons.delete_outline)),
                  ],
          ),
          floatingActionButton: _selected.isEmpty
              ? FloatingActionButton(onPressed: () => _editTask(), child: const Icon(Icons.add))
              : null,
          body: ListView(
            children: groups.entries.map((e) {
              final title = e.key;
              final items = e.value;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  ...items.map(_buildTile),
                  const Divider(height: 24),
                ],
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildTile(Task t) {
    final sel = _selected.contains(t.id);
    final labels = (t.labels ?? '').split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final priColor = [null, Colors.red, Colors.orange, Colors.blue][t.priority];

    return InkWell(
      onLongPress: () => setState(() {
        if (t.id != null) {
          if (sel) _selected.remove(t.id);
          else _selected.add(t.id!);
        }
      }),
      onTap: _selected.isEmpty ? () => _editTask(t) : () => setState(() {
        if (t.id != null) {
          if (sel) _selected.remove(t.id!);
          else _selected.add(t.id!);
        }
      }),
      child: Container(
        color: sel ? Theme.of(context).colorScheme.primary.withValues(alpha: .08) : null,
        child: ListTile(
          leading: Checkbox(
            value: t.done,
            onChanged: (_) async {
              await TaskDao.toggleDone(t);
              setState(() => t.done = !t.done);
            },
          ),
          title: Row(
            children: [
              Text(t.title, style: TextStyle(decoration: t.done ? TextDecoration.lineThrough : null)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: priColor == null ? null : priColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: priColor ?? Colors.grey),
                ),
                child: Text('P${t.priority}', style: TextStyle(color: priColor ?? Colors.grey)),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              runSpacing: 6,
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (t.startTime != null || t.endTime != null)
                  Chip(label: Text('${t.startTime ?? "--"}-${t.endTime ?? "--"}')),
                if (labels.isNotEmpty)
                  ...labels.map((e) => Chip(
                        label: Text('#$e', style: const TextStyle(color: Colors.white)),
                        backgroundColor: colorFromString(e),
                      )),
              ],
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }
}
