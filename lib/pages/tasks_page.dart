import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/dao_task.dart';
import '../db/dao_template.dart';
import '../focus_page.dart';
import '../models/task.dart';
import '../notify/notification_service.dart';
import '../utils/color_hash.dart';
import 'task_note_page.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});
  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  String _date = DateFormat('yyyy-MM-dd').format(DateTime.now());
  String _sort = 'priority'; // 'priority' | 'time'
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    NotificationService.init();
    TemplateDao.seedDefaults(_date);
  }

  String _fmt(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _pickDate() async {
    final now = DateTime.tryParse(_date) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 3),
    );
    if (!mounted) return;
    if (picked != null) setState(() => _date = _fmt(picked));
  }

  void _shiftDay(int delta) {
    final d = DateTime.tryParse(_date) ?? DateTime.now();
    setState(() => _date = _fmt(d.add(Duration(days: delta))));
  }

  Future<void> _moveToTomorrow() async {
    final n = await TaskDao.moveUnfinishedToTomorrow(_date);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已将 $_date 的 $n 个未完成任务移到明天')),
    );
    setState(() {});
  }

  Future<void> _startTaskFocus(Task t) async {
    final minutes = t.expectedMinutes ?? 25;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FocusPage(minutes: minutes, task: t)),
    );
    if (!mounted) return;
    setState(() {});
  }

  // ========== 新：滚轮时间选择 ==========
  Future<String?> _pickTimeWheel(String? initStr) async {
    TimeOfDay init;
    if (initStr != null && RegExp(r'^\d{1,2}:\d{2}$').hasMatch(initStr)) {
      final p = initStr.split(':');
      init = TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
    } else {
      init = TimeOfDay.now();
    }
    TimeOfDay temp = init;

    return await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) {
        DateTime dtInit = DateTime(2000, 1, 1, init.hour, init.minute);
        return SizedBox(
          height: 260,
          child: Column(
            children: [
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: dtInit,
                  use24hFormat: true,
                  onDateTimeChanged: (dt) {
                    temp = TimeOfDay.fromDateTime(dt);
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final hh = temp.hour.toString().padLeft(2, '0');
                      final mm = temp.minute.toString().padLeft(2, '0');
                      Navigator.pop(c, '$hh:$mm');
                    },
                    child: const Text('确定'),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editTask([Task? t]) async {
    final ctrlTitle = TextEditingController(text: t?.title ?? '');
    final ctrlDesc = TextEditingController(text: t?.description ?? '');
    final ctrlStart = TextEditingController(text: t?.startTime ?? '');
    final ctrlEnd = TextEditingController(text: t?.endTime ?? '');
    final ctrlExp = TextEditingController(text: (t?.expectedMinutes ?? 25).toString());
    final ctrlLabels = TextEditingController(text: t?.labels ?? '');
    final ctrlProject = TextEditingController(text: t?.project ?? '');
    final ctrlEstPomos = TextEditingController(text: (t?.estimatePomos ?? '').toString());
    int priority = t?.priority ?? 2;

    // 方便更新对话框内部 UI
    bool dialogMounted = true;

    Future<void> applyTemplate() async {
      final list = await TemplateDao.list();
      if (!mounted || !dialogMounted) return;
      final id = await showModalBottomSheet<int>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: ListView(
            children: list
                .map(
                  (e) => ListTile(
                    title: Text(e['name'] as String),
                    onTap: () => Navigator.pop(c, e['id'] as int),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await TemplateDao.delete(e['id'] as int);
                        if (context.mounted) Navigator.pop(c);
                      },
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      );
      if (!mounted || !dialogMounted) return;
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
        ctrlEstPomos.text = (tmp.estimatePomos ?? '').toString();
        // 对话框内部 TextField 由 controller 驱动，无需 setState
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) {
        return StatefulBuilder(builder: (c2, setD) {
          return WillPopScope(
            onWillPop: () async {
              dialogMounted = false;
              return true;
            },
            child: AlertDialog(
              title: Text(t == null ? '新建任务' : '编辑任务'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 快速模板按钮行
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () {
                            ctrlTitle.text = '深度工作块';
                            ctrlExp.text = '50';
                            priority = 1;
                            ctrlLabels.text = '专注';
                            ctrlProject.text = '工作';
                            ctrlEstPomos.text = '2';
                          },
                          child: const Text('深度工作 50'),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            ctrlTitle.text = '晨间规划';
                            ctrlExp.text = '10';
                            priority = 2;
                            ctrlLabels.text = '规划';
                            ctrlProject.text = '日常';
                          },
                          child: const Text('晨间规划 10'),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            ctrlTitle.text = '阅读';
                            ctrlExp.text = '20';
                            priority = 2;
                            ctrlLabels.text = '学习';
                            ctrlProject.text = '自我提升';
                          },
                          child: const Text('阅读 20'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(controller: ctrlTitle, decoration: const InputDecoration(labelText: '标题')),
                    TextField(controller: ctrlDesc, decoration: const InputDecoration(labelText: '描述')),
                    Row(
                      children: [
                        const Text('优先级：'),
                        const SizedBox(width: 8),
                        DropdownButton<int>(
                          value: priority,
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('P1')),
                            DropdownMenuItem(value: 2, child: Text('P2')),
                            DropdownMenuItem(value: 3, child: Text('P3')),
                          ],
                          onChanged: (v) => setD(() => priority = v ?? 2),
                        ),
                      ],
                    ),
                    // ======= 新：滚轮选择时间 =======
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              final v = await _pickTimeWheel(ctrlStart.text);
                              if (v != null) setD(() => ctrlStart.text = v);
                            },
                            child: AbsorbPointer(
                              child: TextField(
                                controller: ctrlStart,
                                readOnly: true,
                                decoration: const InputDecoration(
                                  labelText: '开始(可点选择)',
                                  suffixIcon: Icon(Icons.access_time),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              final v = await _pickTimeWheel(ctrlEnd.text);
                              if (v != null) setD(() => ctrlEnd.text = v);
                            },
                            child: AbsorbPointer(
                              child: TextField(
                                controller: ctrlEnd,
                                readOnly: true,
                                decoration: const InputDecoration(
                                  labelText: '结束(可点选择)',
                                  suffixIcon: Icon(Icons.access_time),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: ctrlExp,
                            decoration: const InputDecoration(labelText: '预计分钟'),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: ctrlProject,
                            decoration: const InputDecoration(labelText: '项目'),
                          ),
                        ),
                      ],
                    ),
                    TextField(controller: ctrlLabels, decoration: const InputDecoration(labelText: '标签(逗号分隔)')),
                    const SizedBox(height: 8),
                    TextField(
                      controller: ctrlEstPomos,
                      decoration: const InputDecoration(labelText: '预计番茄数(可选)'),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlinedButton(onPressed: applyTemplate, child: const Text('更多模板')),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () async {
                            final nameCtrl = TextEditingController(
                              text: ctrlTitle.text.isEmpty ? '我的模板' : ctrlTitle.text,
                            );
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (c2) => AlertDialog(
                                title: const Text('保存为模板'),
                                content: TextField(
                                  controller: nameCtrl,
                                  decoration: const InputDecoration(labelText: '模板名'),
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('取消')),
                                  FilledButton(onPressed: () => Navigator.pop(c2, true), child: const Text('保存')),
                                ],
                              ),
                            );
                            if (!mounted || !dialogMounted) return;
                            if (ok == true) {
                              final tmpTask = Task(
                                title: ctrlTitle.text,
                                description: ctrlDesc.text.isEmpty ? null : ctrlDesc.text,
                                priority: priority,
                                startTime: ctrlStart.text.isEmpty ? null : ctrlStart.text,
                                endTime: ctrlEnd.text.isEmpty ? null : ctrlEnd.text,
                                expectedMinutes: int.tryParse(ctrlExp.text),
                                labels: ctrlLabels.text.isEmpty ? null : ctrlLabels.text,
                                project: ctrlProject.text.isEmpty ? null : ctrlProject.text,
                                date: _date,
                                estimatePomos: int.tryParse(ctrlEstPomos.text),
                              );
                              await TemplateDao.saveTemplate(nameCtrl.text, tmpTask);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(const SnackBar(content: Text('已保存为模板')));
                            }
                          },
                          child: const Text('保存为模板'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('保存')),
              ],
            ),
          );
        });
      },
    );

    if (!mounted) return;
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
        estimatePomos: int.tryParse(ctrlEstPomos.text),
        actualPomos: t?.actualPomos ?? 0,
        note: t?.note,
      );

      if (t == null) {
        final id = await TaskDao.insert(task);
        task.id = id;
        if (task.id != null) {
          await NotificationService.scheduleTaskReminder(task);
        }
      } else {
        await TaskDao.update(task);
        if (task.id != null) {
          await NotificationService.cancelTaskReminder(task.id!);
          await NotificationService.scheduleTaskReminder(task);
        }
      }
      if (!mounted) return;
      setState(() {});
    }
  }

  Future<void> _batchSetDone(bool done) async {
    await TaskDao.setDoneMany(_selected.toList(), done);
    if (done) {
      for (final id in _selected) {
        await NotificationService.cancelTaskReminder(id);
      }
    }
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
    if (!mounted) return;
    if (ok == true) {
      await TaskDao.deleteMany(_selected.toList());
      for (final id in _selected) {
        await NotificationService.cancelTaskReminder(id);
      }
      setState(() => _selected.clear());
    }
  }

  Future<void> _openNote(Task t) async {
    final updated = await Navigator.of(context).push<String?>(
      MaterialPageRoute(builder: (_) => TaskNotePage(task: t)),
    );
    if (!mounted) return;
    if (updated != null) {
      t.note = updated;
      await TaskDao.update(t);
      if (!mounted) return;
      setState(() {});
    }
  }

  Future<void> _exportDialog() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('导出已完成任务'),
        children: [
          SimpleDialogOption(
            child: const Text('近 7 天'),
            onPressed: () => Navigator.pop(c, '7'),
          ),
          SimpleDialogOption(
            child: const Text('近 30 天'),
            onPressed: () => Navigator.pop(c, '30'),
          ),
          SimpleDialogOption(
            child: const Text('本月'),
            onPressed: () => Navigator.pop(c, 'month'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == null) return;

    DateTime from, to;
    final now = DateTime.now();
    if (choice == 'month') {
      from = DateTime(now.year, now.month, 1);
      to = DateTime(now.year, now.month, 0 + DateTime(now.year, now.month + 1, 0).day);
    } else {
      final days = int.parse(choice);
      from = DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));
      to = DateTime(now.year, now.month, now.day);
    }

    final tasks = await TaskDao.completedInRange(from, to);
    final buf = StringBuffer()
      ..writeln('# 已完成任务导出')
      ..writeln('时间范围：${DateFormat('yyyy-MM-dd').format(from)} ~ ${DateFormat('yyyy-MM-dd').format(to)}')
      ..writeln()
      ..writeln('| 日期 | 标题 | 项目 | 时段 | 笔记 |')
      ..writeln('|---|---|---|---|---|');

    for (final t in tasks) {
      final slot =
          (t.startTime != null || t.endTime != null) ? '${t.startTime ?? "--"}-${t.endTime ?? "--"}' : '';
      final note = (t.note ?? '').replaceAll('\n', '<br/>');
      buf.writeln('| ${t.date} | ${t.title} | ${t.project ?? ""} | $slot | ${note.isEmpty ? "" : note} |');
    }

    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/tasks_export_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.md');
    await file.writeAsString(buf.toString());

    await Share.shareXFiles([XFile(file.path)], text: '完成任务导出');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Task>>(
      future: TaskDao.listByDate(_date, sort: _sort),
      builder: (context, snap) {
        final list = snap.data ?? <Task>[];
        final groups =
            groupBy(list, (Task t) => (t.project?.isNotEmpty == true) ? t.project! : '未分组');
        final d = DateTime.tryParse(_date) ?? DateTime.now();
        final dayStr = DateFormat('yyyy-MM-dd (EEE)', 'zh_CN').format(d);

        return Scaffold(
          appBar: AppBar(
            title: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('任务清单'),
            ),
            actions: _selected.isEmpty
                ? [
                    IconButton(
                      onPressed: _exportDialog,
                      icon: const Icon(Icons.ios_share),
                      tooltip: '导出已完成任务',
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) => setState(() => _sort = v),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'priority', child: Text('按优先级')),
                        PopupMenuItem(value: 'time', child: Text('按时间段')),
                      ],
                    ),
                  ]
                : [
                    IconButton(
                        onPressed: () => _batchSetDone(true),
                        icon: const Icon(Icons.check_circle_outline)),
                    IconButton(
                        onPressed: () => _batchSetDone(false),
                        icon: const Icon(Icons.radio_button_unchecked)),
                    IconButton(onPressed: _batchDelete, icon: const Icon(Icons.delete_outline)),
                  ],
          ),
          floatingActionButton:
              _selected.isEmpty ? FloatingActionButton(onPressed: () => _editTask(), child: const Icon(Icons.add)) : null,
          body: ListView(
            children: [
              // 顶部日期导航行：横向可滚动，避免溢出
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      IconButton(onPressed: () => _shiftDay(-1), icon: const Icon(Icons.chevron_left)),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(dayStr, style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      IconButton(onPressed: _pickDate, icon: const Icon(Icons.event)),
                      IconButton(onPressed: () => _shiftDay(1), icon: const Icon(Icons.chevron_right)),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _moveToTomorrow,
                        icon: const Icon(Icons.redo, size: 18),
                        label: const Text('未完成移到明天'),
                      ),
                    ],
                  ),
                ),
              ),

              // 各分组任务（美化：卡片 + 柔和背景）
              ...groups.entries.map((e) {
                final title = e.key;
                final items = e.value;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                    ...items.map(_buildTile),
                    const SizedBox(height: 8),
                  ],
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTile(Task t) {
    final sel = _selected.contains(t.id);
    final labels =
        (t.labels ?? '').split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final priColor = [null, Colors.red, Colors.orange, Colors.blue][t.priority];
    final baseColor = colorFromString(t.project ?? t.title);
    final bg = baseColor.withValues(alpha: .06);
    final border = baseColor.withValues(alpha: .20);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onLongPress: () => setState(() {
          if (t.id != null) {
            if (sel) {
              _selected.remove(t.id);
            } else {
              _selected.add(t.id!);
            }
          }
        }),
        onTap: _selected.isEmpty
            ? () => _editTask(t)
            : () => setState(() {
                  if (t.id != null) {
                    if (sel) {
                      _selected.remove(t.id!);
                    } else {
                      _selected.add(t.id!);
                    }
                  }
                }),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          leading: Checkbox(
            value: t.done,
            onChanged: (_) async {
              await TaskDao.toggleDone(t);
              setState(() => t.done = !t.done);
              if (t.id != null) {
                if (t.done) {
                  await NotificationService.cancelTaskReminder(t.id!);
                } else {
                  await NotificationService.scheduleTaskReminder(t);
                }
              }
            },
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  t.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    decoration: t.done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
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
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              runSpacing: 6,
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (t.startTime != null || t.endTime != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: border),
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.white.withValues(alpha: .65),
                    ),
                    child: Text('${t.startTime ?? "--"} - ${t.endTime ?? "--"}',
                        style: const TextStyle(letterSpacing: 1)),
                  ),
                if (labels.isNotEmpty)
                  ...labels.map((e) => Chip(
                        label: Text('#$e', style: const TextStyle(color: Colors.white)),
                        backgroundColor: colorFromString(e),
                      )),
                if (t.actualPomos > 0) Chip(label: Text('已完成番茄：${t.actualPomos}')),
              ],
            ),
          ),
          trailing: Wrap(
            spacing: 4,
            children: [
              IconButton(
                icon: const Icon(Icons.note_alt_outlined),
                tooltip: '笔记',
                onPressed: () => _openNote(t),
              ),
              IconButton(
                icon: const Icon(Icons.play_arrow),
                tooltip: '现在去完成任务',
                onPressed: () => _startTaskFocus(t),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
