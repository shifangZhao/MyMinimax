import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../domain/user_memory.dart';
import '../data/task_scheduler.dart';
import 'memory_page.dart' show memoryRepositoryProvider;

class TaskPanel extends ConsumerStatefulWidget {
  const TaskPanel({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TaskPanel(),
    );
  }

  @override
  ConsumerState<TaskPanel> createState() => _TaskPanelState();
}

class _TaskPanelState extends ConsumerState<TaskPanel> {
  List<ScheduledTask> _tasks = [];
  bool _loading = true;
  bool _manageMode = false;
  bool _showForm = false;
  ScheduledTask? _editingTask;

  // Form controllers — allocated lazily when _showForm becomes true, disposed on hide
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _intervalCtrl = TextEditingController(text: '30');
  final _countdownCtrl = TextEditingController(text: '5');
  late TaskType _taskType;
  late DateTime _scheduledDate;
  late TimeOfDay _scheduledTime;
  late int _intervalValue = 30;
  late String _intervalUnit = 'minutes';
  late int _countdownValue = 5;
  late String _countdownUnit = 'minutes';

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  List<ScheduledTask> get _sortedTasks {
    final sorted = List<ScheduledTask>.from(_tasks);
    sorted.sort((a, b) {
      final typeOrder = {TaskType.recurring: 0, TaskType.scheduled: 1, TaskType.countdown: 2};
      final typeCmp = (typeOrder[a.taskType] ?? 9).compareTo(typeOrder[b.taskType] ?? 9);
      if (typeCmp != 0) return typeCmp;
      if (a.nextFireTime == null && b.nextFireTime == null) return 0;
      if (a.nextFireTime == null) return 1;
      if (b.nextFireTime == null) return -1;
      return a.nextFireTime!.compareTo(b.nextFireTime!);
    });
    return sorted;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(memoryRepositoryProvider);
    await repo.init();
    final memory = await repo.loadMemory();
    if (mounted) {
      setState(() { _tasks = memory.tasks; _loading = false; });
    }
  }

  Color get _bg => _isDark ? PixelTheme.darkSurface : PixelTheme.cardBackground;
  Color get _textPrimary => _isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary;
  Color get _textMuted => _isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted;
  Color get _border => _isDark ? PixelTheme.darkBorderSubtle : PixelTheme.pixelBorder.withValues(alpha: 0.4);
  Color get _dragHandleColor => _isDark ? PixelTheme.darkBorderStrong : Colors.grey.shade400;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _intervalCtrl.dispose();
    _countdownCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(color: _bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(children: [
            const SizedBox(height: 12),
            _buildDragHandle(),
            const SizedBox(height: 8),
            _buildHeader(),
            if (_showForm) ...[
              const SizedBox(height: 8),
              _TaskFormCard(
                existingTask: _editingTask,
                titleCtrl: _titleCtrl,
                descCtrl: _descCtrl,
                intervalCtrl: _intervalCtrl,
                countdownCtrl: _countdownCtrl,
                taskType: _taskType,
                scheduledDate: _scheduledDate,
                scheduledTime: _scheduledTime,
                intervalValue: _intervalValue,
                intervalUnit: _intervalUnit,
                countdownValue: _countdownValue,
                countdownUnit: _countdownUnit,
                onTaskTypeChanged: (t) => setState(() => _taskType = t),
                onScheduledDateChanged: (d) => setState(() => _scheduledDate = d),
                onScheduledTimeChanged: (t) => setState(() => _scheduledTime = t),
                onIntervalChanged: (v, u) => setState(() { _intervalValue = v; _intervalUnit = u; }),
                onCountdownChanged: (v, u) => setState(() { _countdownValue = v; _countdownUnit = u; }),
                onCancel: () => setState(() { _showForm = false; _editingTask = null; }),
                onSubmit: _onFormSubmit,
              ),
            ],
            const Divider(height: 24, indent: 20, endIndent: 20),
            Expanded(child: _buildTaskList(scrollController)),
          ]),
        );
      },
    );
  }

  Widget _buildDragHandle() {
    return Container(
      width: 40, height: 4,
      decoration: BoxDecoration(color: _dragHandleColor, borderRadius: BorderRadius.circular(2)),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: PixelTheme.brandBlue.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.schedule, size: 20, color: PixelTheme.brandBlue),
        ),
        const SizedBox(width: 12),
        Text('任务管理', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _textPrimary)),
        const Spacer(),
        _PillButton(
          icon: _manageMode ? Icons.check : Icons.edit_outlined,
          label: _manageMode ? '完成' : '管理',
          active: _manageMode,
          onTap: () => setState(() => _manageMode = !_manageMode),
        ),
        const SizedBox(width: 8),
        _PillButton(
          icon: _showForm ? Icons.close : Icons.add,
          label: _showForm ? '收起' : '新建',
          onTap: _manageMode ? null : () => setState(() {
            if (_showForm) {
              _showForm = false;
              _editingTask = null;
            } else {
              _showForm = true;
              _editingTask = null;
              _resetForm();
            }
          }),
        ),
      ]),
    );
  }


  Widget _buildTaskList(ScrollController scrollController) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: PixelTheme.brandBlue));
    }
    if (_tasks.isEmpty) {
      return Center(child: Text('暂无任务', style: TextStyle(fontSize: 14, color: _textMuted)));
    }
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _sortedTasks.length,
      itemBuilder: (_, i) => _buildTaskRow(_sortedTasks[i]),
    );
  }

  // ═══════════════════════════════════════════
  // 任务行
  // ═══════════════════════════════════════════

  Widget _buildTaskRow(ScheduledTask task) {
    final typeInfo = _taskTypeInfo(task.taskType);
    final nextFire = task.nextFireTime;
    final timeStr = nextFire != null ? _formatDateTime(nextFire) : '';
    final statusColor = _statusColor(task.status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: null,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border, width: 0.5),
            ),
            child: Row(children: [
              _buildTypeIcon(typeInfo),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(task.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Row(children: [
                    _Badge(label: task.taskTypeLabel, color: typeInfo.color),
                    const SizedBox(width: 6),
                    _Badge(label: task.statusLabel, color: statusColor),
                    if (timeStr.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.schedule, size: 12, color: _textMuted),
                      const SizedBox(width: 3),
                      Flexible(child: Text(timeStr, style: TextStyle(fontSize: 11, color: _textMuted), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
                  ]),
                ]),
              ),
              if (_manageMode) ...[
                _IconBtn(icon: Icons.edit_outlined, color: PixelTheme.brandBlue, onTap: () => _editTask(task)),
                const SizedBox(width: 4),
                _IconBtn(icon: Icons.delete_outline, color: PixelTheme.error, onTap: () => _deleteTask(task))
              ]
              else if (task.taskType == TaskType.recurring && task.intervalSeconds > 0)
                Text('每${_formatInterval(task.intervalSeconds)}', style: TextStyle(fontSize: 11, color: _textMuted)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeIcon(_TypeInfo info) {
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: info.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(info.icon, size: 20, color: info.color),
    );
  }

  _TypeInfo _taskTypeInfo(TaskType t) {
    switch (t) {
      case TaskType.recurring: return _TypeInfo(Icons.repeat, PixelTheme.brandBlue);
      case TaskType.countdown: return _TypeInfo(Icons.timer, PixelTheme.warning);
      case TaskType.scheduled: return _TypeInfo(Icons.calendar_today, PixelTheme.success);
    }
  }

  Color _statusColor(TaskStatus s) {
    switch (s) {
      case TaskStatus.pending: return PixelTheme.warning;
      case TaskStatus.inProgress: return PixelTheme.brandBlue;
      case TaskStatus.completed: return PixelTheme.success;
      case TaskStatus.expired: return _isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted;
    }
  }

  String _formatDateTime(DateTime dt) => '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  String _formatInterval(int seconds) {
    if (seconds < 60) return '$seconds秒';
    if (seconds < 3600) return '${seconds ~/ 60}分钟';
    if (seconds < 86400) return '${seconds ~/ 3600}小时';
    return '${seconds ~/ 86400}天';
  }

  // ═══════════════════════════════════════════
  // 编辑
  // ═══════════════════════════════════════════

  void _editTask(ScheduledTask task) {
    _initFormFromTask(task);
    setState(() { _showForm = true; _editingTask = task; });
  }

  // ═══════════════════════════════════════════
  // 删除
  // ═══════════════════════════════════════════

  Future<void> _deleteTask(ScheduledTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ThemedDialog(
        title: '删除任务',
        content: '确定要删除"${task.title}"吗？',
        confirmLabel: '删除',
        confirmColor: PixelTheme.error,
      ),
    );
    if (confirmed == true) {
      final repo = ref.read(memoryRepositoryProvider);
      await repo.deleteTask(task.id);
      final scheduler = ref.read(taskSchedulerProvider);
      await scheduler?.onTaskDeleted(task.id);
      await _load();
    }
  }


  // ═══════════════════════════════════════════
  // 新建任务对话框
  // ═══════════════════════════════════════════

  void _resetForm() {
    _titleCtrl.clear();
    _descCtrl.clear();
    _taskType = TaskType.scheduled;
    _scheduledDate = DateTime.now().add(const Duration(hours: 1));
    _scheduledTime = const TimeOfDay(hour: 9, minute: 0);
    _intervalValue = 30; _intervalUnit = 'minutes';
    _countdownValue = 5; _countdownUnit = 'minutes';
    _intervalCtrl.text = '30';
    _countdownCtrl.text = '5';
  }

  void _initFormFromTask(ScheduledTask task) {
    _titleCtrl.text = task.title;
    _descCtrl.text = task.description;
    _taskType = task.taskType;
    if (task.dueDate != null) {
      _scheduledDate = task.dueDate!;
      _scheduledTime = TimeOfDay(hour: task.dueDate!.hour, minute: task.dueDate!.minute);
    } else {
      _scheduledDate = DateTime.now().add(const Duration(hours: 1));
      _scheduledTime = const TimeOfDay(hour: 9, minute: 0);
    }
    _intervalValue = _parseIntervalValue(task.intervalSeconds);
    _intervalUnit = _parseIntervalUnit(task.intervalSeconds);
    _countdownValue = task.intervalSeconds > 0 ? task.intervalSeconds ~/ 60 : 5;
    _countdownUnit = 'minutes';
    _intervalCtrl.text = _intervalValue.toString();
    _countdownCtrl.text = _countdownValue.toString();
  }

  int _parseIntervalValue(int seconds) {
    if (seconds >= 86400) return seconds ~/ 86400;
    if (seconds >= 3600) return seconds ~/ 3600;
    if (seconds >= 60) return seconds ~/ 60;
    return seconds > 0 ? seconds : 30;
  }

  String _parseIntervalUnit(int seconds) {
    if (seconds >= 86400) return 'days';
    if (seconds >= 3600) return 'hours';
    if (seconds >= 60) return 'minutes';
    return 'seconds';
  }

  Future<void> _onFormSubmit(_TaskFormData data) async {
    final repo = ref.read(memoryRepositoryProvider);
    final now = DateTime.now();

    DateTime? dueDate;
    switch (data.taskType) {
      case TaskType.scheduled: dueDate = data.scheduledTime;
      case TaskType.countdown: dueDate = now.add(Duration(seconds: data.countdownSeconds));
      case TaskType.recurring: dueDate = now.add(Duration(seconds: data.intervalSeconds));
    }

    if (_editingTask != null) {
      final updated = _editingTask!.copyWith(
        title: data.title, description: data.description,
        dueDate: dueDate, taskType: data.taskType,
        intervalSeconds: data.intervalSeconds,
      );
      await repo.updateTask(updated);
      final scheduler = ref.read(taskSchedulerProvider);
      await scheduler?.onTaskChanged(updated);
    } else {
      final task = ScheduledTask(
        id: 'task_${now.millisecondsSinceEpoch}',
        title: data.title, description: data.description,
        dueDate: dueDate, taskType: data.taskType,
        intervalSeconds: data.intervalSeconds, createdAt: now,
      );
      await repo.addTask(task);
      final scheduler = ref.read(taskSchedulerProvider);
      await scheduler?.onTaskChanged(task);
    }

    setState(() { _showForm = false; _editingTask = null; });
    await _load();
  }
}

// ═══════════════════════════════════════════
// 小部件
// ═══════════════════════════════════════════

class _TypeInfo {
  _TypeInfo(this.icon, this.color);
  final IconData icon;
  final Color color;
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(5)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.color, required this.onTap});
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.icon, required this.label, this.onTap, this.active = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disabled = onTap == null;
    final bgColor = active ? PixelTheme.brandBlue : (isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant);
    final fgColor = disabled ? (isDark ? PixelTheme.darkTextDisabled : PixelTheme.textMuted)
        : active ? Colors.white : (isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? Colors.transparent : (isDark ? PixelTheme.darkBorderSubtle : PixelTheme.pixelBorder.withValues(alpha: 0.3))),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: fgColor),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fgColor)),
        ]),
      ),
    );
  }
}

class _ThemedDialog extends StatelessWidget {
  const _ThemedDialog({required this.title, required this.content, this.confirmLabel = '确定', this.confirmColor = PixelTheme.brandBlue});
  final String title;
  final String content;
  final String confirmLabel;
  final Color confirmColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor: isDark ? PixelTheme.darkSurface : PixelTheme.cardBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary)),
      content: Text(content, style: TextStyle(fontSize: 14, color: isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text('取消', style: TextStyle(color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted))),
        TextButton(onPressed: () => Navigator.pop(context, true), child: Text(confirmLabel, style: TextStyle(color: confirmColor, fontWeight: FontWeight.w600))),
      ],
    );
  }
}

// ═══════════════════════════════════════════
// 任务表单数据
// ═══════════════════════════════════════════

class _TaskFormData {
  _TaskFormData({required this.title, required this.taskType, this.description = '', this.scheduledTime, this.intervalSeconds = 0, this.countdownSeconds = 0});
  final String title;
  final String description;
  final TaskType taskType;
  final DateTime? scheduledTime;
  final int intervalSeconds;
  final int countdownSeconds;
}

// ═══════════════════════════════════════════
// 内联任务表单卡片（非弹窗）
// ═══════════════════════════════════════════

class _TaskFormCard extends StatelessWidget {
  const _TaskFormCard({
    this.existingTask,
    required this.titleCtrl,
    required this.descCtrl,
    required this.intervalCtrl,
    required this.countdownCtrl,
    required this.taskType,
    required this.scheduledDate,
    required this.scheduledTime,
    required this.intervalValue,
    required this.intervalUnit,
    required this.countdownValue,
    required this.countdownUnit,
    required this.onTaskTypeChanged,
    required this.onScheduledDateChanged,
    required this.onScheduledTimeChanged,
    required this.onIntervalChanged,
    required this.onCountdownChanged,
    required this.onCancel,
    required this.onSubmit,
  });

  final ScheduledTask? existingTask;
  final TextEditingController titleCtrl;
  final TextEditingController descCtrl;
  final TextEditingController intervalCtrl;
  final TextEditingController countdownCtrl;
  final TaskType taskType;
  final DateTime scheduledDate;
  final TimeOfDay scheduledTime;
  final int intervalValue;
  final String intervalUnit;
  final int countdownValue;
  final String countdownUnit;
  final ValueChanged<TaskType> onTaskTypeChanged;
  final ValueChanged<DateTime> onScheduledDateChanged;
  final ValueChanged<TimeOfDay> onScheduledTimeChanged;
  final void Function(int value, String unit) onIntervalChanged;
  final void Function(int value, String unit) onCountdownChanged;
  final VoidCallback onCancel;
  final void Function(_TaskFormData data) onSubmit;

  int _toSeconds(int value, String unit) {
    switch (unit) {
      case 'seconds': return value;
      case 'minutes': return value * 60;
      case 'hours': return value * 3600;
      case 'days': return value * 86400;
      default: return value * 60;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary;
    final textMuted = isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted;
    final surfaceVariant = isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant;
    final borderColor = isDark ? PixelTheme.darkBorderSubtle : PixelTheme.pixelBorder.withValues(alpha: 0.4);
    final isEditing = existingTask != null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PixelTheme.brandBlue.withValues(alpha: isDark ? 0.2 : 0.15), width: 1),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: PixelTheme.brandBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(isEditing ? Icons.edit_calendar : Icons.add_alarm, size: 18, color: PixelTheme.brandBlue),
          ),
          const SizedBox(width: 10),
          Text(
            isEditing ? '编辑任务' : '新建任务',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onCancel,
            child: Icon(Icons.close, size: 18, color: textMuted),
          ),
        ]),
        const SizedBox(height: 12),

        // Type chips
        Row(children: [
          _TypeChip(label: '定时', icon: Icons.calendar_today, selected: taskType == TaskType.scheduled, onTap: () => onTaskTypeChanged(TaskType.scheduled), isDark: isDark),
          const SizedBox(width: 6),
          _TypeChip(label: '周期', icon: Icons.repeat, selected: taskType == TaskType.recurring, onTap: () => onTaskTypeChanged(TaskType.recurring), isDark: isDark),
          const SizedBox(width: 6),
          _TypeChip(label: '倒计时', icon: Icons.timer, selected: taskType == TaskType.countdown, onTap: () => onTaskTypeChanged(TaskType.countdown), isDark: isDark),
        ]),
        const SizedBox(height: 10),

        // Title
        _CompactInput(titleCtrl, '任务标题', textPrimary, surfaceVariant),
        const SizedBox(height: 6),
        // Description
        _CompactInput(descCtrl, '任务描述（可选）', textPrimary, surfaceVariant, maxLines: 2),

        const SizedBox(height: 10),

        // Conditional pickers
        if (taskType == TaskType.scheduled)
          _ScheduledRow(
            scheduledDate: scheduledDate,
            scheduledTime: scheduledTime,
            onDateChanged: onScheduledDateChanged,
            onTimeChanged: onScheduledTimeChanged,
            textPrimary: textPrimary,
            surfaceVariant: surfaceVariant,
            textMuted: textMuted,
          ),
        if (taskType == TaskType.recurring)
          _NumberUnitRow(
            label: '执行周期',
            ctrl: intervalCtrl,
            value: intervalValue,
            unit: intervalUnit,
            onChanged: onIntervalChanged,
            textPrimary: textPrimary,
            surfaceVariant: surfaceVariant,
            textMuted: textMuted,
          ),
        if (taskType == TaskType.countdown)
          _NumberUnitRow(
            label: '倒计时长',
            ctrl: countdownCtrl,
            value: countdownValue,
            unit: countdownUnit,
            onChanged: onCountdownChanged,
            textPrimary: textPrimary,
            surfaceVariant: surfaceVariant,
            textMuted: textMuted,
          ),

        const SizedBox(height: 12),

        // Buttons
        Row(children: [
          Expanded(
            child: _CompactBtn(
              label: '取消', onTap: onCancel,
              bgColor: surfaceVariant.withValues(alpha: 0.5),
              fgColor: textMuted,
              primary: false, disabled: false,
              borderColor: borderColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: titleCtrl,
              builder: (context, value, _) {
                final hasTitle = value.text.trim().isNotEmpty;
                return _CompactBtn(
                  label: hasTitle ? (isEditing ? '保存' : '创建') : '请输入标题',
                  onTap: hasTitle ? () {
                    int intervalSeconds = 0, countdownSeconds = 0;
                    DateTime? st;
                    switch (taskType) {
                      case TaskType.scheduled:
                        st = DateTime(scheduledDate.year, scheduledDate.month, scheduledDate.day, scheduledTime.hour, scheduledTime.minute);
                      case TaskType.recurring:
                        intervalSeconds = _toSeconds(intervalValue, intervalUnit);
                      case TaskType.countdown:
                        countdownSeconds = _toSeconds(countdownValue, countdownUnit);
                    }
                    onSubmit(_TaskFormData(
                      title: titleCtrl.text.trim(),
                      description: descCtrl.text.trim(),
                      taskType: taskType,
                      scheduledTime: st,
                      intervalSeconds: intervalSeconds,
                      countdownSeconds: countdownSeconds,
                    ));
                  } : null,
                  bgColor: PixelTheme.brandBlue,
                  fgColor: Colors.white,
                  primary: true,
                  disabled: !hasTitle,
                );
              },
            ),
          ),
        ]),
      ]),
    );
  }
}

// ── Card helper widgets ──

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.label, required this.icon, required this.selected, required this.onTap, required this.isDark});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            gradient: selected ? PixelTheme.primaryGradient : null,
            color: selected ? null : (isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant),
            borderRadius: BorderRadius.circular(10),
            border: selected ? null : Border.all(color: isDark ? PixelTheme.darkBorderSubtle : PixelTheme.pixelBorder.withValues(alpha: 0.3)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 15, color: selected ? Colors.white : (isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary)),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: selected ? Colors.white : (isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary))),
          ]),
        ),
      ),
    );
  }
}

class _CompactInput extends StatelessWidget {
  const _CompactInput(this.ctrl, this.hint, this.textColor, this.fillColor, {this.maxLines = 1});
  final TextEditingController ctrl;
  final String hint;
  final Color textColor;
  final Color fillColor;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl, maxLines: maxLines,
      style: TextStyle(fontSize: 13, color: textColor),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 12, color: textColor.withValues(alpha: 0.35)),
        filled: true,
        fillColor: fillColor.withValues(alpha: 0.4),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: PixelTheme.brandBlue, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
    );
  }
}

class _ScheduledRow extends StatelessWidget {
  const _ScheduledRow({
    required this.scheduledDate, required this.scheduledTime,
    required this.onDateChanged, required this.onTimeChanged,
    required this.textPrimary, required this.surfaceVariant, required this.textMuted,
  });
  final DateTime scheduledDate;
  final TimeOfDay scheduledTime;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<TimeOfDay> onTimeChanged;
  final Color textPrimary;
  final Color surfaceVariant;
  final Color textMuted;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: _PickerChip(
          onTap: () async {
            final picked = await showDatePicker(context: context, initialDate: scheduledDate, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365 * 2)));
            if (picked != null) onDateChanged(picked);
          },
          surfaceVariant: surfaceVariant,
          child: Text(scheduledDate.toString().substring(0, 10), style: TextStyle(fontSize: 13, color: textPrimary)),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _PickerChip(
          onTap: () async {
            final picked = await showTimePicker(context: context, initialTime: scheduledTime);
            if (picked != null) onTimeChanged(picked);
          },
          surfaceVariant: surfaceVariant,
          child: Text('${scheduledTime.hour.toString().padLeft(2, '0')}:${scheduledTime.minute.toString().padLeft(2, '0')}', style: TextStyle(fontSize: 13, color: textPrimary)),
        ),
      ),
    ]);
  }
}

class _NumberUnitRow extends StatelessWidget {
  const _NumberUnitRow({
    required this.label, required this.ctrl, required this.value, required this.unit,
    required this.onChanged, required this.textPrimary, required this.surfaceVariant, required this.textMuted,
  });
  final String label;
  final TextEditingController ctrl;
  final int value;
  final String unit;
  final void Function(int value, String unit) onChanged;
  final Color textPrimary;
  final Color surfaceVariant;
  final Color textMuted;

  @override
  Widget build(BuildContext context) {
    final labels = {'seconds': '秒', 'minutes': '分钟', 'hours': '小时', 'days': '天'};
    return Row(children: [
      Expanded(
        flex: 2,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: surfaceVariant.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(10)),
          child: TextField(
            keyboardType: TextInputType.number,
            controller: ctrl,
            style: TextStyle(fontSize: 13, color: textPrimary),
            onChanged: (v) { final n = int.tryParse(v); if (n != null && n > 0) onChanged(n, unit); },
            decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 10)),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        flex: 3,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: surfaceVariant.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(10)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: unit,
              isExpanded: true,
              dropdownColor: Theme.of(context).brightness == Brightness.dark ? PixelTheme.darkElevated : PixelTheme.surface,
              style: TextStyle(fontSize: 13, color: textMuted),
              items: labels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: (v) { if (v != null) onChanged(value, v); },
            ),
          ),
        ),
      ),
    ]);
  }
}

class _PickerChip extends StatelessWidget {
  const _PickerChip({required this.onTap, required this.surfaceVariant, required this.child});
  final VoidCallback onTap;
  final Color surfaceVariant;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: surfaceVariant.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: child,
      ),
    );
  }
}

class _CompactBtn extends StatelessWidget {
  const _CompactBtn({required this.label, required this.onTap, required this.bgColor, required this.fgColor, required this.primary, required this.disabled, this.borderColor});
  final String label;
  final VoidCallback? onTap;
  final Color bgColor;
  final Color fgColor;
  final Color? borderColor;
  final bool primary;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final effectiveBg = disabled ? bgColor.withValues(alpha: 0.35) : bgColor;
    final effectiveFg = disabled ? fgColor.withValues(alpha: 0.5) : fgColor;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: effectiveBg,
          borderRadius: BorderRadius.circular(10),
          border: borderColor != null ? Border.all(color: borderColor!) : null,
        ),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: effectiveFg)),
      ),
    );
  }
}
