import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../settings/equivalents_model.dart';
import '../settings/equivalents_store.dart';
import '../pages/settings_equivalents_page.dart';
import 'package:flutter/rendering.dart'; // ← 新增，用于 RenderRepaintBoundary


class EquivalentsCard extends StatefulWidget {
  final int todayMinutes;
  final int weekMinutes;
  final int? monthMinutes; // 可为 null，则该口径自动禁用
  final int? allMinutes;   // 可为 null，则该口径自动禁用
  final String title;

  const EquivalentsCard({
    super.key,
    required this.todayMinutes,
    required this.weekMinutes,
    this.monthMinutes,
    this.allMinutes,
    this.title = '把专注时间换算成…',
  });

  @override
  State<EquivalentsCard> createState() => _EquivalentsCardState();
}

class _EquivalentsCardState extends State<EquivalentsCard> {
  final _keyBoundary = GlobalKey();
  String _scope = '7d'; // 'today' | '7d' | 'month' | 'all'
  List<EquivalentUnit> _units = [];

  @override
  void initState() {
    super.initState();
    _loadUnits();
  }

  Future<void> _loadUnits() async {
    _units = await EquivalentsStore.load();
    if (mounted) setState(() {});
  }

  int get _minutes {
    switch (_scope) {
      case 'today': return widget.todayMinutes;
      case '7d':    return widget.weekMinutes;
      case 'month': return widget.monthMinutes ?? 0;
      case 'all':   return widget.allMinutes ?? 0;
      default:      return widget.weekMinutes;
    }
  }

  String _fmt(double v) => v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  Future<void> _sharePng() async {
    try {
      final boundary = _keyBoundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final img = await boundary.toImage(pixelRatio: 3);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/equivalents_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await Share.shareXFiles([XFile(file.path)], text: '我的专注等价物');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    for (final u in _units) {
      if (u.minutes <= 0) continue;
      final count = _minutes / u.minutes;
      if (count < .2) continue;
      chips.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        margin: const EdgeInsets.only(right: 8, bottom: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .06),
          border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: .20)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(u.emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text('${_fmt(count)} 个${u.name}', style: const TextStyle(fontWeight: FontWeight.w500)),
        ]),
      ));
    }

    // 口径可用性
    final monthEnabled = widget.monthMinutes != null;
    final allEnabled   = widget.allMinutes != null;

    return Card(
      child: RepaintBoundary(
        key: _keyBoundary,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(
              children: [
                Expanded(child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold))),
                IconButton(
                  tooltip: '配置等价单位',
                  onPressed: () async {
                    final changed = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(builder: (_) => const SettingsEquivalentsPage()),
                    );
                    if (changed == true) _loadUnits();
                  },
                  icon: const Icon(Icons.tune),
                ),
                IconButton(
                  tooltip: '分享为图片',
                  onPressed: _sharePng,
                  icon: const Icon(Icons.ios_share),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 口径选择
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                ChoiceChip(
                  label: const Text('今日'),
                  selected: _scope == 'today',
                  onSelected: (_) => setState(() => _scope = 'today'),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('近7日'),
                  selected: _scope == '7d',
                  onSelected: (_) => setState(() => _scope = '7d'),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('本月'),
                  selected: _scope == 'month',
                  onSelected: monthEnabled ? (_) => setState(() => _scope = 'month') : null,
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('累计'),
                  selected: _scope == 'all',
                  onSelected: allEnabled ? (_) => setState(() => _scope = 'all') : null,
                ),
              ]),
            ),
            const SizedBox(height: 10),
            Wrap(children: chips),
          ]),
        ),
      ),
    );
  }
}
