import '../../features/tools/domain/tool.dart';
import 'tool_registry.dart';
import 'tool_module.dart';
import 'tool_groups.dart';

class BrowserTools implements ToolModule {
  static final BrowserTools module = BrowserTools._();
  BrowserTools._();

  // ---- ToolModule interface ----
  @override
  String get name => 'browser';

  @override
  bool get isDynamic => false;

  @override
  Map<String, ToolGroup> get groupAssignments {
    final map = <String, ToolGroup>{};
    for (final d in _definitions) {
      map[d.name] = ToolGroup.browser;
    }
    return map;
  }

  static List<ToolDefinition> get _definitions => [
        ToolDefinition(
          name: 'browser_navigate',
          description: '导航到指定 URL。不要重复导航同一地址——先用 browser_get_content 确认当前页面。',
          category: ToolCategory.search,
          baseRisk: 0.05,
          tags: ['browser', 'network'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'url': {'type': 'string', 'description': '完整 URL'},
              'tabId': {'type': 'string', 'description': '标签页 ID，省略则使用当前活跃标签页'},
            },
            'required': ['url'],
          },
        ),
        ToolDefinition(
          name: 'browser_get_content',
          description: '提取当前页面内容。支持 text（原始可见文本）和 markdown（清洗后的结构化 Markdown）两种格式。',
          category: ToolCategory.search,
          baseRisk: 0.02,
          tags: ['browser'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'selector': {'type': 'string', 'description': 'CSS 选择器，限定提取范围（可选）'},
              'format': {
                'type': 'string',
                'enum': ['text', 'markdown'],
                'description': '输出格式：text 或 markdown',
              },
              'includeHtml': {'type': 'boolean', 'description': '已废弃，请用 format:"markdown"'},
              'tabId': {'type': 'string', 'description': '标签页 ID（可选）'},
            },
            'required': [],
          },
        ),
        ToolDefinition(
          name: 'browser_summarize',
          description: '获取当前页面的结构化摘要。返回标题、描述、站点名、作者、发布日期、阅读时长和清洗后的 Markdown 内容。',
          category: ToolCategory.search,
          baseRisk: 0.02,
          tags: ['browser', 'summarization'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'tabId': {'type': 'string', 'description': '标签页 ID（可选）'},
            },
            'required': [],
          },
        ),
        ToolDefinition(
          name: 'browser_get_elements',
          description: '扫描当前页面，返回可交互元素的编号列表。'
              '调用 browser_click 或 browser_type 前先用此工具获取元素索引。'
              '返回 JSON：{elements: [{index, tag, text, type, id, placeholder, name, href, ariaLabel, role}], total, hint}。',
          category: ToolCategory.search,
          baseRisk: 0.01,
          tags: ['browser'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'tabId': {'type': 'string', 'description': '标签页 ID（可选）'},
            },
            'required': [],
          },
        ),
        ToolDefinition(
          name: 'browser_execute_js',
          description: '在当前页面执行 JavaScript 代码并返回结果。',
          category: ToolCategory.system,
          baseRisk: 0.12,
          tags: ['browser', 'scripting'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'code': {'type': 'string', 'description': '要执行的 JavaScript 代码'},
              'tabId': {'type': 'string', 'description': '标签页 ID（可选）'},
            },
            'required': ['code'],
          },
        ),
        ToolDefinition(
          name: 'browser_click',
          description: '点击页面元素。index 和 selector 二选一，优先用 index。',
          category: ToolCategory.system,
          baseRisk: 0.06,
          tags: ['browser', 'interaction'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'index': {'type': 'integer', 'description': '元素索引，来自 browser_get_elements'},
              'selector': {'type': 'string', 'description': 'CSS 选择器（备选）'},
              'tabId': {'type': 'string', 'description': '标签页 ID（可选）'},
            },
            'required': [],
          },
        ),
        ToolDefinition(
          name: 'browser_type',
          description: '在输入框中输入文字。index 和 selector 二选一。',
          category: ToolCategory.system,
          baseRisk: 0.08,
          tags: ['browser', 'interaction'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'index': {'type': 'integer', 'description': '元素索引，来自 browser_get_elements'},
              'selector': {'type': 'string', 'description': 'CSS 选择器（备选）'},
              'text': {'type': 'string', 'description': '要输入的文字'},
              'tabId': {'type': 'string', 'description': '标签页 ID（可选）'},
            },
            'required': ['text'],
          },
        ),
        ToolDefinition(
          name: 'browser_screenshot',
          description: '截取浏览器可见区域的截图，返回 base64 PNG 数据。',
          category: ToolCategory.system,
          baseRisk: 0.03,
          tags: ['browser'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'tabId': {'type': 'string', 'description': '标签页 ID（可选）'},
            },
            'required': [],
          },
        ),
        ToolDefinition(
          name: 'browser_scroll',
          description: '滚动当前页面。',
          category: ToolCategory.system,
          baseRisk: 0.01,
          tags: ['browser', 'interaction'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'direction': {
                'type': 'string',
                'enum': ['up', 'down', 'top', 'bottom'],
                'description': '滚动方向',
              },
              'amount': {'type': 'number', 'description': '滚动像素数，默认为一屏高度'},
              'tabId': {'type': 'string', 'description': '标签页 ID（可选）'},
            },
            'required': ['direction'],
          },
        ),
        ToolDefinition(
          name: 'browser_get_url',
          description: '获取当前活跃标签页的 URL。',
          category: ToolCategory.search,
          baseRisk: 0.0,
          tags: ['browser'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'tabId': {'type': 'string', 'description': '标签页 ID（可选）'},
            },
            'required': [],
          },
        ),
        ToolDefinition(
          name: 'browser_get_title',
          description: '获取当前活跃标签页的页面标题。',
          category: ToolCategory.search,
          baseRisk: 0.0,
          tags: ['browser'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'tabId': {'type': 'string', 'description': '标签页 ID（可选）'},
            },
            'required': [],
          },
        ),
        ToolDefinition(
          name: 'browser_go_back',
          description: '返回浏览历史的上一页。',
          category: ToolCategory.system,
          baseRisk: 0.0,
          tags: ['browser'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'tabId': {'type': 'string', 'description': '标签页 ID（可选）'},
            },
            'required': [],
          },
        ),
        ToolDefinition(
          name: 'browser_go_forward',
          description: '前进到浏览历史的下一页。',
          category: ToolCategory.system,
          baseRisk: 0.0,
          tags: ['browser'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'tabId': {'type': 'string', 'description': '标签页 ID（可选）'},
            },
            'required': [],
          },
        ),
        ToolDefinition(
          name: 'browser_wait',
          description: '等待页面加载。可指定 CSS 选择器等待某元素出现，或指定超时时间。',
          category: ToolCategory.system,
          baseRisk: 0.0,
          tags: ['browser'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'selector': {'type': 'string', 'description': '等待此 CSS 选择器对应的元素出现（可选）'},
              'timeout': {'type': 'number', 'description': '最大等待毫秒数，默认 3000'},
              'tabId': {'type': 'string', 'description': '标签页 ID（可选）'},
            },
            'required': [],
          },
        ),
        ToolDefinition(
          name: 'browser_open_tab',
          description: '打开新的浏览器标签页，可同时导航到指定 URL。',
          category: ToolCategory.system,
          baseRisk: 0.02,
          tags: ['browser'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'url': {'type': 'string', 'description': '新标签页加载的 URL（可选）'},
            },
            'required': [],
          },
        ),
        ToolDefinition(
          name: 'browser_find',
          description: '在页面中查找文字并高亮匹配项，返回匹配数量。',
          category: ToolCategory.search,
          baseRisk: 0.01,
          tags: ['browser'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'text': {'type': 'string', 'description': '要查找的文字'},
              'tabId': {'type': 'string', 'description': '标签页 ID（可选）'},
            },
            'required': ['text'],
          },
        ),
        ToolDefinition(
          name: 'browser_load_html',
          description: '直接在浏览器中渲染 HTML 内容。',
          category: ToolCategory.system,
          baseRisk: 0.03,
          tags: ['browser'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'html': {'type': 'string', 'description': '要渲染的完整 HTML 字符串'},
              'baseUrl': {'type': 'string', 'description': '基础 URL，用于解析相对链接（可选）'},
              'tabId': {'type': 'string', 'description': '标签页 ID（可选）'},
            },
            'required': ['html'],
          },
        ),
        ToolDefinition(
          name: 'browser_close_tab',
          description: '关闭浏览器标签页。不能关闭最后一个标签页。',
          category: ToolCategory.system,
          baseRisk: 0.01,
          tags: ['browser'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'tabId': {'type': 'string', 'description': '要关闭的标签页 ID，省略则关闭当前活跃标签页'},
            },
            'required': [],
          },
        ),
        ToolDefinition(
          name: 'browser_human_assist',
          description: '暂停自动化，请求用户协助。遇到无法自动处理的场景时使用。',
          category: ToolCategory.system,
          baseRisk: 0.0,
          tags: ['browser', 'human'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'reason': {'type': 'string', 'description': '需要协助的原因'},
              'prompt': {'type': 'string', 'description': '给用户的操作提示（可选）'},
            },
            'required': ['reason'],
          },
        ),
        ToolDefinition(
          name: 'browser_list_downloads',
          description: '列出本次浏览器会话中下载的所有文件。',
          category: ToolCategory.search,
          baseRisk: 0.0,
          tags: ['browser'],
          inputSchema: {'type': 'object', 'properties': {}, 'required': []},
        ),
        ToolDefinition(
          name: 'browser_screenshot_element',
          description: '对指定索引的元素截图。',
          category: ToolCategory.system,
          baseRisk: 0.03,
          tags: ['browser', 'vision'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'index': {'type': 'integer', 'description': '元素索引，来自 browser_get_elements'},
            },
            'required': ['index'],
          },
        ),
        ToolDefinition(
          name: 'browser_save_cookies',
          description: '保存当前浏览器 cookies，可在后续会话中恢复。',
          category: ToolCategory.system,
          baseRisk: 0.02,
          tags: ['browser', 'session'],
          inputSchema: {'type': 'object', 'properties': {}, 'required': []},
        ),
        ToolDefinition(
          name: 'browser_restore_cookies',
          description: '恢复之前保存的浏览器 cookies。接收 browser_save_cookies 的输出。',
          category: ToolCategory.system,
          baseRisk: 0.02,
          tags: ['browser', 'session'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'cookies': {'type': 'array', 'description': 'browser_save_cookies 输出的 cookies 数组'},
            },
            'required': ['cookies'],
          },
        ),
        ToolDefinition(
          name: 'browser_detect_captcha',
          description: '检测当前页面是否有验证码。返回 {found: bool, type: string, hint: string}。',
          category: ToolCategory.search,
          baseRisk: 0.0,
          tags: ['browser'],
          inputSchema: {'type': 'object', 'properties': {}, 'required': []},
        ),
        ToolDefinition(
          name: 'browser_detect_form_result',
          description: '提交表单后检查是否成功。返回 {success: bool, type: string, messages: [{type, text}]}。',
          category: ToolCategory.search,
          baseRisk: 0.01,
          tags: ['browser', 'form'],
          inputSchema: {'type': 'object', 'properties': {}, 'required': []},
        ),
        ToolDefinition(
          name: 'browser_scroll_and_collect',
          description: '自动滚动页面并逐屏收集文字，内容重复或页面耗尽时自动停止。',
          category: ToolCategory.search,
          baseRisk: 0.02,
          tags: ['browser'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'maxScreens': {'type': 'integer', 'description': '最大滚动屏数，默认 10'},
              'waitMs': {'type': 'integer', 'description': '滚动间等待毫秒数，默认 800'},
            },
            'required': [],
          },
        ),
        ToolDefinition(
          name: 'browser_check_errors',
          description: '检测当前页面是否有加载错误。返回 {hasError: bool, errors: [string]}。',
          category: ToolCategory.search,
          baseRisk: 0.0,
          tags: ['browser'],
          inputSchema: {'type': 'object', 'properties': {}, 'required': []},
        ),
        ToolDefinition(
          name: 'browser_clipboard_copy',
          description: '将页面文字复制到系统剪贴板。传元素索引则复制该元素的文本，不传则复制当前选中文字。',
          category: ToolCategory.system,
          baseRisk: 0.02,
          tags: ['browser', 'clipboard'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'index': {'type': 'integer', 'description': '要复制的元素索引，省略则复制当前选中文字'},
            },
            'required': [],
          },
        ),
        ToolDefinition(
          name: 'browser_clipboard_paste',
          description: '将系统剪贴板内容粘贴到页面输入框。传元素索引则粘贴到该元素，不传则粘贴到当前焦点元素。',
          category: ToolCategory.system,
          baseRisk: 0.03,
          tags: ['browser', 'clipboard'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'index': {'type': 'integer', 'description': '要粘贴到的元素索引，省略则用当前焦点元素'},
            },
            'required': [],
          },
        ),
        ToolDefinition(
          name: 'browser_wait_for',
          description: '等待页面出现或消失指定文字或 CSS 选择器。',
          category: ToolCategory.system,
          baseRisk: 0.0,
          tags: ['browser'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'text': {'type': 'string', 'description': '等待出现的文字'},
              'selector': {'type': 'string', 'description': '等待出现的 CSS 选择器'},
              'disappear': {'type': 'boolean', 'description': '设为 true 则等待消失而非出现'},
              'timeout': {'type': 'integer', 'description': '最大等待毫秒数，默认 10000'},
            },
            'required': [],
          },
        ),
        ToolDefinition(
          name: 'browser_hover',
          description: '鼠标悬停在指定索引的元素上。',
          category: ToolCategory.system,
          baseRisk: 0.02,
          tags: ['browser', 'interaction'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'index': {'type': 'integer', 'description': '要悬停的元素索引'},
            },
            'required': ['index'],
          },
        ),
        ToolDefinition(
          name: 'browser_press_key',
          description: '模拟键盘按键。支持 Enter、Tab、Escape、Backspace、Delete、方向键、Space。传元素索引则先聚焦该元素再按键。',
          category: ToolCategory.system,
          baseRisk: 0.02,
          tags: ['browser', 'interaction'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'key': {'type': 'string', 'description': '按键：Enter/Tab/Escape/Backspace/Delete/ArrowUp/ArrowDown/ArrowLeft/ArrowRight/Space'},
              'index': {'type': 'integer', 'description': '先聚焦的元素索引（可选）'},
            },
            'required': ['key'],
          },
        ),
        ToolDefinition(
          name: 'browser_drag',
          description: '从一个元素拖拽到另一个元素，或按像素偏移拖拽。',
          category: ToolCategory.system,
          baseRisk: 0.05,
          tags: ['browser', 'interaction'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'fromIndex': {'type': 'integer', 'description': '拖拽起始元素索引'},
              'toIndex': {'type': 'integer', 'description': '拖拽目标元素索引。不传则按像素偏移拖拽'},
              'dx': {'type': 'number', 'description': '水平拖拽像素（toIndex 不传时使用）'},
              'dy': {'type': 'number', 'description': '垂直拖拽像素（toIndex 不传时使用）'},
            },
            'required': ['fromIndex'],
          },
        ),
        ToolDefinition(
          name: 'browser_get_iframe',
          description: '列出当前页面所有 iframe，或查看指定 iframe 的内容。返回 {iframes: [{src, sameOrigin, interactiveCount}]}。',
          category: ToolCategory.search,
          baseRisk: 0.01,
          tags: ['browser'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'index': {'type': 'integer', 'description': '要查看的 iframe 元素索引。省略则列出所有 iframe'},
            },
            'required': [],
          },
        ),
        ToolDefinition(
          name: 'browser_search_page',
          description: '在页面中搜索文字。返回 {found, count, results: [{match, context, position}]}。',
          category: ToolCategory.search,
          baseRisk: 0.0,
          tags: ['browser'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'text': {'type': 'string', 'description': '要搜索的文字'},
              'tabId': {'type': 'string', 'description': '标签页 ID（可选）'},
            },
            'required': ['text'],
          },
        ),
        ToolDefinition(
          name: 'browser_find_elements',
          description: '用 CSS 选择器查询页面 DOM 结构。返回 {count, elements: [{tag, id, class, href, text, src, ariaLabel}]}，最多 20 条。',
          category: ToolCategory.search,
          baseRisk: 0.0,
          tags: ['browser'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'selector': {'type': 'string', 'description': 'CSS 选择器'},
              'tabId': {'type': 'string', 'description': '标签页 ID（可选）'},
            },
            'required': ['selector'],
          },
        ),
        ToolDefinition(
          name: 'browser_extract_design',
          description: '提取当前页面的设计语言，返回结构化 JSON。包含配色、字体、间距、圆角、阴影、组件样式和布局结构。',
          category: ToolCategory.search,
          baseRisk: 0.01,
          tags: ['browser', 'design'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'selector': {'type': 'string', 'description': '限定提取范围的 CSS 选择器。省略则提取整页'},
              'tabId': {'type': 'string', 'description': '标签页 ID（可选）'},
            },
            'required': [],
          },
        ),
        // ── 页面控制 ──
        ToolDefinition(
          name: 'browser_reload',
          description: '刷新当前页面。',
          category: ToolCategory.system,
          baseRisk: 0.01,
          tags: ['browser'],
          inputSchema: {'type': 'object', 'properties': {}, 'required': []},
        ),
        ToolDefinition(
          name: 'browser_stop',
          description: '停止当前页面的加载。',
          category: ToolCategory.system,
          baseRisk: 0.01,
          tags: ['browser'],
          inputSchema: {'type': 'object', 'properties': {}, 'required': []},
        ),
        // ── 诊断 ──
        ToolDefinition(
          name: 'browser_get_viewport',
          description: '获取当前视口的宽高和设备像素比。',
          category: ToolCategory.search,
          baseRisk: 0.01,
          tags: ['browser'],
          inputSchema: {'type': 'object', 'properties': {}, 'required': []},
        ),
        ToolDefinition(
          name: 'browser_get_cookies',
          description: '获取当前页面的所有 cookies。browser_save_cookies 的别名。',
          category: ToolCategory.system,
          baseRisk: 0.02,
          tags: ['browser', 'session'],
          inputSchema: {'type': 'object', 'properties': {}, 'required': []},
        ),
        ToolDefinition(
          name: 'browser_delete_cookies',
          description: '清除浏览器的所有 cookies。',
          category: ToolCategory.system,
          baseRisk: 0.05,
          tags: ['browser', 'session'],
          inputSchema: {'type': 'object', 'properties': {}, 'required': []},
        ),
        ToolDefinition(
          name: 'browser_get_dom',
          description: '获取当前页面的完整 DOM HTML 源代码。',
          category: ToolCategory.search,
          baseRisk: 0.01,
          tags: ['browser'],
          inputSchema: {'type': 'object', 'properties': {
            'selector': {'type': 'string', 'description': 'CSS 选择器，限定获取范围（可选）'},
          }, 'required': []},
        ),
        ToolDefinition(
          name: 'browser_fill_form',
          description: '批量填写表单。fields 为 [{index: 元素索引, text: 输入文字}] 数组，依次输入。',
          category: ToolCategory.system,
          baseRisk: 0.05,
          tags: ['browser', 'form'],
          inputSchema: {'type': 'object', 'properties': {
            'fields': {'type': 'array', 'description': '表单字段数组，每项 {index: 元素索引, text: 输入文字}'},
          }, 'required': ['fields']},
        ),
        ToolDefinition(
          name: 'browser_add_script',
          description: '向页面注入 JavaScript 脚本。',
          category: ToolCategory.system,
          baseRisk: 0.05,
          tags: ['browser'],
          inputSchema: {'type': 'object', 'properties': {
            'code': {'type': 'string', 'description': '要注入的 JavaScript 代码'},
          }, 'required': ['code']},
        ),
        ToolDefinition(
          name: 'browser_add_stylesheet',
          description: '向页面注入 CSS 样式表。',
          category: ToolCategory.system,
          baseRisk: 0.02,
          tags: ['browser'],
          inputSchema: {'type': 'object', 'properties': {
            'css': {'type': 'string', 'description': '要注入的 CSS 代码'},
          }, 'required': ['css']},
        ),
        ToolDefinition(
          name: 'browser_clear_cache',
          description: '清除浏览器缓存（不包括 cookies）。',
          category: ToolCategory.system,
          baseRisk: 0.05,
          tags: ['browser', 'session'],
          inputSchema: {'type': 'object', 'properties': {}, 'required': []},
        ),
      ];

  @override
  List<ToolDefinition> get definitions {
    return _definitions.map((t) => ToolDefinition(
      name: t.name,
      description: t.description,
      category: t.category,
      baseRisk: t.baseRisk,
      tags: t.tags,
      inputSchema: t.inputSchema,
    )).toList();
  }
}
