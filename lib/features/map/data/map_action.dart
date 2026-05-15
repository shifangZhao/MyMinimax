import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Icons, IconData;
import '../../../core/api/amap_client.dart' show GeoPoint, PoiItem, RouteStep;

sealed class MapAction {
  const MapAction();
}

class ShowPoisAction extends MapAction {
  final String title;
  final List<PoiItem> pois;
  const ShowPoisAction({required this.title, required this.pois});
}

class ShowRouteAction extends MapAction {
  final String routeType;
  final GeoPoint origin;
  final GeoPoint destination;
  final String? placeName;
  final double distance;
  final String duration;
  final String? polyline;
  final List<RouteStep>? steps;
  final double? cost;
  final String? taxiCost;
  final int strategy;
  const ShowRouteAction({
    required this.routeType,
    required this.origin,
    required this.destination,
    this.placeName,
    required this.distance,
    required this.duration,
    this.polyline,
    this.steps,
    this.cost,
    this.taxiCost,
    this.strategy = 0,
  });
}

class ShowLocationAction extends MapAction {
  final GeoPoint location;
  final String? name;
  final String? address;
  const ShowLocationAction({required this.location, this.name, this.address});
}

class ShowPolygonAction extends MapAction {
  final String title;
  final List<GeoPoint> points;
  final int strokeColor;
  final int fillColor;
  const ShowPolygonAction({
    required this.title,
    required this.points,
    this.strokeColor = 0xFF4F6EF7,
    this.fillColor = 0x334F6EF7,
  });
}

class ShowCircleAction extends MapAction {
  final String title;
  final GeoPoint center;
  final double radius;
  final int strokeColor;
  final int fillColor;
  const ShowCircleAction({
    required this.title,
    required this.center,
    required this.radius,
    this.strokeColor = 0xFF4F6EF7,
    this.fillColor = 0x334F6EF7,
  });
}

class ClearOverlaysAction extends MapAction {
  const ClearOverlaysAction();
}

class ShowArcAction extends MapAction {
  final String title;
  final GeoPoint start;
  final GeoPoint mid;
  final GeoPoint end;
  final int color;
  const ShowArcAction({required this.title, required this.start, required this.mid, required this.end, this.color = 0xFF4F6EF7});
}

class ShowTextAction extends MapAction {
  final String text;
  final GeoPoint position;
  final int fontSize;
  final int fontColor;
  const ShowTextAction({required this.text, required this.position, this.fontSize = 16, this.fontColor = 0xFF000000});
}

class ShowGroundOverlayAction extends MapAction {
  final String imagePath;
  final double swLat;
  final double swLng;
  final double neLat;
  final double neLng;
  const ShowGroundOverlayAction({required this.imagePath, required this.swLat, required this.swLng, required this.neLat, required this.neLng});
}

/// 交通事件 — 在地图上标注事件点
class ShowTrafficEventsAction extends MapAction {
  final String adcode;
  final List<TrafficEventItem> events;
  const ShowTrafficEventsAction({required this.adcode, required this.events});
}

class TrafficEventItem {
  final String id;
  final String eventType;
  final String description;
  final String roadName;
  final String direction;
  final GeoPoint? location;
  const TrafficEventItem({required this.id, required this.eventType, required this.description, required this.roadName, required this.direction, this.location});
}

/// 交通态势道路 — 在地图上绘制道路路况线
class ShowTrafficRoadsAction extends MapAction {
  final String type; // 'circle' | 'road' | 'rectangle'
  final String status; // 总体路况状态
  final String description;
  final double? expedite; // 畅通百分比
  final double? congested;
  final double? blocked;
  final List<TrafficRoadItem> roads;
  const ShowTrafficRoadsAction({
    required this.type,
    required this.status,
    required this.description,
    this.expedite,
    this.congested,
    this.blocked,
    required this.roads,
  });
}

class TrafficRoadItem {
  final String name;
  final String status; // 0:未知 1:畅通 2:缓行 3:拥堵
  final String direction;
  final int speed; // km/h
  final String? polyline; // 道路坐标串 x1,y1;x2,y2
  const TrafficRoadItem({required this.name, required this.status, required this.direction, required this.speed, this.polyline});
}

/// 轨迹纠偏结果 — 在地图上绘制纠偏路线
class ShowGrasproadAction extends MapAction {
  final double distance; // 总距离(米)
  final List<GeoPoint> points; // 纠偏后坐标
  const ShowGrasproadAction({required this.distance, required this.points});
}

/// 未来路径规划 — 在地图上绘制多时间段路线对比
class ShowFutureRouteAction extends MapAction {
  final GeoPoint origin;
  final GeoPoint destination;
  final List<FutureRoutePathItem> paths; // 多个时间段方案
  const ShowFutureRouteAction({required this.origin, required this.destination, required this.paths});
}

class FutureRoutePathItem {
  final String departureTime; // 时间戳文字描述
  final int duration; // 分钟
  final double tolls; // 元
  final int restriction; // 0=不限行 1=限行
  final String? polyline;
  const FutureRoutePathItem({required this.departureTime, required this.duration, required this.tolls, required this.restriction, this.polyline});
}

/// Camera / viewport state snapshot sent after user drags the map.
class MapViewState {
  final double lat;
  final double lng;
  final double zoom;
  final double tilt;
  final double bearing;
  final double swLat;
  final double swLng;
  final double neLat;
  final double neLng;
  const MapViewState({
    required this.lat,
    required this.lng,
    required this.zoom,
    this.tilt = 0,
    this.bearing = 0,
    this.swLat = 0,
    this.swLng = 0,
    this.neLat = 0,
    this.neLng = 0,
  });
}

/// 地图操作记录
class MapOperationRecord {
  final MapAction action;
  final DateTime timestamp;

  const MapOperationRecord({required this.action, required this.timestamp});

  String get summary => switch (action) {
    ShowPoisAction a => '搜索: ${a.title.replaceFirst('搜索: ', '')}',
    ShowRouteAction a => '路线: ${a.routeType}${a.distance > 0 ? " ${(a.distance / 1000).toStringAsFixed(1)}公里" : ""}',
    ShowLocationAction a => '位置: ${a.name ?? "${a.location.lat.toStringAsFixed(4)}, ${a.location.lng.toStringAsFixed(4)}"}',
    ShowPolygonAction a => '区域: ${a.title}',
    ShowCircleAction a => '圆形: ${a.title}',
    ShowArcAction a => '弧线: ${a.title}',
    ShowTextAction a => '文字: ${a.text.length > 10 ? "${a.text.substring(0, 10)}..." : a.text}',
    ShowGroundOverlayAction a => '图片覆盖',
    ShowTrafficEventsAction a => '交通事件: ${a.events.length}条',
    ShowTrafficRoadsAction a => '交通态势: ${a.roads.length}条道路',
    ShowGrasproadAction a => '轨迹纠偏: ${(a.distance / 1000).toStringAsFixed(2)}公里',
    ShowFutureRouteAction a => '未来路线: ${a.paths.length}个时段',
    ClearOverlaysAction _ => '清除',
  };

  IconData get icon => switch (action) {
    ShowPoisAction _ => Icons.search,
    ShowRouteAction _ => Icons.route,
    ShowLocationAction _ => Icons.location_on,
    ShowPolygonAction _ => Icons.pentagon,
    ShowCircleAction _ => Icons.circle_outlined,
    ShowArcAction _ => Icons.show_chart,
    ShowTextAction _ => Icons.text_fields,
    ShowGroundOverlayAction _ => Icons.image,
    ShowTrafficEventsAction _ => Icons.warning_amber,
    ShowTrafficRoadsAction _ => Icons.traffic,
    ShowGrasproadAction _ => Icons.explore,
    ShowFutureRouteAction _ => Icons.schedule,
    ClearOverlaysAction _ => Icons.clear,
  };
}

/// Event bus for ToolExecutor → MapPage communication.
final mapActionBus = ValueNotifier<MapAction?>(null);

/// Persists the last action so the "查看地图" chip in chat can re-emit it
/// when the user switches to the map tab.
final mapActionPending = ValueNotifier<MapAction?>(null);

/// Signal to switch to map tab (triggered from chat bubbles).
final switchToMapTab = ValueNotifier<bool>(false);

/// 操作历史（最多10条，新在前）
final operationHistory = ValueNotifier<List<MapOperationRecord>>([]);

/// 添加操作到历史
void addToHistory(MapAction action) {
  final list = [MapOperationRecord(action: action, timestamp: DateTime.now()), ...operationHistory.value];
  if (list.length > 10) list.removeLast();
  operationHistory.value = list;
}
