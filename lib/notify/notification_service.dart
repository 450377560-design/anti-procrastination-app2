import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/task.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _inited = false;

  static Future<void> init() async {
    if (_inited) return;

    // 仅用纯 Dart 时区库，不依赖原生插件，避免 AGP 冲突
    tz.initializeTimeZones();
    try {
      final name = _guessTimeZoneName();
      tz.setLocalLocation(tz.getLocation(name));
      if (kDebugMode) {
        // ignore: avoid_print
        print('TZ local set to $name');
      }
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Etc/UTC'));
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: androidInit));

    // Android 13+ 请求通知权限
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _inited = true;
  }

  // 依据本机 offset 粗略映射到常见时区名（够用且无原生依赖）
  static String _guessTimeZoneName() {
    final offsetMin = DateTime.now().timeZoneOffset.inMinutes; // 例如 +480
    const map = <int, String>{
      480: 'Asia/Shanghai',
      540: 'Asia/Tokyo',
      60:  'Europe/Berlin',
      0:   'Etc/UTC',
      -300: 'America/New_York',
      -360: 'America/Chicago',
      -420: 'America/Denver',
      -480: 'America/Los_Angeles',
    };
    return map[offsetMin] ?? 'Etc/UTC';
  }

  static const _channelId = 'task_remind';
  static const _channelName = '任务提醒';
  static const _channelDesc = '到达任务开始时间的提醒';

  static NotificationDetails _details() {
    const android = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    return const NotificationDetails(android: android);
  }

  /// 根据任务的 [date] + [startTime] 安排一次提醒（本地时区）
  static Future<void> scheduleTaskReminder(Task t) async {
    if (!_inited) await init();
    if (t.id == null || t.date.isEmpty || t.startTime == null || t.done) return;

    final d = DateTime.tryParse(t.date);
    if (d == null) return;

    final parts = t.startTime!.split(':');
    if (parts.length < 2) return;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;

    final when = tz.TZDateTime(tz.local, d.year, d.month, d.day, h, m);
    if (when.isBefore(tz.TZDateTime.from(DateTime.now(), tz.local))) return;

    await _plugin.zonedSchedule(
      t.id!, // 用任务 id 作为通知 id
      '开始做：${t.title}',
      t.endTime == null ? '现在是你计划的开始时间' : '计划时段：${t.startTime}–${t.endTime}',
      when,
      _details(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
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
