enum TaskStatus { pending, inProgress, completed, expired }

enum TaskType { scheduled, recurring, countdown }

class ScheduledTask {

  const ScheduledTask({
    required this.id,
    required this.title,
    required this.createdAt, this.description = '',
    this.dueDate,
    this.status = TaskStatus.pending,
    this.taskType = TaskType.scheduled,
    this.intervalSeconds = 0,
  });

  factory ScheduledTask.fromJson(Map<String, dynamic> json) => ScheduledTask(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        dueDate: json['dueDate'] != null ? DateTime.tryParse(json['dueDate'] as String) : null,
        status: TaskStatus.values.firstWhere((s) => s.name == json['status'], orElse: () => TaskStatus.pending),
        taskType: TaskType.values.firstWhere((t) => t.name == json['taskType'], orElse: () => TaskType.scheduled),
        intervalSeconds: json['intervalSeconds'] as int? ?? 0,
        createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now() : DateTime.now(),
      );
  final String id;
  final String title;
  final String description;
  final DateTime? dueDate;
  final TaskStatus status;
  final TaskType taskType;
  final int intervalSeconds; // 周期任务：间隔秒数
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'dueDate': dueDate?.toIso8601String(),
        'status': status.name,
        'taskType': taskType.name,
        'intervalSeconds': intervalSeconds,
        'createdAt': createdAt.toIso8601String(),
      };

  ScheduledTask copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? dueDate,
    TaskStatus? status,
    TaskType? taskType,
    int? intervalSeconds,
    DateTime? createdAt,
  }) =>
      ScheduledTask(
        id: id ?? this.id,
        title: title ?? this.title,
        description: description ?? this.description,
        dueDate: dueDate ?? this.dueDate,
        status: status ?? this.status,
        taskType: taskType ?? this.taskType,
        intervalSeconds: intervalSeconds ?? this.intervalSeconds,
        createdAt: createdAt ?? this.createdAt,
      );

  String get statusLabel {
    switch (status) {
      case TaskStatus.pending:
        return '待执行';
      case TaskStatus.inProgress:
        return '进行中';
      case TaskStatus.completed:
        return '已完成';
      case TaskStatus.expired:
        return '已过期';
    }
  }

  String get taskTypeLabel {
    switch (taskType) {
      case TaskType.scheduled:
        return '定时';
      case TaskType.recurring:
        return '周期';
      case TaskType.countdown:
        return '倒计时';
    }
  }

  /// 下次触发时间
  DateTime? get nextFireTime {
    if (status != TaskStatus.pending && status != TaskStatus.inProgress) return null;
    switch (taskType) {
      case TaskType.scheduled:
        return dueDate;
      case TaskType.countdown:
        return dueDate; // dueDate = createdAt + countdown duration
      case TaskType.recurring:
        return dueDate; // dueDate = last fire + interval
    }
  }
}

class UserMemory {

  const UserMemory({
    this.birthday = '',
    this.gender = '',
    this.nativeLanguage = '',
    this.knowledgeBackground = '',
    this.currentIdentity = '',
    this.location = '',
    this.usingLanguage = '',
    this.shortTermGoals = '',
    this.shortTermInterests = '',
    this.behaviorHabits = '',
    this.namePreference = '',
    this.answerStyle = '',
    this.detailLevel = '',
    this.formatPreference = '',
    this.visualPreference = '',
    this.communicationRules = '',
    this.prohibitedItems = '',
    this.otherRequirements = '',
    this.tasks = const [],
  });

  factory UserMemory.fromJson(Map<String, dynamic> json) => UserMemory(
        birthday: json['birthday'] as String? ?? '',
        gender: json['gender'] as String? ?? '',
        nativeLanguage: json['nativeLanguage'] as String? ?? '',
        knowledgeBackground: json['knowledgeBackground'] as String? ?? '',
        currentIdentity: json['currentIdentity'] as String? ?? '',
        location: json['location'] as String? ?? '',
        usingLanguage: json['usingLanguage'] as String? ?? '',
        shortTermGoals: json['shortTermGoals'] as String? ?? '',
        shortTermInterests: json['shortTermInterests'] as String? ?? '',
        behaviorHabits: json['behaviorHabits'] as String? ?? '',
        namePreference: json['namePreference'] as String? ?? '',
        answerStyle: json['answerStyle'] as String? ?? '',
        detailLevel: json['detailLevel'] as String? ?? '',
        formatPreference: json['formatPreference'] as String? ?? '',
        visualPreference: json['visualPreference'] as String? ?? '',
        communicationRules: json['communicationRules'] as String? ?? '',
        prohibitedItems: json['prohibitedItems'] as String? ?? '',
        otherRequirements: json['otherRequirements'] as String? ?? '',
        tasks: (json['tasks'] as List<dynamic>?)
                ?.map((t) => ScheduledTask.fromJson(t as Map<String, dynamic>))
                .toList() ??
            const [],
      );
  final String birthday;
  final String gender;
  final String nativeLanguage;
  final String knowledgeBackground;
  final String currentIdentity;
  final String location;
  final String usingLanguage;
  final String shortTermGoals;
  final String shortTermInterests;
  final String behaviorHabits;
  final String namePreference;
  final String answerStyle;
  final String detailLevel;
  final String formatPreference;
  final String visualPreference;
  final String communicationRules;
  final String prohibitedItems;
  final String otherRequirements;
  final List<ScheduledTask> tasks;

  Map<String, dynamic> toJson() => {
        'birthday': birthday,
        'gender': gender,
        'nativeLanguage': nativeLanguage,
        'knowledgeBackground': knowledgeBackground,
        'currentIdentity': currentIdentity,
        'location': location,
        'usingLanguage': usingLanguage,
        'shortTermGoals': shortTermGoals,
        'shortTermInterests': shortTermInterests,
        'behaviorHabits': behaviorHabits,
        'namePreference': namePreference,
        'answerStyle': answerStyle,
        'detailLevel': detailLevel,
        'formatPreference': formatPreference,
        'visualPreference': visualPreference,
        'communicationRules': communicationRules,
        'prohibitedItems': prohibitedItems,
        'otherRequirements': otherRequirements,
        'tasks': tasks.map((t) => t.toJson()).toList(),
      };

  UserMemory copyWith({
    String? birthday,
    String? gender,
    String? nativeLanguage,
    String? knowledgeBackground,
    String? currentIdentity,
    String? location,
    String? usingLanguage,
    String? shortTermGoals,
    String? shortTermInterests,
    String? behaviorHabits,
    String? namePreference,
    String? answerStyle,
    String? detailLevel,
    String? formatPreference,
    String? visualPreference,
    String? communicationRules,
    String? prohibitedItems,
    String? otherRequirements,
    List<ScheduledTask>? tasks,
  }) =>
      UserMemory(
        birthday: birthday ?? this.birthday,
        gender: gender ?? this.gender,
        nativeLanguage: nativeLanguage ?? this.nativeLanguage,
        knowledgeBackground: knowledgeBackground ?? this.knowledgeBackground,
        currentIdentity: currentIdentity ?? this.currentIdentity,
        location: location ?? this.location,
        usingLanguage: usingLanguage ?? this.usingLanguage,
        shortTermGoals: shortTermGoals ?? this.shortTermGoals,
        shortTermInterests: shortTermInterests ?? this.shortTermInterests,
        behaviorHabits: behaviorHabits ?? this.behaviorHabits,
        namePreference: namePreference ?? this.namePreference,
        answerStyle: answerStyle ?? this.answerStyle,
        detailLevel: detailLevel ?? this.detailLevel,
        formatPreference: formatPreference ?? this.formatPreference,
        visualPreference: visualPreference ?? this.visualPreference,
        communicationRules: communicationRules ?? this.communicationRules,
        prohibitedItems: prohibitedItems ?? this.prohibitedItems,
        otherRequirements: otherRequirements ?? this.otherRequirements,
        tasks: tasks ?? this.tasks,
      );

  bool get isEmpty =>
      birthday.isEmpty &&
      gender.isEmpty &&
      nativeLanguage.isEmpty &&
      knowledgeBackground.isEmpty &&
      currentIdentity.isEmpty &&
      location.isEmpty &&
      usingLanguage.isEmpty &&
      shortTermGoals.isEmpty &&
      shortTermInterests.isEmpty &&
      behaviorHabits.isEmpty &&
      namePreference.isEmpty &&
      answerStyle.isEmpty &&
      detailLevel.isEmpty &&
      formatPreference.isEmpty &&
      visualPreference.isEmpty &&
      communicationRules.isEmpty &&
      prohibitedItems.isEmpty &&
      otherRequirements.isEmpty &&
      tasks.isEmpty;

  String toSystemPrompt() {
    if (isEmpty) return '';

    final buf = StringBuffer();
    buf.writeln('【用户记忆】');

    // 静态画像
    final staticParts = <String>[];
    if (gender.isNotEmpty) staticParts.add('性别: $gender');
    if (birthday.isNotEmpty) staticParts.add('生日: $birthday');
    if (nativeLanguage.isNotEmpty) staticParts.add('母语: $nativeLanguage');
    if (staticParts.isNotEmpty) {
      buf.writeln('📊 静态画像: ${staticParts.join('，')}');
    }

    // 动态画像
    final dynamicParts = <String>[];
    if (knowledgeBackground.isNotEmpty) dynamicParts.add('知识背景: $knowledgeBackground');
    if (currentIdentity.isNotEmpty) dynamicParts.add('当前身份: $currentIdentity');
    if (location.isNotEmpty) dynamicParts.add('所在地区: $location');
    if (usingLanguage.isNotEmpty) dynamicParts.add('使用语言: $usingLanguage');
    if (shortTermGoals.isNotEmpty) dynamicParts.add('短期目标: $shortTermGoals');
    if (shortTermInterests.isNotEmpty) dynamicParts.add('短期兴趣: $shortTermInterests');
    if (behaviorHabits.isNotEmpty) dynamicParts.add('行为习惯: $behaviorHabits');
    if (namePreference.isNotEmpty) dynamicParts.add('称呼: $namePreference');
    if (dynamicParts.isNotEmpty) {
      buf.writeln('🔄 动态画像:');
      for (final p in dynamicParts) {
        buf.writeln('  - $p');
      }
    }

    // 交互偏好
    final prefParts = <String>[];
    if (answerStyle.isNotEmpty) prefParts.add('回答风格: $answerStyle');
    if (detailLevel.isNotEmpty) prefParts.add('详细程度: $detailLevel');
    if (formatPreference.isNotEmpty) prefParts.add('格式偏好: $formatPreference');
    if (visualPreference.isNotEmpty) prefParts.add('视觉偏好: $visualPreference');
    if (prefParts.isNotEmpty) {
      buf.writeln('⚙️ 交互偏好: ${prefParts.join('，')}');
    }

    // 注意事项
    final noteParts = <String>[];
    if (communicationRules.isNotEmpty) noteParts.add('沟通规则: $communicationRules');
    if (prohibitedItems.isNotEmpty) noteParts.add('禁止事项: $prohibitedItems');
    if (otherRequirements.isNotEmpty) noteParts.add('其他要求: $otherRequirements');
    if (noteParts.isNotEmpty) {
      buf.writeln('📝 注意事项:');
      for (final p in noteParts) {
        buf.writeln('  - $p');
      }
    }

    // 定时任务
    final activeTasks = tasks.where((t) => t.status == TaskStatus.pending || t.status == TaskStatus.inProgress).toList();
    if (activeTasks.isNotEmpty) {
      buf.writeln('⏰ 活跃定时任务:');
      for (final t in activeTasks) {
        String dueInfo = '';
        if (t.nextFireTime != null) {
          dueInfo = ' (触发: ${t.nextFireTime!.toString().substring(0, 16)})';
        }
        String typeInfo = '[${t.taskTypeLabel}] ';
        if (t.taskType == TaskType.recurring && t.intervalSeconds > 0) {
          typeInfo += '每${_formatInterval(t.intervalSeconds)} ';
        }
        buf.writeln('  - $typeInfo${t.title}$dueInfo');
        if (t.description.isNotEmpty) buf.writeln('    详情: ${t.description}');
      }
    }

    return buf.toString();
  }

  static String _formatInterval(int seconds) {
    if (seconds < 60) return '$seconds秒';
    if (seconds < 3600) return '${seconds ~/ 60}分钟';
    if (seconds < 86400) return '${seconds ~/ 3600}小时';
    return '${seconds ~/ 86400}天';
  }
}
