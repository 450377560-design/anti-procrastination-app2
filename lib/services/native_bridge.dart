import 'dart:async';
import 'package:flutter/services.dart';

class NativeBridge {
  static const MethodChannel _ch = MethodChannel('focus_bridge');

  static Future<bool> requestNotificationPermission() async {
    final ok = await _ch.invokeMethod('requestNotificationPermission');
    return ok == true;
  }

  static Future<bool> startFocus({required int minutes, required bool lock}) async {
    final ok = await _ch.invokeMethod('startFocus', {'minutes': minutes, 'lock': lock});
    return ok == true;
  }

  static Future<bool> stopFocus() async {
    final ok = await _ch.invokeMethod('stopFocus');
    return ok == true;
  }

  static Future<bool> plannerEnable(int hour, int minute) async {
    final ok = await _ch.invokeMethod('plannerEnable', {'hour': hour, 'minute': minute});
    return ok == true;
  }

  static Future<bool> plannerDisable() async {
    final ok = await _ch.invokeMethod('plannerDisable');
    return ok == true;
  }

  // -------- 原生 → Flutter 回调 --------
  static final _onInterruption = StreamController<void>.broadcast();
  static Stream<void> get onInterruption => _onInterruption.stream;

  static final _onTick = StreamController<int>.broadcast();
  static Stream<int> get onTick => _onTick.stream;

  static final _onFinish = StreamController<void>.broadcast();
  static Stream<void> get onFinish => _onFinish.stream;

  static final _onStop = StreamController<void>.broadcast();
  static Stream<void> get onStop => _onStop.stream;

  static void initCallbacks() {
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onInterruption':
          _onInterruption.add(null);
          break;
        case 'onTick':
          final remaining = (call.arguments as Map?)?['remaining'] as int? ?? 0;
          _onTick.add(remaining);
          break;
        case 'onFinish':
          _onFinish.add(null);
          break;
        case 'onStop':
          _onStop.add(null);
          break;
      }
    });
  }
}
