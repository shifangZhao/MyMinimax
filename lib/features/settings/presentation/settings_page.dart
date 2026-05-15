import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../../app/app.dart';
import '../../../core/permission/permission_manager.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../core/saf/saf_client.dart';
import '../../chat/presentation/chat_page.dart';
import '../../memory/presentation/memory_page.dart';
import '../../speech/presentation/tts_settings_page.dart';
import '../data/settings_repository.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../shared/utils/cache_cleaner.dart';
import '../../../core/mcp/mcp_registry.dart';
import '../../../core/mcp/mcp_client.dart';
import '../../../core/tools/mcp_tools.dart';
import '../../../core/tools/tool_registry.dart';
import '../../../core/tools/tool_module.dart';
import '../../../core/tools/browser_tools.dart';

final settingsRepositoryProvider = Provider((ref) => SettingsRepository());

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _apiKeyController = TextEditingController();
  final _apiKeyStandardController = TextEditingController();
  final _amapKeyController = TextEditingController();
  final _amapNativeKeyController = TextEditingController();
  final _kuaidi100CustomerController = TextEditingController();
  final _kuaidi100KeyController = TextEditingController();
  final _kuaidi100CallbackController = TextEditingController();
  String _selectedModel = SettingsRepository.defaultModel;
  double _temperature = SettingsRepository.defaultTemperature;
  int _inferenceTier = SettingsRepository.defaultInferenceTier;
  String _toolChoice = SettingsRepository.defaultToolChoice;
  bool _conciseMode = false;
  bool _isLoading = true;
  bool _obscureApiKey = true;
  bool _obscureApiKeyStandard = true;
  bool _obscureAmapKey = true;
  bool _obscureAmapNativeKey = true;
  bool _isLoadingQuota = false;
  QuotaInfo? _quotaInfo;
  String? _quotaError;
  String _safUri = '';
  String _keyType = '';
  String _keyTypeStandard = '';
  String _activeApiKeyType = 'token';
  ThemeMode _themeMode = ThemeMode.system;
  String _language = 'zh';

  bool _quotaExpanded = false;
  bool _apiModelExpanded = false;
  bool _thirdPartyExpanded = false;
  bool _obscureKuaidi100 = true;
  bool _infoExpanded = false;
  bool _avatarExpanded = false;
  bool _docsExpanded = false;
  bool _storageExpanded = false;
  bool _mcpExpanded = false;
  ({int count, int bytes})? _cacheSize;
  bool _cleaningCache = false;
  List<Map<String, dynamic>> _mcpServers = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadMcpServers();
    _loadCacheSize();
    _apiKeyController.addListener(_onSettingChanged);
    _amapKeyController.addListener(_onSettingChanged);
    _amapNativeKeyController.addListener(_onSettingChanged);
    _kuaidi100CustomerController.addListener(_onSettingChanged);
    _kuaidi100KeyController.addListener(_onSettingChanged);
    _kuaidi100CallbackController.addListener(_onSettingChanged);
  }

  @override
  void dispose() {
    _apiKeyController.removeListener(_onSettingChanged);
    _amapKeyController.removeListener(_onSettingChanged);
    _amapNativeKeyController.removeListener(_onSettingChanged);
    _kuaidi100CustomerController.removeListener(_onSettingChanged);
    _kuaidi100KeyController.removeListener(_onSettingChanged);
    _kuaidi100CallbackController.removeListener(_onSettingChanged);
    _apiKeyController.dispose();
    _apiKeyStandardController.dispose();
    _amapKeyController.dispose();
    _amapNativeKeyController.dispose();
    _kuaidi100CustomerController.dispose();
    _kuaidi100KeyController.dispose();
    _kuaidi100CallbackController.dispose();
    super.dispose();
  }

  void _onSettingChanged() {
    _autoSave();
  }

  Timer? _saveTimer;
  void _autoSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () {
      _saveSettings();
    });
  }

  Future<void> _loadSettings() async {
    final repo = ref.read(settingsRepositoryProvider);
    final apiKey = await repo.getApiKey();
    final apiKeyStandard = await repo.getApiKeyStandard();
    final amapKey = await repo.getAmapApiKey();
    final amapNativeKey = await repo.getAmapNativeApiKey();
    final kd100Customer = await repo.getKuaidi100Customer();
    final kd100Key = await repo.getKuaidi100Key();
    final kd100Callback = await repo.getKuaidi100CallbackUrl();
    final activeType = await repo.getActiveApiKeyType();
    final model = await repo.getModel();
    final safUri = await repo.getSafUri();
    final themeMode = await repo.getThemeMode();
    final language = await repo.getLanguage();
    final temperature = await repo.getTemperature();
    final inferenceTier = await repo.getInferenceTier();
    final toolChoice = await repo.getToolChoice();
    final conciseMode = await repo.getConciseMode();

    if (mounted) {
      setState(() {
        _apiKeyController.text = apiKey;
        _apiKeyStandardController.text = apiKeyStandard;
        _amapKeyController.text = amapKey;
        _amapNativeKeyController.text = amapNativeKey;
        _kuaidi100CustomerController.text = kd100Customer;
        _kuaidi100KeyController.text = kd100Key;
        _kuaidi100CallbackController.text = kd100Callback;
        _activeApiKeyType = activeType;
        _selectedModel = model;
        _safUri = safUri;
        _themeMode = themeMode;
        _language = language;
        _temperature = temperature;
        _inferenceTier = inferenceTier;
        _toolChoice = toolChoice;
        _conciseMode = conciseMode;
        _isLoading = false;
      });
      if (apiKey.isNotEmpty) {
        _keyType = MinimaxClient.getKeyType(apiKey);
      }
      if (apiKeyStandard.isNotEmpty) {
        _keyTypeStandard = MinimaxClient.getKeyType(apiKeyStandard);
      }
    }
  }

  Future<void> _loadCacheSize() async {
    try {
      final info = await CacheCleaner.scanSize();
      if (mounted) setState(() => _cacheSize = info);
    } catch (_) {}
  }

  Future<void> _clearCache() async {
    setState(() => _cleaningCache = true);
    try {
      final info = await CacheCleaner.cleanAll();
      if (mounted) {
        setState(() {
          _cleaningCache = false;
          _cacheSize = (count: 0, bytes: 0);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已清理 ${info.deletedCount} 个缓存项 (${_formatBytes(info.freedBytes)})')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cleaningCache = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清理失败: $e')),
        );
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
  }

  Future<void> _loadMcpServers() async {
    final repo = ref.read(settingsRepositoryProvider);
    final servers = await repo.getMcpServersConfig();
    if (mounted) setState(() => _mcpServers = servers);
  }

  int get _mcpConnectedCount {
    int count = 0;
    for (final s in _mcpServers) {
      final name = s['name'] as String? ?? '';
      if (McpRegistry.instance.getServer(name)?.health.isConnected == true) count++;
    }
    return count;
  }

  Future<void> _refreshMcpHealth() async {
    try { await McpRegistry.instance.checkAllHealth(); } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _refreshQuota() async {
    setState(() {
      _isLoadingQuota = true;
      _quotaError = null;
    });
    try {
      final repo = ref.read(settingsRepositoryProvider);
      final apiKey = await repo.getActiveApiKey();
      if (apiKey.isEmpty) return;

      final tempClient = MinimaxClient(apiKey: apiKey);
      final quota = await tempClient.getQuota();
      ref.read(quotaInfoProvider.notifier).setQuota(quota);
      if (mounted) setState(() => _quotaInfo = quota);
    } catch (e) {
      print('[settings] error: \$e');
      if (mounted) setState(() => _quotaError = e.toString());
    } finally {
      if (mounted) setState(() => _isLoadingQuota = false);
    }
  }

  Future<void> _saveSettings() async {
    try {
      final repo = ref.read(settingsRepositoryProvider);
      await repo.setApiKey(_apiKeyController.text.trim());
      await repo.setApiKeyStandard(_apiKeyStandardController.text.trim());
      await repo.setAmapApiKey(_amapKeyController.text.trim());
      await repo.setAmapNativeApiKey(_amapNativeKeyController.text.trim());
      await repo.setKuaidi100Customer(_kuaidi100CustomerController.text.trim());
      await repo.setKuaidi100Key(_kuaidi100KeyController.text.trim());
      await repo.setKuaidi100CallbackUrl(_kuaidi100CallbackController.text.trim());
      await repo.setActiveApiKeyType(_activeApiKeyType);
      await repo.setModel(_selectedModel);
      await repo.setTemperature(_temperature);
      await repo.setInferenceTier(_inferenceTier);
      await repo.setToolChoice(_toolChoice);
      await repo.setConciseMode(_conciseMode);
      ref.read(settingsChangedProvider.notifier).notify();
      ref.read(minimaxClientProvider.notifier).switchApiKey(_activeApiKeyType);
    } catch (_) {}
  }

  Future<void> _pickSafDirectory() async {
    if (!SafClient.isSupported) return;
    final safClient = SafClient();
    final uri = await safClient.pickDirectory();
    if (uri == null) return;
    final persisted = await safClient.persistUriPermission(uri);
    if (!persisted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('权限持久化失败'), backgroundColor: PixelTheme.error),
        );
      }
      return;
    }
    final repo = ref.read(settingsRepositoryProvider);
    await repo.setSafUri(uri);
    if (mounted) {
      setState(() => _safUri = uri);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('外部存储已授权'), backgroundColor: PixelTheme.brandBlue),
      );
      ref.read(settingsChangedProvider.notifier).notify();
    }
  }

  Future<void> _clearSafUri() async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.clearSafUri();
    if (mounted) {
      setState(() => _safUri = '');
      ref.read(settingsChangedProvider.notifier).notify();
    }
  }

  String _t(String key, {String fallback = ''}) {
    final i18n = ref.read(i18nProvider);
    if (i18n == null) return fallback.isNotEmpty ? fallback : key;
    final result = i18n.t(key);
    return result == key && fallback.isNotEmpty ? fallback : result;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final i18n = ref.watch(i18nProvider); // 语言切换时触发重建
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            PageHeader(icon: Icons.settings_outlined, title: _t('settings.title', fallback: '设置'), showDivider: true),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: PixelTheme.brandBlue))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildThemeAndLanguageCard(isDark),
                          const SizedBox(height: 12),
                          _buildAvatarRowCollapsible(isDark),
                          const SizedBox(height: 12),
                          _buildApiModelInferenceCard(isDark),
                          const SizedBox(height: 12),
                          _buildQuotaCardCollapsible(isDark),
                          const SizedBox(height: 12),
                          _buildThirdPartyApiCard(isDark),
                          const SizedBox(height: 12),
                          _buildMemoryCard(isDark),
                          const SizedBox(height: 12),
                          _buildMcpCard(isDark),
                          if (Platform.isAndroid) ...[
                            const SizedBox(height: 12),
                            _buildStorageCardCollapsible(isDark),
                          ],
                          const SizedBox(height: 12),
                          _DocsCard(isDark: isDark, onToggle: () => setState(() => _docsExpanded = !_docsExpanded), expanded: _docsExpanded),
                          const SizedBox(height: 12),
                          _buildInfoCardCollapsible(isDark),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildSection({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: PixelTheme.primaryText)),
        const SizedBox(height: 14),
        ...children,
      ],
    );
  }

  Widget _buildThemeAndLanguageCard(bool isDark) {
    final primaryTextColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText;

    return PixelCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 主题行 — 标签左，Chip 右
          Row(
            children: [
              Text(_t('settings.theme', fallback: '主题'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primaryTextColor)),
              const SizedBox(width: 12),
              _buildMiniChip(icon: Icons.brightness_auto, label: _t('settings.theme_auto', fallback: '自动'), isSelected: _themeMode == ThemeMode.system, onTap: () { setState(() => _themeMode = ThemeMode.system); ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.system); }, isDark: isDark),
              const SizedBox(width: 6),
              _buildMiniChip(icon: Icons.light_mode, label: _t('settings.theme_light', fallback: '浅色'), isSelected: _themeMode == ThemeMode.light, onTap: () { setState(() => _themeMode = ThemeMode.light); ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.light); }, isDark: isDark),
              const SizedBox(width: 6),
              _buildMiniChip(icon: Icons.dark_mode, label: _t('settings.theme_dark', fallback: '深色'), isSelected: _themeMode == ThemeMode.dark, onTap: () { setState(() => _themeMode = ThemeMode.dark); ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark); }, isDark: isDark),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: PixelTheme.border),
          ),
          // 语言行
          Row(
            children: [
              Text(_t('settings.language', fallback: '语言'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primaryTextColor)),
              const SizedBox(width: 12),
              _buildMiniChip(label: '简体中文', isSelected: _language == 'zh', onTap: () { setState(() => _language = 'zh'); ref.read(i18nProvider.notifier).switchLanguage('zh'); }, isDark: isDark),
              const SizedBox(width: 6),
              _buildMiniChip(label: 'English', isSelected: _language == 'en', onTap: () { setState(() => _language = 'en'); ref.read(i18nProvider.notifier).switchLanguage('en'); }, isDark: isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniChip({IconData? icon, required String label, required bool isSelected, required VoidCallback onTap, required bool isDark}) {
    final secondaryTextColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? PixelTheme.brandBlue : (isDark ? PixelTheme.darkSurface : PixelTheme.background),
          borderRadius: BorderRadius.circular(PixelTheme.radiusSmall),
          border: Border.all(color: isSelected ? PixelTheme.brandBlue : (isDark ? PixelTheme.darkBorderDefault : PixelTheme.border)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: isSelected ? Colors.white : secondaryTextColor),
              const SizedBox(width: 4),
            ],
            Text(label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal, color: isSelected ? Colors.white : secondaryTextColor)),
          ],
        ),
      ),
    );
  }


  Widget _buildAvatarRowCollapsible(bool isDark) {
    final userPath = ref.watch(userAvatarProvider);
    final agentPath = ref.watch(agentAvatarProvider);
    final primaryTextColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText;
    final secondaryTextColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText;

    return PixelCard(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(PixelTheme.radiusCard),
            onTap: () => setState(() => _avatarExpanded = !_avatarExpanded),
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Icon(Icons.face_outlined, size: 20, color: PixelTheme.primary),
                const SizedBox(width: 12),
                Expanded(child: Text('头像', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: primaryTextColor))),
                AnimatedRotation(turns: _avatarExpanded ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: Icon(Icons.keyboard_arrow_down, color: secondaryTextColor)),
              ]),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildAvatarPicker(
                    label: '用户',
                    imagePath: userPath,
                    isDark: isDark,
                    onTap: () => _pickAvatar(isAgent: false),
                    onClear: userPath.isNotEmpty ? () => _clearAvatar(isAgent: false) : null,
                  ),
                  _buildAvatarPicker(
                    label: '智能体',
                    imagePath: agentPath,
                    isDark: isDark,
                    onTap: () => _pickAvatar(isAgent: true),
                    onClear: agentPath.isNotEmpty ? () => _clearAvatar(isAgent: true) : null,
                  ),
                ],
              ),
            ),
            crossFadeState: _avatarExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarPicker({
    required String label,
    required String imagePath,
    required bool isDark,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    final primaryColor = isDark ? PixelTheme.darkPrimary : PixelTheme.primary;
    final hasCustom = imagePath.isNotEmpty && File(imagePath).existsSync();

    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Stack(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: primaryColor.withValues(alpha: 0.3), width: 1),
                color: isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant,
              ),
              clipBehavior: Clip.antiAlias,
              child: hasCustom
                  ? Image.file(File(imagePath), fit: BoxFit.cover)
                  : Icon(Icons.person, size: 32, color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 20, height: 20,
                decoration: BoxDecoration(
                  color: primaryColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.edit, size: 12, color: Colors.white),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 12, color: isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText)),
        if (onClear != null) ...[
          const SizedBox(height: 2),
          GestureDetector(
            onTap: onClear,
            child: Text('清除', style: TextStyle(fontSize: 11, color: PixelTheme.error.withValues(alpha: 0.7))),
          ),
        ],
      ]),
    );
  }

  Future<void> _pickAvatar({required bool isAgent}) async {
    try {
      final ok = await PermissionManager().request(context, AppPermission.storage);
      if (!ok) return;
      final picker = ImagePicker();
      final xFile = await picker.pickImage(source: ImageSource.gallery);
      if (xFile == null) return;

      final imageBytes = await xFile.readAsBytes();
      if (!mounted) return;

      // 显示交互式裁剪界面
      final croppedBytes = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _CropDialog(imageBytes: imageBytes, title: isAgent ? '裁剪智能体头像' : '裁剪用户头像'),
      );
      if (croppedBytes == null || !mounted) return;

      final dir = await getApplicationDocumentsDirectory();
      final name = isAgent ? 'agent_avatar.png' : 'user_avatar.png';
      final dest = File('${dir.path}/$name');
      await dest.writeAsBytes(croppedBytes);

      final repo = ref.read(settingsRepositoryProvider);
      if (isAgent) {
        await repo.setAgentAvatarPath(dest.path);
        ref.read(agentAvatarProvider.notifier).state = dest.path;
      } else {
        await repo.setUserAvatarPath(dest.path);
        ref.read(userAvatarProvider.notifier).state = dest.path;
      }
    } catch (e) {
      print('[settings] error: \$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('设置头像失败: $e'), backgroundColor: PixelTheme.error),
        );
      }
    }
  }

  Future<void> _clearAvatar({required bool isAgent}) async {
    final repo = ref.read(settingsRepositoryProvider);
    if (isAgent) {
      await repo.setAgentAvatarPath('');
      ref.read(agentAvatarProvider.notifier).state = '';
    } else {
      await repo.setUserAvatarPath('');
      ref.read(userAvatarProvider.notifier).state = '';
    }
  }

  Widget _buildModernTextField({required TextEditingController controller, required String label, required String hint, bool obscureText = false, Widget? suffix, ValueChanged<String>? onChanged, bool isDark = false}) {
    final secondaryTextColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText;
    final surfaceVariantColor = isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: secondaryTextColor)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscureText,
          style: TextStyle(fontSize: 14, color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText),
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: suffix,
            filled: true,
            fillColor: surfaceVariantColor.withValues(alpha: 0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: PixelTheme.brandBlue, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildApiKeySelector(bool isDark) {
    final secondaryTextColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_t('settings.api_key_type', fallback: 'API Key 类型'), style: TextStyle(fontSize: 13, color: secondaryTextColor)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildKeyTypeChip(
                icon: Icons.verified,
                label: 'Token Plan',
                isSelected: _activeApiKeyType == 'token',
                onTap: () {
                  setState(() => _activeApiKeyType = 'token');
                  _saveSettings();
                },
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKeyTypeChip(
                icon: Icons.key,
                label: 'Standard',
                isSelected: _activeApiKeyType == 'standard',
                onTap: () {
                  setState(() => _activeApiKeyType = 'standard');
                  _saveSettings();
                },
                isDark: isDark,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKeyTypeChip({required IconData icon, required String label, required bool isSelected, required VoidCallback onTap, required bool isDark}) {
    final secondaryTextColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText;
    final bgColor = isDark ? PixelTheme.darkSurface : PixelTheme.background;
    final borderColor = isDark ? PixelTheme.darkBorderDefault : PixelTheme.border;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? PixelTheme.brandBlue : bgColor,
          borderRadius: BorderRadius.circular(PixelTheme.radiusCard),
          border: Border.all(color: isSelected ? PixelTheme.brandBlue : borderColor),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: isSelected ? Colors.white : secondaryTextColor),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal, color: isSelected ? Colors.white : secondaryTextColor)),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildKeyTypeBadge(String keyType) {
    final isTokenPlan = keyType.contains('Token Plan');
    final color = isTokenPlan ? PixelTheme.brandBlue : PixelTheme.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(PixelTheme.radiusSmall),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isTokenPlan ? Icons.verified : Icons.paypal, size: 18, color: color),
          const SizedBox(width: 10),
          Text('类型: $keyType', style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildKeyTypeBadgeMini(String keyType) {
    final isTokenPlan = keyType.contains('Token Plan');
    final color = isTokenPlan ? PixelTheme.brandBlue : PixelTheme.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(PixelTheme.radiusSmall),
      ),
      child: Text(
        keyType,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildKeyMismatchWarning(bool isDark, {required bool expectTokenPlan}) {
    const warningColor = PixelTheme.warning;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: warningColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(PixelTheme.radiusSmall),
          border: Border.all(color: warningColor.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, size: 18, color: warningColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                expectTokenPlan
                    ? '当前为 Token Plan 模式，需要 sk-cp- 开头的密钥。你输入的是按量付费密钥，无法使用 Token Plan 功能。'
                    : '当前为 Standard API 模式，需要 sk- 开头的按量付费密钥。你输入的是 Token Plan 密钥，请切换到 Token Plan 模式使用。',
                maxLines: 3, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: warningColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuotaCardCollapsible(bool isDark) {
    final planLevel = _detectPlanLevel();
    final planColor = _getPlanColor(planLevel);
    final primaryTextColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText;
    final secondaryTextColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText;

    return PixelCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(PixelTheme.radiusCard),
            onTap: () => setState(() => _quotaExpanded = !_quotaExpanded),
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.analytics_outlined, size: 20, color: PixelTheme.brandBlue),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_t('settings.quota', fallback: 'TokenPlan 配额'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: primaryTextColor))),
                  IconButton(
                    icon: _RefreshIcon(isRefreshing: _isLoadingQuota),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: _isLoadingQuota ? null : _refreshQuota,
                    tooltip: _t('settings.quota_refresh', fallback: '刷新配额'),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: planColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                    child: Text(planLevel, style: TextStyle(fontSize: 12, color: planColor, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(turns: _quotaExpanded ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: Icon(Icons.keyboard_arrow_down, color: secondaryTextColor)),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: ClipRect(child: _buildQuotaDetails(isDark)),
            crossFadeState: _quotaExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildQuotaDetails(bool isDark) {
    final primaryTextColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText;
    final secondaryTextColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText;
    final bgColor = isDark ? PixelTheme.darkBase : PixelTheme.background;
    if (_quotaInfo == null || _quotaInfo!.models.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Center(
          child: Text(
            _quotaError ?? '点击刷新按钮加载配额信息',
            style: TextStyle(fontSize: 13, color: _quotaError != null ? PixelTheme.error : (isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted)),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: _quotaInfo!.models.map((m) {
          final pct = m.usagePercent;
          final usedColor = pct > 0.8 ? PixelTheme.error : (pct > 0.5 ? PixelTheme.warning : PixelTheme.brandBlue);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(m.modelName, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: primaryTextColor), overflow: TextOverflow.ellipsis)),
                    Text('${m.currentIntervalUsage} / ${m.currentIntervalTotal}', style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(value: pct, backgroundColor: bgColor, valueColor: AlwaysStoppedAnimation(usedColor), minHeight: 5),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('本周: ${m.currentWeeklyUsage}', style: TextStyle(fontSize: 10, color: secondaryTextColor)),
                    Text('剩余: ${m.remaining}', style: TextStyle(fontSize: 10, color: usedColor)),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildModelList(bool isDark) {
    final primaryTextColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText;
    final secondaryTextColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText;
    final cardBgColor = isDark ? PixelTheme.darkSurface : PixelTheme.cardBackground;
    final borderColor = isDark ? PixelTheme.darkBorderSubtle : PixelTheme.border;
    return Container(
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(PixelTheme.radiusCard),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: SettingsRepository.availableModels.asMap().entries.map((entry) {
          final index = entry.key;
          final model = entry.value;
          final isSelected = _selectedModel == model;

          return Column(
            children: [
              if (index > 0) Divider(height: 1, indent: 16, endIndent: 16, color: borderColor),
              InkWell(
                onTap: () {
                  setState(() {
                    _selectedModel = model;
                    _apiModelExpanded = false;
                  });
                  _autoSave();
                },
                highlightColor: Colors.transparent,
                splashColor: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? PixelTheme.brandBlue : Colors.transparent,
                          border: Border.all(color: isSelected ? PixelTheme.brandBlue : secondaryTextColor, width: 2),
                        ),
                        child: isSelected ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(model, style: TextStyle(fontSize: 14, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal, color: isSelected ? PixelTheme.brandBlue : primaryTextColor)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }


  Widget _buildSegmentedSelector({
    required List<int> values,
    required int selected,
    required String Function(int) formatLabel,
    required ValueChanged<int> onChanged,
    required bool isDark,
  }) {
    final secondaryTextColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText;
    final surfaceVariantColor = isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values.map((v) {
        final isSelected = selected == v;
        return GestureDetector(
          onTap: () => onChanged(v),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? PixelTheme.brandBlue : surfaceVariantColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(formatLabel(v), style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal, color: isSelected ? Colors.white : secondaryTextColor)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildToolChoiceSelector(bool isDark) {
    final primaryTextColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText;
    final secondaryTextColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText;
    final options = [
      {'value': 'auto', 'label': _t('settings.tool_choice_auto', fallback: 'Auto'), 'desc': _t('settings.tool_choice_auto_desc', fallback: '模型自动决定是否调用工具')},
      {'value': 'any', 'label': _t('settings.tool_choice_any', fallback: 'Any'), 'desc': _t('settings.tool_choice_any_desc', fallback: '强制至少使用一个工具')},
    ];
    return Column(
      children: options.map((opt) {
        final isSelected = _toolChoice == opt['value'];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () {
              setState(() => _toolChoice = opt['value']!);
              _autoSave();
            },
            child: Row(
              children: [
                Container(
                  width: 20, height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? PixelTheme.brandBlue : Colors.transparent,
                    border: Border.all(color: isSelected ? PixelTheme.brandBlue : secondaryTextColor, width: 2),
                  ),
                  child: isSelected ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(opt['label']!, style: TextStyle(fontSize: 14, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal, color: isSelected ? PixelTheme.brandBlue : primaryTextColor)),
                  Text(opt['desc']!, style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                ])),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInferenceTierSelector(bool isDark) {
    final secondaryTextColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText;
    final surfaceVariantColor = isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: SettingsRepository.inferenceTiers.asMap().entries.map((entry) {
            final index = entry.key;
            final tier = entry.value;
            final isSelected = _inferenceTier == index;
            return GestureDetector(
              onTap: () {
                setState(() => _inferenceTier = index);
                _autoSave();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? PixelTheme.brandBlue : surfaceVariantColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tier.name, style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal, color: isSelected ? Colors.white : secondaryTextColor)),
                    const SizedBox(height: 2),
                    Text('${(tier.maxTokens / 1000).toStringAsFixed(0)}K / 思考${(tier.thinkingBudget / 1000).toStringAsFixed(1)}K', style: TextStyle(fontSize: 10, color: isSelected ? Colors.white70 : (isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted))),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Text('思考预算 = 最大Token × 35%，输出预留 65%', style: TextStyle(fontSize: 10, color: secondaryTextColor)),
      ],
    );
  }
  Widget _buildApiModelInferenceCard(bool isDark) {
    final primaryTextColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText;
    final secondaryTextColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText;

    return PixelCard(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(PixelTheme.radiusCard),
            onTap: () => setState(() => _apiModelExpanded = !_apiModelExpanded),
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.smart_toy_outlined, size: 20, color: PixelTheme.brandBlue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('模型配置', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: primaryTextColor)),
                        const SizedBox(height: 2),
                        Text(_selectedModel, style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                      ],
                    ),
                  ),
                  if (_activeApiKeyType == 'token' && _keyType.isNotEmpty)
                    _buildKeyTypeBadgeMini(_keyType)
                  else if (_activeApiKeyType == 'standard' && _keyTypeStandard.isNotEmpty)
                    _buildKeyTypeBadgeMini(_keyTypeStandard),
                  const SizedBox(width: 8),
                  AnimatedRotation(turns: _apiModelExpanded ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: Icon(Icons.keyboard_arrow_down, color: secondaryTextColor)),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: ClipRect(child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // === API 配置 ===
                  Text(_t('settings.api_config', fallback: 'API 配置'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryTextColor)),
                  const SizedBox(height: 12),
                  _buildApiKeySelector(isDark),
                  const SizedBox(height: 12),
                  if (_activeApiKeyType == 'token') ...[
                    _buildModernTextField(
                      controller: _apiKeyController,
                      label: 'Token Plan Key (sk-cp-xxx)',
                      hint: '输入 Token Plan API Key',
                      obscureText: _obscureApiKey,
                      onChanged: (value) => setState(() => _keyType = MinimaxClient.getKeyType(value)),
                      suffix: IconButton(
                        icon: Icon(_obscureApiKey ? Icons.visibility_off : Icons.visibility, size: 20, color: secondaryTextColor),
                        onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                      ),
                      isDark: isDark,
                    ),
                    if (_apiKeyController.text.isNotEmpty && !MinimaxClient.isTokenPlanKey(_apiKeyController.text))
                      _buildKeyMismatchWarning(isDark, expectTokenPlan: true),
                  ] else ...[
                    _buildModernTextField(
                      controller: _apiKeyStandardController,
                      label: 'Standard API Key',
                      hint: '输入标准 API Key',
                      obscureText: _obscureApiKeyStandard,
                      onChanged: (value) => setState(() => _keyTypeStandard = MinimaxClient.getKeyType(value)),
                      suffix: IconButton(
                        icon: Icon(_obscureApiKeyStandard ? Icons.visibility_off : Icons.visibility, size: 20, color: secondaryTextColor),
                        onPressed: () => setState(() => _obscureApiKeyStandard = !_obscureApiKeyStandard),
                      ),
                      isDark: isDark,
                    ),
                    if (_apiKeyStandardController.text.isNotEmpty && MinimaxClient.isTokenPlanKey(_apiKeyStandardController.text))
                      _buildKeyMismatchWarning(isDark, expectTokenPlan: false),
                  ],
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1, color: PixelTheme.border),
                  ),
                  // === 当前模型 ===
                  Text(_t('settings.current_model', fallback: '当前模型'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryTextColor)),
                  const SizedBox(height: 8),
                  _buildModelList(isDark),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1, color: PixelTheme.border),
                  ),
                  // === 推理参数 ===
                  Text(_t('settings.inference_params', fallback: '推理参数'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryTextColor)),
                  const SizedBox(height: 12),
                  // Temperature
                  Text(_t('settings.temperature', fallback: '温度 (Temperature)'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryTextColor)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _temperature,
                          min: 0.1, max: 1.0, divisions: 9,
                          activeColor: PixelTheme.brandBlue,
                          onChanged: (v) {
                            setState(() => _temperature = double.parse(v.toStringAsFixed(1)));
                            _autoSave();
                          },
                        ),
                      ),
                      SizedBox(width: 48, child: Text(_temperature.toStringAsFixed(1), textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primaryTextColor))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 推理挡位
                  Text(_t('settings.inference_tier', fallback: '推理挡位'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryTextColor)),
                  const SizedBox(height: 8),
                  _buildInferenceTierSelector(isDark),
                  const SizedBox(height: 16),
                  // 精简模式
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('精简模式', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryTextColor)),
                            Text('去掉客套话，直接给结论', style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                          ],
                        ),
                      ),
                      Switch(
                        value: _conciseMode,
                        activeThumbColor: PixelTheme.brandBlue,
                        onChanged: (v) {
                          setState(() => _conciseMode = v);
                          _autoSave();
                        },
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1, color: PixelTheme.border),
                  ),
                  // === 聊天语音播报 ===
                  _buildTtsInline(isDark),
                ],
              ),
            )),
            crossFadeState: _apiModelExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildTtsInline(bool isDark) {
    final ttsEnabled = ref.watch(ttsEnabledProvider);
    final ttsVoice = ref.watch(ttsVoiceProvider);
    final primaryTextColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText;
    final secondaryTextColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText;

    void openTtsSettings() {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const TtsSettingsPage()));
    }

    return GestureDetector(
      onTap: openTtsSettings,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('聊天语音播报', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryTextColor)),
                const SizedBox(height: 2),
                Text(
                  ttsEnabled ? '已开启 · $ttsVoice' : '已关闭 — 点击配置',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: secondaryTextColor),
                ),
                Text(
                  '使用 Token Plan 包含的模型服务，无需额外付费',
                  style: TextStyle(fontSize: 10, color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted),
                ),
              ],
            ),
          ),
          Switch(
            value: ttsEnabled,
            activeThumbColor: PixelTheme.primary,
            onChanged: (v) { ref.read(ttsEnabledProvider.notifier).state = v; SettingsRepository().setTtsEnabled(v); },
          ),
        ],
      ),
    );
  }

  Widget _buildThirdPartyApiCard(bool isDark) {
    final primaryTextColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText;
    final secondaryTextColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText;

    final amapConfigured = _amapKeyController.text.isNotEmpty || _amapNativeKeyController.text.isNotEmpty;
    final kdConfigured = _kuaidi100CustomerController.text.isNotEmpty;

    return PixelCard(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(PixelTheme.radiusCard),
            onTap: () => setState(() => _thirdPartyExpanded = !_thirdPartyExpanded),
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.api_outlined, size: 20, color: PixelTheme.success),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('第三方 API', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: primaryTextColor)),
                        const SizedBox(height: 2),
                        Text(
                          '${amapConfigured ? '高德已配置' : '高德未配置'} · ${kdConfigured ? '快递100已配置' : '快递100未配置'}',
                          style: TextStyle(fontSize: 12, color: secondaryTextColor),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(turns: _thirdPartyExpanded ? 0.5 : 0, duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.keyboard_arrow_down, color: secondaryTextColor)),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: ClipRect(child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 高德地图 API
                  Text('高德地图 API', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryTextColor)),
                  const SizedBox(height: 12),
                  _buildModernTextField(
                    controller: _amapKeyController,
                    label: 'Web服务 Key',
                    hint: '用于地图定位、导航路线规划等 HTTP API',
                    obscureText: _obscureAmapKey,
                    suffix: IconButton(
                      icon: Icon(_obscureAmapKey ? Icons.visibility_off : Icons.visibility, size: 20, color: secondaryTextColor),
                      onPressed: () => setState(() => _obscureAmapKey = !_obscureAmapKey),
                    ),
                    isDark: isDark,
                  ),
                  const SizedBox(height: 12),
                  _buildModernTextField(
                    controller: _amapNativeKeyController,
                    label: 'Android Native SDK Key',
                    hint: '用于高德地图 SDK（定位、导航、地图展示）',
                    obscureText: _obscureAmapNativeKey,
                    suffix: IconButton(
                      icon: Icon(_obscureAmapNativeKey ? Icons.visibility_off : Icons.visibility, size: 20, color: secondaryTextColor),
                      onPressed: () => setState(() => _obscureAmapNativeKey = !_obscureAmapNativeKey),
                    ),
                    isDark: isDark,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1, color: PixelTheme.border),
                  ),
                  // 快递100 API
                  Text('快递100 API', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryTextColor)),
                  const SizedBox(height: 12),
                  _buildModernTextField(
                    controller: _kuaidi100CustomerController,
                    label: 'customer（授权码）',
                    hint: '申请地址: api.kuaidi100.com',
                    obscureText: _obscureKuaidi100,
                    suffix: IconButton(
                      icon: Icon(_obscureKuaidi100 ? Icons.visibility_off : Icons.visibility, size: 20, color: secondaryTextColor),
                      onPressed: () => setState(() => _obscureKuaidi100 = !_obscureKuaidi100),
                    ),
                    isDark: isDark,
                  ),
                  const SizedBox(height: 10),
                  _buildModernTextField(
                    controller: _kuaidi100KeyController,
                    label: 'key（密钥）',
                    hint: '',
                    obscureText: _obscureKuaidi100,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 10),
                  _buildModernTextField(
                    controller: _kuaidi100CallbackController,
                    label: 'callbackUrl（推送回调，可选）',
                    hint: '例: https://your-server.com/kuaidi',
                    obscureText: false,
                    isDark: isDark,
                  ),
                ],
              ),
            )),
            crossFadeState: _thirdPartyExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryCard(bool isDark) {
    final primaryTextColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText;
    final secondaryTextColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText;

    return PixelCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(PixelTheme.radiusCard),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MemoryPage()),
          );
        },
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.psychology_outlined, size: 20, color: PixelTheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_t('settings.user_memory', fallback: '用户记忆'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: primaryTextColor)),
                    const SizedBox(height: 2),
                    Text('查看和管理AI学习的偏好与习惯', style: TextStyle(fontSize: 13, color: secondaryTextColor)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: secondaryTextColor),
            ],
          ),
        ),
      ),
    );
  }



  // ignore: unused_element
  Widget _buildStorageCard() {
    return PixelCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.sd_storage, size: 20, color: PixelTheme.brandBlue),
              SizedBox(width: 10),
              Expanded(child: Text('外部存储授权 (SAF)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            ],
          ),
          const SizedBox(height: 8),
          const Text('授权后文件将保存到外部目录，否则保存到应用私有目录', style: TextStyle(fontSize: 12, color: PixelTheme.secondaryText)),
          const SizedBox(height: 16),
          if (_safUri.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: PixelTheme.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(PixelTheme.radiusSmall),
                border: Border.all(color: PixelTheme.success.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, size: 18, color: PixelTheme.success),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('已授权外部目录', style: TextStyle(fontSize: 13, color: PixelTheme.success, fontWeight: FontWeight.w500))),
                  TextButton(onPressed: _clearSafUri, child: const Text('取消授权')),
                ],
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _pickSafDirectory,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('授权外部目录'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: PixelTheme.brandBlue,
                  side: const BorderSide(color: PixelTheme.brandBlue),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PixelTheme.radiusCode)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStorageCardCollapsible(bool isDark) {
    final primaryTextColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText;
    final secondaryTextColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText;

    return PixelCard(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(PixelTheme.radiusCard),
            onTap: () => setState(() => _storageExpanded = !_storageExpanded),
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.sd_storage, size: 20, color: PixelTheme.brandBlue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_t('settings.external_storage', fallback: '外部存储'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: primaryTextColor)),
                        const SizedBox(height: 2),
                        Text(
                          _safUri.isNotEmpty ? _t('settings.storage_authorized', fallback: '已授权') : _t('settings.storage_not_authorized', fallback: '未授权'),
                          style: TextStyle(fontSize: 13, color: secondaryTextColor),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(turns: _storageExpanded ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: Icon(Icons.keyboard_arrow_down, color: secondaryTextColor)),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: ClipRect(child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('授权后文件将保存到外部目录，否则保存到应用私有目录', style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                  const SizedBox(height: 16),
                  if (_safUri.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: PixelTheme.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(PixelTheme.radiusSmall),
                        border: Border.all(color: PixelTheme.success.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, size: 18, color: PixelTheme.success),
                          const SizedBox(width: 10),
                          const Expanded(child: Text('已授权外部目录', style: TextStyle(fontSize: 13, color: PixelTheme.success, fontWeight: FontWeight.w500))),
                          TextButton(onPressed: _clearSafUri, child: const Text('取消授权')),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _pickSafDirectory,
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: const Text('授权外部目录'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: PixelTheme.brandBlue,
                          side: const BorderSide(color: PixelTheme.brandBlue),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PixelTheme.radiusCode)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  // 缓存清理
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('应用缓存', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryTextColor)),
                        const SizedBox(height: 2),
                        Text(
                          _cacheSize != null ? '${_cacheSize!.count} 项 · ${_formatBytes(_cacheSize!.bytes)}' : '加载中...',
                          style: TextStyle(fontSize: 11, color: secondaryTextColor),
                        ),
                      ]),
                    ),
                    OutlinedButton(
                      onPressed: _cleaningCache ? null : _clearCache,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: PixelTheme.warning,
                        side: const BorderSide(color: PixelTheme.warning),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: _cleaningCache
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('清理缓存', style: TextStyle(fontSize: 12)),
                    ),
                  ]),
                ],
              ),
            )),
            crossFadeState: _storageExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildMcpCard(bool isDark) {
    final primaryTextColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText;
    final secondaryTextColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText;

    return PixelCard(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(PixelTheme.radiusCard),
            onTap: () {
              setState(() => _mcpExpanded = !_mcpExpanded);
              if (_mcpExpanded && _mcpServers.isNotEmpty) _refreshMcpHealth();
            },
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Icon(Icons.cloud_outlined, size: 20, color: Color(0xFF3B82F6)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('MCP 服务器', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: primaryTextColor)),
                    const SizedBox(height: 2),
                    Text(
                      _mcpServers.isEmpty ? '未配置 · 点击展开添加' : '${_mcpServers.length} 个服务器 · ${_mcpConnectedCount} 个在线',
                      style: TextStyle(fontSize: 12, color: secondaryTextColor),
                    ),
                  ]),
                ),
                AnimatedRotation(turns: _mcpExpanded ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: Icon(Icons.keyboard_arrow_down, color: secondaryTextColor)),
              ]),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: ClipRect(child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: (isDark ? PixelTheme.darkBase : const Color(0xFFF0F4FF)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.info_outline, size: 16, color: PixelTheme.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      'MCP 服务器可为 AI 提供额外工具能力。使用 JSON 模板一键配置，支持 HTTP transport。',
                      style: TextStyle(fontSize: 12, color: secondaryTextColor, height: 1.4),
                    )),
                  ]),
                ),
                if (_mcpServers.isNotEmpty) ...[
                  ..._mcpServers.map((s) => _buildMcpServerItem(s, isDark)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _refreshMcpHealth,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('检查连接', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: PixelTheme.brandBlue,
                          side: BorderSide(color: PixelTheme.brandBlue.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showMcpServerDialog(isDark),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('添加服务器', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: PixelTheme.primary,
                          side: BorderSide(color: PixelTheme.primary.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ]),
                ] else ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _showMcpServerDialog(isDark),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('添加 MCP 服务器', style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: PixelTheme.primary,
                        side: BorderSide(color: PixelTheme.primary.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ]),
            )),
            crossFadeState: _mcpExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildMcpServerItem(Map<String, dynamic> server, bool isDark) {
    final primaryTextColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText;
    final secondaryTextColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText;
    final surfaceVariantColor = isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant;
    final serverName = server['name'] as String? ?? '';
    final client = McpRegistry.instance.getServer(serverName);
    final connected = client?.health.isConnected == true;
    final toolCount = client?.tools.length ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceVariantColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: (isDark ? PixelTheme.darkBorderSubtle : PixelTheme.border).withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: connected ? PixelTheme.success : const Color(0xFF9CA3AF),
            boxShadow: connected ? [BoxShadow(color: PixelTheme.success.withValues(alpha: 0.5), blurRadius: 4)] : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(serverName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primaryTextColor)),
          Text(
            connected && toolCount > 0 ? '已连接 · $toolCount 个工具' : (connected ? '已连接' : '未连接'),
            style: TextStyle(fontSize: 11, color: secondaryTextColor),
          ),
        ])),
        InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => _showMcpServerDialog(isDark, existing: server),
          child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.edit_outlined, size: 18, color: secondaryTextColor)),
        ),
        const SizedBox(width: 4),
        InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => _deleteMcpServer(serverName),
          child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.delete_outline, size: 18, color: PixelTheme.error)),
        ),
      ]),
    );
  }

  Future<void> _showMcpServerDialog(bool isDark, {Map<String, dynamic>? existing}) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: isDark ? PixelTheme.darkSurface : PixelTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _McpServerSheet(isDark: isDark, existing: existing),
    );
    if (result != null && mounted) {
      final repo = ref.read(settingsRepositoryProvider);
      await repo.addMcpServer(result);
      await _syncMcpToRegistry(result);
      final servers = await repo.getMcpServersConfig();
      setState(() { _mcpServers = servers; _mcpExpanded = true; });
    }
  }

  Future<void> _syncMcpToRegistry(Map<String, dynamic> config) async {
    try {
      final serverConfig = McpServerConfig.fromJson(config['name'] as String, config);
      McpRegistry.instance.register(serverConfig);
      await McpRegistry.instance.discoverAllTools();
      final schemas = McpRegistry.instance.allToolSchemas;
      if (schemas.isNotEmpty) {
        ToolRegistry.instance.registerModule(McpToolModule.fromSchemas(schemas));
      }
    } catch (e) {
      debugPrint('[MCP] sync error: $e');
    }
  }

  Future<void> _deleteMcpServer(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除 MCP 服务器'),
        content: Text('确定要删除 "$name" 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('删除', style: TextStyle(color: PixelTheme.error))),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final repo = ref.read(settingsRepositoryProvider);
      await repo.removeMcpServer(name);
      McpRegistry.instance.unregister(name);
      final servers = await repo.getMcpServersConfig();
      setState(() => _mcpServers = servers);
    }
  }

  Widget _buildInfoCardCollapsible(bool isDark) {
    final primaryTextColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText;
    final secondaryTextColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText;

    return PixelCard(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(PixelTheme.radiusCard),
            onTap: () => setState(() => _infoExpanded = !_infoExpanded),
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 20, color: PixelTheme.brandBlue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(_t('settings.info', fallback: '说明'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: primaryTextColor)),
                  ),
                  AnimatedRotation(turns: _infoExpanded ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: Icon(Icons.keyboard_arrow_down, color: secondaryTextColor)),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: const ClipRect(child: Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(title: 'API Key 获取地址', value: 'https://platform.minimaxi.com', isLink: true),
                  SizedBox(height: 16),
                  _InfoTitle(title: '模型说明'),
                  _InfoBullet(text: 'M2.7: 旗舰模型，204800 token 上下文'),
                  _InfoBullet(text: 'M2.7-highspeed: 极速版，约100tps'),
                  _InfoBullet(text: 'M2.5: 顶尖性能与性价比'),
                  _InfoBullet(text: 'M2.1: 强大多语言编程能力'),
                  _InfoBullet(text: 'M2: 高效编码与Agent工作流'),
                  SizedBox(height: 12),
                  _InfoTitle(title: '计划要求'),
                  _InfoBullet(text: '基础模型 (M2系列): 基础额度'),
                  _InfoBullet(text: 'Plus 计划: 语音合成、图片生成'),
                  _InfoBullet(text: 'Max 计划: 视频生成、音乐生成'),
                ],
              ),
            )),
            crossFadeState: _infoExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildInfoCard() {
    return const PixelCard(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(title: 'API Key 获取地址', value: 'https://platform.minimaxi.com', isLink: true),
          SizedBox(height: 16),
          _InfoTitle(title: '模型说明'),
          _InfoBullet(text: 'M2.7: 旗舰模型，204800 token 上下文'),
          _InfoBullet(text: 'M2.7-highspeed: 极速版，约100tps'),
          _InfoBullet(text: 'M2.5: 顶尖性能与性价比'),
          _InfoBullet(text: 'M2.1: 强大多语言编程能力'),
          _InfoBullet(text: 'M2: 高效编码与Agent工作流'),
          SizedBox(height: 12),
          _InfoTitle(title: '计划要求'),
          _InfoBullet(text: '基础模型 (M2系列): 基础额度'),
          _InfoBullet(text: 'Plus 计划: 语音合成、图片生成'),
          _InfoBullet(text: 'Max 计划: 视频生成、音乐生成'),
        ],
      ),
    );
  }

  String _detectPlanLevel() {
    if (_quotaInfo == null) return '未知';
    final modelNames = _quotaInfo!.models.map((m) => m.modelName).toList();
    final hasVideo = modelNames.any((name) => name.toLowerCase().contains('hailuo') || name.toLowerCase().contains('s2v'));
    final hasMusic = modelNames.any((name) => name.toLowerCase().contains('music'));
    final hasSpeech = modelNames.any((name) => name.toLowerCase().contains('speech'));
    final hasImage = modelNames.any((name) => name.toLowerCase().contains('image'));
    if (hasVideo || hasMusic) return 'Max';
    if (hasSpeech || hasImage) return 'Plus';
    return '基础';
  }

  Color _getPlanColor(String plan) {
    switch (plan) {
      case 'Max':
        return PixelTheme.error;
      case 'Plus':
        return PixelTheme.warning;
      case '基础':
        return PixelTheme.brandBlue;
      default:
        return PixelTheme.secondaryText;
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.title, required this.value, this.isLink = false});
  final String title;
  final String value;
  final bool isLink;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText;
    final secondaryTextColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: secondaryTextColor)),
        const SizedBox(height: 4),
        SelectableText(value, style: TextStyle(fontSize: 13, color: isLink ? PixelTheme.brandBlue : primaryTextColor, decoration: isLink ? TextDecoration.underline : null)),
      ],
    );
  }
}

class _InfoTitle extends StatelessWidget {
  const _InfoTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryTextColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText;
    return Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: secondaryTextColor)));
  }
}

class _RefreshIcon extends StatefulWidget {

  const _RefreshIcon({required this.isRefreshing});
  final bool isRefreshing;

  @override
  State<_RefreshIcon> createState() => _RefreshIconState();
}

class _RefreshIconState extends State<_RefreshIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 600), vsync: this);
  }

  @override
  void didUpdateWidget(_RefreshIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRefreshing && !oldWidget.isRefreshing) {
      _controller.repeat();
    } else if (!widget.isRefreshing && oldWidget.isRefreshing) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: const Icon(Icons.refresh, size: 20, color: PixelTheme.secondaryText),
    );
  }
}

class _InfoBullet extends StatelessWidget {
  const _InfoBullet({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryTextColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('  • ', style: TextStyle(fontSize: 12, color: secondaryTextColor)),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: secondaryTextColor))),
        ],
      ),
    );
  }
}

class _DocsCard extends StatefulWidget {
  const _DocsCard({required this.isDark, required this.onToggle, required this.expanded});
  final bool isDark;
  final VoidCallback onToggle;
  final bool expanded;
  @override
  State<_DocsCard> createState() => _DocsCardState();
}

class _DocsCardState extends State<_DocsCard> {
  static const _sections = <_DocSection>[
    _DocSection(icon: Icons.chat_bubble_outline, title: '对话', items: [
      _DocItem('多会话管理', '左侧抽屉管理历史对话，切换、重命名、删除'),
      _DocItem('分支系统', '长按消息创建分支、回溯、编辑、重试，顶部切换'),
      _DocItem('上下文压缩', '对话过长时自动总结，输入 /压缩 手动触发'),
      _DocItem('消息编辑', '长按编辑后重发，自动创建分支保留原对话'),
      _DocItem('撤销回溯', '回溯后可一键撤销，文件操作协同回滚'),
      _DocItem('附件发送', '+ 号添加图片和文档，支持多文件同时发送'),
      _DocItem('流式输出', '逐字显示，可随时中断，中断后可继续'),
      _DocItem('思考模式', 'AI 推理过程以折叠卡片展示在回复上方'),
      _DocItem('消息渲染', 'Markdown 排版 + 代码高亮 + LaTeX 数学公式'),
      _DocItem('复制 / 重命名', '长按气泡复制内容，长按会话重命名'),
      _DocItem('自动滚动', '回复时自动跟随，手动上滑暂停，滑回底恢复'),
      _DocItem('Token 用量', '输入框下方显示用量 — 充裕/良好/紧张/临界'),
    ]),
    _DocSection(icon: Icons.mic, title: '语音', items: [
      _DocItem('离线语音输入', 'Vosk 本地识别，无需联网'),
      _DocItem('实时 TTS', '开启后 AI 回复按句流式播报，可随时停止，低延迟预取'),
      _DocItem('语音克隆', '上传 10s~5min 样本音频，克隆自定义声音'),
      _DocItem('AI 语音设计', '自然语言描述声线特征，自动生成定制声音'),
      _DocItem('语音历史', '所有合成音频自动保存，支持回放导出'),
    ]),
    _DocSection(icon: Icons.language, title: '浏览器', items: [
      _DocItem('内置浏览器', '多标签页、地址栏搜索、常规网页浏览'),
      _DocItem('Web Agent', 'AI 自主操控浏览器完成登录、填表、采集等任务'),
      _DocItem('浏览器工具', '点击/输入/滚动/截图/执行JS 等 16 种自动化操作'),
    ]),
    _DocSection(icon: Icons.auto_awesome, title: 'AI 工具箱', items: [
      _DocItem('图片生成', '文生图、图生图，多种比例风格，一次最多 9 张'),
      _DocItem('视频生成', '文生视频、图生视频、首尾帧、人物参考、模板'),
      _DocItem('音乐生成', '文生音乐、填词、伴奏、歌曲翻唱'),
      _DocItem('语音合成', '长文本异步合成，多音色切换'),
      _DocItem('图像理解', '上传图片让 AI 分析描述内容'),
      _DocItem('生成历史', '图片/视频/音乐独立历史页，预览回放保存'),
    ]),
    _DocSection(icon: Icons.folder_outlined, title: '文件系统', items: [
      _DocItem('工作目录', '设置中通过 SAF 授权外部存储目录'),
      _DocItem('文件工具', '读/写/改/删/移动/追加/列目录/glob/grep/创建目录'),
      _DocItem('文件回溯', '消息回溯时自动回滚 AI 所做的文件变更'),
      _DocItem('文件树', '顶部文件夹图标浏览工作目录结构'),
    ]),
    _DocSection(icon: Icons.search, title: '信息检索', items: [
      _DocItem('联网搜索', 'AI 调用 webSearch 获取最新信息'),
      _DocItem('网页抓取', 'fetchUrl 读取任意网页内容'),
      _DocItem('天气查询', '全球城市实时天气，7日预报/逐小时/AQI/预警'),
      _DocItem('世界时钟', '全球任意时区精确时间，自动使用设备时区'),
    ]),
    _DocSection(icon: Icons.phone_android, title: '手机原生', items: [
      _DocItem('通讯录', '搜索、查看详情、新建联系人'),
      _DocItem('日历', '查询日程、创建事件、删除事件'),
      _DocItem('电话', '拨打电话（需确认）、通话记录'),
      _DocItem('短信', '读取收件箱、发送短信（需确认）'),
      _DocItem('定位', '获取当前 GPS 位置'),
      _DocItem('悬浮窗', '其他 App 上方显示气泡，拖拽+点击回 App'),
      _DocItem('通知监听', '读取其他 App 通知内容（需系统设置授权）'),
    ]),
    _DocSection(icon: Icons.psychology, title: '智能体', items: [
      _DocItem('用户记忆', '自动学习偏好习惯，注入提示词。在设置中可查看和管理'),
      _DocItem('定时任务', '一次性/周期/倒计时，内联卡片创建，闹钟精确触发，开机恢复'),
      _DocItem('MCP 协议', 'JSON 模板一键配置，动态发现远程工具并注入对话'),
      _DocItem('技能系统', '兼容 Claude Code SKILL.md，意图匹配自动激活'),
      _DocItem('Hook 中间件', '8 个生命周期钩子 + 6 个内置安全处理器'),
      _DocItem('风险管控', '安全/标准/宽松三档，独立阻断确认阈值'),
    ]),
    _DocSection(icon: Icons.tips_and_updates, title: '提示', items: [
      _DocItem('提示词优化', '输入框右侧魔法棒，AI 帮你优化措辞再发送'),
      _DocItem('快捷回溯', '每条用户气泡上都有回溯按钮'),
      _DocItem('日志查看', '工具栏书签图标，查看引擎决策和错误'),
      _DocItem('模型与参数', '设置中切换模型、温度、Token、思考预算'),
      _DocItem('双密钥', '标准 API Key + Token 套餐 Key 可切换'),
      _DocItem('主题与语言', '深色/浅色、中文/英文随时切换'),
      _DocItem('输入优化', '点击输入框才弹键盘，切 Tab 自动收起，输入框紧贴键盘'),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final primaryTextColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText;
    final secondaryTextColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText;

    return PixelCard(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(PixelTheme.radiusCard),
            onTap: widget.onToggle,
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Icon(Icons.menu_book_outlined, size: 20, color: PixelTheme.primary),
                const SizedBox(width: 12),
                Expanded(child: Text('使用文档', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: primaryTextColor))),
                AnimatedRotation(turns: widget.expanded ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: Icon(Icons.keyboard_arrow_down, color: secondaryTextColor)),
              ]),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: ClipRect(child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              itemCount: _sections.length,
              itemBuilder: (ctx, i) => _buildSection(_sections[i], isDark, primaryTextColor, secondaryTextColor),
            )),
            crossFadeState: widget.expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(_DocSection s, bool isDark, Color titleColor, Color bodyColor) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 12, 12),
        leading: Icon(s.icon, size: 20, color: isDark ? PixelTheme.darkPrimary : PixelTheme.primary),
        title: Text(s.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: titleColor)),
        initiallyExpanded: false,
        shape: const Border(),
        children: s.items.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('• ', style: TextStyle(fontSize: 13, color: PixelTheme.textMuted)),
              Expanded(child: RichText(text: TextSpan(
                style: TextStyle(fontSize: 13, height: 1.6, color: bodyColor),
                children: [
                  TextSpan(text: item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: '  ${item.desc}', style: TextStyle(color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted)),
                ],
              ))),
            ],
          ),
        )).toList(),
      ),
    );
  }
}

class _DocSection {
  const _DocSection({required this.icon, required this.title, required this.items});
  final IconData icon;
  final String title;
  final List<_DocItem> items;
}

class _DocItem {
  const _DocItem(this.name, this.desc);
  final String name;
  final String desc;
}

/// 头像裁剪对话框 — 全屏 + 1:1 正方形
class _CropDialog extends StatefulWidget {
  const _CropDialog({required this.imageBytes, required this.title});
  final Uint8List imageBytes;
  final String title;

  @override
  State<_CropDialog> createState() => _CropDialogState();
}

class _CropDialogState extends State<_CropDialog> {
  final _controller = CropController();
  bool _isCropping = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? PixelTheme.darkBackground : Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isCropping)
            const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
          else
            IconButton(
              icon: const Icon(Icons.check, color: Colors.white),
              onPressed: () {
                setState(() => _isCropping = true);
                _controller.crop();
              },
            ),
        ],
      ),
      body: Crop(
        image: widget.imageBytes,
        controller: _controller,
        aspectRatio: 1.0,
        withCircleUi: false,
        interactive: true,
        maskColor: Colors.black87,
        onCropped: (result) {
          if (result is CropSuccess) {
            Navigator.pop(context, result.croppedImage);
          } else if (mounted) {
            setState(() => _isCropping = false);
          }
        },
      ),
    );
  }

}

// ═══════════════════════════════════════════
// MCP 服务器编辑表单 — JSON 模板模式
// ═══════════════════════════════════════════

const _mcpJsonTemplate = '{\n'
    '  "name": "my-server",\n'
    '  "url": "https://mcp.example.com/mcp",\n'
    '  "description": "服务器用途说明",\n'
    '  "timeout": 30,\n'
    '  "headers": {\n'
    '    "Authorization": "Bearer xxx"\n'
    '  }\n'
    '}';

class _McpServerSheet extends StatefulWidget {
  const _McpServerSheet({required this.isDark, this.existing});
  final bool isDark;
  final Map<String, dynamic>? existing;

  @override
  State<_McpServerSheet> createState() => _McpServerSheetState();
}

class _McpServerSheetState extends State<_McpServerSheet> {
  late final TextEditingController _jsonCtrl;
  bool _testing = false;
  String? _testResult;

  bool get _isEditing => widget.existing != null;
  bool get _isDark => widget.isDark;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      final json = <String, dynamic>{
        'name': e['name'] ?? '',
        'url': e['url'] ?? '',
      };
      if ((e['description'] as String?)?.isNotEmpty == true) json['description'] = e['description'];
      json['timeout'] = e['timeout'] ?? 30;
      if (e['headers'] != null && (e['headers'] as Map).isNotEmpty) json['headers'] = e['headers'];
      _jsonCtrl = TextEditingController(text: _prettyJson(json));
    } else {
      _jsonCtrl = TextEditingController(text: _mcpJsonTemplate);
    }
  }

  static String _prettyJson(Map<String, dynamic> json) => const JsonEncoder.withIndent('  ').convert(json);

  @override
  void dispose() {
    _jsonCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _parseJson() {
    try { return jsonDecode(_jsonCtrl.text.trim()) as Map<String, dynamic>; }
    catch (_) { return null; }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = _isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText;
    final textSecondary = _isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText;

    return Padding(
      padding: EdgeInsets.only(left: 24, right: 24, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: _isDark ? PixelTheme.darkBorderDefault : PixelTheme.border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Text(_isEditing ? '编辑 MCP 服务器' : '添加 MCP 服务器', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary))),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => Navigator.of(context).pop(),
              child: Container(width: 36, height: 36, decoration: BoxDecoration(color: textSecondary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(18)), child: Icon(Icons.close, size: 18, color: textSecondary)),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _jsonCtrl,
            maxLines: 14,
            style: TextStyle(fontSize: 13, fontFamily: 'monospace', color: textPrimary, height: 1.5),
            decoration: InputDecoration(
              filled: true,
              fillColor: _isDark ? PixelTheme.darkBase : PixelTheme.surfaceVariant,
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: PixelTheme.primary, width: 1.5)),
            ),
          ),
          const SizedBox(height: 12),
          if (_testResult != null)
            Container(
              width: double.infinity, padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: (_testResult!.startsWith('✓') ? PixelTheme.success : PixelTheme.error).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: (_testResult!.startsWith('✓') ? PixelTheme.success : PixelTheme.error).withValues(alpha: 0.3)),
              ),
              child: Text(_testResult!, style: TextStyle(fontSize: 13, color: textPrimary)),
            ),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _testing ? null : _testConnection,
                style: OutlinedButton.styleFrom(
                  foregroundColor: PixelTheme.primary,
                  side: BorderSide(color: PixelTheme.primary.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _testing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('测试连接', style: TextStyle(fontSize: 14)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _onSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: PixelTheme.primary, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(_isEditing ? '保存修改' : '添加', style: const TextStyle(fontSize: 14)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  void _onSave() {
    final json = _parseJson();
    if (json == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSON 格式错误'))); return; }
    final name = (json['name'] as String?)?.trim() ?? '';
    final url = (json['url'] as String?)?.trim() ?? '';
    if (name.isEmpty || url.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('name 和 url 为必填字段'))); return; }
    Navigator.of(context).pop({
      'name': name, 'url': url,
      'description': json['description'] as String? ?? '',
      'headers': json['headers'] is Map ? Map<String, String>.from((json['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()))) : {},
      'timeout': json['timeout'] is int ? json['timeout'] as int : 30,
    });
  }

  Future<void> _testConnection() async {
    final json = _parseJson();
    if (json == null) { setState(() => _testResult = '✗ JSON 格式错误'); return; }
    final url = (json['url'] as String?)?.trim() ?? '';
    if (url.isEmpty) { setState(() => _testResult = '✗ url 字段为空'); return; }
    setState(() { _testing = true; _testResult = null; });
    try {
      final config = McpServerConfig(
        name: (json['name'] as String?)?.trim() ?? '_test', url: url,
        headers: json['headers'] is Map ? Map<String, String>.from((json['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()))) : null,
        timeout: Duration(seconds: json['timeout'] is int ? json['timeout'] as int : 30),
      );
      final client = McpClient(config: config);
      await client.initialize();
      final discovered = await client.discoverTools();
      client.disconnect();
      if (mounted) setState(() { _testing = false; _testResult = '✓ 连接成功，发现 ${discovered.length} 个工具'; });
    } catch (e) {
      if (mounted) setState(() { _testing = false; _testResult = '✗ 连接失败: $e'; });
    }
  }
}