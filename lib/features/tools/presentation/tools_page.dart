import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../../settings/data/settings_repository.dart';
import '../domain/tool.dart';
import '../data/tool_executor.dart';

final toolExecutorProvider = Provider((ref) => ToolExecutor(settingsRepo: SettingsRepository(), ref: ref));

class ToolsPage extends ConsumerStatefulWidget {
  const ToolsPage({super.key});

  @override
  ConsumerState<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends ConsumerState<ToolsPage> {
  final _pathController = TextEditingController();
  final _contentController = TextEditingController();
  final _queryController = TextEditingController();
  final _urlController = TextEditingController();
  ToolResult? _lastResult;
  String? _selectedTool;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary;
    final dividerColor = isDark ? PixelTheme.darkBorderSubtle : Colors.grey.withValues(alpha: 0.12);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 自定义顶部栏 - 44dp 紧凑高度
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  const SizedBox(width: 40),
                  // 标题（Expanded 居中）
                  Expanded(
                    child: Text(
                      '🔧 工具箱',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  // 占位保持对称
                  const SizedBox(width: 40),
                ],
              ),
            ),
            // 底部分割线
            Divider(height: 1, thickness: 0.5, color: dividerColor),
            // 内容区域
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('可用工具', style: TextStyle(fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ToolExecutor.availableTools.map((tool) => _ToolChip(
                        tool: tool,
                        isSelected: _selectedTool == tool.name,
                        onTap: () => setState(() => _selectedTool = tool.name),
                      )).toList(),
                    ),
                    const SizedBox(height: 24),
                    if (_selectedTool == 'readFile') ...[
                      _buildTextField(_pathController, '文件路径'),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => _executeTool('readFile', {'path': _pathController.text}),
                        child: const Text('读取'),
                      ),
                    ] else if (_selectedTool == 'writeFile') ...[
                      _buildTextField(_pathController, '文件路径'),
                      const SizedBox(height: 12),
                      _buildTextField(_contentController, '文件内容', maxLines: 5),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => _executeTool('writeFile', {'path': _pathController.text, 'content': _contentController.text}),
                        child: const Text('写入'),
                      ),
                    ] else if (_selectedTool == 'listFiles') ...[
                      _buildTextField(_pathController, '目录路径（留空为应用目录）'),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => _executeTool('listFiles', {'path': _pathController.text.isEmpty ? null : _pathController.text}),
                        child: const Text('列出文件'),
                      ),
                    ] else if (_selectedTool == 'webSearch') ...[
                      _buildTextField(_queryController, '搜索关键词'),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => _executeTool('webSearch', {'query': _queryController.text}),
                        child: const Text('搜索'),
                      ),
                    ] else if (_selectedTool == 'fetch_url') ...[
                      _buildTextField(_urlController, '网页URL'),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => _executeTool('fetch_url', {'url': _urlController.text}),
                        child: const Text('抓取'),
                      ),
                    ],
                    if (_lastResult != null) ...[
                      const SizedBox(height: 24),
                      _buildResultCard(_lastResult!),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, {int maxLines = 1}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(fontFamily: 'monospace'),
      decoration: InputDecoration(hintText: hint),
    );
  }

  Widget _buildResultCard(ToolResult result) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PixelTheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: result.success ? PixelTheme.primary : PixelTheme.error, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${result.success ? '✅' : '❌'} ${result.toolName}',
            style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
          ),
          if (result.error != null)
            Text('Error: ${result.error}', style: const TextStyle(fontFamily: 'monospace', color: PixelTheme.error)),
          const SizedBox(height: 8),
          SelectableText(result.output.isEmpty ? '(empty)' : result.output,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _executeTool(String tool, Map<String, dynamic> params) async {
    setState(() => _lastResult = null);
    final executor = ref.read(toolExecutorProvider);
    final result = await executor.execute(tool, params);
    setState(() => _lastResult = result);
  }
}

class _ToolChip extends StatelessWidget {

  const _ToolChip({required this.tool, required this.isSelected, required this.onTap});
  final Tool tool;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? PixelTheme.primary : PixelTheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isSelected ? PixelTheme.primary : PixelTheme.pixelBorder, width: 2),
        ),
        child: Column(
          children: [
            Text(tool.name, style: TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              color: isSelected ? PixelTheme.background : PixelTheme.textPrimary,
            )),
            Text(tool.description, style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: isSelected ? PixelTheme.background : PixelTheme.textSecondary,
            )),
          ],
        ),
      ),
    );
  }
}