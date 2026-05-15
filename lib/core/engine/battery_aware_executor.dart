import 'package:flutter/widgets.dart';
import 'tool_cancel_registry.dart';

class BatteryAwareExecutor {
  BatteryAwareExecutor._();
  static final BatteryAwareExecutor instance = BatteryAwareExecutor._();

  bool _isBackground = false;
  final _criticalTools = {'writeFile', 'deleteFile', 'updateFile'};

  void init() {
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
  }

  final _lifecycleObserver = _AppLifecycleObserver();

  void onBackground() {
    _isBackground = true;
  }

  void onForeground() {
    _isBackground = false;
  }

  bool get isBackground => _isBackground;

  bool isCriticalTool(String toolName) => _criticalTools.contains(toolName);

  void cancelNonCriticalTools() {
    if (!_isBackground) return;
    ToolCancelRegistry.instance.cancelAll();
  }
}

class _AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final executor = BatteryAwareExecutor.instance;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        executor.onBackground();
        break;
      case AppLifecycleState.resumed:
        executor.onForeground();
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }
}