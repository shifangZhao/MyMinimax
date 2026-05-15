import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../core/api/minimax_client.dart';

final Map<String, List<String>> quotaModelAliases = {
  'speech-hd': ['speech-2.8-hd', 'speech-2.6-hd', 'speech-02-hd', 'speech-2.8-turbo', 'speech-2.6-turbo', 'speech-02-turbo'],
  'hailuo-2.3': ['MiniMax-Hailuo-2.3-6s-768p', 'MiniMax-Hailuo-2.3-Fast-6s-768p'],
  'music-2.6': ['music-2.6', 'music-cover'],
};

bool _matchesQuota(String selectorModel, String quotaModelName) {
  if (selectorModel == quotaModelName) return true;
  final aliases = quotaModelAliases[quotaModelName];
  if (aliases != null && aliases.contains(selectorModel)) return true;
  return false;
}

class QuotaAwareModelSelector extends StatelessWidget {

  const QuotaAwareModelSelector({
    required this.label, required this.selectedModel, required this.models, required this.modelDescriptions, required this.onChanged, super.key,
    this.quotaModels,
  });
  final String label;
  final String selectedModel;
  final List<String> models;
  final Map<String, String> modelDescriptions;
  final ValueChanged<String> onChanged;
  final List<QuotaModelInfo>? quotaModels;

  bool _isModelAvailable(String modelName) {
    if (quotaModels == null || quotaModels!.isEmpty) return true;
    for (final q in quotaModels!) {
      if (_matchesQuota(modelName, q.modelName)) return q.isAvailable;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: PixelTheme.primaryText,
          ),
        ),
        const SizedBox(height: 10),
        _buildChipSelector(),
      ],
    );
  }

  Widget _buildChipSelector() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: models.map((model) {
        final isSelected = selectedModel == model;
        final isAvailable = _isModelAvailable(model);
        final desc = modelDescriptions[model] ?? '';
        
        return GestureDetector(
          onTap: isAvailable ? () => onChanged(model) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: isSelected ? PixelTheme.primaryGradient : null,
              color: isSelected ? null : (isAvailable ? PixelTheme.surfaceVariant : PixelTheme.surfaceVariant.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? Colors.transparent : (isAvailable ? PixelTheme.border : PixelTheme.border.withValues(alpha: 0.5)),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected 
                        ? Colors.white 
                        : (isAvailable ? PixelTheme.primaryText : PixelTheme.textMuted),
                  ),
                ),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected 
                          ? Colors.white70 
                          : (isAvailable ? PixelTheme.secondaryText : PixelTheme.textMuted),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class ModelInfo {

  const ModelInfo({
    required this.model,
    required this.description,
    this.usage,
  });
  final String model;
  final String description;
  final String? usage;
}

List<ModelInfo> imageModelInfos = const [
  ModelInfo(model: 'image-01', description: '基础图片生成'),
  ModelInfo(model: 'image-01-live', description: '图片增强/图生图', usage: '需要上传一张图片作为参考'),
];

List<ModelInfo> videoModelInfos = const [
  ModelInfo(model: 'MiniMax-Hailuo-2.3-6s-768p', description: '全新视频生成模型，肢体动作、面部表情、物理表现与指令遵循再度突破', usage: '输入文字描述生成视频'),
  ModelInfo(model: 'MiniMax-Hailuo-2.3-Fast-6s-768p', description: '全新图生视频模型，物理表现与指令遵循具佳，更快更优惠', usage: '需要上传首帧图片'),
];

List<ModelInfo> musicModelInfos = const [
  ModelInfo(model: 'music-2.6', description: '音乐生成', usage: '根据描述创作音乐'),
  ModelInfo(model: 'music-cover', description: '音乐混音/翻唱', usage: '基于原曲创作新版本'),
];

List<ModelInfo> speechModelInfos = const [
  ModelInfo(model: 'speech-2.8-hd', description: '高清语音'),
  ModelInfo(model: 'speech-2.8-turbo', description: '快速语音'),
  ModelInfo(model: 'speech-2.6-hd', description: '高清语音 2.6'),
  ModelInfo(model: 'speech-2.6-turbo', description: '快速语音 2.6'),
  ModelInfo(model: 'speech-02-hd', description: '语音02 高清'),
  ModelInfo(model: 'speech-02-turbo', description: '语音02 快速'),
];