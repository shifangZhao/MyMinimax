import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers.dart';
import '../../../app/theme.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../app/app.dart' show navigationIndexProvider;
import '../../../features/chat/presentation/chat_page.dart' show settingsChangedProvider;
import '../../../core/api/amap_client.dart' show AmapClient, AmapException, GeoPoint, PoiItem, InputTip, RouteResult;
import '../../../core/phone/location_client.dart' show LocationClient;
import '../../../features/settings/data/settings_repository.dart';
import '../../../features/tools/data/tool_executor.dart' show ToolExecutor;
import '../data/map_action.dart';
import '../data/polyline_decoder.dart' show decodeAmapPolyline;
import '../../../utils/map_marker_generator.dart' show generateUserLocationIcon;
import '../../../utils/arrow_polyline.dart' show ArrowPolyline;
import '../../../features/route_planning/route_planning_state.dart';
import '../../../features/route_planning/presentation/widgets/route_planning_overlay.dart';

// Gives the native Android map view priority over Flutter's GestureDetector
// for all pointer events, so map panning/scrolling doesn't trigger tab switching.
// Note: DO NOT use a singleton here — Factory must create a new instance per build.

// ── Navi info state notifier (avoids full MapPage rebuilds on GPS updates) ──

class NaviInfo {
  final String roadName;
  final double distanceRemain;
  final int timeRemain;
  final String nextRoad;
  final int iconType;
  final int curStepDistance;
  final int speed;
  final bool gpsSignalWeak;
  final bool isRecalculating;
  final String parallelRoadHint;
  final int parallelRoadType;
  final String naviTtsText;
  final bool crossVisible;
  final Uint8List? crossImage;
  final int laneCount;
  final bool laneVisible;
  final Uint8List? laneImage;
  final bool isMuted;
  final bool isHudMode;
  final bool isOverviewMode;
  final int naviMapMode;
  final bool showNaviSteps;
  final List<Map<String, dynamic>> naviSteps;
  final bool isNavigating;
  final bool isUserInteracting;

  const NaviInfo({
    this.roadName = '',
    this.distanceRemain = 0,
    this.timeRemain = 0,
    this.nextRoad = '',
    this.iconType = 0,
    this.curStepDistance = 0,
    this.speed = 0,
    this.gpsSignalWeak = false,
    this.isRecalculating = false,
    this.parallelRoadHint = '',
    this.parallelRoadType = 0,
    this.naviTtsText = '',
    this.crossVisible = false,
    this.crossImage,
    this.laneCount = 0,
    this.laneVisible = false,
    this.laneImage,
    this.isMuted = false,
    this.isHudMode = false,
    this.isOverviewMode = false,
    this.naviMapMode = 0,
    this.showNaviSteps = false,
    this.naviSteps = const [],
    this.isNavigating = false,
    this.isUserInteracting = false,
  });

  NaviInfo copyWith({
    String? roadName, double? distanceRemain, int? timeRemain,
    String? nextRoad, int? iconType, int? curStepDistance, int? speed,
    bool? gpsSignalWeak, bool? isRecalculating,
    String? parallelRoadHint, int? parallelRoadType,
    String? naviTtsText, bool? crossVisible, Uint8List? crossImage,
    int? laneCount, bool? laneVisible, Uint8List? laneImage,
    bool? isMuted, bool? isHudMode, bool? isOverviewMode,
    int? naviMapMode, bool? showNaviSteps,
    List<Map<String, dynamic>>? naviSteps, bool? isNavigating,
    bool? isUserInteracting,
  }) => NaviInfo(
    roadName: roadName ?? this.roadName,
    distanceRemain: distanceRemain ?? this.distanceRemain,
    timeRemain: timeRemain ?? this.timeRemain,
    nextRoad: nextRoad ?? this.nextRoad,
    iconType: iconType ?? this.iconType,
    curStepDistance: curStepDistance ?? this.curStepDistance,
    speed: speed ?? this.speed,
    gpsSignalWeak: gpsSignalWeak ?? this.gpsSignalWeak,
    isRecalculating: isRecalculating ?? this.isRecalculating,
    parallelRoadHint: parallelRoadHint ?? this.parallelRoadHint,
    parallelRoadType: parallelRoadType ?? this.parallelRoadType,
    naviTtsText: naviTtsText ?? this.naviTtsText,
    crossVisible: crossVisible ?? this.crossVisible,
    crossImage: crossImage ?? this.crossImage,
    laneCount: laneCount ?? this.laneCount,
    laneVisible: laneVisible ?? this.laneVisible,
    laneImage: laneImage ?? this.laneImage,
    isMuted: isMuted ?? this.isMuted,
    isHudMode: isHudMode ?? this.isHudMode,
    isOverviewMode: isOverviewMode ?? this.isOverviewMode,
    naviMapMode: naviMapMode ?? this.naviMapMode,
    showNaviSteps: showNaviSteps ?? this.showNaviSteps,
    naviSteps: naviSteps ?? this.naviSteps,
    isNavigating: isNavigating ?? this.isNavigating,
    isUserInteracting: isUserInteracting ?? this.isUserInteracting,
  );
}

final naviInfoProvider = StateProvider<NaviInfo>((ref) => const NaviInfo());

class MapPage extends ConsumerStatefulWidget {
  const MapPage({super.key});

  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage> with WidgetsBindingObserver {
  String _t(String k, String fb) => ref.read(i18nProvider)?.t(k) ?? fb;
  static const _viewType = 'com.myminimax/amap_view';
  MethodChannel? _channel;
  bool _is3D = false;
  bool _isDark = false;
  bool _isTraffic = false;
  bool _isSatellite = false;
  bool _isLeftCollapsed = false;
  bool _isRightCollapsed = false;
  bool _showHistoryPopup = false;

  // Scale bar / camera center
  double _currentZoom = 15.0;
  double _currentLat = 39.9;
  double _currentLng = 116.4;

  // Search
  final _searchController = TextEditingController();
  bool _isSearching = false;
  String? _errorMsg;
  String? _infoMsg;
  List<InputTip> _searchTips = [];
  bool _showSearchTips = false;
  Timer? _searchDebounce;


  Timer? _msgTimer;
  bool _hasMapAction = false;
  String _actionTitle = '';
  String _actionSubtitle = '';
  String? _actionRouteType;
  ShowRouteAction? _currentRouteAction;

  // Navigation state (migrated to naviInfoProvider)
  bool _naviRouteCalculated = false;
  bool _cameraInitialized = false;

  // 导航跟随模式状态
  bool _naviFollowNeedsResume = false; // 是否需要恢复自动跟随
  Timer? _followCheckTimer; // 归位检测定时器
  double? _lastGpsLat; // 用于归位检测
  double? _lastGpsLng;

  // Multi-route state
  bool _hasMultipleRoutes = false;
  int _routeCount = 0;
  int _selectedRouteIndex = 0;
  List<Map<String, dynamic>> _routeSummary = [];
  int _currentStrategy = 0;
  String _currentVehicle = 'car';

  // Arrival page state
  bool _showArrivalPage = false;
  String _arrivalDestinationName = '';
  double _arrivalTotalDistance = 0;
  int _arrivalTotalTime = 0;

  // Viewport state

  // POI click state
  String? _poiName;
  double? _poiLat;
  double? _poiLng;

  // POI 吸附过滤：直接点中 POI 文字时只有 onPOIClick，不会有 onMapClick；
  // 点击空白处被 SDK 自动吸附时，先触发 onMapClick 再触发 onPOIClick。
  // 通过坐标距离判断：直接点中时 POI 坐标与点击坐标几乎相同，吸附时差异大。
  double? _lastMapClickLat;
  double? _lastMapClickLng;
  static const _poiSnapToleranceDeg = 0.0005; // ~50 米以内视为直接点击

  // Long press state
  double? _longPressLat;
  double? _longPressLng;
  String? _longPressAddress;

  // Distance measurement
  bool _isMeasuring = false;
  final List<GeoPoint> _measurePoints = [];

  // Screenshot
  bool _isScreenshotting = false;
  int _screenshotCacheLimit = 3;

  // Language
  String _mapLanguage = 'zh';
  bool _isMapLangEn = false;

  // Location detail (from native location client)
  Map<String, dynamic> _locationDetail = {};
  // Last known GPS location for navi origin fallback
  Map<String, dynamic>? _lastKnownLocation;
  // Native SDK API key (loaded from settings)
  String? _amapNativeKey;
  bool _keyLoaded = false;
  int _viewVersion = 0;
  bool _wasPaused = false;

  // Tile load detection — auto-retry when tiles fail to load
  Timer? _tileLoadTimer;
  int _tileRetryCount = 0;

  // 用户定位图标缓存
  Color _lastPrimaryColor = Colors.transparent;

  // UI 动画旋转角度（后续可接指南针数据，当前为占位）
  double _userHeading = 0;

  // ── Route planning mode (uses RoutePlanningOverlay instead of _actionBar) ──
  bool _routePlanningMode = false;

  // Native callbacks
  VoidCallback? _mapActionListener;
  String? _tappedAddress;
  String? _markerTitle;
  String? _markerSnippet;

  // Batched state updates
  bool _pendingState = false;

  void _send(String method, {Map<String, dynamic>? args}) {
    _channel?.invokeMethod(method, args ?? {});
  }

  void _scheduleState(VoidCallback fn) {
    fn();
    if (!_pendingState) {
      _pendingState = true;
      // addPostFrameCallback: 同一帧内的多次变更合并为一次 setState
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pendingState = false;
        if (mounted) setState(() {});
      });
    }
  }

  void _setMsg(String? errorMsg, String? infoMsg) {
    _msgTimer?.cancel();
    _scheduleState(() {
      if (errorMsg != null) _errorMsg = errorMsg;
      if (infoMsg != null) _infoMsg = infoMsg;
      _msgTimer = Timer(const Duration(seconds: 5), () { if (mounted) setState(() { _errorMsg = null; _infoMsg = null; }); });
    });
  }

  void _showPopup(VoidCallback clearFn) {
    _msgTimer?.cancel();
    _scheduleState(() {
      clearFn();
      _msgTimer = Timer(const Duration(seconds: 5), () { if (mounted) setState(() { _tappedAddress = null; _markerTitle = null; _markerSnippet = null; _poiName = null; _poiLat = null; _poiLng = null; }); });
    });
  }

  @override
  void initState() {
    super.initState();
    // 监听 tab 切换：离开地图 tab 时隐藏 decorView 中的 MapView，回来时显示
    ref.listen<int>(navigationIndexProvider, (prev, next) {
      if (next == 1) {
        _send('resumeMap');
      } else if (prev == 1) {
        _send('pauseMap');
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(navigationIndexProvider) != 1) {
        _send('pauseMap');
      }
    });
    _mapActionListener = () {
      final action = mapActionBus.value;
      if (action != null) {
        _handleMapAction(action);
        mapActionBus.value = null;
        mapActionPending.value = null;
      }
    };
    mapActionBus.addListener(_mapActionListener!);
    final pending = mapActionPending.value;
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleMapAction(pending);
        mapActionPending.value = null;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyMapCacheLimit(ref.read(mapCacheLimitProvider));
    });
    // Load Native SDK API key from settings
    _loadAmapNativeKey();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final primary = Theme.of(context).colorScheme.primary;
    if (primary != _lastPrimaryColor) {
      _lastPrimaryColor = primary;
      // 只在 channel 就绪后生成（否则首帧由 _onPlatformViewCreated 触发）
      if (_channel != null) {
        _generateUserMarkerIcon();
      }
    }
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    // 系统亮暗切换时重建图标（didChangeDependencies 也会触发，双重保障）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _generateUserMarkerIcon();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 回到前台 → 重启 Tile 超时检测
      if (_wasPaused) {
        _wasPaused = false;
        _send('resumeMap');
        _startTileLoadTimer();
      }
      // 后台可能切换了主题，重新生成图标
      _generateUserMarkerIcon();
    } else if (state == AppLifecycleState.paused) {
      // 退到后台 → 取消 Tile 超时检测（避免后台重建导致崩溃）
      _wasPaused = true;
      _cancelTileLoadTimer();
      _send('pauseMap');
    }
  }

  Future<void> _loadAmapNativeKey() async {
    final repo = SettingsRepository();
    final key = await repo.getAmapNativeApiKey();
    if (mounted) {
      if (_keyLoaded && key != _amapNativeKey) {
        // Key changed → refresh map tiles (no PlatformView rebuild, avoids OOM)
        setState(() => _amapNativeKey = key);
        if (key.isNotEmpty) {
          _send('setApiKey', args: {'key': key});
        }
        _send('refreshMap');
      } else {
        setState(() {
          _amapNativeKey = key;
          _keyLoaded = true;
        });
      }
    }
  }

  /// Re-read API key and rebuild AndroidView if key is now available.
  void _retryMap() => _loadAmapNativeKey();

  /// Navigate to the settings page so user can enter the API key.
  void _navigateToSettings() {
    // Try to find and trigger the settings navigation from the parent widget/app shell
    // The settings route is typically at index 2 in the bottom nav.
    try {
      ref.read(navigationIndexProvider.notifier).state = 2;
    } catch (_) {
      // fallback: do nothing, user can manually navigate
    }
  }

  /// 生成用户定位图标并通过 MethodChannel 发送到原生端。
  /// 主题色变化时自动重新生成。
  Future<void> _generateUserMarkerIcon() async {
    try {
      final bytes = await generateUserLocationIcon(
        context,
        heading: _userHeading, // 弧度，默认0朝上
      );
      if (!mounted) return;
      _channel?.invokeMethod('updateUserMarkerIcon', <String, dynamic>{
        'data': bytes,
        'anchorX': 0.5,
        'anchorY': 0.85,
      });
    } catch (e) {
      debugPrint('[MapPage] generateUserMarkerIcon error: $e');
    }
  }

  /// Calculate arrow positions and send to native for rendering.
  /// Native side handles bitmap drawing, avoiding PNG byte transfer.
  Future<void> _addArrowMarkers(List<List<double>> points, String routeType) async {
    if (points.length < 2) return;
    try {
      final positions = ArrowPolyline.calculateArrowPositions(
        points,
        spacingMeters: 120,
      );
      if (positions.isNotEmpty && mounted) {
        _send('addArrowMarkers', args: {
          'positions': positions,
          'color': _routeColor(routeType),
        });
      }
    } catch (e) {
      debugPrint('[MapPage] addArrowMarkers error: $e');
    }
  }

  /// Fetch route polyline points from native side and add direction arrows.
  Future<void> _fetchRoutePointsAndAddArrows() async {
    if (!mounted || _channel == null) return;
    try {
      final pts = await _channel?.invokeMethod<List<dynamic>>('getRoutePoints');
      if (pts != null && pts.isNotEmpty && mounted) {
        final points = pts.map((p) {
          final list = p as List<dynamic>;
          return [(list[0] as num).toDouble(), (list[1] as num).toDouble()];
        }).toList();
        if (points.length >= 2) {
          final routeType = _actionRouteType ?? 'driving';
          final positions = ArrowPolyline.calculateArrowPositions(
            points,
            spacingMeters: 120,
          );
          if (positions.isNotEmpty && mounted) {
            _send('addArrowMarkers', args: {
              'positions': positions,
              'color': _routeColor(routeType),
            });
          }
        }
      }
    } catch (e) {
      debugPrint('[MapPage] fetchRoutePointsAndAddArrows error: $e');
    }
  }

  void dispose() {
    _cancelTileLoadTimer();
    if (_mapActionListener != null) {
      mapActionBus.removeListener(_mapActionListener!);
    }
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ── Handle MapAction ──

  void _handleMapAction(MapAction action) {
    _send('clearMarkers');
    _send('clearRoutes');
    _send('clearPolygons');
    _send('clearCircles');
    _naviRouteCalculated = false;

    switch (action) {
      case ShowPoisAction(:final title, :final pois):
        _hasMapAction = true;
        _actionTitle = title;
        _actionSubtitle = '${pois.length} 个地点';
        _actionRouteType = null;
        _currentRouteAction = null;
        final markers = pois.map(_poiToMarker).toList();
        _send('addMarkers', args: {'markers': markers});
        if (pois.length == 1) {
          _send('moveCamera', args: {'lat': pois.first.location.lat, 'lng': pois.first.location.lng, 'zoom': 15});
        } else if (pois.length > 1) {
          _fitBoundsForMarkers(markers);
        }
        _scheduleState(() {});

      case ShowRouteAction(:final routeType, :final origin, :final destination, :final placeName, :final distance, :final duration, :final polyline):
        _hasMapAction = true;
        _actionRouteType = routeType;
        _currentRouteAction = action;
        _actionTitle = '${_routeModeIcon(routeType)} ${_routeModeLabel(routeType)}路线';
        _actionSubtitle = '${_formatDistance(distance)} / $duration';
        // Draw route on map
        _send('addMarkers', args: {'markers': [
          {'lat': origin.lat, 'lng': origin.lng, 'title': '起点', 'snippet': '', 'color': 0xFF34C759, 'anchorX': 0.5, 'anchorY': 0.5},
          {'lat': destination.lat, 'lng': destination.lng, 'title': '终点', 'snippet': '', 'color': 0xFFFF3B30, 'anchorX': 0.5, 'anchorY': 0.5},
        ]});
        if (polyline != null && polyline.isNotEmpty) {
          final points = decodeAmapPolyline(polyline);
          if (points.isNotEmpty) {
            _send('drawRoute', args: {'points': points, 'color': _routeColor(routeType), 'width': 14});
            // Add direction arrow markers along the route
            _addArrowMarkers(points, routeType);
          }
        }
        final cLat = _lastKnownLocation != null ? (_lastKnownLocation!['lat'] as double?) ?? origin.lat : origin.lat;
        final cLng = _lastKnownLocation != null ? (_lastKnownLocation!['lng'] as double?) ?? origin.lng : origin.lng;
        _send('moveCamera', args: {'lat': cLat, 'lng': cLng, 'zoom': _currentZoom});
        // Activate route planning overlay / update route info
        final TravelMode mode = switch (routeType) {
          'cycling' => TravelMode.cycling,
          'walking' => TravelMode.walking,
          'transit' => TravelMode.transit,
          _ => TravelMode.driving,
        };
        _routePlanningMode = true;
        // Try to use GPS as origin
        double sLat = origin.lat;
        double sLng = origin.lng;
        String sAddr = '我的位置';
        if (_lastKnownLocation != null) {
          sLat = (_lastKnownLocation!['lat'] as double?) ?? origin.lat;
          sLng = (_lastKnownLocation!['lng'] as double?) ?? origin.lng;
          final addr = _lastKnownLocation!['address'] as String?;
          if (addr != null && addr.isNotEmpty) sAddr = addr;
        }
        ref.read(routePlanProvider.notifier).activate(
          startAddress: sAddr,
          startLat: sLat,
          startLng: sLng,
          destAddress: placeName ?? '${destination.lat.toStringAsFixed(5)}, ${destination.lng.toStringAsFixed(5)}',
          destLat: destination.lat,
          destLng: destination.lng,
          mode: mode,
        );
        // Only show cards when route has actual data (API tools).
        // POI-to-route flow passes empty data and relies on native callbacks.
        if (distance > 0) {
          final routeInfo = RouteInfo(
            index: 0,
            distance: distance,
            duration: _parseDurationToSeconds(duration),
            tollCost: 0,
          );
          ref.read(routePlanProvider.notifier).setRoutes([routeInfo]);
        }
        _scheduleState(() {});

      case ShowLocationAction(:final location, :final name, :final address):
        _hasMapAction = true;
        _actionTitle = name ?? address ?? '位置';
        _actionSubtitle = '${location.lng.toStringAsFixed(4)}, ${location.lat.toStringAsFixed(4)}';
        _actionRouteType = null;
        _currentRouteAction = null;
        _send('addMarkers', args: {'markers': [{'lat': location.lat, 'lng': location.lng, 'title': name ?? address ?? '', 'snippet': address ?? ''}]});
        _send('moveCamera', args: {'lat': location.lat, 'lng': location.lng, 'zoom': 15});
        _scheduleState(() {});

            case ShowPolygonAction(:final title, :final points, :final strokeColor, :final fillColor):
        _hasMapAction = true;
        _actionTitle = title;
        _actionSubtitle = '${points.length} 个顶点';
        _actionRouteType = null;
        _currentRouteAction = null;
        _send('drawPolygon', args: {
          'points': points.map((p) => [p.lat, p.lng]).toList(),
          'strokeColor': strokeColor,
          'fillColor': fillColor,
        });
        _fitBoundsForPoints(points);
        _scheduleState(() {});

      case ShowCircleAction(:final title, :final center, :final radius, :final strokeColor, :final fillColor):
        _hasMapAction = true;
        _actionTitle = title;
        _actionSubtitle = '半径 ${_formatDistance(radius)}';
        _actionRouteType = null;
        _currentRouteAction = null;
        _send('drawCircle', args: {'lat': center.lat, 'lng': center.lng, 'radius': radius, 'strokeColor': strokeColor, 'fillColor': fillColor});
        _send('moveCamera', args: {'lat': center.lat, 'lng': center.lng, 'zoom': 14});
        _scheduleState(() {});

      case ClearOverlaysAction():
        _clearAction();

      case ShowArcAction(:final title, :final start, :final mid, :final end, :final color):
        _hasMapAction = true;
        _actionTitle = title;
        _actionSubtitle = '弧线';
        _actionRouteType = null;
        _currentRouteAction = null;
        _send('drawArc', args: {'startLat': start.lat, 'startLng': start.lng, 'midLat': mid.lat, 'midLng': mid.lng, 'endLat': end.lat, 'endLng': end.lng, 'color': color});
        _fitBoundsForPoints([start, mid, end]);
        _scheduleState(() {});

      case ShowTextAction(:final text, :final position, :final fontSize, :final fontColor):
        _send('drawText', args: {'lat': position.lat, 'lng': position.lng, 'text': text, 'fontSize': fontSize, 'fontColor': fontColor});
        _setMsg(null, '已添加文字标注');

      case ShowGroundOverlayAction(:final imagePath, :final swLat, :final swLng, :final neLat, :final neLng):
        _send('addGroundOverlay', args: {'path': imagePath, 'swLat': swLat, 'swLng': swLng, 'neLat': neLat, 'neLng': neLng});
        _setMsg(null, '已添加图片层');

      case ShowTrafficEventsAction(:final events):
        _hasMapAction = true;
        _actionTitle = '交通事件';
        _actionSubtitle = '${events.length} 条事件';
        _actionRouteType = null;
        _currentRouteAction = null;
        final markers = <Map<String, dynamic>>[];
        for (final e in events) {
          if (e.location != null) {
            markers.add({'lat': e.location!.lat, 'lng': e.location!.lng, 'title': e.eventType, 'snippet': e.description});
          }
        }
        if (markers.isNotEmpty) {
          _send('addMarkers', args: {'markers': markers});
          _fitBoundsForMarkers(markers);
        }
        _scheduleState(() {});

      case ShowTrafficRoadsAction(:final type, :final status, :final description, :final expedite, :final roads):
        _hasMapAction = true;
        _actionTitle = '交通态势';
        _actionSubtitle = description;
        _actionRouteType = null;
        _currentRouteAction = null;
        // 颜色映射：0=未知灰 1=畅通绿 2=缓行黄 3=拥堵橙 4=严重拥堵红
        final statusColors = {0: 0xFF9E9E9E, 1: 0xFF4CAF50, 2: 0xFFFFEB3B, 3: 0xFFFF9800, 4: 0xFFF44336};
        int idx = 0;
        for (final road in roads) {
          if (road.polyline != null && road.polyline!.isNotEmpty) {
            final points = _parseRoadPolyline(road.polyline!);
            if (points.isNotEmpty) {
              final color = statusColors[int.tryParse(road.status) ?? 0] ?? 0xFF9E9E9E;
              _send('drawRoute', args: {'points': points, 'color': color, 'width': 10, 'index': idx});
              idx++;
            }
          }
        }
        if (roads.isNotEmpty) {
          _scheduleState(() {});
        }

      case ShowGrasproadAction(:final distance, :final points):
        _hasMapAction = true;
        _actionTitle = '轨迹纠偏';
        _actionSubtitle = '${(distance / 1000).toStringAsFixed(2)} 公里';
        _actionRouteType = null;
        _currentRouteAction = null;
        if (points.isNotEmpty) {
          _send('addMarkers', args: {'markers': [
            {'lat': points.first.lat, 'lng': points.first.lng, 'title': '起点', 'snippet': ''},
            {'lat': points.last.lat, 'lng': points.last.lng, 'title': '终点', 'snippet': ''},
          ]});
          _send('drawRoute', args: {'points': points, 'color': 0xFF4F6EF7, 'width': 14});
          _fitBoundsForPoints(points);
        }
        _scheduleState(() {});

      case ShowFutureRouteAction(:final origin, :final destination, :final paths):
        _hasMapAction = true;
        _actionTitle = '未来路线';
        _actionSubtitle = '${paths.length} 个时段方案';
        _actionRouteType = null;
        _currentRouteAction = null;
        // 颜色列表，用于区分不同时段的路线
        final routeColors = [0xFF4F6EF7, 0xFFFF6B6B, 0xFF51CF66, 0xFFFFCC00, 0xFF40C9FF, 0xFFFF7D7D, 0xFF66FF7F, 0xFFFF9F43];
        int colorIdx = 0;
        for (int i = 0; i < paths.length; i++) {
          final path = paths[i];
          if (path.polyline != null && path.polyline!.isNotEmpty) {
            final points = decodeAmapPolyline(path.polyline!);
            if (points.isNotEmpty) {
              final color = routeColors[colorIdx % routeColors.length];
              _send('drawRoute', args: {'points': points, 'color': color, 'width': 12, 'index': i});
              colorIdx++;
            }
          }
        }
        // 添上起终点标记
        _send('addMarkers', args: {'markers': [
          {'lat': origin.lat, 'lng': origin.lng, 'title': '起点', 'snippet': '', 'color': 0xFF34C759, 'anchorX': 0.5, 'anchorY': 0.5},
          {'lat': destination.lat, 'lng': destination.lng, 'title': '终点', 'snippet': '', 'color': 0xFFFF3B30, 'anchorX': 0.5, 'anchorY': 0.5},
        ]});
        final cLat = _lastKnownLocation != null ? (_lastKnownLocation!['lat'] as double?) ?? origin.lat : origin.lat;
        final cLng = _lastKnownLocation != null ? (_lastKnownLocation!['lng'] as double?) ?? origin.lng : origin.lng;
        _send('moveCamera', args: {'lat': cLat, 'lng': cLng, 'zoom': _currentZoom});
        _scheduleState(() {});
    }
  }

  // ── Navigation ──

  void _stopNavi() {
    _send('stopNavi');
    _send('stopHudNavi');
    _scheduleState(() {
      _naviRouteCalculated = false;
      _routePlanningMode = false;
    });
    // 清理导航跟随状态
    _followCheckTimer?.cancel();
    _naviFollowNeedsResume = false;
    ref.read(naviInfoProvider.notifier).update((n) => const NaviInfo());
    ref.read(routePlanProvider.notifier).setNavigating(false);
    // 清掉旧 action bar 的状态，防止退出导航后旧卡片弹出
    _hasMapAction = false;
  }

  void _toggleNaviMapMode() {
    final current = ref.read(naviInfoProvider).naviMapMode;
    _send('setNaviMapMode', args: {'naviMode': current == 0 ? 1 : 0});
    ref.read(naviInfoProvider.notifier).update((n) => n.copyWith(naviMapMode: current == 0 ? 1 : 0));
  }

  void _toggleOverviewMode() {
    final current = ref.read(naviInfoProvider).isOverviewMode;
    if (current) {
      _send('recoverLockMode');
    } else {
      _send('displayOverview');
      _fetchNaviSteps();
    }
    ref.read(naviInfoProvider.notifier).update((n) => n.copyWith(isOverviewMode: !current));
  }

  Future<void> _fetchNaviSteps() async {
    try {
      final result = await _channel?.invokeMethod<List<dynamic>>('getNaviSteps');
      if (result != null) {
        ref.read(naviInfoProvider.notifier).update((n) => n.copyWith(
          naviSteps: result.cast<Map<String, dynamic>>(),
          showNaviSteps: result.isNotEmpty,
        ));
      }
    } catch (_) {}
  }

  void _switchParallelRoad(int type) {
    _send('switchParallelRoad', args: {'type': type});
  }

  void _toggleNaviSteps() {
    final current = ref.read(naviInfoProvider).showNaviSteps;
    ref.read(naviInfoProvider.notifier).update((n) => n.copyWith(showNaviSteps: !current));
  }

  // ── Search ──

  void _fetchSearchTipsDebounced(String query) {
    _searchDebounce?.cancel();
    if (query.trim().isEmpty) {
      _scheduleState(() { _searchTips = []; _showSearchTips = false; });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () => _fetchSearchTips(query));
  }

  Future<void> _fetchSearchTips(String query) async {
    try {
      final repo = SettingsRepository();
      final key = await repo.getAmapApiKey();
      if (key.isEmpty) return;
      final client = AmapClient(apiKey: key);
      // 传入当前地图中心位置，使搜索结果优先显示附近的相关地点
      final location = GeoPoint(_currentLng, _currentLat);
      final tips = await client.inputTips(query, location: location);
      if (!mounted) return;
      _scheduleState(() { _searchTips = tips; _showSearchTips = tips.isNotEmpty; });
    } catch (_) {
      if (!mounted) return;
      _scheduleState(() { _searchTips = []; _showSearchTips = false; });
    }
  }

  Future<void> _doSearch(String query) async {
    if (query.trim().isEmpty) return;
    _searchDebounce?.cancel();
    _scheduleState(() { _isSearching = true; _errorMsg = null; _showSearchTips = false; _searchTips = []; });
    try {
      final repo = SettingsRepository();
      final key = await repo.getAmapApiKey();
      if (key.isEmpty) { _setMsg('请先在设置中配置高德地图 API Key', null); return; }
      final client = AmapClient(apiKey: key);
      final result = await client.searchPoi(query);
      if (result.pois.isEmpty) { _setMsg('未找到 "$query" 相关地点', null); return; }
      mapActionBus.value = ShowPoisAction(title: '搜索: $query', pois: result.pois);
    } on AmapException catch (e) {
      _setMsg('搜索失败: $e', null);
    } catch (e) {
      print('[map] error: $e');
      _setMsg('搜索失败: $e', null);
    } finally {
      _scheduleState(() => _isSearching = false);
    }
  }

  void _onSearchTipSelected(InputTip tip) {
    _scheduleState(() {
      _searchController.text = tip.name;
      _showSearchTips = false;
      _searchTips = [];
    });
    if (tip.location != null) {
      mapActionBus.value = ShowLocationAction(
        location: tip.location!,
        name: tip.name,
        address: tip.address.isNotEmpty ? tip.address : tip.district ?? '',
      );
    } else {
      _doSearch(tip.name);
    }
  }

  // ── Locate ──

  Future<void> _doLocate({bool silent = false}) async {
    _send('locate');
  }

  // ── Location Info (getVersion, getLocationDetail, getLocationQualityReport) ──

  void _showMapActionHistory() {
    _scheduleState(() => _showHistoryPopup = !_showHistoryPopup);
  }

  Future<void> _showLocationInfo() async {
    String version = '未知';
    String detail = '无可用详情';
    final loc = _locationDetail;

    try {
      final ver = await _channel?.invokeMethod<String>('getLocationVersion');
      if (ver != null) version = ver;
    } catch (_) {}

    try {
      final d = await _channel?.invokeMethod<String>('getLocationDetail');
      if (d != null && d.isNotEmpty) detail = d;
    } catch (_) {}

    if (!mounted) return;

    final sig = loc['gpsAccuracyStatus'] as int? ?? -1;
    final sigStr = switch (sig) { 0 => '强', 1 => '弱', _ => '未知' };
    final trust = loc['trustedLevel'] as int? ?? 0;
    final trustStr = switch (trust) { 1 => '高', 2 => '中', 3 => '低', 4 => '差', _ => '未知' };
    final qualitySummary = loc['qualityReportSummary']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('定位SDK信息'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _infoRow('SDK版本', version),
              _infoRow('定位类型', loc['provider']?.toString() ?? '未知'),
              _infoRow('坐标类型', loc['coordType']?.toString() ?? '未知'),
              _infoRow('GPS信号', sigStr),
              _infoRow('可信度', trustStr),
              _infoRow('卫星数', '${loc['satellites'] ?? 0}'),
              _infoRow('定位精度', '${(loc['accuracy'] as num?)?.toInt() ?? 0}m'),
              if (qualitySummary.isNotEmpty) ...[
                const Divider(),
                Text('质量报告:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: PixelTheme.textMuted)),
                const SizedBox(height: 4),
                Text(qualitySummary, style: const TextStyle(fontSize: 11)),
              ],
              const Divider(),
              _infoRow('定位详情', detail),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await _channel?.invokeMethod('clearMapCache');
              if (mounted && ctx.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('地图缓存已清理'), behavior: SnackBarBehavior.floating, duration: Duration(seconds: 2)),
                );
              }
            },
            child: const Text('清理缓存'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 100, child: Text('$label:', style: const TextStyle(fontSize: 12, color: PixelTheme.textMuted))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );

  // ── Map Click ──

  void _onMapClick(double lat, double lng) async {
    _lastMapClickLat = lat;
    _lastMapClickLng = lng;
    if (_isMeasuring) { _addMeasurePoint(lat, lng); return; }
    _clearPopups();
    try {
      final repo = SettingsRepository();
      final key = await repo.getAmapApiKey();
      if (key.isEmpty) return;
      final client = AmapClient(apiKey: key);
      final result = await client.regeocode(GeoPoint(lng, lat));
      _showPopup(() { _tappedAddress = null; });
      _scheduleState(() => _tappedAddress = result?.address ?? '未知地址');
    } catch (_) {
      _showPopup(() { _tappedAddress = null; });
      _scheduleState(() => _tappedAddress = '$lat, $lng');
    }
  }

  void _onMapLongClick(double lat, double lng) async {
    _clearPopups();
    _scheduleState(() { _longPressLat = lat; _longPressLng = lng; _longPressAddress = null; });
    try {
      final repo = SettingsRepository();
      final key = await repo.getAmapApiKey();
      if (key.isNotEmpty) {
        final client = AmapClient(apiKey: key);
        final result = await client.regeocode(GeoPoint(lng, lat));
        _scheduleState(() => _longPressAddress = result?.address ?? '未知地址');
      }
    } catch (_) {}
  }

  void _onPOIClick(String name, String poiId, double lat, double lng) {
    if (_lastMapClickLat != null && _lastMapClickLng != null) {
      final dLat = (lat - _lastMapClickLat!).abs();
      final dLng = (lng - _lastMapClickLng!).abs();
      if (dLat > _poiSnapToleranceDeg || dLng > _poiSnapToleranceDeg) {
        _lastMapClickLat = null;
        _lastMapClickLng = null;
        return;
      }
    }
    _lastMapClickLat = null;
    _lastMapClickLng = null;
    _clearPopups();
    _showPopup(() { _poiName = null; _poiLat = null; _poiLng = null; });
    _scheduleState(() { _poiName = name; _poiLat = lat; _poiLng = lng; });
  }

  void _onMarkerClick(String title, String snippet) {
    _clearPopups();
    _showPopup(() { _markerTitle = null; _markerSnippet = null; });
    _scheduleState(() { _tappedAddress = null; _markerTitle = title; _markerSnippet = snippet; });
  }

  // 节流：避免每帧都创建/取消 Timer
  int _lastCameraFrameMs = 0;

  void _onCameraChange(MapViewState state, {bool userInteracting = false}) {
    _currentZoom = state.zoom;
    _currentLat = state.lat;
    _currentLng = state.lng;

    // 用户手势操作且正在导航 → 退出自动追踪（节流到 200ms）
    if (userInteracting) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastCameraFrameMs > 200) {
        _lastCameraFrameMs = now;
        final isNavigating = ref.read(naviInfoProvider).isNavigating;
        if (isNavigating) {
          _naviFollowNeedsResume = true;
          _followCheckTimer?.cancel();
          _send('setNaviFollowMode', args: {'enabled': false});
        }
      }
    }
  }

  /// 检测用户是否将地图归位（回到 GPS 位置附近），如果是则恢复自动追踪
  void _checkMapRealigned() {
    if (!_naviFollowNeedsResume) return;
    if (_lastGpsLat == null || _lastGpsLng == null) return;

    // 计算当前视图中心与 GPS 位置的距离（近似）
    final dLat = (_currentLat - _lastGpsLat!).abs();
    final dLng = (_currentLng - _lastGpsLng!).abs();
    // 大约 0.001 度 ≈ 100 米，取 0.003（约 300 米）作为归位阈值
    if (dLat < 0.003 && dLng < 0.003) {
      _naviFollowNeedsResume = false;
      _followCheckTimer?.cancel();
      _send('setNaviFollowMode', args: {'enabled': true});
    }
  }

  void _clearPopups() {
    _msgTimer?.cancel();
    _scheduleState(() {
      _tappedAddress = null;
      _markerTitle = null;
      _markerSnippet = null;
      _poiName = null;
      _longPressAddress = null;
    });
  }

  // ── Navigation callbacks ──

  void _onNaviRouteCalculated(double distance, int duration, double tollCost) {
    _scheduleState(() { _naviRouteCalculated = true; _errorMsg = null; });
    // Also update route plan state if in planning mode
    if (_routePlanningMode) {
      ref.read(routePlanProvider.notifier).setRoutes([
        RouteInfo(index: 0, distance: distance, duration: duration, tollCost: tollCost),
      ]);
      _fetchRoutePointsAndAddArrows();
    }
  }

  void _onNaviRouteCalculatedWithOptions(double distance, int duration, double tollCost, int routeCount, List<Map<String, dynamic>> routeSummary) {
    final isInitialCalc = routeSummary.isNotEmpty;
    _scheduleState(() {
      _naviRouteCalculated = true;
      _errorMsg = null;
      _hasMultipleRoutes = routeCount > 1;
      _routeCount = routeCount;
      _routeSummary = routeSummary;
      if (isInitialCalc) _selectedRouteIndex = 0;
    });
    if (_routePlanningMode) {
      final List<RouteInfo> routes;
      if (isInitialCalc) {
        routes = routeSummary.map((r) => RouteInfo(
            index: (r['index'] as num?)?.toInt() ?? 0,
            distance: (r['distance'] as num?)?.toDouble() ?? distance,
            duration: (r['duration'] as num?)?.toInt() ?? duration,
            tollCost: (r['tollCost'] as num?)?.toDouble() ?? tollCost,
          )).toList();
        // 如果原生端无法获取所有路线详情，用占位数据补齐到 routeCount
        while (routes.length < routeCount) {
          routes.add(RouteInfo(index: routes.length, distance: distance, duration: duration, tollCost: tollCost));
        }
      } else {
        // 切换路线回传：更新选中那条，保留其他
        final existing = ref.read(routePlanProvider).routes;
        final selIdx = _selectedRouteIndex;
        if (existing.length > 1 && selIdx < existing.length) {
          routes = List<RouteInfo>.from(existing);
          routes[selIdx] = RouteInfo(index: selIdx, distance: distance, duration: duration, tollCost: tollCost);
        } else {
          routes = [RouteInfo(index: 0, distance: distance, duration: duration, tollCost: tollCost)];
        }
      }
      ref.read(routePlanProvider.notifier).setRoutes(routes);
      _fetchRoutePointsAndAddArrows();
    }
  }

  void _onNaviRouteFailed(int errorCode) {
    _setMsg('导航路线计算失败 (错误码: $errorCode)', null);
    _scheduleState(() { _naviRouteCalculated = false; });
  }

  /// Parse duration string from AMap format back to seconds.
  /// Formats: "Z秒", "Y分钟", "X小时", "X小时Y分钟"
  static int _parseDurationToSeconds(String duration) {
    int seconds = 0;
    final hourMatch = RegExp(r'(\d+)小时').firstMatch(duration);
    if (hourMatch != null) {
      seconds += int.parse(hourMatch.group(1)!) * 3600;
    }
    final minMatch = RegExp(r'(\d+)分钟').firstMatch(duration);
    if (minMatch != null) {
      seconds += int.parse(minMatch.group(1)!) * 60;
    }
    if (hourMatch == null && minMatch == null) {
      final secMatch = RegExp(r'(\d+)秒').firstMatch(duration);
      if (secMatch != null) seconds += int.parse(secMatch.group(1)!);
    }
    return seconds;
  }

  Future<void> _selectRoute(int index) async {
    if (index < 0 || index >= _routeCount) return;
    _scheduleState(() => _selectedRouteIndex = index);
    _send('selectRoute', args: {'index': index});
  }

  void _onNaviInfoUpdate(String roadName, int distanceRemain, int timeRemain, String nextRoad,
      {int iconType = 0, int curStepDistance = 0, int speed = 0}) {
    ref.read(naviInfoProvider.notifier).update((n) => n.copyWith(
      roadName: roadName,
      distanceRemain: distanceRemain.toDouble(),
      timeRemain: timeRemain,
      nextRoad: nextRoad,
      iconType: iconType,
      curStepDistance: curStepDistance,
      speed: speed,
      isRecalculating: false,
    ));
  }

  void _onNaviArriveDestination() {
    _stopNavi();
    final action = _currentRouteAction;
    _scheduleState(() {
      _errorMsg = null;
      _showArrivalPage = true;
      _arrivalDestinationName = action?.placeName ?? (action?.destination != null ? '目的地' : '目的地');
      _arrivalTotalDistance = action?.distance ?? 0;
      _arrivalTotalTime = ref.read(naviInfoProvider).timeRemain > 0 ? ref.read(naviInfoProvider).timeRemain : 0;
    });
    ref.read(naviInfoProvider.notifier).update((n) => n.copyWith(
      showNaviSteps: false, isHudMode: false,
    ));
  }

  void _dismissArrivalPage() {
    _scheduleState(() {
      _showArrivalPage = false;
      _arrivalDestinationName = '';
      _arrivalTotalDistance = 0;
      _arrivalTotalTime = 0;
    });
  }

  int _lastLocationDetailMs = 0;

  void _onLocationDetail(Map<String, dynamic> detail) {
    // GPS 每秒回传，节流到 500ms，减少不必要的 rebuild
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastLocationDetailMs < 500) return;
    _lastLocationDetailMs = now;

    final lat = detail['lat'] as double?;
    final lng = detail['lng'] as double?;
    final accuracy = detail['accuracy'] as double?;
    final address = detail['address'] as String? ?? '';

    _scheduleState(() {
      _locationDetail = detail;
      // Store last known location with valid GPS for navi origin fallback
      if (lat != null && lng != null && accuracy != null && accuracy < 100) {
        _lastKnownLocation = detail;
      }
    });

    // 更新 GPS 位置用于归位检测
    if (lat != null && lng != null) {
      _lastGpsLat = lat;
      _lastGpsLng = lng;
      // 检查地图是否已归位，恢复自动追踪
      if (_naviFollowNeedsResume) {
        _checkMapRealigned();
      }
    }

    // 同步 GPS 坐标到路线规划起点（如果起点是"我的位置"且当前在进行路线规划）
    if (lat != null && lng != null && accuracy != null && accuracy < 50) {
      final rpState = ref.read(routePlanProvider);
      if (rpState.isActive && (rpState.startAddress == '我的位置' || rpState.startAddress.isEmpty)) {
        ref.read(routePlanProvider.notifier).updateStartAddress(address, lat, lng);
      }
    }
  }

  void _onMarkerDrag(double lat, double lng) => _setMsg(null, '正在拖动标记: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}');
  void _onMarkerDragEnd(double lat, double lng) => _setMsg(null, '标记已移动到: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}');
  void _onNaviTtsText(String text) {
    ref.read(naviInfoProvider.notifier).update((n) => n.copyWith(naviTtsText: text));
  }
  void _onNaviCrossUpdate(bool visible, {Uint8List? image}) {
    ref.read(naviInfoProvider.notifier).update((n) => n.copyWith(crossVisible: visible, crossImage: visible ? image : null));
  }
  void _onNaviLaneUpdate(bool visible, int count, {Uint8List? image}) {
    ref.read(naviInfoProvider.notifier).update((n) => n.copyWith(laneVisible: visible, laneCount: count, laneImage: visible ? image : null));
  }
  void _onGpsSignalWeak(bool weak) {
    ref.read(naviInfoProvider.notifier).update((n) => n.copyWith(gpsSignalWeak: weak));
  }
  void _onNaviRecalculate(String type) {
    // 偏航或交通拥堵导致重新算路
    ref.read(naviInfoProvider.notifier).update((n) => n.copyWith(isRecalculating: true));
    _setMsg(type == 'traffic' ? '检测到拥堵，正在重新规划路线...' : '检测到偏航，正在重新规划路线...', null);
    // 重新计算路线（使用已存储的起点终点）
    final rpState = ref.read(routePlanProvider);
    if (rpState.startLat != null && rpState.destLat != null) {
      _send('calcNaviRoute', args: {
        'originLat': rpState.startLat,
        'originLng': rpState.startLng,
        'destLat': rpState.destLat,
        'destLng': rpState.destLng,
        'multiRoute': true,
      });
    }
  }
  void _onParallelRoad(int type) {
    ref.read(naviInfoProvider.notifier).update((n) => n.copyWith(
      parallelRoadType: type,
      parallelRoadHint: type == 1 ? '主辅路切换' : (type == 2 ? '高架上下切换' : ''),
    ));
  }

  // ── Distance measurement ──

  void _toggleMeasure() {
    _scheduleState(() {
      if (_isMeasuring) {
        _isMeasuring = false;
        _send('clearMarkers');
        _send('clearRoutes');
        _measurePoints.clear();
        _infoMsg = null;
      } else {
        _isMeasuring = true;
        _measurePoints.clear();
        _setMsg(null, '点击地图添加测量点');
      }
    });
  }

  void _addMeasurePoint(double lat, double lng) async {
    _measurePoints.add(GeoPoint(lng, lat));
    _send('addMarkers', args: {'markers': [
      {'lat': lat, 'lng': lng, 'title': '${_measurePoints.length}', 'snippet': ''}
    ]});
    if (_measurePoints.length >= 2) {
      final pts = _measurePoints.map((p) => [p.lat, p.lng]).toList();
      _send('drawRoute', args: {'points': pts, 'color': 0xFFEF4444, 'width': 6});
      try {
        final total = await _channel?.invokeMethod<double>('measureDistance', {'points': pts});
        if (total != null && mounted) {
          _setMsg(null, '总距离: ${_formatDistance(total)}');
        }
      } catch (_) {}
    }
    if (mounted) _scheduleState(() {});
  }

  // ── Screenshot cache limit sync ──

  Future<void> _applyMapCacheLimit(int limit) async {
    if (_channel == null) return;
    if (limit != _screenshotCacheLimit) {
      _screenshotCacheLimit = limit;
      await _channel?.invokeMethod('setMapCacheLimit', {'limit': limit});
    }
  }

  // ── Screenshot ──

  Future<void> _takeScreenshot() async {
    _scheduleState(() => _isScreenshotting = true);
    try {
      final path = await _channel?.invokeMethod<String>('getScreenshot');
      if (path != null && path.isNotEmpty && mounted) {
        _setMsg(null, '截图已保存');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('截图已保存到: $path'), backgroundColor: PixelTheme.brandBlue, behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      print('[map] error: `$e');
      _setMsg('截图失败: $e', null);
    } finally {
      _scheduleState(() => _isScreenshotting = false);
    }
  }

  Future<void> _executeAiScreenshot() async {
    try {
      final path = await _channel?.invokeMethod<String>('getScreenshot');
      final result = path?.isNotEmpty == true ? path : null;
      ToolExecutor.onScreenshotComplete?.call(result);
    } catch (e) {
      print('[map] error: `$e');
      ToolExecutor.onScreenshotComplete?.call(null);
    } finally {
      ToolExecutor.onScreenshotComplete = null;
    }
  }

  // ── Language ──

  void _toggleLanguage() {
    _scheduleState(() {
      _mapLanguage = _mapLanguage == 'zh' ? 'en' : 'zh';
      _isMapLangEn = !_isMapLangEn;
    });
    _send('setLanguage', args: {'language': _mapLanguage});
  }

  // ── Long press actions ──

  void _navigateToLongPress() {
    if (_longPressLat == null || _longPressLng == null) return;
    final dest = GeoPoint(_longPressLng!, _longPressLat!);
    final name = _longPressAddress;
    _scheduleState(() { _longPressLat = null; _longPressLng = null; _longPressAddress = null; });
    LocationClient().getCurrentPosition().then((loc) {
      final origin = GeoPoint(loc['longitude'] as double, loc['latitude'] as double);
      mapActionBus.value = ShowRouteAction(
        routeType: 'driving', origin: origin, destination: dest,
        placeName: name,
        distance: 0, duration: '', polyline: null,
      );
    }).catchError((_) {
      mapActionBus.value = ShowLocationAction(
        location: dest, name: name, address: name,
      );
    });
  }

  void _addMarkerAtLongPress() {
    if (_longPressLat == null || _longPressLng == null) return;
    _send('addMarkers', args: {'markers': [
      {'lat': _longPressLat!, 'lng': _longPressLng!, 'title': _longPressAddress ?? '标记点', 'snippet': '${_longPressLat!.toStringAsFixed(5)}, ${_longPressLng!.toStringAsFixed(5)}'}
    ]});
    mapActionBus.value = ShowLocationAction(
      location: GeoPoint(_longPressLng!, _longPressLat!),
      name: _longPressAddress ?? '标记点', address: '${_longPressLat!.toStringAsFixed(5)}, ${_longPressLng!.toStringAsFixed(5)}',
    );
    _scheduleState(() { _longPressLat = null; _longPressLng = null; _longPressAddress = null; });
  }

  void _searchNearLongPress() {
    if (_longPressLat == null || _longPressLng == null) return;
    final lat = _longPressLat!;
    final lng = _longPressLng!;
    _scheduleState(() { _longPressLat = null; _longPressLng = null; _longPressAddress = null; });
    SettingsRepository().getAmapApiKey().then((key) {
      if (key.isEmpty) return;
      AmapClient(apiKey: key).searchNearby(GeoPoint(lng, lat), 1000).then((result) {
        if (result.pois.isNotEmpty) {
          mapActionBus.value = ShowPoisAction(title: '周边地点', pois: result.pois);
        }
      });
    });
  }

  // ── POI actions ──

  void _navigateToPoi() {
    if (_poiLat == null || _poiLng == null) return;
    final dest = GeoPoint(_poiLng!, _poiLat!);
    final name = _poiName; // 在清除前保存
    _scheduleState(() { _poiName = null; _poiLat = null; _poiLng = null; });
    LocationClient().getCurrentPosition().then((loc) {
      final origin = GeoPoint(loc['longitude'] as double, loc['latitude'] as double);
      mapActionBus.value = ShowRouteAction(
        routeType: 'driving', origin: origin, destination: dest,
        placeName: name, distance: 0, duration: '', polyline: null,
      );
    }).catchError((_) {
      mapActionBus.value = ShowLocationAction(location: dest, name: name, address: null);
    });
  }

  // ── Helpers ──

  Map<String, dynamic> _poiToMarker(PoiItem p) => {'lat': p.location.lat, 'lng': p.location.lng, 'title': p.name, 'snippet': p.address};

  void _fitBoundsForMarkers(List<Map<String, dynamic>> markers) {
    if (markers.isEmpty) return;
    double minLat = double.infinity, maxLat = double.negativeInfinity;
    double minLng = double.infinity, maxLng = double.negativeInfinity;
    for (final m in markers) {
      final lat = (m['lat'] as num).toDouble();
      final lng = (m['lng'] as num).toDouble();
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }
    _send('fitBounds', args: {'lat1': minLat, 'lng1': minLng, 'lat2': maxLat, 'lng2': maxLng, 'padding': 120});
  }

  void _fitBoundsForPoints(List<GeoPoint> points) {
    if (points.isEmpty) return;
    double minLat = double.infinity, maxLat = double.negativeInfinity;
    double minLng = double.infinity, maxLng = double.negativeInfinity;
    for (final p in points) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lng < minLng) minLng = p.lng;
      if (p.lng > maxLng) maxLng = p.lng;
    }
    _send('fitBounds', args: {'lat1': minLat, 'lng1': minLng, 'lat2': maxLat, 'lng2': maxLng, 'padding': 120});
  }

  /// 解析道路坐标串 (x1,y1;x2,y2;...) -> List<GeoPoint>
  List<GeoPoint> _parseRoadPolyline(String polyline) {
    if (polyline.isEmpty) return [];
    final points = <GeoPoint>[];
    for (final seg in polyline.split(';')) {
      final parts = seg.split(',');
      if (parts.length == 2) {
        final lng = double.tryParse(parts[0]);
        final lat = double.tryParse(parts[1]);
        if (lng != null && lat != null) {
          points.add(GeoPoint(lat, lng)); // 注意：高德道路坐标串是 lng,lat 顺序
        }
      }
    }
    return points;
  }

  int _routeColor(String type) => switch (type) {
    'driving' => 0xFF4F6EF7, 'walking' => 0xFF10B981, 'cycling' => 0xFFF59E0B, 'transit' => 0xFF8B5CF6, _ => 0xFF4F6EF7,
  };

  String _formatDistance(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} 公里';
    return '${meters.toInt()} 米';
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '$seconds秒';
    final min = seconds ~/ 60;
    if (min < 60) return '$min分钟';
    final h = min ~/ 60;
    final m = min % 60;
    return '$h小时$m分钟';
  }

  void _clearAction() {
    _send('clearMarkers');
    _send('clearRoutes');
    _send('clearPolygons');
    _send('clearCircles');
    _stopNavi();
    _scheduleState(() {
      _routePlanningMode = false;
      _hasMapAction = false;
      _actionTitle = '';
      _actionSubtitle = '';
      _actionRouteType = null;
      _naviRouteCalculated = false;
      _currentRouteAction = null;
      _measurePoints.clear();
      _isMeasuring = false;
    });
    ref.read(routePlanProvider.notifier).dismiss();
  }

  void _onPlatformViewCreated(int id) {
    _channel = MethodChannel('com.myminimax/amap_view_$id');
    _channel?.setMethodCallHandler((call) {
      final args = call.arguments as Map?;
      switch (call.method) {
        case 'onMapClick':
          _onMapClick((args?['lat'] as num).toDouble(), (args?['lng'] as num).toDouble());
          break;
        case 'onMapLongClick':
          _onMapLongClick((args?['lat'] as num).toDouble(), (args?['lng'] as num).toDouble());
          break;
        case 'onPOIClick':
          _onPOIClick(args?['name'] as String? ?? '', args?['poiId'] as String? ?? '', (args?['lat'] as num).toDouble(), (args?['lng'] as num).toDouble());
          break;
        case 'onMarkerClick':
          _onMarkerClick(args?['title'] as String? ?? '', args?['snippet'] as String? ?? '');
          break;
        case 'onCameraChange':
          final userInteracting = args?['userInteracting'] as bool? ?? false;
          _onCameraChange(
            MapViewState(
              lat: (args?['lat'] as num?)?.toDouble() ?? 0, lng: (args?['lng'] as num?)?.toDouble() ?? 0,
              zoom: (args?['zoom'] as num?)?.toDouble() ?? 0, tilt: (args?['tilt'] as num?)?.toDouble() ?? 0,
              bearing: (args?['bearing'] as num?)?.toDouble() ?? 0,
              swLat: (args?['swLat'] as num?)?.toDouble() ?? 0, swLng: (args?['swLng'] as num?)?.toDouble() ?? 0,
              neLat: (args?['neLat'] as num?)?.toDouble() ?? 0, neLng: (args?['neLng'] as num?)?.toDouble() ?? 0,
            ),
            userInteracting: userInteracting,
          );
          break;
        case 'onNaviRouteCalculated':
          final routeCount = (args?['routeCount'] as num?)?.toInt() ?? 1;
          final summaryRaw = (args?['routeSummary'] as List<dynamic>?) ?? [];
          final summary = summaryRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _onNaviRouteCalculatedWithOptions(
            (args?['distance'] as num?)?.toDouble() ?? 0,
            (args?['duration'] as num?)?.toInt() ?? 0,
            (args?['tollCost'] as num?)?.toDouble() ?? 0,
            routeCount,
            summary,
          );
          break;
        case 'onNaviRouteFailed':
          _onNaviRouteFailed((args?['errorCode'] as num?)?.toInt() ?? -1);
          break;
        case 'onNaviInfoUpdate':
          _onNaviInfoUpdate(
            args?['roadName'] as String? ?? '',
            (args?['distanceRemain'] as num?)?.toInt() ?? 0,
            (args?['timeRemain'] as num?)?.toInt() ?? 0,
            args?['nextRoad'] as String? ?? '',
            iconType: (args?['iconType'] as num?)?.toInt() ?? 0,
            curStepDistance: (args?['curStepDistance'] as num?)?.toInt() ?? 0,
            speed: (args?['speed'] as num?)?.toInt() ?? 0,
          );
          break;
        case 'onNaviArriveDestination':
          _onNaviArriveDestination();
          break;
        case 'onLocationDetail':
          if (args != null) _onLocationDetail(Map<String, dynamic>.from(args));
          break;
        case 'onMarkerDrag':
          _onMarkerDrag((args?['lat'] as num).toDouble(), (args?['lng'] as num).toDouble());
          break;
        case 'onMarkerDragEnd':
          _onMarkerDragEnd((args?['lat'] as num).toDouble(), (args?['lng'] as num).toDouble());
          break;
        case 'onNaviTtsText':
          _onNaviTtsText(args?['text'] as String? ?? '');
          break;
        case 'onNaviCrossUpdate':
          _onNaviCrossUpdate(args?['visible'] as bool? ?? false,
            image: (args?['image'] as Uint8List?));
          break;
        case 'onNaviLaneUpdate':
          _onNaviLaneUpdate(args?['visible'] as bool? ?? false,
            (args?['laneCount'] as num?)?.toInt() ?? 0,
            image: (args?['image'] as Uint8List?));
          break;
        case 'onGpsSignalWeak':
          _onGpsSignalWeak(args?['weak'] as bool? ?? false);
          break;
        case 'onNaviStarted':
          ref.read(naviInfoProvider.notifier).update((n) => n.copyWith(isNavigating: true));
          break;
        case 'onNaviFollowInterrupted':
          ref.read(naviInfoProvider.notifier).update((n) => n.copyWith(isUserInteracting: true));
          break;
        case 'onNaviRecalculate':
          _onNaviRecalculate(args?['type'] as String? ?? '');
          break;
        case 'onOverviewModeChanged':
          ref.read(naviInfoProvider.notifier).update((n) => n.copyWith(isOverviewMode: args?['isOverview'] as bool? ?? false));
          break;
        case 'onParallelRoad':
          final type = args?['type'] as int? ?? 0;
          ref.read(naviInfoProvider.notifier).update((n) => n.copyWith(
            parallelRoadType: type,
            parallelRoadHint: type == 1 ? '主辅路切换' : (type == 2 ? '高架上下切换' : ''),
          ));
          break;
        case 'onHudModeChanged':
          ref.read(naviInfoProvider.notifier).update((n) => n.copyWith(isHudMode: args?['isHud'] as bool? ?? false));
          break;
        case 'onMapLoaded':
          _cancelTileLoadTimer();
          _tileRetryCount = 0;
          break;
      }
      return Future.value();
    });
    // Channel 就绪后首帧生成用户定位图标
    _generateUserMarkerIcon();
    // 地图加载后请求定位，收到 GPS 后移到用户位置
    Future.delayed(const Duration(milliseconds: 100), () { if (mounted) _doLocate(silent: true); });
    // 瓦片加载超时检测：OnMapLoaded 未在 15s 内触发 → 自动重建
    _startTileLoadTimer();
  }

  /// Timeout durations per retry attempt (index 0 = first, 1 = second, 2 = third).
  static const _tileRetryDelays = [8, 12, 18];

  void _cancelTileLoadTimer() {
    _tileLoadTimer?.cancel();
    _tileLoadTimer = null;
  }

  void _startTileLoadTimer() {
    // Only start timer when key is configured — otherwise the hint overlay is shown
    if (_amapNativeKey == null || _amapNativeKey!.isEmpty) return;
    _cancelTileLoadTimer();
    final delay = _tileRetryDelays[_tileRetryCount.clamp(0, _tileRetryDelays.length - 1)];
    _tileLoadTimer = Timer(Duration(seconds: delay), _onTileLoadTimeout);
  }

  void _onTileLoadTimeout() {
    if (!mounted) return;
    // Double-check key is still configured
    if (_amapNativeKey == null || _amapNativeKey!.isEmpty) return;
    if (_tileRetryCount >= _tileRetryDelays.length) {
      debugPrint('[MapPage] Tile load failed after $_tileRetryCount retries, giving up');
      return;
    }
    _tileRetryCount++;
    debugPrint('[MapPage] Tile load timeout #$_tileRetryCount — refreshing map');
    // 轻量级刷新瓦片，不重建 PlatformView（避免 OOM）
    _send('refreshMap');
    // 重新启动定时器等待下一次超时
    _startTileLoadTimer();
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsChangedProvider, (prev, _) => _loadAmapNativeKey());
    ref.listen(mapCacheLimitProvider, (_, limit) => _applyMapCacheLimit(limit));
    ref.listen(mapScreenshotRequestProvider, (_, request) {
      if (request != null) _executeAiScreenshot();
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isNavigating = ref.watch(naviInfoProvider.select((n) => n.isNavigating));

    return Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: isDark ? PixelTheme.darkBase : PixelTheme.background,
        body: SafeArea(
          child: Stack(
          children: [
            if (!_keyLoaded)
              const Center(child: CircularProgressIndicator())
            else if (_amapNativeKey != null && _amapNativeKey!.isNotEmpty)
              AndroidView(
              key: ValueKey('amap_view_$_viewVersion'),
              viewType: _viewType,
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
              },
              creationParams: _amapNativeKey,
              creationParamsCodec: const StandardMessageCodec(),
              onPlatformViewCreated: _onPlatformViewCreated,
            ),

            // ── Key 缺失/认证失败 → 智能重建提示 ──
            if (_keyLoaded && (_amapNativeKey == null || _amapNativeKey!.isEmpty))
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => _retryMap(),
                  child: Container(
                    color: isDark ? Colors.black54 : Colors.white54,
                    child: Center(
                      child: GestureDetector(
                        onTap: () {}, // block tap-through to map
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 40),
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                          decoration: BoxDecoration(
                            color: isDark ? PixelTheme.darkSurface : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: const Offset(0, 6))],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.map_outlined, size: 48, color: isDark ? Colors.orange.shade300 : Colors.orange.shade600),
                              const SizedBox(height: 16),
                              Text('地图 Key 未配置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
                              const SizedBox(height: 8),
                              Text('请在设置→第三方 API 中填入 Android Native SDK Key', textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black54)),
                              const SizedBox(height: 20),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _RetryButton(
                                    label: '去设置',
                                    icon: Icons.settings,
                                    onTap: () => _navigateToSettings(),
                                  ),
                                  const SizedBox(width: 12),
                                  _RetryButton(
                                    label: '重试',
                                    icon: Icons.refresh,
                                    onTap: () => _retryMap(),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // ── Search bar (full width at top) ──
            Positioned(
              left: 62, right: 64, top: 20,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: isDark ? PixelTheme.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 2))],
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(fontSize: 14, color: isDark ? Colors.white : PixelTheme.primaryText),
                    decoration: InputDecoration(
                      hintText: _isMeasuring ? _t('map.measure_hint', '点击地图测距...') : _t('map.search_hint', '搜索地点...'),
                      hintStyle: TextStyle(fontSize: 14, color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted),
                      prefixIcon: _isSearching
                          ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                          : Icon(_isMeasuring ? Icons.straighten : Icons.search, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { _searchController.clear(); _scheduleState(() { _searchTips = []; _showSearchTips = false; }); }) : null,
                      border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: (v) {
                      _fetchSearchTipsDebounced(v);
                    },
                    onSubmitted: _isMeasuring ? null : (v) => _doSearch(v),
                    readOnly: _isMeasuring,
                  ),
                ),
                // Search tips dropdown
                if (_showSearchTips && _searchTips.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      color: isDark ? PixelTheme.darkSurface : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 2))],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _searchTips.length,
                        itemBuilder: _buildSearchTipItem,
                      ),
                    ),
                  ),
              ]),
            ),

            // ── Left toolbar column ──
            Positioned(
              left: 14, top: 66,
              child: _CollapsibleToolbar(
                isDark: isDark,
                isCollapsed: _isLeftCollapsed,
                isLeft: true,
                onToggle: () => _scheduleState(() => _isLeftCollapsed = !_isLeftCollapsed),
                buttons: [
                  _ToolbarBtn(icon: '🗺', isActive: operationHistory.value.isNotEmpty, onTap: () { _showMapActionHistory(); _scheduleState(() {}); }),
                  _ToolbarBtn(icon: '🌙', isActive: _isDark, onTap: () { _isDark = !_isDark; _send('setDark', args: {'enabled': _isDark}); _scheduleState(() {}); }),
                  _ToolbarBtn(icon: '📋', isActive: false, onTap: () => _showLocationInfo()),
                  _ToolbarBtn(icon: '📷', isActive: false, onTap: _isScreenshotting ? null : () => _takeScreenshot()),
                  _ToolbarBtn(icon: _mapLanguage == 'zh' ? '🇨🇳' : '🇬🇧', isActive: _isMapLangEn, onTap: () => _toggleLanguage()),
                ],
              ),
            ),

            // ── Right toolbar column ──
            Positioned(
              right: 8,
              top: _showSearchTips && _searchTips.isNotEmpty ? 274 : 66,
              child: _CollapsibleToolbar(
                isDark: isDark,
                isCollapsed: _isRightCollapsed,
                isLeft: false,
                onToggle: () => _scheduleState(() => _isRightCollapsed = !_isRightCollapsed),
                buttons: [
                  _ToolbarBtn(icon: '🏙', isActive: _is3D, onTap: () { _is3D = !_is3D; _send('set3D', args: {'enabled': _is3D}); _scheduleState(() {}); }),
                  _ToolbarBtn(icon: '🚥', isActive: _isTraffic, onTap: () { _isTraffic = !_isTraffic; _send('setTraffic', args: {'enabled': _isTraffic}); _scheduleState(() {}); }),
                  _ToolbarBtn(icon: '🛰', isActive: _isSatellite, onTap: () { _isSatellite = !_isSatellite; _send('setSatellite', args: {'enabled': _isSatellite}); _scheduleState(() {}); }),
                  _ToolbarBtn(icon: '📍', isActive: false, onTap: () => _doLocate()),
                  _ToolbarBtn(icon: '📏', isActive: _isMeasuring, onTap: () => _toggleMeasure()),
                ],
              ),
            ),

            // ── Operation history popup (below navi/route-planning, next to left toolbar) ──
            if (_showHistoryPopup && !isNavigating && !_routePlanningMode)
              Stack(children: [
                // Tap map background to dismiss
                Positioned.fill(child: GestureDetector(
                  onTap: () => _scheduleState(() => _showHistoryPopup = false),
                  behavior: HitTestBehavior.translucent,
                )),
                Positioned(left: 60, top: 66, child: Material(
                  borderRadius: BorderRadius.circular(10),
                  color: isDark ? PixelTheme.darkSurface : Colors.white,
                  elevation: 4,
                  child: Container(
                    width: 220,
                    height: 180,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isDark ? PixelTheme.darkBorderDefault : PixelTheme.border, width: 0.5),
                    ),
                    child: Column(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                          border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.history, size: 16, color: PixelTheme.brandBlue),
                          const SizedBox(width: 6),
                          const Text('操作历史', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => _scheduleState(() => _showHistoryPopup = false),
                            child: const Icon(Icons.close, size: 16, color: Colors.grey),
                          ),
                        ]),
                      ),
                      Expanded(child: operationHistory.value.isEmpty
                        ? Center(child: Text('暂无操作记录', style: TextStyle(fontSize: 12, color: Colors.grey[500])))
                        : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: operationHistory.value.length,
                          itemBuilder: (ctx, idx) {
                            final record = operationHistory.value[idx];
                            return InkWell(
                              onTap: () {
                                _scheduleState(() => _showHistoryPopup = false);
                                _handleMapAction(record.action);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(children: [
                                  Icon(record.icon, size: 14, color: PixelTheme.brandBlue),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(record.summary, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                  Text('${record.timestamp.hour}:${record.timestamp.minute.toString().padLeft(2, '0')}', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                                ]),
                              ),
                            );
                          },
                        )),
                    ]),
                  ),
                )),
              ]),

            // ── Error / Info card (only when NOT measuring; during measure info is in _measureCard) ──
            if (_errorMsg != null && !_isMeasuring)
              Positioned(left: 14, right: 60, top: 120, child: _msgCard(_errorMsg!, isError: true, onDismiss: () => _scheduleState(() { _errorMsg = null; }))),
            if (_infoMsg != null && !_isMeasuring)
              Positioned(left: 14, right: 60, top: 120, child: _msgCard(_infoMsg!, isError: false, onDismiss: () => _scheduleState(() { _infoMsg = null; }))),

            // ── POI info card ──
            if (_poiName != null)
              Positioned(left: 58, right: 58, top: 62, child: _poiInfoSheet(
                isDark: isDark,
                name: _poiName ?? '',
                onNavigate: _navigateToPoi,
                onClose: () => _scheduleState(() { _poiName = null; _poiLat = null; _poiLng = null; }),
              )),

            // ── Marker info ──
            if (_markerTitle != null && _markerTitle!.isNotEmpty)
              Positioned(left: 14, right: 14, bottom: _calculateBottomOffset(), child: _markerInfoSheet(
                isDark: isDark,
                title: _markerTitle ?? '',
                snippet: _markerSnippet,
                onClose: () => _scheduleState(() { _markerTitle = null; _markerSnippet = null; }),
              )),

            // ── Tapped address ──
            if (_tappedAddress != null && _markerTitle == null)
              Positioned(left: 58, right: 58, top: 62, child: _addressSheet(
                isDark: isDark,
                address: _tappedAddress ?? '',
                onClose: () => _scheduleState(() => _tappedAddress = null),
              )),

            // ── Arrival page ──
            if (_showArrivalPage)
              Positioned(left: 0, right: 0, top: 0, child: _arrivalPage(
                isDark: isDark,
                destinationName: _arrivalDestinationName ?? '',
                totalDistance: _arrivalTotalDistance,
                totalTime: _arrivalTotalTime,
                onDismiss: _dismissArrivalPage,
                onViewDestination: () {
                  if (_currentRouteAction != null) {
                    _send('moveCamera', args: {'lat': _currentRouteAction!.destination.lat, 'lng': _currentRouteAction!.destination.lng, 'zoom': 16});
                  }
                  _dismissArrivalPage();
                },
              )),

            // ── Navigation overlay (isolated, only rebuilds on navi state) ──
            if (isNavigating)
              Positioned(left: 0, right: 0, top: 0, child: _NaviInfoPanel(
                onToggleNaviMapMode: _toggleNaviMapMode,
                onToggleOverviewMode: _toggleOverviewMode,
                onToggleNaviSteps: _toggleNaviSteps,
                onSwitchParallelRoad: _switchParallelRoad,
                onStopNavi: _stopNavi,
                onSetMuted: (muted) => _send('setNaviMuted', args: {'muted': muted}),
              )),

            // ── Measure + info card (combined) ──
            if (_isMeasuring)
              Positioned(left: 58, right: 58, top: 62, child: _measureCard(
                isDark: isDark,
                pointCount: _measurePoints.length,
                distanceInfo: _infoMsg,
                onComplete: _toggleMeasure,
              )),

            // ── Route Planning Overlay (高德-style full route planning UI) ──
            if (_routePlanningMode && !_isMeasuring && !isNavigating && !ref.watch(routePlanProvider.select((r) => r.isNavigating)))
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: false,
                  child: RoutePlanningOverlay(
                    onClear: () {
                      _routePlanningMode = false;
                      _clearAction();
                    },
                    send: _send,
                    currentZoom: _currentZoom,
                    currentLat: _currentLat,
                    currentLng: _currentLng,
                  ),
                ),
              ),

          ],
        ),
      ),
  );
  }

  Widget _buildSearchTipItem(BuildContext ctx, int i) {
    final tip = _searchTips[i];
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.location_on, size: 18, color: PixelTheme.brandBlue),
        title: Text(tip.name, style: TextStyle(fontSize: 13, color: isDark ? Colors.white : PixelTheme.primaryText), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${tip.address}${tip.district != null ? ' · ${tip.district}' : ''}', style: TextStyle(fontSize: 11, color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () => _onSearchTipSelected(tip),
      ),
    );
  }

  double _floatingBallBottomOffset() {
    // Avoid overlapping with _actionBar (bottom: 20 + height ~100)
    if (ref.watch(naviInfoProvider).isNavigating) return 170;
    if (_hasMapAction) return 130;
    return 130;
  }

  double _calculateBottomOffset() {
    if (ref.watch(naviInfoProvider.select((n) => n.isNavigating))) return 64;
    if (_hasMapAction) return 100;
    if (_longPressLat != null) return 100;
    return 100;
  }
}

// ── Toolbar widgets ──

class _ToolbarBtn {
  final String icon;
  final bool isActive;
  final VoidCallback? onTap;
  const _ToolbarBtn({required this.icon, required this.isActive, required this.onTap});
}

class _CollapsibleToolbar extends StatelessWidget {
  final bool isDark;
  final bool isCollapsed;
  final bool isLeft;
  final List<_ToolbarBtn> buttons;
  final VoidCallback onToggle;

  const _CollapsibleToolbar({
    required this.isDark,
    required this.isCollapsed,
    required this.isLeft,
    required this.buttons,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final pillBg = isDark ? const Color(0xF02A2A3C) : const Color(0xF0FFFFFF);
    final pillShadow = [
      BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.08), blurRadius: 6, offset: const Offset(0, 1)),
    ];

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOutCubic,
      alignment: isLeft ? Alignment.topRight : Alignment.topLeft,
      child: isCollapsed
          ? GestureDetector(
              onTap: onToggle,
              child: Container(
                width: 28, height: 24,
                decoration: BoxDecoration(
                  color: pillBg,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: pillShadow,
                ),
                alignment: Alignment.center,
                child: Icon(
                  isLeft ? Icons.chevron_right : Icons.chevron_left,
                  size: 16,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Collapse toggle pill
                GestureDetector(
                  onTap: onToggle,
                  child: Container(
                    width: 36, height: 20,
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: pillBg,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: pillShadow,
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isLeft ? Icons.chevron_left : Icons.chevron_right,
                          size: 10,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                        Icon(
                          isLeft ? Icons.chevron_left : Icons.chevron_right,
                          size: 10,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ],
                    ),
                  ),
                ),
                // Regular buttons
                ...buttons.map((b) => _ToolbarButton(btn: b, isDark: isDark)),
              ],
            ),
    );
  }
}

class _ToolbarColumn extends StatelessWidget {
  final bool isDark;
  final List<_ToolbarBtn> buttons;
  const _ToolbarColumn({required this.isDark, required this.buttons});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: buttons.map((b) => _ToolbarButton(btn: b, isDark: isDark)).toList(),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final _ToolbarBtn btn;
  final bool isDark;
  const _ToolbarButton({required this.btn, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final disabled = btn.onTap == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GestureDetector(
        onTap: btn.onTap,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: disabled ? const Color(0xFFE0E0E0) : (btn.isActive ? PixelTheme.brandBlue : const Color(0xF5FFFFFF)),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 1))],
          ),
          alignment: Alignment.center,
          child: Text(btn.icon, style: TextStyle(fontSize: 14, color: disabled ? const Color(0xFF9E9E9E) : null)),
        ),
      ),
    );
  }
}

// ── NaviInfoPanel — only rebuilds on navi state changes, not full MapPage ──

class _NaviInfoPanel extends ConsumerWidget {
  final VoidCallback onToggleNaviMapMode;
  final VoidCallback onToggleOverviewMode;
  final VoidCallback onToggleNaviSteps;
  final void Function(int) onSwitchParallelRoad;
  final VoidCallback onStopNavi;
  final void Function(bool muted) onSetMuted;

  const _NaviInfoPanel({
    required this.onToggleNaviMapMode,
    required this.onToggleOverviewMode,
    required this.onToggleNaviSteps,
    required this.onSwitchParallelRoad,
    required this.onStopNavi,
    required this.onSetMuted,
  });

  Widget _naviTurnIcon(int iconType) {
    final icon = switch (iconType) {
      1 => Icons.arrow_upward,
      2 => Icons.turn_left,
      3 => Icons.turn_right,
      4 => Icons.turn_slight_left,
      5 => Icons.turn_slight_right,
      6 => Icons.turn_sharp_left,
      7 => Icons.turn_sharp_right,
      8 || 9 => Icons.u_turn_left,
      10 => Icons.arrow_left,
      11 => Icons.arrow_right,
      12 || 13 => Icons.traffic,
      14 || 15 => Icons.flag,
      _ => Icons.navigation,
    };
    return Icon(icon, size: 36, color: const Color(0xFF4F6EF7));
  }

  String _naviTurnText(NaviInfo n) {
    final distStr = n.curStepDistance > 0 ? _formatDistanceStatic(n.curStepDistance.toDouble()) : '';
    final action = switch (n.iconType) {
      1 => '直行', 2 => '左转', 3 => '右转',
      4 => '左前方', 5 => '右前方', 6 => '左后方', 7 => '右后方',
      8 || 9 => '掉头', 10 => '靠左', 11 => '靠右',
      12 => '进入环岛', 13 => '驶出环岛', 14 || 15 => '到达',
      _ => '',
    };
    if (action.isEmpty) return '';
    if (distStr.isEmpty) return action;
    return '$distStr后 $action';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(naviInfoProvider);

    return Material(
      color: const Color(0xFF1A1A2E), elevation: 4,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (n.isRecalculating)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                child: const Row(children: [
                  SizedBox(width: 8, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF59E0B))),
                  SizedBox(width: 8),
                  Text('正在重新规划路线...', style: TextStyle(fontSize: 12, color: Color(0xFFF59E0B))),
                ]),
              ),
            if (n.parallelRoadHint.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                child: Row(children: [
                  const Icon(Icons.swap_horiz, size: 16, color: Color(0xFF10B981)),
                  const SizedBox(width: 8),
                  Text(n.parallelRoadHint, style: const TextStyle(fontSize: 12, color: Color(0xFF10B981))),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => onSwitchParallelRoad(n.parallelRoadType),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFF10B981), borderRadius: BorderRadius.circular(4)),
                      child: const Text('切换', style: TextStyle(fontSize: 11, color: Colors.white)),
                    ),
                  ),
                ]),
              ),
            // ── Turn direction arrow + instruction ──
            if (n.iconType > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  _naviTurnIcon(n.iconType),
                  const SizedBox(width: 8),
                  Text(
                    _naviTurnText(n),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  if (n.curStepDistance > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      _formatDistanceStatic(n.curStepDistance.toDouble()),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF4F6EF7)),
                    ),
                  ],
                ]),
              ),
            // ── Current road + next road ──
            if (n.roadName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(children: [
                  Expanded(child: Text(n.roadName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFFCBD5E1)), overflow: TextOverflow.ellipsis)),
                  if (n.nextRoad.isNotEmpty) ...[
                    const Icon(Icons.arrow_forward, size: 14, color: Color(0xFF64748B)),
                    const SizedBox(width: 2),
                    Flexible(child: Text(n.nextRoad, style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)), overflow: TextOverflow.ellipsis)),
                  ],
                ]),
              ),
            // ── Junction/cross image ──
            if (n.crossVisible && n.crossImage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(n.crossImage!, height: 140, fit: BoxFit.contain),
                ),
              ),
            // ── Lane guidance ──
            if (n.laneVisible && n.laneImage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(n.laneImage!, height: 40, fit: BoxFit.contain),
                ),
              ),
            // ── Bottom bar: remaining info + speed + controls ──
            Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  '${_formatDistanceStatic(n.distanceRemain)} · ${_formatDurationStatic(n.timeRemain)}',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                ),
                if (n.naviTtsText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(children: [
                      const Icon(Icons.volume_up, size: 12, color: Color(0xFF10B981)),
                      const SizedBox(width: 2),
                      Flexible(child: Text(n.naviTtsText, style: const TextStyle(fontSize: 11, color: Color(0xFF10B981)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ]),
                  ),
                if (n.gpsSignalWeak)
                  const Text('GPS信号弱', style: TextStyle(fontSize: 11, color: Color(0xFFEF4444))),
                if (n.speed > 0)
                  Text('${n.speed} km/h', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
              ]),
              const Spacer(),
              Column(children: [
                _NaviControlChip(
                  icon: Icon(n.naviMapMode == 0 ? Icons.navigation : Icons.explore, size: 16, color: Colors.white),
                  label: n.naviMapMode == 0 ? '车头' : '北向',
                  onTap: onToggleNaviMapMode,
                ),
                const SizedBox(height: 4),
                _NaviControlChip(
                  icon: Icon(n.isOverviewMode ? Icons.map : Icons.map_outlined, size: 16, color: Colors.white),
                  label: '全览',
                  active: n.isOverviewMode,
                  activeColor: const Color(0xFF10B981),
                  onTap: onToggleOverviewMode,
                ),
                const SizedBox(height: 4),
                _NaviControlChip(
                  icon: Icon(n.isMuted ? Icons.volume_off : Icons.volume_up, size: 16, color: Colors.white),
                  label: n.isMuted ? '静音' : '播报',
                  active: n.isMuted,
                  activeColor: const Color(0xFFEF4444),
                  onTap: () {
                    final newMuted = !n.isMuted;
                    ref.read(naviInfoProvider.notifier).update((ni) => ni.copyWith(isMuted: newMuted));
                    onSetMuted(newMuted);
                  },
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: onStopNavi,
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(6)), child: const Text('退出', style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600))),
                ),
              ]),
            ]),
            if (n.naviSteps.isNotEmpty)
              GestureDetector(
                onTap: onToggleNaviSteps,
                child: Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF374151), borderRadius: BorderRadius.circular(6)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(n.showNaviSteps ? Icons.expand_less : Icons.expand_more, size: 14, color: Colors.white),
                    const SizedBox(width: 2),
                    Text(n.showNaviSteps ? '收起步骤' : '导航步骤', style: const TextStyle(fontSize: 11, color: Colors.white)),
                  ]),
                ),
              ),
            if (n.showNaviSteps && n.naviSteps.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(color: const Color(0xFF252A3A), borderRadius: BorderRadius.circular(8)),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: n.naviSteps.length,
                  padding: EdgeInsets.zero,
                  itemBuilder: (ctx, idx) => _NaviStepItem(step: n.naviSteps[idx], index: idx),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}


/// Internal navi bar control chip.
class _NaviControlChip extends StatelessWidget {
  final Widget icon;
  final String label;
  final bool active;
  final Color? activeColor;
  final VoidCallback onTap;
  const _NaviControlChip({required this.icon, required this.label, this.active = false, this.activeColor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(color: active ? (activeColor ?? const Color(0xFF374151)) : const Color(0xFF374151), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [icon, const SizedBox(width: 4), Text(label, style: const TextStyle(fontSize: 12, color: Colors.white))]),
      ),
    );
  }
}

class _NaviStepItem extends StatelessWidget {
  final Map<String, dynamic> step;
  final int index;
  const _NaviStepItem({required this.step, required this.index});

  @override
  Widget build(BuildContext context) {
    final instruction = step['instruction'] as String? ?? '';
    final roadName = step['roadName'] as String? ?? '';
    final distance = (step['distance'] as num?)?.toDouble() ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        Container(
          width: 20, height: 20,
          decoration: BoxDecoration(color: const Color(0xFF4F6EF7).withValues(alpha: 0.3), shape: BoxShape.circle),
          child: Center(child: Text('${index + 1}', style: const TextStyle(fontSize: 10, color: Colors.white))),
        ),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(instruction, style: const TextStyle(fontSize: 12, color: Colors.white), maxLines: 2, overflow: TextOverflow.ellipsis),
          if (roadName.isNotEmpty) Text('$roadName · ${_formatDistanceStatic(distance)}', style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
        ])),
      ]),
    );
  }
}

class _HudOverlayPanel extends ConsumerWidget {
  final Map<String, dynamic> locationDetail;
  const _HudOverlayPanel({required this.locationDetail});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(naviInfoProvider);

    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Stack(
          children: [
            // Top bar
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Color(0xCC000000), Colors.transparent],
                  ),
                ),
                child: Row(children: [
                  GestureDetector(
                    onTap: () => ref.read(naviInfoProvider.notifier).update((ni) => ni.copyWith(isHudMode: false)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.close, size: 18, color: Colors.white),
                        SizedBox(width: 4),
                        Text('退出HUD', style: TextStyle(fontSize: 12, color: Colors.white)),
                      ]),
                    ),
                  ),
                  const Spacer(),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('${(locationDetail['speed'] as num?)?.toInt() ?? 0}', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.white)),
                    const Text('km/h', style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8))),
                  ]),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: n.gpsSignalWeak ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(n.gpsSignalWeak ? Icons.gps_off : Icons.gps_fixed, size: 16, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(n.gpsSignalWeak ? '信号弱' : '信号强', style: const TextStyle(fontSize: 12, color: Colors.white)),
                    ]),
                  ),
                ]),
              ),
            ),
            // Center
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_formatDistanceStatic(n.distanceRemain), style: const TextStyle(fontSize: 72, fontWeight: FontWeight.w200, color: Colors.white, letterSpacing: 4)),
                const SizedBox(height: 8),
                Text('剩余 ${_formatDurationStatic(n.timeRemain)}', style: const TextStyle(fontSize: 24, color: Color(0xFF94A3B8))),
                const SizedBox(height: 40),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(n.roadName.isNotEmpty ? n.roadName : '正在定位...', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
                const SizedBox(height: 16),
                if (n.nextRoad.isNotEmpty)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.arrow_forward, size: 32, color: Color(0xFF4F6EF7)),
                    const SizedBox(width: 12),
                    Text(n.nextRoad, style: const TextStyle(fontSize: 24, color: Color(0xFF94A3B8))),
                  ]),
              ]),
            ),
            // Bottom bar
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter, end: Alignment.topCenter,
                    colors: [Color(0xCC000000), Colors.transparent],
                  ),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (n.naviTtsText.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)),
                      child: Row(children: [
                        const Icon(Icons.volume_up, size: 20, color: Color(0xFF10B981)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(n.naviTtsText, style: const TextStyle(fontSize: 18, color: Colors.white))),
                      ]),
                    ),
                  if (n.naviTtsText.isNotEmpty) const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    if (n.crossVisible)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.3), borderRadius: BorderRadius.circular(6)),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.turn_right, size: 20, color: Color(0xFFF59E0B)),
                          SizedBox(width: 8),
                          Text('路口放大', style: TextStyle(fontSize: 14, color: Color(0xFFF59E0B))),
                        ]),
                      ),
                    if (n.laneVisible)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(color: const Color(0xFF4F6EF7).withValues(alpha: 0.3), borderRadius: BorderRadius.circular(6)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.straighten, size: 20, color: Color(0xFF4F6EF7)),
                          const SizedBox(width: 8),
                          Text('${n.laneCount} 车道', style: const TextStyle(fontSize: 14, color: Color(0xFF4F6EF7))),
                        ]),
                      ),
                  ]),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Static format helpers (used in NaviInfoPanel and HudOverlayPanel) ──

String _formatDistanceStatic(double meters) {
  if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} 公里';
  return '${meters.toInt()} 米';
}

String _formatDurationStatic(int seconds) {
  if (seconds < 60) return '$seconds秒';
  final min = seconds ~/ 60;
  if (min < 60) return '$min分钟';
  final h = min ~/ 60;
  final m = min % 60;
  return '$h小时$m分钟';
}

// ── UI widgets ──

Widget _msgCard(String msg, {required bool isError, VoidCallback? onDismiss}) {
  return Material(
    borderRadius: BorderRadius.circular(10),
    color: isError ? const Color(0xFFFFF3F0) : const Color(0xFFF0F9FF),
    elevation: 3,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        Icon(isError ? Icons.error_outline : Icons.info_outline, size: 16, color: isError ? const Color(0xFFEF4444) : const Color(0xFF4F6EF7)),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: TextStyle(fontSize: 12, color: isError ? const Color(0xFF991B1B) : const Color(0xFF1E40AF)))),
        GestureDetector(onTap: onDismiss ?? () {}, child: Icon(Icons.close, size: 14, color: isError ? const Color(0xFF991B1B) : const Color(0xFF1E40AF))),
      ]),
    ),
  );
}

Widget _longPressSheet({
  required bool isDark,
  required String? address,
  required double? lat,
  required double? lng,
  required VoidCallback onNavigate,
  required VoidCallback onAddMarker,
  required VoidCallback onSearchNearby,
  required VoidCallback onCancel,
}) {
  return Material(
    borderRadius: BorderRadius.circular(12),
    color: isDark ? PixelTheme.darkSurface : Colors.white,
    elevation: 4,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(address ?? '${lat?.toStringAsFixed(5) ?? ""}, ${lng?.toStringAsFixed(5) ?? ""}',
            style: TextStyle(fontSize: 13, color: isDark ? Colors.white : PixelTheme.primaryText)),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _sheetBtn('导航到这里', Icons.navigation, onNavigate),
          _sheetBtn('添加标记', Icons.place, onAddMarker),
          _sheetBtn('搜周边', Icons.search, onSearchNearby),
          _sheetBtn('取消', Icons.close, onCancel),
        ]),
      ]),
    ),
  );
}

Widget _poiInfoSheet({
  required bool isDark,
  required String name,
  required VoidCallback onNavigate,
  required VoidCallback onClose,
}) {
  return Material(
    borderRadius: BorderRadius.circular(12),
    color: isDark ? PixelTheme.darkSurface : Colors.white,
    elevation: 4,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        const Icon(Icons.location_city, size: 18, color: PixelTheme.brandBlue),
        const SizedBox(width: 8),
        Expanded(child: Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white : PixelTheme.primaryText))),
        GestureDetector(onTap: onNavigate, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: const Color(0xFF10B981), borderRadius: BorderRadius.circular(6)),
          child: const Text('规划路线', style: TextStyle(fontSize: 12, color: Colors.white)),
        )),
        const SizedBox(width: 6),
        GestureDetector(onTap: onClose, child: Icon(Icons.close, size: 16, color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted)),
      ]),
    ),
  );
}

Widget _markerInfoSheet({
  required bool isDark,
  required String title,
  required String? snippet,
  required VoidCallback onClose,
}) {
  return Material(
    borderRadius: BorderRadius.circular(12),
    color: isDark ? PixelTheme.darkSurface : Colors.white,
    elevation: 4,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        const Icon(Icons.place, size: 18, color: PixelTheme.brandBlue),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white : PixelTheme.primaryText)),
          if (snippet != null && snippet.isNotEmpty)
            Text(snippet, style: TextStyle(fontSize: 11, color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textSecondary)),
        ])),
        GestureDetector(onTap: onClose, child: Icon(Icons.close, size: 16, color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted)),
      ]),
    ),
  );
}

Widget _addressSheet({
  required bool isDark,
  required String address,
  required VoidCallback onClose,
}) {
  return Material(
    borderRadius: BorderRadius.circular(12),
    color: isDark ? PixelTheme.darkSurface : Colors.white,
    elevation: 4,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        const Icon(Icons.location_on, size: 18, color: PixelTheme.brandBlue),
        const SizedBox(width: 8),
        Expanded(child: Text(address, style: TextStyle(fontSize: 13, color: isDark ? Colors.white : PixelTheme.primaryText))),
        GestureDetector(onTap: onClose, child: Icon(Icons.close, size: 16, color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted)),
      ]),
    ),
  );
}

Widget _arrivalPage({
  required bool isDark,
  required String destinationName,
  required double totalDistance,
  required int totalTime,
  required VoidCallback onDismiss,
  required VoidCallback onViewDestination,
}) {
  return Material(
    color: const Color(0xFF1A1A2E), elevation: 8,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 20),
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.2), shape: BoxShape.circle),
            child: const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 48),
          ),
          const SizedBox(height: 20),
          const Text('已到达目的地', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 8),
          Text(destinationName, style: const TextStyle(fontSize: 16, color: Color(0xFF94A3B8)), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _arrivalStat('总路程', _formatDistanceStatic(totalDistance), Icons.straighten),
            Container(width: 1, height: 40, color: const Color(0xFF374151)),
            _arrivalStat('总时长', _formatDurationStatic(totalTime), Icons.access_time),
          ]),
          const SizedBox(height: 30),
          GestureDetector(
            onTap: onDismiss,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(color: const Color(0xFF4F6EF7), borderRadius: BorderRadius.circular(12)),
              child: const Text('完成导航', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onViewDestination,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(color: const Color(0xFF374151), borderRadius: BorderRadius.circular(12)),
              child: const Text('查看目的地', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
            ),
          ),
        ]),
      ),
    ),
  );
}

Widget _arrivalStat(String label, String value, IconData icon) {
  return Column(children: [
    Icon(icon, color: const Color(0xFF94A3B8), size: 20),
    const SizedBox(height: 6),
    Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
  ]);
}

Widget _measureCard({
  required bool isDark,
  required int pointCount,
  required String? distanceInfo,
  required VoidCallback onComplete,
}) {
  final hasDistance = distanceInfo != null && pointCount >= 2;
  return Material(
    borderRadius: BorderRadius.circular(12),
    color: isDark ? PixelTheme.darkSurface : Colors.white,
    elevation: 4,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.straighten, size: 18, color: Color(0xFFEF4444)),
          const SizedBox(width: 8),
          Expanded(child: Text(
            pointCount < 2 ? '点击地图添加测量点 ($pointCount)' : '$pointCount 点  |  点击继续添加',
            style: TextStyle(fontSize: 13, color: isDark ? Colors.white : PixelTheme.primaryText),
          )),
          GestureDetector(
            onTap: onComplete,
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: const Color(0xFFEF4444).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)), child: const Text('完成', style: TextStyle(fontSize: 12, color: Color(0xFFEF4444)))),
          ),
        ]),
        if (hasDistance) ...[
          const SizedBox(height: 6),
          Container(width: double.infinity, height: 1, color: isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB)),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.straighten, size: 14, color: Color(0xFF4F6EF7)),
            const SizedBox(width: 6),
            Expanded(child: Text(distanceInfo!, style: TextStyle(fontSize: 12, color: isDark ? Colors.white : PixelTheme.primaryText))),
          ]),
        ],
      ]),
    ),
  );
}

Widget _FloatingHistoryBall({required bool isDark, required void Function(MapAction) onReplay, required double historyBallBottomOffset}) {
  return ValueListenableBuilder<List<MapOperationRecord>>(
    valueListenable: operationHistory,
    builder: (ctx, history, _) {
      return GestureDetector(
        onTap: () => _showOperationHistorySheet(ctx, history, onReplay, historyBallBottomOffset),
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: Stack(alignment: Alignment.center, children: [
            Icon(Icons.map_outlined, size: 22, color: PixelTheme.brandBlue),
            if (history.isNotEmpty)
              Positioned(top: 4, right: 4, child: Container(
                width: 16, height: 16,
                decoration: const BoxDecoration(color: PixelTheme.brandBlue, shape: BoxShape.circle),
                child: Center(child: Text('${history.length}', style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold))),
              )),
          ]),
        ),
      );
    },
  );
}

void _showOperationHistorySheet(BuildContext ctx, List<MapOperationRecord> history, void Function(MapAction) onReplay, double historyBallBottomOffset) {
  final bottomOffset = historyBallBottomOffset;
  final overlay = Overlay.of(ctx);
  final theme = Theme.of(ctx);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Stack(children: [
      // 点击背景关闭（不阻挡地图交互）
      Positioned.fill(child: GestureDetector(
        onTap: () => entry.remove(),
        behavior: HitTestBehavior.opaque,
      )),
      Positioned(left: 14, bottom: bottomOffset + 52, child: Material(
        borderRadius: BorderRadius.circular(10),
        color: theme.cardColor,
        elevation: 4,
        child: Container(
          width: 220,
          height: 180,
          child: Column(children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                border: Border(bottom: BorderSide(color: theme.dividerColor, width: 0.5)),
              ),
              child: Row(children: [
                Icon(Icons.history, size: 16, color: PixelTheme.brandBlue),
                const SizedBox(width: 6),
                const Text('操作历史', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                GestureDetector(onTap: () => entry.remove(), child: Icon(Icons.close, size: 16, color: Colors.grey)),
              ]),
            ),
            // 列表
            Expanded(child: history.isEmpty
              ? Center(child: Text('暂无操作记录', style: TextStyle(fontSize: 12, color: Colors.grey[500])))
              : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: history.length,
                itemBuilder: (ctx, idx) {
                  final record = history[idx];
                  return InkWell(
                    onTap: () { entry.remove(); onReplay(record.action); },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(children: [
                        Icon(record.icon, size: 14, color: PixelTheme.brandBlue),
                        const SizedBox(width: 8),
                        Expanded(child: Text(record.summary, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        Text('${record.timestamp.hour}:${record.timestamp.minute.toString().padLeft(2, '0')}', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                      ]),
                    ),
                  );
                },
              )),
          ]),
        ),
      )),
    ]),
  );
  overlay.insert(entry);
}

String _routeModeIcon(String mode) =>
    {'driving': '🚗', 'walking': '🚶', 'cycling': '🚴', 'transit': '🚌'}[mode] ?? '📍';
String _routeModeLabel(String mode) =>
    {'driving': '驾车', 'walking': '步行', 'cycling': '骑行', 'transit': '公交'}[mode] ?? mode;


Widget _sheetBtn(String label, IconData icon, VoidCallback? onTap) {
  return GestureDetector(
    onTap: onTap,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 22, color: PixelTheme.brandBlue),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(fontSize: 11, color: PixelTheme.primaryText)),
    ]),
  );
}

/// Styled button used in the API-key retry overlay.
class _RetryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _RetryButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.12) : PixelTheme.brandBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: isDark ? Colors.white : PixelTheme.brandBlue),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : PixelTheme.brandBlue)),
          ],
        ),
      ),
    );
  }
}

double _calculateBottomOffsetStatic(bool isNavigating, bool hasMapAction, double? longPressLat) {
  if (isNavigating) return 64;
  if (hasMapAction) return 100;
  if (longPressLat != null) return 100;
  return 100;
}
