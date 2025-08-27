// lib/pages/stats_page.dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../db/dao_focus.dart';
import '../db/dao_task.dart';
import '../widgets/equivalents_card.dart';

/// 临时总开关：等价卡片（若要排查卡首屏，把它设为 false）
const bool kEquivalentsEnabled = true;

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});
  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  /// 注意：改成可空，首帧先不触发异步，避免阻塞第一帧
  Future<Map<String, dynamic>>? _future;

  @override
  void initState() {
    super.initState();
    // 关键：把数据加载延后到“首帧之后”，先让第一帧渲染出来
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _future = _load();
      });
    });
  }

  Future<Map<String, dynamic>> _load() async {
    try {
      // 今日、本周时间范围
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1)).subtract(const Duration(seconds: 1));
      final weekStart = todayStart.subtract(Duration(days: todayStart.weekday - 1));
      final weekEnd = weekStart.add(const Duration(days: 7)).subtract(const Duration(seconds: 1));

      // 今日/本周 专注分钟 & 会话
      int _sumMinutes(List<Map<String, Object?>> rows) {
        int total = 0;
        for (final r in rows) {
          final m = (r['minutes'] as int?) ?? 0;
          total += m;
        }
        return total;
      }

      final todaySessions = await FocusDao.loadSessionsBetween(todayStart, todayEnd);
      final weekSessions = await FocusDao.loadSessionsBetween(weekStart, weekEnd);
      final focusTodayMin = _sumMinutes(todaySessions);
      final focusWeekMin = _sumMinutes(weekSessions);

      // 今日中断次数
      final todayInter = await FocusDao.loadInterruptionsBetween(todayStart, todayEnd);
      final interruptToday = todayInter.length;

      // 今日休息时长（秒）
      final restSecToday = await FocusDao.restSecondsBetween(todayStart, todayEnd);

      // 近 7 天打断分布
      final interAll = await FocusDao.loadInterruptionsBetween(
        todayStart.subtract(const Duration(days: 6)),
        todayEnd,
      );
      final interMap7 = <String, int>{};
      for (final it in interAll) {
        final reason = (it['reason'] as String?)?.trim();
        final key = (reason == null || reason.isEmpty) ? '未填写原因' : reason;
        interMap7[key] = (interMap7[key] ?? 0) + 1;
      }

      // 近 7 天专注分钟（柱状）
      final last7 = <int>[];
      for (int i = 6; i >= 0; i--) {
        final d0 = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
        final d1 = d0.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
        final rows = await FocusDao.loadSessionsBetween(d0, d1);
        last7.add(_sumMinutes(rows));
      }

      // 连续达成 & 积分
      final streak = await FocusDao.streakDays();
      final points = await FocusDao.pointsTotal();

      // 本月任务日历 + 完成率
      String fmt(DateTime x) =>
          '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
      final monthStart = DateTime(now.year, now.month, 1);
      final monthEnd = DateTime(now.year, now.month + 1, 0);
      final calendar = await TaskDao.countsByDateRange(fmt(monthStart), fmt(monthEnd));

      // 今日/近 7 日完成率
      final todayCounts = await TaskDao.countsByDateRange(fmt(todayStart), fmt(todayStart));
      final todayKey = fmt(todayStart);
      final todayTotal = (todayCounts[todayKey]?['total'] as int?) ?? 0;
      final todayDone = (todayCounts[todayKey]?['done'] as int?) ?? 0;

      final sevenStart = todayStart.subtract(const Duration(days: 6));
      final sevenCounts = await TaskDao.countsByDateRange(fmt(sevenStart), fmt(todayStart));
      int total7 = 0, done7 = 0;
      for (final v in sevenCounts.values) {
        total7 += (v['total'] as int?) ?? 0;
        done7 += (v['done'] as int?) ?? 0;
      }

      final monthMin = await FocusDao.minutesThisMonth();
      final allMin = await FocusDao.minutesAll();

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

        'focusMonthMin': monthMin,
        'focusAllMin': allMin,
      };
    } catch (e) {
      // 任何异常都不要阻塞页面，回退安全默认
      return {
        'focusTodayMin': 0,
        'focusWeekMin': 0,
        'sessionsToday': 0,
        'sessionsWeek': 0,
        'interruptToday': 0,
        'restToday': 0,
        'inter': <String, int>{},
        'last7': List<int>.filled(7, 0),
        'streak': 0,
        'points': 0,
        'monthStart': DateTime.now(),
        'calendar': <String, Map<String, int>>{},
        'todayTotal': 0,
        'todayDone': 0,
        'total7': 0,
        'done7': 0,
        'focusMonthMin': 0,
        'focusAllMin': 0,
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    // 关键：首帧先画“骨架”，即使 Future 还没开始也能交第一帧
    if (_future == null) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: const [
          SizedBox(height: 16),
          LinearProgressIndicator(),
          SizedBox(height: 12),
          Card(child: ListTile(title: Text('统计加载中…'))),
        ],
      );
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          // 同样返回“骨架”，保持首帧可渲染
          return ListView(
            padding: const EdgeInsets.all(12),
            children: const [
              SizedBox(height: 16),
              LinearProgressIndicator(),
              SizedBox(height: 12),
              Card(child: ListTile(title: Text('统计加载中…'))),
            ],
          );
        }
        final m = snap.data ?? const {};

        return SafeArea(
          child: RefreshIndicator(
            onRefresh: () async => setState(() => _future = _load()),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // 顶部两张卡
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

                // 等价卡片（可一键熔断）
                if (kEquivalentsEnabled)
                  EquivalentsCard(
                    todayMinutes: (m['focusTodayMin'] as int?) ?? 0,
                    weekMinutes:  (m['focusWeekMin']  as int?) ?? 0,
                    monthMinutes: (m['focusMonthMin'] as int?) ?? 0,
                    allMinutes:   (m['focusAllMin']   as int?) ?? 0,
                    title: '把专注时间换算成…',
                  ),
                if (kEquivalentsEnabled) const SizedBox(height: 12),

                // 近 7 天专注分钟
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('近 7 天专注时长（分钟）', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        _bar7Days((m['last7'] as List<int>?) ?? const []),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 近 7 天打断分布（多色 + 图例）
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

                // 本月任务日历（避免溢出）
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('本月任务完成日历', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      _calendarMonth(
                        (m['monthStart'] as DateTime?) ?? DateTime.now(),
                        (m['calendar'] as Map<String, Map<String, int>>?) ?? const {},
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _focusCard(String title, int minutes, int sessions, int? interrupt) {
    String mm(int x) => '${(x ~/ 60).toString().padLeft(2, '0')}小时${(x % 60).toString().padLeft(2, '0')}分钟';
    return Card(
      child: ListTile(
        leading: const Icon(Icons.timer_outlined),
        title: Text(title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('专注：${mm(minutes)}'),
            Text('完成次数：$sessions'),
            if (interrupt != null) Text('今日打断：$interrupt 次'),
          ],
        ),
      ),
    );
  }

  Widget _rateCard(String title, int done, int total) {
    final pct = total == 0 ? 0.0 : (done / total);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: pct),
          const SizedBox(height: 6),
          Text('$done / $total（${(pct * 100).toStringAsFixed(0)}%）'),
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
        leading: const Icon(Icons.self_improvement_outlined),
        title: const Text('今日休息时长'),
        subtitle: Text(txt),
      ),
    );
  }

  Widget _bar7Days(List<int> mins) {
    final data = mins.length == 7 ? mins : List<int>.filled(7, 0);
    final maxV = (data.isEmpty ? 0 : data.reduce((a, b) => a > b ? a : b)).clamp(0, 120);
    return AspectRatio(
      aspectRatio: 1.6,
      child: BarChart(
        BarChartData(
          gridData: FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (value, meta) {
                  final labels = ['-6', '-5', '-4', '-3', '-2', '-1', '今天'];
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(labels[value.toInt().clamp(0, 6)]),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (int i = 0; i < 7; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: data[i].toDouble(),
                    width: 16,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              )
          ],
          maxY: (maxV == 0 ? 60 : (maxV * 1.2)).toDouble(),
        ),
      ),
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
                    color: _palette[i % _palette.length],
                    title: '${((entries[i].value * 100) / total).round()}%',
                    radius: 60,
                    titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // 图例
        ...entries.asMap().entries.map((e) {
          final idx = e.key;
          final item = e.value;
          final pct = ((item.value * 100) / total).toStringAsFixed(0);
          return ListTile(
            dense: true,
            leading: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: _palette[idx % _palette.length],
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            title: Text(item.key),
            trailing: Text('${item.value} · $pct%'),
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
    final wlabels = ['一', '二', '三', '四', '五', '六', '日'];
    final header = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: wlabels
          .map((e) => Expanded(
                child: Center(child: Text(e, style: const TextStyle(fontWeight: FontWeight.bold))),
              ))
          .toList(),
    );

    // 单元格们
    List<Widget> cells = [];
    // 补足月初前的空白
    for (int i = 1; i < firstWeekday; i++) {
      cells.add(Container());
    }

    String keyOf(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    for (int day = 1; day <= daysInMonth; day++) {
      final d = DateTime(monthStart.year, monthStart.month, day);
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
        margin: const EdgeInsets.all(3), // 稍微缩小，给高度留余量
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(day.toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(
              total == 0 ? '-' : '完成 $done/$total',
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ));
    }

    return Column(
      children: [
        header,
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.85, // 增高格子，解决 BOTTOM OVERFLOWED
          children: cells,
        ),
      ],
    );
  }
}
