import 'package:flutter/material.dart';
import '../settings/equivalents_model.dart';
import '../settings/equivalents_store.dart';

/// 把“等价显示”做成首帧后懒加载，不阻塞启动。
class EquivalentsCard extends StatefulWidget {
  final int todayMinutes;
  final int weekMinutes;
  final int? monthMinutes;
  final int? allMinutes;
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
  List<EquivalentUnit> _units = kDefaultEquivalentUnits;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    // 放到首帧之后再取 SharedPreferences，避免在 very-early 阶段触发通道
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final u = await EquivalentsStore.load();
        if (!mounted) return;
        setState(() {
          _units = u;
          _ready = true;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _units = List.of(kDefaultEquivalentUnits);
          _ready = true;
        });
      }
    });
  }

  String _fmt(int minutes) {
    final h = minutes ~/ 60, m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}小时${m.toString().padLeft(2, '0')}分钟';
  }

  List<Widget> _rows(String label, int minutes) {
    if (minutes <= 0 || _units.isEmpty) return [];
    final tiles = <Widget>[];
    for (final u in _units) {
      if (u.minutes <= 0) continue;
      final n = (minutes / u.minutes).toStringAsFixed(1);
      tiles.add(Row(
        children: [
          Text(u.emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(child: Text('${u.name} ≈ $n 个')),
        ],
      ));
    }
    if (tiles.isEmpty) return [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text('$label（${_fmt(minutes)}）',
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      ...tiles,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: _ready
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      style: Theme.of(context).textTheme.titleMedium),
                  ..._rows('今日', widget.todayMinutes),
                  ..._rows('本周', widget.weekMinutes),
                  if (widget.monthMinutes != null)
                    ..._rows('本月', widget.monthMinutes!),
                  if (widget.allMinutes != null)
                    ..._rows('累计', widget.allMinutes!),
                ],
              )
            : Row(
                children: const [
                  SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('加载中…'),
                ],
              ),
      ),
    );
  }
}
