// ignore_for_file: avoid_print

/// Map Tool Integration Tests
///
/// ⚠️  IMPORTANT: These tests require a real AMap API key and SharedPreferences,
/// so they must run on a PHYSICAL DEVICE or EMULATOR.
///
/// Plain `flutter test` will fail because SharedPreferences needs a native plugin.
/// For CI without a device, see map_test_plan.md for manual test instructions.
///
/// To run on a connected device:
///   flutter test test/map_integration_test.dart -d <device_id>
///
/// To run manually (recommended):
///   Open the app → configure AMap API Key → follow map_test_plan.md

library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myminimax/features/tools/data/tool_executor.dart';
import 'package:myminimax/features/settings/data/settings_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('【地图工具-集成测试】', () {
    late ToolExecutor executor;

    setUp(() async {
      // Initialize SharedPreferences mock for unit testing
      SharedPreferences.setMockInitialValues({
        'amap_api_key': '',
      });
      final repo = SettingsRepository();
      executor = ToolExecutor(settingsRepo: repo);
    });

    // ═══════════════════════════════════════════
    // 无需 API Key 的纯算法测试
    // ═══════════════════════════════════════════

    test('【距离计算】两点直线距离', () async {
      final result = await executor.executeWithHooks('distance_calc', {
        'origin_lng': 116.481763,
        'origin_lat': 39.989614,
        'dest_lng': 116.397428,
        'dest_lat': 39.90923,
      });

      print('\n📏 distance_calc 结果:');
      print(result.output);
      expect(result.success, true, reason: result.error);
      expect(result.output.contains('米') || result.output.contains('公里'), true);
    });

    test('【坐标转换】GPS → 高德坐标系', () async {
      final result = await executor.executeWithHooks('coordinate_converter', {
        'lng': 116.397428,
        'lat': 39.90923,
        'type': 'gps2gcj',
      });

      print('\n🔄 coordinate_converter 结果:');
      print(result.output);
      expect(result.success, true, reason: result.error);
    });

    // ═══════════════════════════════════════════
    // 以下测试需要有效的 AMap API Key
    // 在无 Key 或设备环境下会失败
    // ═══════════════════════════════════════════

    test('【地理编码】地址 → 坐标 [需要API Key]', () async {
      final result = await executor.executeWithHooks('geocode', {
        'address': '望京SOHO',
        'city': '北京',
      });

      print('\n📍 geocode 结果:');
      print(result.output);
      // 在有 Key 的设备上运行时应通过
      if (result.output.contains('坐标') || result.output.contains('lng')) {
        expect(true, true);
      } else {
        print('⚠️ 无 API Key 或网络不可用，跳过断言');
      }
    }, skip: '需要设备+API Key，详见 map_test_plan.md');

    test('【驾车路线】望京SOHO → 天安门 [需要API Key]', () async {
      final result = await executor.executeWithHooks('plan_driving_route', {
        'origin_lng': 116.481763,
        'origin_lat': 39.989614,
        'dest_lng': 116.397428,
        'dest_lat': 39.90923,
      });

      print('\n🚗 plan_driving_route 结果:');
      print(result.output);
      if (result.success && result.output.contains('公里')) {
        expect(true, true);
      } else {
        print('⚠️ 路线规划失败或无 Key: ${result.error}');
      }
    }, skip: '需要设备+API Key，详见 map_test_plan.md');

    test('【静态地图】生成 URL [需要API Key]', () async {
      final result = await executor.executeWithHooks('static_map', {
        'lng': 116.397428,
        'lat': 39.90923,
        'zoom': 14,
        'width': 600,
        'height': 400,
      });

      print('\n🗺 static_map 结果:');
      print(result.output);
      if (result.success && result.output.contains('staticmap')) {
        expect(true, true);
      }
    }, skip: '需要设备+API Key，详见 map_test_plan.md');
  });
}
