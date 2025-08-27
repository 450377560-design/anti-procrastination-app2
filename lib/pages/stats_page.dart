import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
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

    // 常用时间点
    final startToday = DateTime(now.year, now.month, now.day);
    final startTomorrow = startToday.add(const Duration(days: 1));
    final start7 = startToday.subtract(const Duration(days: 6));
    final monthStart = DateTime(now.year, now.month, 1);
    final nextMonthStart = DateTime(now.year, now.month + 1, 1);
    final monthEnd = nextMonthStart.subtract(const Duration(days: 1));

    // 近 7 天/今日的会话
    final todaySessions = await FocusDao.loadSessionsBetween(
      startToday.millisecondsSinceEpoch,
      startTomorrow.millisecondsSinceEpoch,
    );
    final weekSessions = await FocusDao.loadSessionsBetween(
      start7.millisecondsSinceEpoch,
      startTomorrow.millisecondsSinceEpoch,
    );

    int _sumMinutes(List<Map<String, dynamic>> rows) {
      int sum = 0;
      for (final r in rows) {
        final st = r['start_ts'] as int?;
        final et = r['end_ts'] as int?;
        if (st != null && et != null && et > st) {
          sum += ((et - st) ~/ 60000);
        }
      }
      return sum;
    }

    final focusTodayMin = _sumMinutes(todaySessions);
    final focusWeekMin = _sumMinutes(weekSessions);

    // 今日休息
    final restSecToday = await FocusDao.restSecondsBetween(
      startToday.millisecondsSinceEpoch,
      startTomorrow.millisecondsSinceEpoch,
    );

    // 近 7 天打断分布 + 今日打断次数
    final interRows7 = await FocusDao.loadInterruptionsBetween(
      start7.millisecondsSinceEpoch,
      startTomorrow.millisecondsSinceEpoch,
    );
    final interMap7 = <String, int>{};
    for (final r in interRows7) {
      interMap7[r['reason'] as String] = (r['cnt'] as int?) ?? 0;
    }
    int interruptToday = 0;
    final interRowsToday = await FocusDao.loadInterruptionsBetween(
      startToday.millisecondsSinceEpoch,
      startTomorrow.millisecondsSinceEpoch,
    );
    for (final r in interRowsToday) {
      interruptToday += (r['cnt'] as int?) ?? 0;
    }

    // 近 7 天专注分钟（柱状图）
    final last7 = <int>[];
    for (int i = 0; i < 7; i++) {
      final d0 = DateTime(start7.year, start7.month, start7.day + i);
      final d1 = d0.add(const Duration(days: 1));
      final rows = await FocusDao.loadSessionsBetween(d0.millisecondsSinceEpoch, d1.millisecondsSinceEpoch);
      last7.add(_sumMinutes(rows));
    }

    // 连续达成 & 积分
    final streak = await FocusDao.streakDays();
    final points = await FocusDao.pointsTotal();

    // 本月任务日历 + 完成率
    String fmt(DateTime x) =>
        '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    final calendar = await TaskDao.countsByDateRange(fmt(monthStart), fmt(monthEnd));

    // 今日 & 近 7 日完成率
    final todayKey = fmt(startToday);
    final todayTotal = calendar[todayKey]?['total'] ?? 0;
    final todayDone = calendar[todayKey]?['done'] ?? 0;

    int total7 = 0, done7 = 0;
    for (int i = 0; i < 7; i++) {
      final key = fmt(DateTime(start7.year, start7.month, start7.day + i));
      total7 += calendar[key]?['total'] ?? 0;
      done7 += calendar[key]?['done'] ?? 0;
    }

    return {
      'focusTodayMin': focusTodayMin,
      'focusWeekMin': focusWeekMin,
      'sessionsToday': todaySessions.length,
      'sessionsWeek': weekSessions.length,
      'interruptToday': interruptToday,

      'restToday': restSecToday,
      'inter': interMap7,
      'last7': last7,

      'streak': streak,
      'points': points,

      'monthStart': monthStart,
      'calendar': calendar,

      'todayTotal': todayTotal,
      'todayDone': todayDone,
      'total7': total7,
      'done7': done7,
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
        return SafeArea( // ← 避免被 AppBar/刘海遮住
          child: RefreshIndicator(
            onRefresh: () async => setState(() => _future = _load()),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // 顶部专注两张卡
                Row(
                  children: [
                    Expanded(child: _focusCard('今日专注', m['focusTodayMin'] ?? 0, m['sessionsToday'] ?? 0, m['interruptToday'] ?? 0)),
                    const SizedBox(width: 12),
                    Expanded(child: _focusCard('本周专注', m['focusWeekMin'] ?? 0, m['sessionsWeek'] ?? 0, null)),
                  ],
                ),
                const SizedBox(height: 12),

                // 今日/近7日完成率
                Row(
                  children: [
                    Expanded(child: _rateCard('今日任务完成率', m['todayDone'] ?? 0, m['todayTotal'] ?? 0)),
                    const SizedBox(width: 12),
                    Expanded(child: _rateCard('近 7 日完成率', m['done7'] ?? 0, m['total7'] ?? 0)),
                  ],
                ),
                const SizedBox(height: 12),

                _streakCard((m['streak'] as int?) ?? 0, (m['points'] as int?) ?? 0),
                const SizedBox(height: 12),
                _restCard((m['restToday'] as int?) ?? 0),
                const SizedBox(height: 12),

                // 近 7 天专注分钟柱状图
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('近 7 天专注分钟', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      _bar7((m['last7'] as List<int>? ?? List.filled(7, 0))),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),

                // 打断饼图（彩色）
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('近 7 天打断分布', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      _pieChart((m['inter'] as Map<String, int>?) ?? const {}),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),

                // 本月任务日历
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        '本月任务日历（已完成/总数）  ${DateFormat('yyyy年MM月').format(m['monthStart'] as DateTime)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      _calendarMonth(m['monthStart'] as DateTime, (m['calendar'] as Map<String, Map<String, int>>?) ?? const {}),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ======= 小部件们 =======

  Widget _focusCard(String title, int minutes, int sessions, int? interrupt) {
    String mm(int x) => '${(x ~/ 60).toString().padLeft(2, '0')}小时${(x % 60).toString().padLeft(2, '0')}分钟';
    return Card(
      child: ListTile(
        leading: const Icon(Icons.timer_outlined),
        title: Text(title),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('专注：$mm(minutes)'),
          Text('完成次数：$sessions'),
          if (interrupt != null) Text('今日打断：$interrupt 次'),
        ]),
      ),
    );
  }

  Widget _rateCard(String title, int done, int total) {
    final pct = total == 0 ? 0 : ((done * 100.0) / total).round();
    return Card(
      child: ListTile(
        leading: const Icon(Icons.task_alt_outlined),
        title: Text(title),
        subtitle: Text('$done / $total  ·  $pct%'),
      ),
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

  Widget _bar7(List<int> mins) {
    final groups = <BarChartGroupData>[];
    for (int i = 0; i < 7; i++) {
      groups.add(BarChartGroupData(
        x: i,
        barRods: [BarChartRodData(toY: mins[i].toDouble())],
      ));
    }
    return SizedBox(
      height: 180,
      child: BarChart(BarChartData(
        barGroups: groups,
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                const labels = ['一', '二', '三', '四', '五', '六', '日'];
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(labels[value.toInt().clamp(0, 6)]),
                );
              },
            ),
          ),
        ),
      )),
    );
  }

  // 颜色盘（用于饼图和图例）
  static const _palette = <Color>[
    Color(0xFF26C6DA), // 青
    Color(0xFF66BB6A), // 绿
    Color(0xFFFFCA28), // 黄
    Color(0xFFEF5350), // 红
    Color(0xFFAB47BC), // 紫
    Color(0xFF8D6E63), // 褐
    Color(0xFF42A5F5), // 蓝
    Color(0xFFFFA726), // 橙
  ];

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
                for (int i = 0; i < entries.length; i++)
                  PieChartSectionData(
                    value: entries[i].value.toDouble(),
                    color: _palette[i % _palette.length], // ← 不同颜色
                    title: '${((entries[i].value * 100) / total).round()}%',
                    radius: 60,
                    titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...List.generate(entries.length, (i) {
          final e = entries[i];
          final pct = ((e.value * 100) / total).round();
          return ListTile(
            dense: true,
            visualDensity: const VisualDensity(vertical: -3),
            leading: Container(width: 12, height: 12, decoration: BoxDecoration(color: _palette[i % _palette.length], shape: BoxShape.circle)),
            title: Text(e.key),
            trailing: Text('${e.value} · $pct%'),
          );
        }),
      ],
    );
  }

  Widget _calendarMonth(DateTime monthStart, Map<String, Map<String, int>> counts) {
    final firstWeekday = DateTime(monthStart.year, monthStart.month, 1).weekday; // 1=Mon..7=Sun
    final nextMonthStart = DateTime(monthStart.year, monthStart.month + 1, 1);
    final daysInMonth = nextMonthStart.subtract(const Duration(days: 1)).day;

    // 顶部：一到日
    const wd = ['一', '二', '三', '四', '五', '六', '日'];

    final cells = <Widget>[];
    for (int i = 1; i < firstWeekday; i++) {
      cells.add(const SizedBox());
    }
    String keyOf(int day) =>
        '${monthStart.year.toString().padLeft(4, '0')}-${monthStart.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

    for (int d = 1; d <= daysInMonth; d++) {
      final key = keyOf(d);
      final info = counts[key];
      final total = info?['total'] ?? 0;
      final done = info?['done'] ?? 0;
      final rate = (total == 0) ? 0 : ((done * 100) ~/ total);

      final color = total == 0
          ? Colors.grey.withValues(alpha: .10)
          : (rate >= 80
              ? Colors.green.withValues(alpha: .18)
              : (rate >= 50 ? Colors.orange.withValues(alpha: .18) : Colors.red.withValues(alpha: .18)));

      cells.add(Container(
        margin: const EdgeInsets.all(3),   // 稍微缩小，给高度留余量
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: color,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$d', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 2),
            Text('$done/$total', style: const TextStyle(fontSize: 10)), // 字号调小，避免溢出
          ],
        ),
      ));
    }
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox());
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [for (final s in wd) Expanded(child: Center(child: Text(s)))],
        ),
        const SizedBox(height: 6),
        // 关键：设置 childAspectRatio < 1，让单元格更高，避免 Column 溢出
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.85, // ← 增高格子，解决 BOTTOM OVERFLOWED
          children: cells,
        ),
      ],
    );
  }
}
