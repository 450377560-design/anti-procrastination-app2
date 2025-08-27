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
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final now = DateTime.now();

    // 近7天专注分钟
    final startWeek = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    final startMs = startWeek.millisecondsSinceEpoch;
    final endMs = DateTime(now.year, now.month, now.day + 1).millisecondsSinceEpoch;
    final sessions = await FocusDao.loadSessionsBetween(startMs, endMs);

    final byDay = <String, int>{};
    for (int i = 0; i < 7; i++) {
      final d = startWeek.add(Duration(days: i));
      byDay[DateFormat('MM-dd').format(d)] = 0;
    }
    for (final s in sessions) {
      final start = DateTime.fromMillisecondsSinceEpoch(s['start_ts'] as int);
      final end = DateTime.fromMillisecondsSinceEpoch((s['end_ts'] as int?) ?? s['start_ts'] as int);
      final key = DateFormat('MM-dd').format(DateTime(start.year, start.month, start.day));
      final minutes = ((end.millisecondsSinceEpoch - start.millisecondsSinceEpoch) / 60000).round();
      if (byDay.containsKey(key)) byDay[key] = (byDay[key] ?? 0) + minutes;
    }

    // 打断原因
    final inter = await FocusDao.loadInterruptionsBetween(startMs, endMs);
    final interMap = {for (final r in inter) r['reason'] as String: (r['cnt'] as int)};

    
    // 今日任务完成率
    final today = DateFormat('yyyy-MM-dd').format(now);
    final tasksToday = await TaskDao.listByDate(today);
    final doneToday = tasksToday.where((t) => t.done).length;
    final rateToday = tasksToday.isEmpty ? 0 : ((doneToday * 100) / tasksToday.length).round();

    // 今日休息时长
    final startOfToday = DateTime(now.year, now.month, now.day);
    final restSec = await FocusDao.restSecondsBetween(
      startOfToday.millisecondsSinceEpoch,
      DateTime(now.year, now.month, now.day + 1).millisecondsSinceEpoch,
    );

    return {
      'byDay': byDay,
      'inter': interMap,
      'rateToday': rateToday,
      'rateSeries': rateSeries,
      'calendar': calendar,
      'streak': streak,
      'points': points,
      'restToday': restSec, // ← 新增
    };

    // 近7天任务完成率
    final rate7 = await TaskDao.completionByDay(7);
    final rateSeries = <String, int>{};
    for (int i = 0; i < 7; i++) {
      final d = startWeek.add(Duration(days: i));
      final keyFull = DateFormat('yyyy-MM-dd').format(d);
      final label = DateFormat('MM-dd').format(d);
      rateSeries[label] = rate7[keyFull] ?? 0;
    }

    // 任务日历（当月）
    final first = _month;
    final last = DateTime(_month.year, _month.month + 1, 0);
    final startDate = DateFormat('yyyy-MM-dd').format(first);
    final endDate = DateFormat('yyyy-MM-dd').format(last);
    final calendar = await TaskDao.countsByDateRange(startDate, endDate);

    // 连续专注天数 + 积分
    final streak = await FocusDao.streakDays();
    final points = await FocusDao.pointsTotal();

    return {
      'byDay': byDay,
      'inter': interMap,
      'rateToday': rateToday,
      'rateSeries': rateSeries,
      'calendar': calendar,
      'streak': streak,
      'points': points,
    };
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
      _future = _load();
    });
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
                    _streakCard(m!['streak'] as int, m['points'] as int),
                    const SizedBox(height: 12),
                    _restCard(m['restToday'] as int),            // ← 新增
                    const SizedBox(height: 12),
                    _sectionTitle('近 7 天专注时长（分钟）'),
                    _barChart(m['byDay'] as Map<String, int>),
                    const SizedBox(height: 16),
                    _sectionTitle('打断原因（最近 7 天）'),
                    _pieChart(m['inter'] as Map<String, int>),
                    const SizedBox(height: 16),
                    _sectionTitle('今日任务完成率'),
                    _donut(m['rateToday'] as int),
                    const SizedBox(height: 16),
                    _calendarHeader(),
                    _taskCalendar(m['calendar'] as Map<String, Map<String, int>>),
                    const SizedBox(height: 16),
                    _sectionTitle('近 7 天任务完成率'),
                    _lineBars(m['rateSeries'] as Map<String, int>),
                  ],
                ),
        );
      },
    );
  }

  Widget _streakCard(int streak, int points) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.local_fire_department),
        title: Text('连续专注天数：$streak 天'),
        subtitle: Text('已获积分：$points（完成一次 +10）'),
      ),
    );
  }

  Widget _calendarHeader() {
    final label = DateFormat('yyyy年MM月').format(_month);
    return Row(
      children: [
        Text('任务日历 · $label', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const Spacer(),
        IconButton(onPressed: () => _shiftMonth(-1), icon: const Icon(Icons.chevron_left)),
        IconButton(onPressed: () => _shiftMonth(1), icon: const Icon(Icons.chevron_right)),
      ],
    );
  }

  // 简易日历网格：一~日 7 列，每天显示 done/total，避免溢出
  Widget _taskCalendar(Map<String, Map<String, int>> map) {
    final first = _month;
    final lastDay = DateTime(_month.year, _month.month + 1, 0).day;
    final firstWeekday = (first.weekday + 6) % 7; // 0=周一…6=周日

    final cells = <Widget>[];
    const wds = ['一', '二', '三', '四', '五', '六', '日'];
    cells.addAll(wds.map((w) => Center(child: Text(w, style: const TextStyle(fontWeight: FontWeight.bold)))));

    for (int i = 0; i < firstWeekday; i++) {
      cells.add(const SizedBox.shrink());
    }

    for (int d = 1; d <= lastDay; d++) {
      final date = DateTime(_month.year, _month.month, d);
      final key = DateFormat('yyyy-MM-dd').format(date);
      final info = map[key] ?? {'total': 0, 'done': 0};
      final total = info['total']!;
      final done = info['done']!;
      final allDone = total > 0 && done == total;
      final hasAny = total > 0;

      final bg = allDone
          ? Colors.green.withValues(alpha: .12)
          : hasAny
              ? Colors.orange.withValues(alpha: .12)
              : null;
      final border = allDone
          ? Border.all(color: Colors.green)
          : hasAny
              ? Border.all(color: Colors.orange)
              : Border.all(color: Colors.grey.shade300);

      cells.add(Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8), border: border),
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$d', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 2),
            Text('$done/$total', style: TextStyle(fontSize: 10, color: hasAny ? null : Colors.grey)),
          ],
        ),
      ));
    }

    while (cells.length < 49) cells.add(const SizedBox.shrink());

    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        childAspectRatio: 0.75, // 每格更高，避免文字溢出
      ),
      children: cells,
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
              return Padding(padding: const EdgeInsets.only(top: 4), child: Text(keys[i], style: const TextStyle(fontSize: 10)));
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
                  )
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 图例列表：名称 + 次数 + 百分比
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
 
  
  // 折线图：近 7 天任务完成率（稀疏显示 0/3/6 三个刻度）
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
              if (i < 0 || i >= keys.length || !(i == 0 || i == 3 || i == 6)) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(keys[i], style: const TextStyle(fontSize: 10)),
              );
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
