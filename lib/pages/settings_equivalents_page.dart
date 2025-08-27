import 'package:flutter/material.dart';
import '../settings/equivalents_model.dart';
import '../settings/equivalents_store.dart';

class SettingsEquivalentsPage extends StatefulWidget {
  const SettingsEquivalentsPage({super.key});
  @override
  State<SettingsEquivalentsPage> createState() => _SettingsEquivalentsPageState();
}

class _SettingsEquivalentsPageState extends State<SettingsEquivalentsPage> {
  List<EquivalentUnit> _units = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _units = await EquivalentsStore.load();
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    await EquivalentsStore.save(_units);
    if (!mounted) return;
    Navigator.pop(context, true); // 返回 true 提示上层刷新
  }

  Future<void> _reset() async {
    await EquivalentsStore.reset();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已恢复默认映射')));
  }

  Future<void> _edit({EquivalentUnit? unit, int? index}) async {
    final emojiCtrl = TextEditingController(text: unit?.emoji ?? '🎯');
    final nameCtrl = TextEditingController(text: unit?.name ?? '');
    final minCtrl  = TextEditingController(text: unit?.minutes.toString() ?? '60');

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(unit == null ? '新增等价单位' : '编辑等价单位'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: emojiCtrl, decoration: const InputDecoration(labelText: '图标(Emoji)')),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '名称')),
            TextField(
              controller: minCtrl,
              decoration: const InputDecoration(labelText: '对应分钟数(>=1)'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) return;

    final minutes = int.tryParse(minCtrl.text.trim());
    if (minutes == null || minutes <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('分钟数需为正整数')));
      return;
    }

    final item = EquivalentUnit(
      emoji: emojiCtrl.text.trim().isEmpty ? '🎯' : emojiCtrl.text.trim(),
      name: nameCtrl.text.trim().isEmpty ? '未命名' : nameCtrl.text.trim(),
      minutes: minutes,
    );

    setState(() {
      if (index == null) {
        _units.add(item);
      } else {
        _units[index] = item;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('等价单位配置'),
        actions: [
          IconButton(onPressed: _reset, icon: const Icon(Icons.restore), tooltip: '恢复默认'),
          const SizedBox(width: 4),
          FilledButton(onPressed: _save, child: const Text('保存')),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(),
        child: const Icon(Icons.add),
      ),
      body: _units.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ReorderableListView.builder(
              itemBuilder: (c, i) {
                final u = _units[i];
                return ListTile(
                  key: ValueKey('eq_$i'),
                  leading: Text(u.emoji, style: const TextStyle(fontSize: 20)),
                  title: Text(u.name),
                  subtitle: Text('1 个 = ${u.minutes} 分钟'),
                  trailing: Wrap(
                    spacing: 6,
                    children: [
                      IconButton(icon: const Icon(Icons.edit), onPressed: () => _edit(unit: u, index: i)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(() => _units.removeAt(i)),
                      ),
                      const Icon(Icons.drag_handle),
                    ],
                  ),
                );
              },
              itemCount: _units.length,
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex -= 1;
                setState(() {
                  final item = _units.removeAt(oldIndex);
                  _units.insert(newIndex, item);
                });
              },
            ),
    );
  }
}
