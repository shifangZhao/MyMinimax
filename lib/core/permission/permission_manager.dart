import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../../app/theme.dart';

/// 应用内所有可请求的权限类型
enum AppPermission {
  storage,
  camera,
  microphone,
  location,
  contacts,
  calendar,
  phoneCall,
  sms,
  overlay,
  notificationListener,
}

extension AppPermissionMeta on AppPermission {
  String get permissionName {
    switch (this) {
      case AppPermission.storage: return 'android.permission.READ_EXTERNAL_STORAGE';
      case AppPermission.camera: return 'android.permission.CAMERA';
      case AppPermission.microphone: return 'android.permission.RECORD_AUDIO';
      case AppPermission.location: return 'android.permission.ACCESS_FINE_LOCATION';
      case AppPermission.contacts: return 'android.permission.READ_CONTACTS';
      case AppPermission.calendar: return 'android.permission.READ_CALENDAR';
      case AppPermission.phoneCall: return 'android.permission.CALL_PHONE';
      case AppPermission.sms: return 'android.permission.READ_SMS';
      case AppPermission.overlay: return 'android.permission.SYSTEM_ALERT_WINDOW';
      case AppPermission.notificationListener: return 'notification_listener';
    }
  }

  IconData get icon {
    switch (this) {
      case AppPermission.storage: return Icons.folder_outlined;
      case AppPermission.camera: return Icons.camera_alt_outlined;
      case AppPermission.microphone: return Icons.mic_outlined;
      case AppPermission.location: return Icons.location_on_outlined;
      case AppPermission.contacts: return Icons.contacts_outlined;
      case AppPermission.calendar: return Icons.calendar_month_outlined;
      case AppPermission.phoneCall: return Icons.phone_outlined;
      case AppPermission.sms: return Icons.message_outlined;
      case AppPermission.overlay: return Icons.picture_in_picture_alt_outlined;
      case AppPermission.notificationListener: return Icons.notifications_outlined;
    }
  }

  String get title {
    switch (this) {
      case AppPermission.storage: return '存储';
      case AppPermission.camera: return '相机';
      case AppPermission.microphone: return '麦克风';
      case AppPermission.location: return '位置';
      case AppPermission.contacts: return '通讯录';
      case AppPermission.calendar: return '日历';
      case AppPermission.phoneCall: return '电话';
      case AppPermission.sms: return '短信';
      case AppPermission.overlay: return '悬浮窗';
      case AppPermission.notificationListener: return '通知监听';
    }
  }

  String get description {
    switch (this) {
      case AppPermission.storage: return '保存生成的图片／视频到相册，读取工作目录文件';
      case AppPermission.camera: return '拍照作为图片生成参考，视频生成首尾帧';
      case AppPermission.microphone: return '语音输入、语音克隆样本上传';
      case AppPermission.location: return '在地图上定位当前位置，搜索附近地点';
      case AppPermission.contacts: return '搜索、查看、新建联系人';
      case AppPermission.calendar: return '查看日程、创建日程事件';
      case AppPermission.phoneCall: return '点击号码直接拨打电话';
      case AppPermission.sms: return '读取和发送短信';
      case AppPermission.overlay: return '在其他应用上方显示悬浮球，快速返回本 App';
      case AppPermission.notificationListener: return '读取通知内容，让 AI 理解其他 App 的消息';
    }
  }

  bool get isSpecial => this == AppPermission.overlay || this == AppPermission.notificationListener;
}

// ──────────────────────────────────────────────
// 统一权限获取器 — 所有功能从这里申请权限
// ──────────────────────────────────────────────

class PermissionManager {
  factory PermissionManager() => _instance;
  PermissionManager._internal();
  static final PermissionManager _instance = PermissionManager._internal();

  static const _channel = MethodChannel('com.agent.my_agent_app/permissions');

  /// 检查某个权限是否已授予
  Future<bool> has(AppPermission perm) async {
    if (perm.isSpecial) return hasSpecial(perm);
    try {
      final result = await _channel.invokeMethod<bool>('checkPermission', {
        'permission': perm.permissionName,
      });
      return result ?? false;
    } catch (_) {
      return true; // 通道出错时保守放行
    }
  }

  /// 检查特殊权限（悬浮窗、通知监听）
  Future<bool> hasSpecial(AppPermission perm) async {
    try {
      final result = await _channel.invokeMethod<bool>('checkSpecialPermission', {
        'permission': perm.permissionName,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 检查权限是否被永久拒绝（不再弹出系统对话框）
  Future<bool> isPermanentlyDenied(AppPermission perm) async {
    if (perm.isSpecial) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isPermissionPermanentlyDenied', {
        'permission': perm.permissionName,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 请求权限（UI 场景）：先弹解释弹窗 → 系统权限弹窗 → 失败引导
  /// [reason] 可选，自定义申请原因，不传则使用默认描述
  Future<bool> request(BuildContext context, AppPermission perm, {String? reason, bool showRationale = true}) async {
    // 已有权限
    if (await has(perm)) return true;

    // 特殊权限走独立流程
    if (perm.isSpecial) {
      return _requestSpecial(context, perm);
    }

    // 显示解释弹窗（可在 requestMultiple 等场景跳过）
    if (showRationale && context.mounted) {
      final agreed = await _showRequestDialog(context, perm, reason: reason);
      if (!agreed) return false;
    }

    // 调起系统权限弹窗
    try {
      final granted = await _channel.invokeMethod<bool>('requestPermission', {
        'permission': perm.permissionName,
      });
      if (granted == true) return true;

      // 拒绝后检查是否被永久拒绝
      if (context.mounted) {
        if (await isPermanentlyDenied(perm)) {
          await _showGoToSettingsDialog(context, perm);
        } else {
          _showDeniedSnackBar(context, perm);
        }
      }
      return false;
    } catch (_) {
      return true;
    }
  }

  /// 请求多个权限（批量），返回每个权限的授予结果
  Future<Map<AppPermission, bool>> requestMultiple(
    BuildContext context,
    List<AppPermission> perms, {
    String? reason,
  }) async {
    final results = <AppPermission, bool>{};
    final missing = <AppPermission>[];

    for (final perm in perms) {
      if (await has(perm)) {
        results[perm] = true;
      } else {
        missing.add(perm);
      }
    }

    if (missing.isEmpty) return results;

    // 批量解释弹窗
    if (context.mounted) {
      final agreed = await _showMultiRequestDialog(context, missing, reason: reason);
      if (!agreed) {
        for (final perm in missing) {
          results[perm] = false;
        }
        return results;
      }
    }

    for (final perm in missing) {
      final granted = await request(context, perm, showRationale: false);
      results[perm] = granted;
    }

    return results;
  }

  /// 工具执行场景的轻量权限请求：不弹解释弹窗，失败直接抛异常
  /// 供 phone_client / sms_client 等 AI 工具调用
  Future<void> requireForTool(AppPermission perm) async {
    if (await has(perm)) return;

    // 特殊权限无法通过 requestPermission 弹出系统弹窗,
    // 必须引导用户去设置页面手动开启
    if (perm.isSpecial) {
      final settingsName = switch (perm) {
        AppPermission.overlay => '悬浮窗',
        AppPermission.notificationListener => '通知使用权限',
        _ => perm.title,
      };
      throw Exception(
        '请在手机设置中开启"$settingsName"权限。\n'
        '${perm.description}\n'
        '路径: 设置 → 应用 → My Minimax → $settingsName',
      );
    }

    final granted = await _channel.invokeMethod<bool>('requestPermission', {
      'permission': perm.permissionName,
    });
    if (granted == true) return;

    throw Exception(
      '${perm.title}权限未授予。${perm.description}\n'
      '请在手机设置 → 应用 → 权限中手动开启。',
    );
  }

  /// 打开应用设置页面
  Future<bool> openSettings() async {
    try {
      await _channel.invokeMethod('openSettings');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 打开悬浮窗权限设置
  Future<bool> openOverlaySettings() async {
    try {
      await _channel.invokeMethod('openOverlaySettings');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 打开通知监听权限设置
  Future<bool> openNotificationListenerSettings() async {
    try {
      await _channel.invokeMethod('openNotificationListenerSettings');
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─── 内部方法 ──────────────────────────────────

  /// 特殊权限：悬浮窗直接开系统设置（系统自带开关，不需要我们解释），通知监听弹提示
  Future<bool> _requestSpecial(BuildContext context, AppPermission perm) async {
    switch (perm) {
      case AppPermission.overlay:
        await openOverlaySettings();
        await Future.delayed(const Duration(milliseconds: 500));
        return await has(perm);
      case AppPermission.notificationListener:
        if (context.mounted) {
          final agreed = await _showRequestDialog(context, perm);
          if (!agreed) return false;
          final goSettings = await _showGoToSettingsDialog(context, perm);
          if (goSettings == true) {
            await openNotificationListenerSettings();
          }
        }
        return false;
      default:
        return false;
    }
  }

  void _showDeniedSnackBar(BuildContext context, AppPermission perm) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${perm.title}权限被拒绝', style: const TextStyle(fontFamily: 'monospace')),
        backgroundColor: PixelTheme.error,
        action: SnackBarAction(
          label: '设置',
          textColor: PixelTheme.textPrimary,
          onPressed: () => openSettings(),
        ),
      ),
    );
  }

  Future<bool> _showRequestDialog(
    BuildContext context,
    AppPermission perm, {
    String? reason,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? PixelTheme.darkSurface : PixelTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: PixelTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(perm.icon, size: 28, color: PixelTheme.primary),
            ),
            const SizedBox(height: 16),
            Text('需要${perm.title}权限',
              style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w600,
                color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              reason ?? perm.description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14, height: 1.5,
                color: isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary,
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted,
                side: BorderSide(color: isDark ? PixelTheme.darkBorderDefault : PixelTheme.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('暂不允许', style: TextStyle(fontFamily: 'monospace')),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: PixelTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
              ),
              child: const Text('允许', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    ).then((r) => r ?? false);
  }

  Future<bool> _showMultiRequestDialog(
    BuildContext context,
    List<AppPermission> perms, {
    String? reason,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? PixelTheme.darkSurface : PixelTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: PixelTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.shield_outlined, size: 28, color: PixelTheme.primary),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text('需要以下权限',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600,
                  color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary)),
            ),
            if (reason != null) ...[
              const SizedBox(height: 6),
              Center(
                child: Text(reason, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13,
                    color: isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary)),
              ),
            ],
            const SizedBox(height: 16),
            ...perms.map((perm) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: PixelTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(perm.icon, size: 18, color: PixelTheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(perm.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500,
                      color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary)),
                    Text(perm.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11,
                        color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted)),
                  ]),
                ),
              ]),
            )),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted,
                side: BorderSide(color: isDark ? PixelTheme.darkBorderDefault : PixelTheme.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('暂不允许', style: TextStyle(fontFamily: 'monospace')),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: PixelTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
              ),
              child: const Text('全部允许', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    ).then((r) => r ?? false);
  }

  Future<bool> _showGoToSettingsDialog(
    BuildContext context,
    AppPermission perm, {
    String? message,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? PixelTheme.darkSurface : PixelTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: PixelTheme.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.settings, size: 28, color: PixelTheme.warning),
            ),
            const SizedBox(height: 16),
            Text('${perm.title}权限未开启',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600,
                color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary)),
            const SizedBox(height: 8),
            Text(
              message ?? '${perm.description}\n\n需要在系统设置中手动开启。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.5,
                color: isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted,
                side: BorderSide(color: isDark ? PixelTheme.darkBorderDefault : PixelTheme.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('稍后再说', style: TextStyle(fontFamily: 'monospace')),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: PixelTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
              ),
              child: const Text('前往设置', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
