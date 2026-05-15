// ignore_for_file: avoid_dynamic_calls

/// 外部 Skill 加载器
///
/// 目录结构：
/// ```
/// skills/
///   my-skill/
///     SKILL.md          ← 必须：YAML frontmatter + Markdown body
///     config.json       ← 可选：observer/trigger 配置
///     agents/           ← 可选：关联 agent 定义
///     hooks/            ← 可选：关联 hook 脚本（移动端暂不支持）
///     scripts/          ← 可选：辅助脚本（移动端暂不支持）
/// ```
///
/// SKILL.md 格式：
/// ```markdown
/// ---
/// name: security-review
/// description: 当添加认证、处理用户输入、涉及敏感数据时使用此 skill
/// origin: community
/// version: 1.0.0
/// category: security
/// suggested_tools: readFile,updateFile
/// ---
/// # Security Review
/// ## When to Activate
/// - 用户请求添加登录/注册功能
/// ...
/// ```
library;

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'skill.dart';

class SkillLoadResult {

  SkillLoadResult({
    required this.loaded,
    required this.skipped,
    required this.errors,
    required this.totalScanned,
  });
  final List<String> loaded;
  final List<String> skipped;
  final List<String> errors;
  final int totalScanned;

  String summarize() {
    final buf = StringBuffer();
    buf.write('Skills 扫描: $totalScanned 个目录, '
        '加载 ${loaded.length}');
    if (skipped.isNotEmpty) buf.write(', 跳过 ${skipped.length}');
    if (errors.isNotEmpty) buf.write(', 错误 ${errors.length}');
    return buf.toString();
  }
}

/// 解析后的 frontmatter
class SkillFrontmatter {

  SkillFrontmatter({
    required this.fields,
    required this.body,
    this.rawYaml,
  });
  final Map<String, String> fields;
  final String body;
  final String? rawYaml;

  String? get name => fields['name'];
  String? get description => fields['description'];
  String? get category => fields['category'];
  String? get origin => fields['origin'];
  String? get version => fields['version'];
}

class SkillLoader {
  /// Skill 扫描路径（按优先级）
  static const scanPaths = [
    '.claude/skills', // 优先级最高（用户覆盖）
    'skills',         // 项目级 skills
  ];

  /// 从工作目录加载所有外部 skills
  ///
  /// 扫描 `{workspace}/.claude/skills/` 和 `{workspace}/skills/`，
  /// 查找每个子目录下的 SKILL.md。
  static Future<SkillLoadResult> loadFromWorkspace(String workspacePath) async {
    final allLoaded = <String>[];
    final allSkipped = <String>[];
    final allErrors = <String>[];
    var totalScanned = 0;

    for (final relativePath in scanPaths) {
      final scanDir = Directory(p.join(workspacePath, relativePath));
      if (!await scanDir.exists()) continue;

      final result = await _scanSkillDirectory(scanDir);
      allLoaded.addAll(result.loaded);
      allSkipped.addAll(result.skipped);
      allErrors.addAll(result.errors);
      totalScanned += result.totalScanned;
    }

    return SkillLoadResult(
      loaded: allLoaded,
      skipped: allSkipped,
      errors: allErrors,
      totalScanned: totalScanned,
    );
  }

  /// 扫描单个 skills 目录（如 `skills/`）
  ///
  /// 遍历子目录，查找 SKILL.md 文件。
  static Future<SkillLoadResult> _scanSkillDirectory(Directory skillsDir) async {
    final loaded = <String>[];
    final skipped = <String>[];
    final errors = <String>[];
    var scanned = 0;

    await for (final entity in skillsDir.list()) {
      if (entity is! Directory) continue;
      scanned++;

      final skillMdPath = p.join(entity.path, 'SKILL.md');
      final skillMdFile = File(skillMdPath);

      if (!await skillMdFile.exists()) {
        // 也尝试小写
        final altPath = p.join(entity.path, 'skill.md');
        if (!await File(altPath).exists()) {
          skipped.add('${p.basename(entity.path)} (无 SKILL.md)');
          continue;
        }
      }

      try {
        final content = await skillMdFile.readAsString();
        final skill = await _parseSkillFromDir(entity.path, content);

        if (skill != null) {
          // 不覆盖同名的内置 skill
          final existing = SkillRegistry.instance.getSkill(skill.name);
          if (existing != null && existing.source == SkillSource.builtin) {
            skipped.add('${skill.name} (与内置 skill 同名，保留内置版本)');
            continue;
          }

          SkillRegistry.instance.register(skill);
          loaded.add(skill.name);
        } else {
          skipped.add('${p.basename(entity.path)} (解析失败)');
        }
      } catch (e) {
        print('[skill] error: \$e');
        errors.add('${p.basename(entity.path)}: $e');
      }
    }

    return SkillLoadResult(
      loaded: loaded,
      skipped: skipped,
      errors: errors,
      totalScanned: scanned,
    );
  }

  /// 从 skill 目录解析完整 skill 数据
  static Future<Skill?> _parseSkillFromDir(String dirPath, String skillMdContent) async {
    final fm = _parseFrontmatter(skillMdContent);
    if (fm == null || fm.name == null || fm.name!.isEmpty) return null;

    // 提取 trigger keywords
    final triggerOn = _extractTriggerKeywords(fm.description ?? '', fm.body);

    // 解析 suggested_tools
    final toolsRaw = fm.fields['suggested_tools'] ?? '';
    final suggestedTools = toolsRaw.isNotEmpty
        ? toolsRaw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
        : <String>[];

    // 尝试加载 config.json
    Map<String, dynamic>? configJson;
    final configPath = p.join(dirPath, 'config.json');
    final configFile = File(configPath);
    if (configFile.existsSync()) {
      try {
        configJson = jsonDecode(await configFile.readAsString()) as Map<String, dynamic>?;
      } catch (_) {}
    }

    final isEnabled = fm.fields['enabled'] != 'false'; // 默认启用

    return Skill(
      name: fm.name!,
      description: fm.description ?? '',
      category: fm.category ?? 'external',
      origin: fm.origin ?? 'user',
      version: fm.version,
      systemPromptSnippet: fm.body.trim(),
      triggerOn: triggerOn,
      suggestedTools: suggestedTools,
      source: SkillSource.externalDirectory,
      directoryPath: dirPath,
      configJson: configJson,
      isEnabled: isEnabled,
    );
  }

  /// 从 SAF 客户端加载 skills
  static Future<SkillLoadResult> loadFromSaf({
    required dynamic safClient,
    required String safUri,
    required List<String> skillDirNames,
  }) async {
    final loaded = <String>[];
    final skipped = <String>[];
    final errors = <String>[];

    for (final dirName in skillDirNames) {
      try {
        // 读取 SKILL.md（路径格式：skills/dirName/SKILL.md）
        final content = await safClient.readFile(safUri, '$dirName/SKILL.md') as String;
        final skill = await _parseSkillFromDir('$safUri/$dirName', content);
        if (skill != null) {
          skill.source = SkillSource.saf;
          SkillRegistry.instance.register(skill);
          loaded.add(skill.name);
        } else {
          skipped.add(dirName);
        }
      } catch (e) {
        print('[skill] error: \$e');
        errors.add('$dirName: $e');
      }
    }

    return SkillLoadResult(
      loaded: loaded,
      skipped: skipped,
      errors: errors,
      totalScanned: skillDirNames.length,
    );
  }

  /// 从 SAF 客户端自动发现并加载 skills（扫描 skills/ 和 .claude/skills/ 目录）
  static Future<SkillLoadResult> loadFromSafAuto({
    required dynamic safClient,
    required String safUri,
  }) async {
    final dirNames = <String>[];
    for (final scanPath in scanPaths) {
      try {
        final dirs = await safClient.listDir(safUri, scanPath) as List<dynamic>?;
        if (dirs != null) {
          for (final d in dirs) {
            if (d is String) {
              dirNames.add('$scanPath/$d');
            }
          }
        }
      } catch (_) {}
    }
    if (dirNames.isEmpty) {
      return SkillLoadResult(loaded: [], skipped: [], errors: [], totalScanned: 0);
    }
    return loadFromSaf(safClient: safClient, safUri: safUri, skillDirNames: dirNames);
  }

  /// 重新扫描 — 清空外部 skills 后重新加载
  static Future<SkillLoadResult> reload(String workspacePath) async {
    SkillRegistry.instance.clearExternal();
    return loadFromWorkspace(workspacePath);
  }

  // ---- 解析 ----

  /// 解析 YAML frontmatter，返回字段 + body
  static SkillFrontmatter? _parseFrontmatter(String content) {
    final trimmed = content.trimLeft();
    if (!trimmed.startsWith('---')) return null;

    // 跳过第一个 ---
    final afterFirstDelim = trimmed.substring(3);
    final secondDelimIdx = _findFrontmatterEnd(afterFirstDelim);
    if (secondDelimIdx == -1) return null;

    final yamlBlock = afterFirstDelim.substring(0, secondDelimIdx);
    final body = afterFirstDelim.substring(secondDelimIdx + 3).trim();

    final fields = <String, String>{};
    _parseYamlKeyValues(yamlBlock, fields);

    return SkillFrontmatter(fields: fields, body: body, rawYaml: yamlBlock);
  }

  /// 找到第二个 `---` 的位置
  static int _findFrontmatterEnd(String text) {
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim() == '---') return text.indexOf('\n---');
    }
    // 备选：直接找 ---
    return text.indexOf('\n---');
  }

  /// 简易 YAML key: value 解析
  static void _parseYamlKeyValues(String block, Map<String, String> result) {
    for (final line in block.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      final colonIdx = trimmed.indexOf(':');
      if (colonIdx == -1) continue;

      final key = trimmed.substring(0, colonIdx).trim();
      var value = trimmed.substring(colonIdx + 1).trim();

      // 去引号
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }

      result[key] = value;
    }
  }

  /// 从 description + body 中提取触发关键词
  static List<String> _extractTriggerKeywords(String description, String body) {
    final keywords = <String>{};

    // 从 description 中提取 noun phrases
    final descWords = description
        .split(RegExp(r'[，,、\s]+'))
        .where((w) => w.length > 1)
        .toList();
    keywords.addAll(descWords);

    // 从 body 的 ## When to Activate 段落提取
    final activateSection = RegExp(
      r'##\s*When\s+to\s+Activate\s*\n(.*?)(?=\n##|\n---|$)',
      caseSensitive: false,
      dotAll: true,
    );
    final match = activateSection.firstMatch(body);
    if (match != null) {
      final section = match.group(1) ?? '';
      // 提取列表项
      final items = RegExp(r'[-*]\s+(.+)').allMatches(section);
      for (final item in items) {
        final text = item.group(1)?.toLowerCase() ?? '';
        // 提取关键名词
        final nouns = text
            .split(RegExp(r'\s+'))
            .where((w) => w.length > 2)
            .where((w) => !['the', 'and', 'for', 'when', 'that', 'this', 'with', 'use'].contains(w));
        keywords.addAll(nouns);
      }
    }

    return keywords.toList();
  }
}
