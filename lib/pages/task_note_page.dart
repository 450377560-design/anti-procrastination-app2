import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/task.dart';

class TaskNotePage extends StatefulWidget {
  final Task task;
  const TaskNotePage({super.key, required this.task});

  @override
  State<TaskNotePage> createState() => _TaskNotePageState();
}

class _TaskNotePageState extends State<TaskNotePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  late final TextEditingController _note;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _note = TextEditingController(text: widget.task.note ?? '');
    _tab = TabController(length: 2, vsync: this);
    _note.addListener(() => setState(() => _dirty = true));
  }

  @override
  void dispose() {
    _tab.dispose();
    _note.dispose();
    super.dispose();
  }

  // ===== 工具函数：在选中范围包裹/插入文本 =====
  void _wrapSelection(String left, [String right = '']) {
    final sel = _note.selection;
    final text = _note.text;
    final start = sel.start;
    final end = sel.end;
    if (start < 0 || end < 0) return;

    final selected = text.substring(start, end);
    final newText = text.replaceRange(start, end, '$left$selected$right');
    _note.value = _note.value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: start + left.length + selected.length + right.length),
      composing: TextRange.empty,
    );
  }

  void _insertAtLineStart(String prefix) {
    final sel = _note.selection;
    if (sel.start < 0) return;
    final text = _note.text;
    final lineStart = text.lastIndexOf('\n', sel.start - 1) + 1;
    final newText = text.replaceRange(lineStart, lineStart, prefix);
    final delta = prefix.length;
    final newSel = sel.copyWith(
      baseOffset: sel.baseOffset + delta,
      extentOffset: sel.extentOffset + delta,
    );
    _note.value = _note.value.copyWith(text: newText, selection: newSel);
  }

  void _toggleChecklist() {
    final sel = _note.selection;
    if (sel.start < 0) return;
    final text = _note.text;
    final lineStart = text.lastIndexOf('\n', sel.start - 1) + 1;
    final lineEnd = text.indexOf('\n', sel.start);
    final end = lineEnd == -1 ? text.length : lineEnd;
    final line = text.substring(lineStart, end).trimLeft();

    String replace;
    if (line.startsWith('- [ ] ')) {
      replace = line.replaceFirst('- [ ] ', '- [x] ');
    } else if (line.startsWith('- [x] ')) {
      replace = line.replaceFirst('- [x] ', '- [ ] ');
    } else if (line.startsWith('- ')) {
      replace = line.replaceFirst('- ', '- [ ] ');
    } else {
      replace = '- [ ] $line';
    }

    final newText = text.replaceRange(lineStart, end, replace);
    _note.value = _note.value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: lineStart + replace.length),
    );
  }

  void _insertTimestamp() {
    final now = DateTime.now();
    final s = DateFormat('yyyy-MM-dd HH:mm').format(now);
    _wrapSelection('`$s` ');
  }

  Future<void> _insertTemplate() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          children: [
            ListTile(
              title: const Text('复盘模板（WWIN）'),
              subtitle: const Text('What went well / Issues / Next actions'),
              onTap: () => Navigator.pop(c, 'retro'),
            ),
            ListTile(
              title: const Text('问题-思路-方案-结果'),
              onTap: () => Navigator.pop(c, 'pssr'),
            ),
            ListTile(
              title: const Text('会议记录'),
              subtitle: const Text('参与者 / 议题 / 结论 / 待办'),
              onTap: () => Navigator.pop(c, 'meeting'),
            ),
            ListTile(
              title: const Text('空白（带今日时间）'),
              onTap: () => Navigator.pop(c, 'blank'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    String tpl = '';
    switch (choice) {
      case 'retro':
        tpl = '''
# 复盘（$today）

## ✅ What went well
- 

## ⚠️ Issues
- 

## 🎯 Next actions
- [ ] 
''';
        break;
      case 'pssr':
        tpl = '''
# 记录（$today）

## 🧩 问题
- 

## 🧠 思路
- 

## 🛠 方案
- 

## 📈 结果
- 
''';
        break;
      case 'meeting':
        tpl = '''
# 会议记录（$today）

**参与者**：  
**议题**：  

## 讨论要点
- 

## 结论
- 

## 待办
- [ ] 
''';
        break;
      default:
        tpl = '# $today\n\n';
    }

    // 插入到当前光标处
    final sel = _note.selection;
    final text = _note.text;
    final pos = sel.start < 0 ? text.length : sel.start;
    final newText = text.replaceRange(pos, pos, tpl);
    _note.value = _note.value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: pos + tpl.length),
    );
  }

  Future<void> _exportMarkdown() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/note_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.md');
    await file.writeAsString(_note.text);
    await Share.shareXFiles([XFile(file.path)], text: '任务《${widget.task.title}》笔记导出');
  }

  int get _words {
    final t = _note.text.trim();
    if (t.isEmpty) return 0;
    // 粗略词数：以空白分割
    return t.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).length;
  }

  @override
  Widget build(BuildContext context) {
    final title = '笔记 · ${widget.task.title}';
    return WillPopScope(
      onWillPop: () async {
        if (!_dirty) return true;
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('放弃未保存的更改？'),
            content: const Text('返回将丢失本次编辑内容。'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('继续编辑')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('放弃')),
            ],
          ),
        );
        return ok == true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title, overflow: TextOverflow.ellipsis),
          bottom: TabBar(
            controller: _tab,
            tabs: const [Tab(text: '编辑'), Tab(text: '预览')],
          ),
          actions: [
            IconButton(
              tooltip: '导出为 Markdown',
              onPressed: _exportMarkdown,
              icon: const Icon(Icons.ios_share),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: () => Navigator.pop(context, _note.text),
              child: const Text('保存'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            _toolbar(),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  _editor(),
                  Markdown(
                    data: _note.text,
                    selectable: true,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  ),
                ],
              ),
            ),
            _statusBar(),
          ],
        ),
      ),
    );
  }

  Widget _toolbar() {
    final iconSize = 22.0;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            IconButton(
              tooltip: '加粗 **text**',
              iconSize: iconSize,
              onPressed: () => _wrapSelection('**', '**'),
              icon: const Icon(Icons.format_bold),
            ),
            IconButton(
              tooltip: '斜体 _text_',
              iconSize: iconSize,
              onPressed: () => _wrapSelection('_', '_'),
              icon: const Icon(Icons.format_italic),
            ),
            IconButton(
              tooltip: '删除线 ~~text~~',
              iconSize: iconSize,
              onPressed: () => _wrapSelection('~~', '~~'),
              icon: const Icon(Icons.format_strikethrough),
            ),
            IconButton(
              tooltip: '行内代码 `code`',
              iconSize: iconSize,
              onPressed: () => _wrapSelection('`', '`'),
              icon: const Icon(Icons.code),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '一级标题',
              iconSize: iconSize,
              onPressed: () => _insertAtLineStart('# '),
              icon: const Icon(Icons.looks_one),
            ),
            IconButton(
              tooltip: '二级标题',
              iconSize: iconSize,
              onPressed: () => _insertAtLineStart('## '),
              icon: const Icon(Icons.looks_two),
            ),
            IconButton(
              tooltip: '三级标题',
              iconSize: iconSize,
              onPressed: () => _insertAtLineStart('### '),
              icon: const Icon(Icons.looks_3),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '项目符号 - ',
              iconSize: iconSize,
              onPressed: () => _insertAtLineStart('- '),
              icon: const Icon(Icons.format_list_bulleted),
            ),
            IconButton(
              tooltip: '有序列表 1. ',
              iconSize: iconSize,
              onPressed: () => _insertAtLineStart('1. '),
              icon: const Icon(Icons.format_list_numbered),
            ),
            IconButton(
              tooltip: '清单 - [ ]',
              iconSize: iconSize,
              onPressed: _toggleChecklist,
              icon: const Icon(Icons.check_box_outlined),
            ),
            IconButton(
              tooltip: '引用 > ',
              iconSize: iconSize,
              onPressed: () => _insertAtLineStart('> '),
              icon: const Icon(Icons.format_quote),
            ),
            IconButton(
              tooltip: '分隔线 ---',
              iconSize: iconSize,
              onPressed: () => _insertAtLineStart('\n---\n'),
              icon: const Icon(CupertinoIcons.minus),
            ),
            IconButton(
              tooltip: '时间戳',
              iconSize: iconSize,
              onPressed: _insertTimestamp,
              icon: const Icon(Icons.access_time),
            ),
            IconButton(
              tooltip: '插入模板',
              iconSize: iconSize,
              onPressed: _insertTemplate,
              icon: const Icon(Icons.description_outlined),
            ),
          ],
        ),
      ),
    );
  }

  Widget _editor() {
    return TextField(
      controller: _note,
      keyboardType: TextInputType.multiline,
      maxLines: null,
      expands: true,
      decoration: const InputDecoration(
        hintText: '支持 Markdown：**加粗** _斜体_ ~~删除线~~ `代码`\n- [ ] 清单项\n- 项目符号\n1. 有序列表\n> 引用\n\n点击上方工具栏快速插入',
        contentPadding: EdgeInsets.fromLTRB(12, 12, 12, 24),
        border: InputBorder.none,
      ),
      style: const TextStyle(height: 1.35),
    );
  }

  Widget _statusBar() {
    final length = _note.text.characters.length;
    return Container(
      height: 32,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        '字数：$length  ·  词数：$_words',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
