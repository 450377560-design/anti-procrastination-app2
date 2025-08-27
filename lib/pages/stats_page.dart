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

    // 今日、明日、近7天、当月
    final startToday = DateTime(now.year, now.month, now.day);
    final startTomorrow = startToday.add(const Duration(days: 1));
    final start7 = startToday.subtract(const Duration(days: 6)); // 含今天共7天
    final monthStart = DateTime(now.year, now.month, 1);
    final nextMonthStart = DateTime(now.year, now.month + 1, 1);
    final monthEnd = nextMonthStart.subtract(const Duration(days: 1));

    // 1) 今日/本周专注
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

    // 2) 今日休息时长
    final restSecToday = await FocusDao.restSecondsBetween(
      startToday.millisecondsSinceEpoch,
      startTomorrow.millisecondsSinceEpoch,
    );

    // 3) 近7天打断分布（合计为饼图 & 今日打断数）
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

    // 4) 近7天专注分钟（柱状图）
    final last7 = <int>[];
    for (int i = 0; i < 7; i++) {
      final d0 = DateTime(start7.year, start7.month, start7.day + i);
      final d1 = d0.add(const Duration(days: 1));
      final rows = await FocusDao.loadSessionsBetween(d0.millisecondsSinceEpoch, d1.millisecondsSinceEpoch);
      last7.add(_sumMinutes(rows));
    }

    // 5) streak & 积分
    final streak = await FocusDao.streakDays();
    final points = await FocusDao.pointsTotal();

    // 6) 本月任务日历（已完成/总数）
    String fmt(DateTime x) =>
        '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    final calendar = await TaskDao.countsByDateRange(fmt(monthStart), fmt(monthEnd));

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
        return RefreshIndicator(
          onRefresh: () async => setState(() => _future = _load()),
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // 顶部两张卡：今日/本周专注
              Row(
                children: [
                  Expanded(child: _focusCard('今日专注', m['focusTodayMin'] ?? 0, m['sessionsToday'] ?? 0, m['interruptToday'] ?? 0)),
                  const SizedBox(width: 12),
                  Expanded(child: _focusCard('本周专注', m['focusWeekMin'] ?? 0, m['sessionsWeek'] ?? 0, null)),
                ],
              ),
              const SizedBox(height: 12),
              _streakCard((m['streak'] as int?) ?? 0, (m['points'] as int?) ?? 0),
              const SizedBox(height: 12),
              _restCard((m['restToday'] as int?) ?? 0),
              const SizedBox(height: 12),

              // 近7天专注分钟柱状图
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

              // 打断饼图 + 图例
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
          Text('专注：${mm(minutes)}'),
          Text('完成次数：$sessions'),
          if (interrupt != null) Text('今日打断：$interrupt 次'),
        ]),
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
                // 显示近7天的最后1个字母（M/T/W/T/F/S/S）
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

    // 头部：一到日
    final wd = const ['一', '二', '三', '四', '五', '六', '日'];

    // 构建表格单元
    final cells = <Widget>[];
    // 前置空位
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
          ? Colors.grey.withValues(alpha: .15)
          : (rate >= 80
              ? Colors.green.withValues(alpha: .2)
              : (rate >= 50 ? Colors.orange.withValues(alpha: .2) : Colors.red.withValues(alpha: .2)));

      cells.add(Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: color,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$d', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${done}/${total}', style: const TextStyle(fontSize: 11)),
          ],
        ),
      ));
    }

    // 补尾部空位凑整
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox());
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [for (final s in wd) Expanded(child: Center(child: Text(s)))],
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: cells,
        ),
      ],
    );
  }
}
