class Task {
  int? id;
  String title;
  String? description;
  int priority; // 1/2/3
  String? startTime; // "09:30"
  String? endTime;   // "10:15"
  int? expectedMinutes;
  String? labels;
  String? project;
  String date; // "YYYY-MM-DD"
  bool done;

  int? estimatePomos;
  int actualPomos;

  String? note; // 新增：笔记

  Task({
    this.id,
    required this.title,
    this.description,
    this.priority = 2,
    this.startTime,
    this.endTime,
    this.expectedMinutes,
    this.labels,
    this.project,
    required this.date,
    this.done = false,
    this.estimatePomos,
    this.actualPomos = 0,
    this.note,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'priority': priority,
        'start_time': startTime,
        'end_time': endTime,
        'expected_minutes': expectedMinutes,
        'labels': labels,
        'project': project,
        'date': date,
        'done': done ? 1 : 0,
        'estimate_pomos': estimatePomos,
        'actual_pomos': actualPomos,
        'note': note,
      }..removeWhere((k, v) => v == null);

  static Task fromMap(Map<String, dynamic> m) => Task(
        id: m['id'] as int?,
        title: m['title'] as String,
        description: m['description'] as String?,
        priority: (m['priority'] as int?) ?? 2,
        startTime: m['start_time'] as String?,
        endTime: m['end_time'] as String?,
        expectedMinutes: m['expected_minutes'] as int?,
        labels: m['labels'] as String?,
        project: m['project'] as String?,
        date: m['date'] as String,
        done: ((m['done'] as int?) ?? 0) == 1,
        estimatePomos: m['estimate_pomos'] as int?,
        actualPomos: (m['actual_pomos'] as int?) ?? 0,
        note: m['note'] as String?,
      );
}
