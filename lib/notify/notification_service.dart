import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_native_timezone/flutter_native_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/task.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _inited = false;

  static Future<void> init() async {
    if (_inited) return;
    // 时区
    tz.initializeTimeZones();
    try {
      final name = await FlutterNativeTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    }

    // 初始化
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: androidInit));

    // Android 13+ 通知权限
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _inited = true;
  }

  static const _channelId = 'task_remind';
  static const _channelName = '任务提醒';
  static const _channelDesc = '到达任务开始时间的提醒';

  static NotificationDetails _details() {
    const android = AndroidNotificationDetails(
      _channelId, _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    return const NotificationDetails(android: android);
  }

  /// 为带有 [date] + [startTime] 的任务安排一次性提醒
  static Future<void> scheduleTaskReminder(Task t) async {
    if (!_inited) await init();
    if (t.id == null || t.date.isEmpty || t.startTime == null || t.done) return;

    final parts = t.startTime!.split(':');
    if (parts.length < 2) return;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;

    final d = DateTime.tryParse(t.date);
    if (d == null) return;
    final fire = DateTime(d.year, d.month, d.day, h, m);
    if (fire.isBefore(DateTime.now())) return;

    final when = tz.TZDateTime.from(fire, tz.local);
    await _plugin.zonedSchedule(
      t.id!, // 用任务 id 作为通知 id，便于取消
      '开始做：${t.title}',
      t.endTime == null ? '现在是你计划的开始时间' : '计划时段：${t.startTime}–${t.endTime}',
      when,
      _details(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'task:${t.id}',
    );
    if (kDebugMode) {
      // ignore: avoid_print
      print('Scheduled #${t.id} at $when');
    }
  }

  static Future<void> cancelTaskReminder(int id) async {
    if (!_inited) await init();
    await _plugin.cancel(id);
  }
}
