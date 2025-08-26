import 'dart:math';
import 'package:flutter/material.dart';

Color colorFromString(String s) {
  var h = 0;
  for (final r in s.runes) h = (h * 31 + r) & 0x7fffffff;
  final hue = (h % 360).toDouble();
  final sat = 0.55 + (h % 15) / 100;   // 0.55–0.69
  final light = 0.50 + (h % 8) / 100;  // 0.50–0.57
  return HSLColor.fromAHSL(1, hue, min(sat, .75), min(light, .62)).toColor();
}
