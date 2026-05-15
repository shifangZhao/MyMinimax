import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/model_dropdown.dart';
import '../../../core/api/minimax_client.dart';
import '../../settings/data/settings_repository.dart';
import '../../chat/presentation/chat_page.dart' show minimaxClientProvider, ttsModelProvider, ttsVoiceProvider;

class TtsSettingsPage extends ConsumerStatefulWidget {
  const TtsSettingsPage({super.key});

  @override
  ConsumerState<TtsSettingsPage> createState() => _TtsSettingsPageState();
}

class _TtsSettingsPageState extends ConsumerState<TtsSettingsPage> {
  List<VoiceInfo> _systemVoices = [];
  List<VoiceInfo> _chineseVoices = [];
  List<VoiceInfo> _englishVoices = [];
  List<VoiceInfo> _clonedVoices = [];
  List<VoiceInfo> _generatedVoices = [];
  bool _isLoadingVoices = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadVoices();
  }

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Future<void> _loadVoices() async {
    setState(() { _isLoadingVoices = true; _loadError = null; });
    try {
      await ref.read(minimaxClientProvider.notifier).loadFromSettings();
      final client = ref.read(minimaxClientProvider);
      final result = await client.getVoiceListAll();
      if (mounted) {
        final systemVoices = result.systemVoices;
        final chinese = systemVoices.where((v) => RegExp(r'[一-鿿]').hasMatch(v.voiceName)).toList();
        final english = systemVoices.where((v) => !RegExp(r'[一-鿿]').hasMatch(v.voiceName)).toList();
        setState(() {
          _systemVoices = systemVoices;
          _chineseVoices = chinese;
          _englishVoices = english;
          _clonedVoices = result.clonedVoices;
          _generatedVoices = result.generatedVoices;
          _isLoadingVoices = false;
        });
      }
    } catch (e) {
      print('[tts] error: \$e');
      if (mounted) {
        setState(() { _loadError = e.toString(); _isLoadingVoices = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ttsModel = ref.watch(ttsModelProvider);
    final ttsVoice = ref.watch(ttsVoiceProvider);
    final primaryColor = _isDark ? PixelTheme.darkPrimary : PixelTheme.primary;
    final textPrimary = _isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary;
    final textSecondary = _isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary;

    return Scaffold(
      backgroundColor: _isDark ? PixelTheme.darkBase : PixelTheme.background,
      appBar: AppBar(
        title: Text('播报设置', style: TextStyle(fontFamily: 'monospace', color: textPrimary)),
        centerTitle: true,
        backgroundColor: _isDark ? PixelTheme.darkBase : PixelTheme.background,
        foregroundColor: textPrimary,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 模型选择
          Text('模型', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary)),
          const SizedBox(height: 4),
          Text('选择语音合成模型', style: TextStyle(fontSize: 11, color: _isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted)),
          const SizedBox(height: 8),
          ModelDropdown(
            label: '选择模型',
            selectedModel: ttsModel,
            models: const ['speech-2.8-hd', 'speech-2.8-turbo', 'speech-2.6-hd', 'speech-2.6-turbo', 'speech-02-hd', 'speech-02-turbo'],
            modelDescriptions: const {
              'speech-2.8-hd': '高清语音 2.8',
              'speech-2.8-turbo': '快速语音 2.8',
              'speech-2.6-hd': '高清语音 2.6',
              'speech-2.6-turbo': '快速语音 2.6',
              'speech-02-hd': '语音02 高清',
              'speech-02-turbo': '语音02 快速',
            },
            onChanged: (m) { ref.read(ttsModelProvider.notifier).state = m; SettingsRepository().setTtsModel(m); },
          ),
          const SizedBox(height: 24),

          // 音色选择
          Text('音色', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary)),
          const SizedBox(height: 4),
          Row(children: [
            Text('从 MiniMax 官方加载', style: TextStyle(fontSize: 11, color: _isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted)),
            if (_isLoadingVoices) ...[
              const SizedBox(width: 8),
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ]),
          const SizedBox(height: 12),

          if (_loadError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                const Icon(Icons.error_outline, size: 16, color: PixelTheme.error),
                const SizedBox(width: 6),
                Expanded(child: Text(_loadError!, style: const TextStyle(fontSize: 12, color: PixelTheme.error))),
                TextButton(onPressed: _loadVoices, child: const Text('重试', style: TextStyle(fontSize: 12))),
              ]),
            ),

          if (_systemVoices.isNotEmpty || _clonedVoices.isNotEmpty || _generatedVoices.isNotEmpty) ...[
            if (_chineseVoices.isNotEmpty) _buildVoiceRow('中文', _chineseVoices, ttsVoice),
            if (_chineseVoices.isNotEmpty && _englishVoices.isNotEmpty) const SizedBox(height: 8),
            if (_englishVoices.isNotEmpty) _buildVoiceRow('英文', _englishVoices, ttsVoice),
            if (_clonedVoices.isNotEmpty) ...[const SizedBox(height: 8), _buildVoiceRow('克隆音色', _clonedVoices, ttsVoice)],
            if (_generatedVoices.isNotEmpty) ...[const SizedBox(height: 8), _buildVoiceRow('AI 生成音色', _generatedVoices, ttsVoice)],
          ] else if (!_isLoadingVoices) ...[
            Text('暂无可用音色', style: TextStyle(fontSize: 13, color: textSecondary)),
          ],
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (_isDark ? PixelTheme.darkBase : const Color(0xFFF0F4FF)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 14, color: _isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '语音播报使用 Token Plan 包含的 MiniMax 语音合成模型服务，消耗 Token 额度，无需额外付费订阅。',
                    style: TextStyle(fontSize: 11, color: _isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildVoiceRow(String title, List<VoiceInfo> voices, String selectedVoice) {
    final textPrimary = _isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary;
    final primaryColor = _isDark ? PixelTheme.darkPrimary : PixelTheme.primary;
    final selected = voices.where((v) => v.voiceId == selectedVoice).firstOrNull;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _showVoiceSheet(title, voices, selectedVoice),
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        decoration: BoxDecoration(
          color: _isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: primaryColor, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: textPrimary)),
          const SizedBox(width: 8),
          Text('(${voices.length})', style: TextStyle(fontSize: 11, color: _isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted)),
          const Spacer(),
          Flexible(child: Text(selected?.voiceName ?? '', style: TextStyle(fontSize: 11, color: _isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText), overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right, size: 16, color: _isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary),
        ]),
      ),
    );
  }

  void _showVoiceSheet(String title, List<VoiceInfo> voices, String selectedVoice) {
    final textPrimary = _isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary;
    final textSecondary = _isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary;
    String query = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _isDark ? PixelTheme.darkSurface : PixelTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (ctx, scroll) => Column(children: [
            Container(margin: const EdgeInsets.only(top: 10), width: 36, height: 4, decoration: BoxDecoration(color: _isDark ? PixelTheme.darkBorderDefault : Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                autofocus: true,
                style: TextStyle(fontSize: 14, color: textPrimary),
                decoration: InputDecoration(
                  hintText: '搜索音色...',
                  hintStyle: TextStyle(fontSize: 13, color: _isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted),
                  prefixIcon: Icon(Icons.search, size: 20, color: _isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted),
                  filled: true,
                  fillColor: _isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (v) => setSheet(() => query = v),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: voices.length,
                itemBuilder: (_, i) {
                  final v = voices[i];
                  if (query.isNotEmpty && !v.voiceName.toLowerCase().contains(query.toLowerCase())) return const SizedBox.shrink();
                  final sel = v.voiceId == selectedVoice;
                  return ListTile(
                    dense: true,
                    leading: Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off, size: 20, color: sel ? (_isDark ? PixelTheme.darkPrimary : PixelTheme.primary) : textSecondary),
                    title: Text(v.voiceName, style: TextStyle(fontSize: 14, fontWeight: sel ? FontWeight.w600 : FontWeight.normal, color: sel ? (_isDark ? PixelTheme.darkPrimary : PixelTheme.primary) : textPrimary)),
                    subtitle: Text(v.voiceId, style: TextStyle(fontSize: 11, color: _isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted)),
                    onTap: () {
                      ref.read(ttsVoiceProvider.notifier).state = v.voiceId;
                      SettingsRepository().setTtsVoice(v.voiceId);
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
