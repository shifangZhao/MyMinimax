import '../hook_pipeline.dart';

Future<void> browserSessionStartHook(HookContext context) async {
  if (!context.data.containsKey('_browserContextInjected')) {
    context.data['_browserContextInjected'] = true;
  }
}

Future<void> browserPageLoadedHook(HookContext context) async {
  final toolName = context.data['toolName'] as String? ?? '';
  const pageLoadTools = {
    'browser_navigate',
    'browser_load_html',
    'browser_go_back',
    'browser_go_forward',
  };
  if (pageLoadTools.contains(toolName) && context.data['success'] == true) {
    context.data['_browserNavigated'] = true;
  }
}
