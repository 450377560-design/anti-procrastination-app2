class EquivalentUnit {
  final String name;      // 名称，如：番茄、短文、跑步
  final String emoji;     // 小图标
  final int minutes;      // 1个单位对应的分钟数

  const EquivalentUnit({
    required this.name,
    required this.emoji,
    required this.minutes,
  });

  factory EquivalentUnit.fromJson(Map<String, dynamic> j) => EquivalentUnit(
        name: j['name'] as String? ?? '',
        emoji: j['emoji'] as String? ?? '',
        minutes: (j['minutes'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() =>
      {'name': name, 'emoji': emoji, 'minutes': minutes};
}

/// 默认等价清单 —— 纯常量，不做任何异步，安全
const List<EquivalentUnit> kDefaultEquivalentUnits = [
  EquivalentUnit(emoji: '🗓️', name: '有效工作日', minutes: 480), // 8h
  EquivalentUnit(emoji: '📅', name: '工作周', minutes: 2400),   // 5×8h
  EquivalentUnit(emoji: '🎯', name: '深度工作块', minutes: 90),
  EquivalentUnit(emoji: '📚', name: '课时(参考)', minutes: 45),
  EquivalentUnit(emoji: '🎓', name: '学分(参考)', minutes: 720), // 16×45min
  EquivalentUnit(emoji: '🧱', name: '里程碑块', minutes: 120),
];
