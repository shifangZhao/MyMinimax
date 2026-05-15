import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/browser/domain/browser_tab.dart';
import '../../features/browser/data/browser_tool_handler.dart';
import 'adapters/browser_tool_adapter.dart';
import 'browser_constants.dart';

final browserTabsProvider =
    StateNotifierProvider<BrowserTabsNotifier, List<BrowserTab>>((ref) {
  return BrowserTabsNotifier();
});

final browserActiveTabIndexProvider = StateProvider<int>((ref) => 0);

final browserActiveTabProvider = Provider<BrowserTab?>((ref) {
  final tabs = ref.watch(browserTabsProvider);
  final idx = ref.watch(browserActiveTabIndexProvider);
  if (tabs.isEmpty || idx >= tabs.length) return null;
  return tabs[idx];
});

final browserCurrentUrlProvider = Provider<String>((ref) {
  return ref.watch(browserActiveTabProvider)?.url ?? '';
});

final browserIsLoadingProvider = Provider<bool>((ref) {
  return ref.watch(browserActiveTabProvider)?.isLoading ?? false;
});

final browserProgressProvider = StateProvider<int>((ref) => 0);

final browserToolHandlerProvider =
    StateProvider<BrowserToolHandler?>((ref) => null);

/// The active browser backend (CDP on Android, JS on iOS).
/// Initialized by BrowserWebView._registerHandler() via ToolBackendRouter.
final browserBackendProvider = StateProvider<IBrowserBackend?>((ref) => null);

/// Whether CDP (Chrome DevTools Protocol) is currently active.
/// True when the Android CDP backend connected successfully.
final browserCdpAvailableProvider = StateProvider<bool>((ref) => false);

/// Current browser backend mode.
enum BrowserBackendMode {
  /// Backend not yet initialized — browser just opened.
  initializing,

  /// CDP is connected and serving all browser tools.
  cdp,

  /// CDP unavailable or permanently failed — using JS injection.
  jsFallback,
}

final browserBackendModeProvider = StateProvider<BrowserBackendMode>(
  (ref) => BrowserBackendMode.initializing,
);

/// 浏览器面板的显示/隐藏。AI 调用 browser_open_tab 自动设为 true。
/// 用户下滑隐藏时设为 false（引擎仍在后台运行）。
final browserPanelVisibleProvider = StateProvider<bool>((ref) => false);

/// 浏览器引擎是否激活。true = BrowserWebView 在 widget tree 中，controller 存活。
/// 首次打开时激活，只有用户点击关闭按钮才变为 false。
final browserEngineActiveProvider = StateProvider<bool>((ref) => false);

/// 当前活动标签页的加载错误信息。有值时表示页面加载失败。
final browserErrorProvider = StateProvider<String?>((ref) => null as String?);

/// 桌面模式开关。true = 桌面 UA，false = 移动 UA
final browserDesktopModeProvider = StateProvider<bool>((ref) => false);

/// 强制深色模式开关。为页面注入暗色 CSS
final browserDarkModeProvider = StateProvider<bool>((ref) => false);

/// 页内查找可见性
final browserFindBarVisibleProvider = StateProvider<bool>((ref) => false);

/// 文件变更通知。文件操作后 +1，文件树监听到后静默刷新。
final fileChangeNotifier = ValueNotifier<int>(0);

class BrowserTabsNotifier extends StateNotifier<List<BrowserTab>> {
  BrowserTabsNotifier() : super([BrowserTab.createNew()]);

  void addTab({String? url}) {
    if (state.length >= BrowserConstants.maxTabs) return;
    state = [...state, BrowserTab.createNew(url: url)];
  }

  void closeTab(int index) {
    if (state.length <= 1) return;
    final newList = [...state];
    newList.removeAt(index);
    state = newList;
  }

  void updateTab(int index, BrowserTab tab) {
    if (index >= state.length) return;
    final newList = [...state];
    newList[index] = tab;
    state = newList;
  }

  void setTabLoading(int index, bool loading) {
    if (index >= state.length) return;
    state = [
      for (var i = 0; i < state.length; i++)
        if (i == index) state[i].copyWith(isLoading: loading) else state[i]
    ];
  }

  void setTabTitle(int index, String title) {
    if (index >= state.length) return;
    state = [
      for (var i = 0; i < state.length; i++)
        if (i == index) state[i].copyWith(title: title) else state[i]
    ];
  }

  void setTabUrl(int index, String url) {
    if (index >= state.length) return;
    state = [
      for (var i = 0; i < state.length; i++)
        if (i == index) state[i].copyWith(url: url) else state[i]
    ];
  }

  void closeAllButFirst() {
    if (state.isNotEmpty) {
      state = [state.first.copyWith(title: '', url: state.first.initialUrl ?? BrowserConstants.homeUrl)];
    }
  }

  void setTabNavState(int index, bool canGoBack, bool canGoForward) {
    if (index >= state.length) return;
    state = [
      for (var i = 0; i < state.length; i++)
        if (i == index)
          state[i].copyWith(canGoBack: canGoBack, canGoForward: canGoForward)
        else
          state[i]
    ];
  }
}
