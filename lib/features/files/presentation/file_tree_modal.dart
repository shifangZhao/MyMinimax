import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme.dart';
import '../../../../core/saf/saf_client.dart';
import '../../../../core/browser/browser_state.dart';
import '../../../../shared/utils/file_utils.dart';
import '../../settings/data/settings_repository.dart';

class FileTreeModal extends ConsumerStatefulWidget {
  const FileTreeModal({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const FileTreeModal(),
    );
  }

  @override
  ConsumerState<FileTreeModal> createState() => _FileTreeModalState();
}

class _FileTreeModalState extends ConsumerState<FileTreeModal> {
  final SafClient _safClient = SafClient();
  String? _safUri;
  List<_TreeNode> _roots = [];
  bool _loading = true;
  bool _manageMode = false;
  String? _error;
  String? _currentPath;
  int _lastChangeVersion = 0;
  VoidCallback? _changeListener;

  @override
  void initState() {
    super.initState();
    _changeListener = () {
      if (mounted) _onExternalChange();
    };
    fileChangeNotifier.addListener(_changeListener!);
    _loadRoot();
  }

  @override
  void dispose() {
    if (_changeListener != null) {
      fileChangeNotifier.removeListener(_changeListener!);
    }
    super.dispose();
  }

  /// 收到外部变更通知后静默刷新当前目录
  Future<void> _onExternalChange() async {
    if (_safUri == null || !mounted) return;
    final expandedPaths = _collectExpandedPaths(_roots);
    try {
      final path = _currentPath ?? '';
      final files = await _safClient.listFiles(_safUri!, path);
      if (!mounted) return;
      final nodes = _sortEntries(files.map((f) => _TreeNode(
            name: f.name,
            path: path.isEmpty ? f.name : '$path/${f.name}',
            isDirectory: f.isDirectory,
            size: f.size,
            lastModified: f.lastModified,
            uri: f.uri,
            children: f.isDirectory ? null : [],
          )).toList());
      _restoreExpanded(nodes, expandedPaths);
      setState(() {
        if (path.isEmpty) {
          _roots = nodes;
        } else {
          _updateChildNodes(_roots, path, nodes);
        }
      });
    } catch (e) {
      debugPrint('[FileTreeModal] _onExternalChange error: $e');
    }
  }

  Set<String> _collectExpandedPaths(List<_TreeNode> nodes) {
    final paths = <String>{};
    for (final node in nodes) {
      if (node.isDirectory && node.expanded) {
        paths.add(node.path);
        if (node.children != null) {
          paths.addAll(_collectExpandedPaths(node.children!));
        }
      }
    }
    return paths;
  }

  void _restoreExpanded(List<_TreeNode> nodes, Set<String> expandedPaths) {
    for (final node in nodes) {
      if (node.isDirectory && expandedPaths.contains(node.path)) {
        node.expanded = true;
      }
    }
  }

  Future<void> _loadRoot() async {
    final repo = SettingsRepository();
    final uri = await repo.getSafUri();
    if (!mounted) return;
    if (uri.isEmpty) {
      setState(() {
        _error = 'External storage not authorized\nPlease authorize in settings first / 未授权外部存储\n请先在设置中授权';
        _loading = false;
      });
      return;
    }
    _safUri = uri;
    await _loadDirectory('');
  }

  Future<void> _loadDirectory(String path) async {
    if (_safUri == null) return;
    try {
      final files = await _safClient.listFiles(_safUri!, path);
      if (!mounted) return;
      final nodes = _sortEntries(files.map((f) => _TreeNode(
            name: f.name,
            path: path.isEmpty ? f.name : '$path/${f.name}',
            isDirectory: f.isDirectory,
            size: f.size,
            lastModified: f.lastModified,
            uri: f.uri,
            children: f.isDirectory ? null : [],
          )).toList());

      setState(() {
        if (path.isEmpty) {
          _roots = nodes;
        } else {
          _updateChildNodes(_roots, path, nodes);
        }
        _currentPath = path;
        _loading = false;
      });
      _lastChangeVersion = fileChangeNotifier.value;
    } catch (e) {
      print('[file] error: \$e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<_TreeNode> _sortEntries(List<_TreeNode> nodes) {
    nodes.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return nodes;
  }

  bool _updateChildNodes(List<_TreeNode> roots, String targetPath, List<_TreeNode> children) {
    for (final node in roots) {
      if (node.path == targetPath) {
        node.children = children;
        return true;
      }
      if (node.isDirectory && node.children != null) {
        if (_updateChildNodes(node.children!, targetPath, children)) return true;
      }
    }
    return false;
  }

  void _toggleNode(_TreeNode node) {
    if (!node.isDirectory) return;
    if (node.children != null && node.children!.isNotEmpty) {
      // Already loaded — toggle expand
      setState(() => node.expanded = !node.expanded);
    } else {
      // Not loaded yet — load now
      _loadDirectory(node.path);
    }
  }

  void _onFileTap(_TreeNode node) async {
    if (node.isDirectory) {
      _toggleNode(node);
      return;
    }
    if (_manageMode) return;
    if (_safUri == null) return;

    _showFileDetail(node);
  }

  void _showFileDetail(_TreeNode node) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText;
    final mutedColor = isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted;
    final bgColor = isDark ? PixelTheme.darkSurface : PixelTheme.surface;
    final mime = FileUtils.detectMimeType(node.name);
    final sizeStr = _formatSize(node.size);
    final timeStr = _formatDateTime(node.lastModified);
    final isImage = mime.startsWith('image/');
    final isText = _isTextPreviewable(node.name);
    final isPdf = mime == 'application/pdf';

    // Load preview content for text/images
    Uint8List? previewBytes;
    String? previewText;

    if (isText && node.size < 100 * 1024) {
      try {
        final bytes = await _safClient.readFileBytes(_safUri!, node.path);
        if (bytes != null) {
          previewBytes = bytes;
          previewText = utf8.decode(bytes, allowMalformed: true);
        }
      } catch (e) {
        debugPrint('[FileTreeModal] text preview read error: $e');
      }
    } else if (isImage && node.size < 5 * 1024 * 1024) {
      try {
        previewBytes = await _safClient.readFileBytes(_safUri!, node.path);
      } catch (e) {
        debugPrint('[FileTreeModal] image preview read error: $e');
      }
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: mutedColor, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              // File icon + name
              Row(
                children: [
                  Icon(_fileIcon(node.name), size: 36, color: _fileColor(node.name)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(node.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
                        const SizedBox(height: 2),
                        Text(node.path, style: TextStyle(fontSize: 11, color: mutedColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Metadata
              _detailRow(Icons.insert_drive_file_outlined, '类型', mime ?? '未知', textColor, mutedColor),
              const SizedBox(height: 6),
              _detailRow(Icons.data_usage, '大小', sizeStr, textColor, mutedColor),
              const SizedBox(height: 6),
              _detailRow(Icons.access_time, '修改时间', timeStr, textColor, mutedColor),
              const SizedBox(height: 16),
              // Inline preview
              if (previewText != null) ...[
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 300),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1a1a2e) : const Color(0xFFf5f5f5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isDark ? PixelTheme.darkBorderSubtle : PixelTheme.border),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: SingleChildScrollView(
                    child: Text(
                      previewText,
                      style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: textColor, height: 1.5),
                    ),
                  ),
                ),
                if (node.size > 100 * 1024)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('仅显示前 100KB', style: TextStyle(fontSize: 10, color: mutedColor)),
                  ),
              ] else if (isImage && previewBytes != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(previewBytes, fit: BoxFit.contain, height: 250),
                ),
              ] else if (isText && node.size >= 100 * 1024) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1a1a2e) : const Color(0xFFf5f5f5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 18, color: mutedColor),
                      const SizedBox(width: 8),
                      Text('文件较大 (${_formatSize(node.size)})，不支持内联预览', style: TextStyle(fontSize: 13, color: mutedColor)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // Actions
              Row(
                children: [
                  if (isPdf)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _previewInBrowser(node);
                        },
                        icon: const Icon(Icons.open_in_browser, size: 18),
                        label: const Text('浏览器预览'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: PixelTheme.brandBlue,
                          side: const BorderSide(color: PixelTheme.brandBlue),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  if (isPdf) const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _deleteFile(node);
                      },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('删除'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: PixelTheme.error,
                        side: const BorderSide(color: PixelTheme.error),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  static const _textPreviewableExts = {
    'txt', 'md', 'csv', 'json', 'xml', 'yaml', 'yml', 'toml',
    'log', 'ini', 'cfg', 'properties', 'gitignore', 'dockerfile',
    'html', 'htm', 'css', 'scss', 'less',
    'js', 'ts', 'jsx', 'tsx',
    'py', 'dart', 'java', 'kt', 'c', 'cpp', 'cs', 'h', 'swift', 'go', 'rs',
    'sh', 'bat', 'ps1', 'sql',
  };

  bool _isTextPreviewable(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    return _textPreviewableExts.contains(ext);
  }

  Widget _detailRow(IconData icon, String label, String value, Color textColor, Color mutedColor) {
    return Row(
      children: [
        Icon(icon, size: 16, color: mutedColor),
        const SizedBox(width: 8),
        Text('$label: ', style: TextStyle(fontSize: 13, color: mutedColor)),
        Expanded(
          child: Text(value, style: TextStyle(fontSize: 13, color: textColor), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _previewInBrowser(_TreeNode node) async {
    if (_safUri == null) return;
    ref.read(browserEngineActiveProvider.notifier).state = true;
    ref.read(browserPanelVisibleProvider.notifier).state = true;

    InAppWebViewController? controller;
    int activeIdx = 0;
    for (var i = 0; i < 100; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      final handler = ref.read(browserToolHandlerProvider);
      if (handler != null) {
        final tabs = ref.read(browserTabsProvider);
        activeIdx = ref.read(browserActiveTabIndexProvider);
        if (activeIdx < tabs.length) {
          controller = handler.controllers[tabs[activeIdx].id];
          if (controller != null) break;
        }
      }
    }

    if (controller != null && mounted) {
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(node.uri)));
      ref.read(browserTabsProvider.notifier).setTabUrl(activeIdx, node.path);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('浏览器初始化超时，请重试', style: TextStyle(fontFamily: 'monospace')),
          backgroundColor: PixelTheme.warning,
        ),
      );
    }
  }

  // 新建文件支持的类型（纯文本类，与 writeFile 能力对齐）
  // Office 文档 (docx/xlsx/pptx/pdf/epub) 由智能体 generate* 工具创建，不在此列出
  static const _newFileTypes = <_NewFileType>[
    // ── 文档类 ──
    _NewFileType('Text', 'txt', 'text/plain'),
    _NewFileType('Markdown', 'md', 'text/markdown'),
    // ── 前端 ──
    _NewFileType('HTML', 'html', 'text/html'),
    _NewFileType('CSS', 'css', 'text/css'),
    _NewFileType('JavaScript', 'js', 'application/javascript'),
    _NewFileType('TypeScript', 'ts', 'application/typescript'),
    _NewFileType('JSX', 'jsx', 'text/jsx'),
    _NewFileType('TSX', 'tsx', 'text/tsx'),
    _NewFileType('SCSS', 'scss', 'text/x-scss'),
    _NewFileType('Less', 'less', 'text/x-less'),
    // ── 后端/脚本 ──
    _NewFileType('Python', 'py', 'text/x-python'),
    _NewFileType('Dart', 'dart', 'application/dart'),
    _NewFileType('Java', 'java', 'text/x-java'),
    _NewFileType('Kotlin', 'kt', 'text/x-kotlin'),
    _NewFileType('C', 'c', 'text/x-c'),
    _NewFileType('C++', 'cpp', 'text/x-c++'),
    _NewFileType('C#', 'cs', 'text/x-csharp'),
    _NewFileType('Swift', 'swift', 'text/x-swift'),
    _NewFileType('Go', 'go', 'text/x-go'),
    _NewFileType('Rust', 'rs', 'text/rust'),
    _NewFileType('Shell', 'sh', 'text/x-sh'),
    _NewFileType('Batch', 'bat', 'text/x-bat'),
    _NewFileType('PowerShell', 'ps1', 'application/x-powershell'),
    // ── 数据/配置 ──
    _NewFileType('JSON', 'json', 'application/json'),
    _NewFileType('CSV', 'csv', 'text/csv'),
    _NewFileType('XML', 'xml', 'application/xml'),
    _NewFileType('YAML', 'yaml', 'text/yaml'),
    _NewFileType('TOML', 'toml', 'application/toml'),
    _NewFileType('INI', 'ini', 'text/x-ini'),
    _NewFileType('SQL', 'sql', 'text/x-sql'),
    // ── 其它 ──
    _NewFileType('Dockerfile', 'dockerfile', 'text/x-dockerfile'),
    _NewFileType('Gitignore', 'gitignore', 'text/plain'),
    _NewFileType('Log', 'log', 'text/plain'),
  ];

  Future<void> _deleteFile(_TreeNode node) async {
    if (_safUri == null || node.isDirectory) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? PixelTheme.darkSurface : PixelTheme.surface,
          title: Text('确认删除', style: TextStyle(color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText)),
          content: Text('删除 ${node.name}？\n此操作不可撤销。', style: TextStyle(color: isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: PixelTheme.error))),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    try {
      await _safClient.deleteFile(_safUri!, node.path);
      // Refresh the current directory
      final parentPath = _currentPath ?? '';
      setState(() { _loading = true; _manageMode = false; });
      await _loadDirectory(parentPath.isEmpty ? '' : parentPath);
    } catch (e) {
      print('[file] error: \$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e', style: const TextStyle(fontFamily: 'monospace')), backgroundColor: PixelTheme.error),
        );
      }
    }
  }

  void _showNewFileDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText;
    final bgColor = isDark ? PixelTheme.darkSurface : PixelTheme.surface;
    final mutedColor = isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted;
    bool isFolder = false;
    _NewFileType selectedType = _newFileTypes.first;
    final nameController = TextEditingController();
    final searchController = TextEditingController();
    String query = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final filtered = query.isEmpty
              ? _newFileTypes
              : _newFileTypes.where((t) =>
                  t.label.toLowerCase().contains(query) ||
                  t.ext.toLowerCase().contains(query)).toList();

          return AlertDialog(
            backgroundColor: bgColor,
            title: Text(isFolder ? '新建文件夹' : '新建文件', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
            content: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // File / Folder toggle
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setDialogState(() => isFolder = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: !isFolder ? PixelTheme.brandBlue : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('文件', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: !isFolder ? Colors.white : textColor, fontWeight: FontWeight.w500)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setDialogState(() => isFolder = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: isFolder ? PixelTheme.brandBlue : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('文件夹', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: isFolder ? Colors.white : textColor, fontWeight: FontWeight.w500)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!isFolder) ...[
                    // Search
                    TextField(
                      controller: searchController,
                      style: TextStyle(color: textColor, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: '搜索文件类型...',
                        hintStyle: TextStyle(color: mutedColor, fontSize: 13),
                        prefixIcon: Icon(Icons.search, size: 18, color: mutedColor),
                        suffixIcon: query.isNotEmpty
                            ? GestureDetector(
                                onTap: () {
                                  searchController.clear();
                                  setDialogState(() => query = '');
                                },
                                child: Icon(Icons.clear, size: 16, color: mutedColor),
                              )
                            : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        isDense: true,
                      ),
                      onChanged: (v) => setDialogState(() => query = v.toLowerCase().trim()),
                    ),
                    const SizedBox(height: 8),
                    // Type list
                    SizedBox(
                      height: 200,
                      child: filtered.isEmpty
                          ? Center(child: Text('无匹配类型', style: TextStyle(color: mutedColor, fontSize: 13)))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final t = filtered[i];
                                final selected = selectedType == t;
                                return InkWell(
                                  onTap: () => setDialogState(() => selectedType = t),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: selected ? PixelTheme.brandBlue.withValues(alpha: 0.15) : Colors.transparent,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          selected ? Icons.radio_button_checked : Icons.radio_button_off,
                                          size: 16,
                                          color: selected ? PixelTheme.brandBlue : mutedColor,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(t.label, style: TextStyle(fontSize: 13, color: textColor)),
                                        ),
                                        Text('.${t.ext}', style: TextStyle(fontSize: 11, color: mutedColor)),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // Name input
                  Text(isFolder ? '文件夹名' : '文件名', style: TextStyle(fontSize: 12, color: mutedColor)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: nameController,
                          autofocus: true,
                          style: TextStyle(color: textColor, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: isFolder ? '输入文件夹名' : '输入文件名',
                            hintStyle: TextStyle(color: mutedColor, fontSize: 14),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            isDense: true,
                          ),
                        ),
                      ),
                      if (!isFolder) ...[
                        const SizedBox(width: 8),
                        Text('.${selectedType.ext}', style: TextStyle(color: isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText, fontSize: 14)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              TextButton(
                onPressed: () async {
                  final rawName = nameController.text.trim();
                  if (rawName.isEmpty) return;
                  final finalName = isFolder ? rawName : '$rawName.${selectedType.ext}';
                  final exists = _roots.any((n) => n.name == finalName);
                  if (exists) {
                    final overwrite = await showDialog<bool>(
                      context: ctx,
                      builder: (c) => AlertDialog(
                        title: const Text('文件已存在'),
                        content: Text('$finalName 已存在，要覆盖吗？\n覆盖后原内容将丢失。'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('覆盖', style: TextStyle(color: PixelTheme.error))),
                        ],
                      ),
                    );
                    if (overwrite != true) return;
                  }
                  Navigator.pop(ctx);
                  if (isFolder) {
                    _createFolder(rawName);
                  } else {
                    _createFile(finalName, selectedType);
                  }
                },
                child: const Text('创建'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createFolder(String folderName) async {
    if (_safUri == null) return;
    final parentPath = _currentPath ?? '';
    final folderPath = parentPath.isEmpty ? folderName : '$parentPath/$folderName';
    try {
      await _safClient.createDirectory(_safUri!, folderPath);
      if (!mounted) return;
      setState(() => _loading = true);
      await _loadDirectory(parentPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已创建: $folderName/', style: const TextStyle(fontFamily: 'monospace')), backgroundColor: PixelTheme.brandBlue),
        );
      }
    } catch (e) {
      print('[file] error: \$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败: $e', style: const TextStyle(fontFamily: 'monospace')), backgroundColor: PixelTheme.error),
        );
      }
    }
  }

  Future<void> _createFile(String fileName, _NewFileType type) async {
    if (_safUri == null) return;
    final parentPath = _currentPath ?? '';
    final filePath = parentPath.isEmpty ? fileName : '$parentPath/$fileName';
    final template = type.template(fileName);
    try {
      await _safClient.writeFile(_safUri!, filePath, template);
      if (!mounted) return;
      setState(() => _loading = true);
      await _loadDirectory(parentPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已创建: $fileName', style: const TextStyle(fontFamily: 'monospace')), backgroundColor: PixelTheme.brandBlue),
        );
      }
    } catch (e) {
      print('[file] error: \$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败: $e', style: const TextStyle(fontFamily: 'monospace')), backgroundColor: PixelTheme.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText;
    final mutedColor = isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: isDark ? PixelTheme.darkBase : PixelTheme.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // Drag handle + header
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.folder_outlined, size: 20, color: PixelTheme.brandBlue),
                  const SizedBox(width: 8),
                  Text('文件浏览', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor)),
                  const Spacer(),
                  if (_currentPath != null && _currentPath!.isNotEmpty) ...[
                    Flexible(child: Text(_currentPath!, style: TextStyle(fontSize: 11, color: mutedColor), overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 12),
                  ],
                  _HeaderIconButton(
                    icon: _manageMode ? Icons.check : Icons.edit_note,
                    tooltip: _manageMode ? '完成' : '管理',
                    color: _manageMode ? PixelTheme.brandBlue : mutedColor,
                    onTap: () => setState(() => _manageMode = !_manageMode),
                  ),
                  const SizedBox(width: 4),
                  _HeaderIconButton(
                    icon: Icons.add,
                    tooltip: '新建文件',
                    color: mutedColor,
                    onTap: _manageMode ? null : _showNewFileDialog,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: isDark ? PixelTheme.darkBorderSubtle : PixelTheme.border),
            // Content
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: PixelTheme.brandBlue))
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(_error!, textAlign: TextAlign.center,
                                style: TextStyle(color: mutedColor, fontSize: 13)),
                          ),
                        )
                      : ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          children: _roots.map((n) => _buildNode(n, 0, isDark)).toList(),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNode(_TreeNode node, int depth, bool isDark) {
    final textColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText;
    final mutedColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText;

    // Determine the current path for refresh after delete
    final isFile = !node.isDirectory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => node.isDirectory ? _toggleNode(node) : _onFileTap(node),
          child: Container(
            padding: EdgeInsets.only(left: 16.0 + depth * 20.0, right: 12, top: 10, bottom: 10),
            color: Colors.transparent,
            child: Row(
              children: [
                if (node.isDirectory)
                  AnimatedRotation(
                    turns: node.expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(Icons.arrow_right, size: 18, color: mutedColor),
                  )
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 4),
                Icon(
                  node.isDirectory ? Icons.folder_outlined : _fileIcon(node.name),
                  size: 18,
                  color: node.isDirectory ? PixelTheme.warning : _fileColor(node.name),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    node.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: textColor),
                  ),
                ),
                if (!node.isDirectory && !_manageMode)
                  Text(
                    _formatDateTime(node.lastModified),
                    style: TextStyle(fontSize: 10, color: mutedColor),
                  ),
                if (isFile && _manageMode)
                  GestureDetector(
                    onTap: () => _deleteFile(node),
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.delete_outline, size: 18, color: PixelTheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (node.isDirectory && node.expanded && node.children != null)
          ...node.children!.map((c) => _buildNode(c, depth + 1, isDark)),
      ],
    );
  }

  IconData _fileIcon(String name) {
    final mime = FileUtils.detectMimeType(name);
    if (mime.startsWith('image/')) return Icons.image_outlined;
    if (mime.startsWith('video/')) return Icons.videocam_outlined;
    if (mime.startsWith('audio/')) return Icons.music_note_outlined;
    if (mime.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (mime.contains('text/')) return Icons.article_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _formatDateTime(DateTime dt) {
    if (dt.year <= 1970) return '-';
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(dt.month)}-${pad(dt.day)} ${pad(dt.hour)}:${pad(dt.minute)}:${pad(dt.second)}';
  }

  Color _fileColor(String name) {
    final mime = FileUtils.detectMimeType(name);
    if (mime.startsWith('image/')) return PixelTheme.brandBlue;
    if (mime.startsWith('video/')) return PixelTheme.error;
    if (mime.startsWith('audio/')) return PixelTheme.warning;
    if (mime.contains('pdf')) return PixelTheme.error;
    return PixelTheme.secondaryText;
  }
}

class _TreeNode {

  _TreeNode({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.lastModified,
    required this.uri,
    this.children,
  }) : expanded = false;
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime lastModified;
  final String uri;
  List<_TreeNode>? children;
  bool expanded;
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.tooltip, required this.color, this.onTap});
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Icon(icon, size: 20, color: onTap != null ? color : color.withValues(alpha: 0.3)),
      ),
    );
  }
}

class _NewFileType {
  const _NewFileType(this.label, this.ext, this.mime);
  final String label;
  final String ext;
  final String mime;

  String template(String fileName) {
    switch (ext) {
      case 'html':
        return '<!DOCTYPE html>\n<html lang="en">\n<head>\n  <meta charset="UTF-8">\n  <meta name="viewport" content="width=device-width, initial-scale=1.0">\n  <title>$fileName</title>\n</head>\n<body>\n  \n</body>\n</html>\n';
      case 'json':
        return '{\n  \n}\n';
      case 'xml':
        return '<?xml version="1.0" encoding="UTF-8"?>\n<root>\n  \n</root>\n';
      case 'css':
      case 'scss':
      case 'less':
        return '/* $fileName */\n\n';
      case 'js':
      case 'ts':
      case 'jsx':
      case 'tsx':
      case 'dart':
      case 'java':
      case 'kt':
      case 'c':
      case 'cpp':
      case 'cs':
      case 'swift':
      case 'go':
      case 'rs':
        return '// $fileName\n\n';
      case 'py':
      case 'sh':
      case 'yaml':
      case 'yml':
      case 'toml':
      case 'dockerfile':
      case 'ps1':
        return '# $fileName\n\n';
      case 'bat':
        return '@echo off\n\n';
      case 'md':
        return '# $fileName\n\n';
      case 'sql':
        return '-- $fileName\n\n';
      case 'ini':
        return '; $fileName\n\n';
      case 'csv':
      case 'gitignore':
      case 'log':
        return '';
      default:
        return '';
    }
  }
}
