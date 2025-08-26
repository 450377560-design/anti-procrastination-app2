import 'dart:math';
import 'package:flutter/material.dart';

Color colorFromString(String s) {
  // 简单稳定 hash → HSL → Color（避免过浅）
  var h = 0;
  for (final r in s.runes) h = (h * 31 + r) & 0x7fffffff;
  final hue = (h % 360).toDouble();
  final sat = 0.50 + (h % 20) / 100;   // 0.50–0.69
  final light = 0.45 + (h % 10) / 100; // 0.45–0.54
  return HSLColor.fromAHSL(1, hue, min(sat, .75), min(light, .62)).toColor();
}
