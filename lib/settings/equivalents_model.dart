class EquivalentUnit {
  String emoji;
  String name;
  int minutes; // 1 个单位对应多少分钟

  EquivalentUnit({required this.emoji, required this.name, required this.minutes});

  factory EquivalentUnit.fromJson(Map<String, dynamic> j) =>
      EquivalentUnit(emoji: j['emoji'] as String, name: j['name'] as String, minutes: j['minutes'] as int);

  Map<String, dynamic> toJson() => {'emoji': emoji, 'name': name, 'minutes': minutes};
}

/// 成就感导向默认映射
final List<EquivalentUnit> kDefaultEquivalentUnits = [
  EquivalentUnit(emoji: '🗓️', name: '有效工作日', minutes: 480), // 8h
  EquivalentUnit(emoji: '📅', name: '工作周', minutes: 2400),   // 5×8h
  EquivalentUnit(emoji: '🎯', name: '深度工作块', minutes: 90),
  EquivalentUnit(emoji: '📚', name: '课时(参考)', minutes: 45),
  EquivalentUnit(emoji: '🎓', name: '学分(参考)', minutes: 720), // 16×45min
  EquivalentUnit(emoji: '🧱', name: '里程碑块', minutes: 120),
];
