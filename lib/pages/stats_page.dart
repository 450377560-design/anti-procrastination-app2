import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db/dao_focus.dart';
import '../db/dao_task.dart';

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
    final startWeek = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6)); // 最近7天
    final startMs = startWeek.millisecondsSinceEpoch;
    final endMs = DateTime(now.year, now.month, now.day + 1).millisecondsSinceEpoch;

    final sessions = await FocusDao.loadSessionsBetween(startMs, endMs);

    // 近7天每天分钟
    final byDay = <String, int>{};
    for (int i = 0; i < 7; i++) {
      final d = startWeek.add(Duration(days: i));
      final key = DateFormat('MM-dd').format(d);
      byDay[key] = 0;
    }
    for (final s in sessions) {
      final start = DateTime.fromMillisecondsSinceEpoch(s['start_ts'] as int);
      final end = DateTime.fromMillisecondsSinceEpoch((s['end_ts'] as int?) ?? s['start_ts'] as int);
      final key = DateFormat('MM-dd').format(DateTime(start.year, start.month, start.day));
      final minutes = ((end.millisecondsSinceEpoch - start.millisecondsSinceEpoch) / 60000).round();
      if (byDay.containsKey(key)) byDay[key] = (byDay[key] ?? 0) + minutes;
    }

    // 打断原因 Top
    final inter = await FocusDao.loadInterruptionsBetween(startMs, endMs);
    final interMap = {for (final r in inter) r['reason'] as String: (r['cnt'] as int)};

    // 今日任务完成率
    final today = DateFormat('yyyy-MM-dd').format(now);
    final tasks = await TaskDao.listByDate(today);
    final done = tasks.where((t) => t.done).length;
    final rate = tasks.isEmpty ? 0 : ((done * 100) / tasks.length).round();

    // 近7天任务完成率（用于折线/柱状，简单展示）
    final rate7 = await TaskDao.completionByDay(7); // yyyy-MM-dd → %
    final rateSeries = <String, int>{};
    for (int i = 0; i < 7; i++) {
      final d = startWeek.add(Duration(days: i));
      final keyFull = DateFormat('yyyy-MM-dd').format(d);
      final label = DateFormat('MM-dd').format(d);
      rateSeries[label] = rate7[keyFull] ?? 0;
    }

    return {
      'byDay': byDay,
      'inter': interMap,
      'rateToday': rate,
      'rateSeries': rateSeries,
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (_, snap) {
        final m = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: const Text('统计'),
            actions: [
              IconButton(onPressed: () => setState(() => _future = _load()), icon: const Icon(Icons.refresh)),
            ],
          ),
          body: snap.connectionState != ConnectionState.done
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _sectionTitle('近 7 天专注时长（分钟）'),
                    _barChart(m!['byDay'] as Map<String, int>),
                    const SizedBox(height: 16),
                    _sectionTitle('打断原因（最近 7 天）'),
                    _pieChart(m['inter'] as Map<String, int>),
                    const SizedBox(height: 16),
                    _sectionTitle('今日任务完成率'),
                    _donut(m['rateToday'] as int),
                    const SizedBox(height: 16),
                    _sectionTitle('近 7 天任务完成率'),
                    _lineBars(m['rateSeries'] as Map<String, int>),
                  ],
                ),
        );
      },
    );
  }

  Widget _sectionTitle(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(s, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      );

  // 柱状图：近7天分钟
  Widget _barChart(Map<String, int> byDay) {
    final keys = byDay.keys.toList();
    final maxv = (byDay.values.isEmpty ? 10 : byDay.values.reduce((a, b) => a > b ? a : b)).toDouble();
    return AspectRatio(
      aspectRatio: 1.8,
      child: BarChart(
        BarChartData(
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, meta) {
              final i = v.toInt();
              if (i < 0 || i >= keys.length) return const SizedBox.shrink();
              return Padding(padding: const EdgeInsets.only(top: 4), child: Text(keys[i], style: const TextStyle(fontSize: 11)));
            })),
          ),
          barGroups: [
            for (var i = 0; i < keys.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(toY: byDay[keys[i]]!.toDouble(), width: 14, borderRadius: BorderRadius.circular(4)),
              ])
          ],
          maxY: (maxv == 0 ? 10 : maxv * 1.2),
        ),
      ),
    );
  }

  // 饼图：打断原因
  Widget _pieChart(Map<String, int> inter) {
    if (inter.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('暂无打断数据')),
      );
    }
    final total = inter.values.fold<int>(0, (a, b) => a + b);
    final entries = inter.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return AspectRatio(
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
              )
          ],
          // Legend 自己画：
          // ignore: invalid_use_of_visible_for_testing_member
        ),
      ),
    );
  }

  // 环形图：今日完成率
  Widget _donut(int rate) {
    return SizedBox(
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(PieChartData(
            centerSpaceRadius: 56,
            sectionsSpace: 2,
            sections: [
              PieChartSectionData(value: rate.toDouble(), radius: 60, title: ''),
              PieChartSectionData(value: (100 - rate).toDouble(), radius: 60, title: ''),
            ],
          )),
          Text('$rate%', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // 折线柱组合（这里用折线）: 近7天任务完成率
  Widget _lineBars(Map<String, int> series) {
    final keys = series.keys.toList();
    final spots = [
      for (var i = 0; i < keys.length; i++) FlSpot(i.toDouble(), series[keys[i]]!.toDouble()),
    ];
    return AspectRatio(
      aspectRatio: 1.8,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 100,
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, meta) {
              final i = v.toInt();
              if (i < 0 || i >= keys.length) return const SizedBox.shrink();
              return Padding(padding: const EdgeInsets.only(top: 4), child: Text(keys[i], style: const TextStyle(fontSize: 11)));
            })),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(spots: spots, isCurved: true, dotData: const FlDotData(show: true), barWidth: 3),
          ],
        ),
      ),
    );
  }
}
