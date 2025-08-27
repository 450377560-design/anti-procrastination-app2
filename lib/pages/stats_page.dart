import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../db/dao_focus.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});
  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final now = DateTime.now();

    // 今日区间（用于休息时长）
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = DateTime(now.year, now.month, now.day + 1);

    // 近 7 天区间（用于打断统计）
    final start7 = DateTime(now.year, now.month, now.day - 6);
    final end7 = endOfToday;

    // 数据查询
    final restSec = await FocusDao.restSecondsBetween(
      startOfToday.millisecondsSinceEpoch,
      endOfToday.millisecondsSinceEpoch,
    );

    final interRows = await FocusDao.loadInterruptionsBetween(
      start7.millisecondsSinceEpoch,
      end7.millisecondsSinceEpoch,
    );
    final interMap = <String, int>{};
    for (final r in interRows) {
      interMap[r['reason'] as String] = (r['cnt'] as int?) ?? 0;
    }

    final streak = await FocusDao.streakDays();
    final points = await FocusDao.pointsTotal();

    return {
      'restToday': restSec,
      'inter': interMap,
      'streak': streak,
      'points': points,
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final m = snap.data ?? const {};
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _streakCard((m['streak'] as int?) ?? 0, (m['points'] as int?) ?? 0),
            const SizedBox(height: 12),
            _restCard((m['restToday'] as int?) ?? 0),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('近 7 天打断分布', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _pieChart((m['inter'] as Map<String, int>?) ?? const {}),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _streakCard(int streak, int points) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.local_fire_department_outlined),
        title: Text('连续达成：$streak 天'),
        subtitle: Text('总积分：$points'),
      ),
    );
  }

  Widget _restCard(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final txt = '${h.toString().padLeft(2, '0')}小时${m.toString().padLeft(2, '0')}分钟';
    return Card(
      child: ListTile(
        leading: const Icon(Icons.free_breakfast),
        title: const Text('今日休息时长'),
        subtitle: Text(txt),
      ),
    );
  }

  Widget _pieChart(Map<String, int> inter) {
    if (inter.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('暂无打断数据')),
      );
    }
    final total = inter.values.fold<int>(0, (a, b) => a + b);
    final entries = inter.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1.6,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 36,
              sections: [
                for (final e in entries)
                  PieChartSectionData(
                    value: e.value.toDouble(),
                    title: '${((e.value * 100) / total).round()}%',
                    radius: 60,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...entries.map((e) {
          final pct = ((e.value * 100) / total).round();
          return ListTile(
            dense: true,
            visualDensity: const VisualDensity(vertical: -3),
            leading: const Icon(Icons.label_outline),
            title: Text(e.key),
            trailing: Text('${e.value} · ${pct}%'),
          );
        }),
      ],
    );
  }
}
