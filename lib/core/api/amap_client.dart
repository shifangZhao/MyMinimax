// ignore_for_file: avoid_dynamic_calls

import 'package:dio/dio.dart';
import 'safe_response.dart';

class AmapException implements Exception {
  AmapException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'Amap API error [$code]: $message';

  static String getErrorDescription(String code) {
    switch (code) {
      case '10000': return '请求正常';
      case '10001': return 'key不正确或过期';
      case '10002': return '没有权限使用相应的服务或请求路径拼写错误';
      case '10003': return '访问已超出日访问量限制';
      case '10004': return '单位时间内访问过于频繁';
      case '10005': return 'IP白名单出错，服务器IP不在白名单内';
      case '10006': return '绑定域名无效';
      case '10007': return '数字签名未通过验证';
      case '10008': return 'MD5安全码未通过验证';
      case '10009': return '请求key与绑定平台不符';
      case '10010': return 'IP访问超限';
      case '10011': return '服务不支持https请求';
      case '10012': return '权限不足，服务请求被拒绝';
      case '10013': return 'Key被删除';
      case '10014': return '云图服务QPS超限';
      case '10015': return '受单机QPS限流限制';
      case '10016': return '服务器负载过高，请稍后重试';
      case '10017': return '所请求的资源不可用';
      case '10019': return '某个服务总QPS超限';
      case '10020': return 'Key使用某个服务接口QPS超出限制';
      case '10021': return '账号使用某个服务接口QPS超出限制';
      case '10026': return '账号处于被封禁状态';
      case '10029': return '某个Key的QPS超出限制';
      case '10041': return '请求的接口权限过期';
      case '10044': return '账号维度日调用量超出限制';
      case '10045': return '账号维度海外服务日调用量超出限制';
      case '20000': return '请求参数非法';
      case '20001': return '缺少必填参数';
      case '20002': return '请求协议非法';
      case '20003': return '其他未知错误';
      case '20011': return '查询坐标在海外，但没有海外地图权限';
      case '20012': return '查询信息存在非法内容';
      case '20800': return '规划点不在中国陆地范围内';
      case '20801': return '起点终点附近搜不到路';
      case '20802': return '路线计算失败';
      case '20803': return '起点终点距离过长';
      default: return '未知错误: $code';
    }
  }
}

class GeoPoint {
  const GeoPoint(this.lng, this.lat);
  final double lng;
  final double lat;
  String get coords => '$lng,$lat';
}

/// 静态地图标注
/// size: small/mid/large, color: 0xRRGGBB, label: A-Z/0-9/中文, iconUrl: 自定义图片
class StaticMapMarker {
  final String size;
  final int? color;
  final String? label;
  final String? iconUrl;
  final List<GeoPoint> points;
  const StaticMapMarker({
    this.size = 'mid',
    this.color,
    this.label,
    this.iconUrl,
    required this.points,
  });
  @override
  String toString() {
    if (iconUrl != null) {
      return '-1,$iconUrl,0:${points.map((p) => p.coords).join(';')}';
    }
    final colorHex = color != null ? '0x${color!.toRadixString(16).padLeft(6, '0').substring(2).toUpperCase()}' : '';
    return '$size,$colorHex,${label ?? ''}:${points.map((p) => p.coords).join(';')}';
  }
}

/// 静态地图文字标签
/// font: 0=微软雅黑, 1=宋体, 2=Times, 3=Helvetica
class StaticMapLabel {
  final String content;
  final int font;
  final bool bold;
  final int fontSize;
  final int fontColor;
  final int background;
  final List<GeoPoint> points;
  const StaticMapLabel({
    required this.content,
    this.font = 0,
    this.bold = false,
    this.fontSize = 10,
    this.fontColor = 0xFFFFFF,
    this.background = 0x5288d8,
    required this.points,
  });
  @override
  String toString() {
    final bgHex = '0x${background.toRadixString(16).padLeft(6, '0').substring(2).toUpperCase()}';
    final fcHex = '0x${fontColor.toRadixString(16).padLeft(6, '0').substring(2).toUpperCase()}';
    return '$content,$font,${bold ? 1 : 0},$fontSize,$fcHex,$bgHex:${points.map((p) => p.coords).join(';')}';
  }
}

/// 静态地图折线/多边形
class StaticMapPath {
  final int weight;
  final int color;
  final double transparency;
  final int? fillColor;
  final double fillTransparency;
  final List<GeoPoint> points;
  const StaticMapPath({
    this.weight = 5,
    this.color = 0x0000FF,
    this.transparency = 1.0,
    this.fillColor,
    this.fillTransparency = 0.5,
    required this.points,
  });
  @override
  String toString() {
    final colorHex = '0x${color.toRadixString(16).padLeft(6, '0').substring(2).toUpperCase()}';
    final fillHex = fillColor != null ? '0x${fillColor!.toRadixString(16).padLeft(6, '0').substring(2).toUpperCase()}' : '';
    return '$weight,$colorHex,$transparency,$fillHex,${fillColor != null ? fillTransparency.toString() : ''}:${points.map((p) => p.coords).join(';')}';
  }
}

class GeoResult {
  const GeoResult({
    required this.address,
    required this.location, this.name,
    this.adcode,
    this.city,
    this.province,
    this.rectangle,
  });
  final String address;
  final String? name;
  final GeoPoint location;
  final String? adcode;
  final String? city;
  final String? province;
  final String? rectangle;
}

/// 未来路径规划 — 时间段路况信息
class FutureRouteTrafficInfo {
  const FutureRouteTrafficInfo({
    required this.starttime,
    required this.elements,
  });
  final String starttime; // Unix时间戳(毫秒)
  final List<FutureRouteElement> elements;
}

class FutureRouteElement {
  const FutureRouteElement({
    required this.pathIndex,
    required this.duration,
    required this.tolls,
    required this.restriction,
    this.tmcs,
  });
  final int pathIndex;
  final int duration; // 分钟
  final double tolls; // 元
  final int restriction; // 0:未限行 1:限行无法规避
  final List<TmcInfo>? tmcs;
}

class TmcInfo {
  const TmcInfo({required this.status, this.polyline});
  final String status; // 畅通/拥堵等
  final String? polyline;
}

/// 未来路径规划 — 路径段
class FutureRouteStep {
  const FutureRouteStep({
    required this.adcode,
    required this.road,
    required this.distance,
    required this.toll,
    required this.polyline,
    this.timeInfos,
  });
  final String adcode;
  final String road;
  final int distance; // 米
  final int toll; // 0:不收费 1:收费
  final String polyline;
  final List<FutureRouteTrafficInfo>? timeInfos;
}

/// 未来路径规划 — 单条路径
class FutureRoutePath {
  const FutureRoutePath({
    required this.distance,
    required this.trafficLights,
    required this.steps,
  });
  final int distance; // 米
  final int trafficLights;
  final List<FutureRouteStep> steps;
}

/// 未来路径规划结果
class FutureRouteResult {
  const FutureRouteResult({
    required this.paths,
    this.errcode,
    this.errmsg,
    this.errdetail,
  });
  final List<FutureRoutePath> paths;
  final int? errcode;
  final String? errmsg;
  final String? errdetail;
}

class PoiItem {
  const PoiItem({
    required this.id,
    required this.name,
    required this.address,
    required this.location,
    this.type,
    this.tel,
    this.adcode,
    this.city,
    this.distance,
    this.typecode,
    this.rating,
    this.openingHours,
    this.photos,
    this.parent,
    this.pname,
    this.adname,
    this.pcode,
    this.citycode,
    this.cityname,
    this.alias,
    this.businessArea,
    this.tag,
    this.cost,
    this.parkingType,
    this.children,
    this.naviEntrLocation,
    this.naviExitLocation,
  });
  final String id;
  final String name;
  final String address;
  final GeoPoint location;
  final String? type;
  final String? tel;
  final String? adcode;
  final String? city;
  final String? distance;
  final String? typecode;
  final double? rating;
  final String? openingHours;
  final List<String>? photos;
  final String? parent;
  final String? pname;
  final String? adname;
  final String? pcode;
  final String? citycode;
  final String? cityname;
  final String? alias;
  final String? businessArea;
  final String? tag;
  final double? cost;
  final String? parkingType;
  final List<PoiChild>? children;
  final GeoPoint? naviEntrLocation;
  final GeoPoint? naviExitLocation;
}

class PoiChild {
  const PoiChild({
    required this.id,
    required this.name,
    required this.location,
    required this.address,
    this.subtype,
    this.typecode,
    this.sname,
  });
  final String id;
  final String name;
  final GeoPoint location;
  final String address;
  final String? subtype;
  final String? typecode;
  final String? sname;
}

class PoiDetail {
  const PoiDetail({
    required this.id,
    required this.name,
    required this.address,
    required this.location,
    this.type,
    this.tel,
    this.adcode,
    this.city,
    this.typecode,
    this.rating,
    this.openingHours,
    this.photos,
    this.website,
    this.email,
    this.province,
    this.district,
    this.businessArea,
  });
  final String id;
  final String name;
  final String address;
  final GeoPoint location;
  final String? type;
  final String? tel;
  final String? adcode;
  final String? city;
  final String? typecode;
  final double? rating;
  final String? openingHours;
  final List<String>? photos;
  final String? website;
  final String? email;
  final String? province;
  final String? district;
  final String? businessArea;
}

class InputTip {
  const InputTip({
    required this.name,
    required this.address,
    this.id,
    this.adcode,
    this.type,
    this.location,
    this.district,
  });
  final String name;
  final String address;
  final String? id;
  final String? adcode;
  final String? type;
  final GeoPoint? location;
  final String? district;
}

class PoiSearchResult {
  const PoiSearchResult({required this.count, required this.pois, this.suggestion});
  final int count;
  final List<PoiItem> pois;
  final String? suggestion;
}

class RouteStep {
  const RouteStep({
    required this.instruction,
    required this.road,
    required this.distance,
    required this.duration,
    this.orientation,
  });
  final String instruction;
  final String road;
  final String distance;
  final String duration;
  final String? orientation;
}

class TransitStop {
  const TransitStop({
    required this.name,
    required this.id,
    required this.location,
    this.arrivalTime,
    this.departureTime,
  });
  final String name;
  final String id;
  final GeoPoint location;
  final String? arrivalTime;
  final String? departureTime;
}

class TransitSegment {
  const TransitSegment({
    required this.type,
    required this.stopCount, required this.distance, required this.duration, this.lineName,
    this.departureStop,
    this.arrivalStop,
    this.stops,
  });
  final String type; // 'walk' | 'bus' | 'subway' | 'train'
  final String? lineName;
  final String? departureStop;
  final String? arrivalStop;
  final int stopCount;
  final String distance;
  final String duration;
  final List<TransitStop>? stops;
}

class RouteResult {
  const RouteResult({
    required this.distance,
    required this.duration,
    this.cost,
    this.taxiCost,
    this.steps,
    this.transitSegments,
    this.polyline,
    this.origin,
    this.destination,
  });
  final double distance;
  final String duration;
  final double? cost;
  final String? taxiCost;
  final List<RouteStep>? steps;
  final List<TransitSegment>? transitSegments;
  final String? polyline;
  final GeoPoint? origin;
  final GeoPoint? destination;
}

class BusArrival {
  const BusArrival({
    required this.busName,
    required this.stopName,
    required this.direction,
    required this.lines,
  });
  final String busName;
  final String stopName;
  final String direction;
  final List<BusLineArrival> lines;
}

class BusLineArrival {
  const BusLineArrival({
    required this.name,
    required this.terminus,
    this.etaSeconds,
    this.etaText,
    this.distanceMeters,
    this.busCount,
    this.busPosition,
  });
  final String name;
  final String terminus;
  final int? etaSeconds;
  final String? etaText;
  final int? distanceMeters;
  final int? busCount;
  final String? busPosition;
}

class BusStop {
  const BusStop({
    required this.id,
    required this.name,
    required this.location,
    this.adcode,
    this.citycode,
    this.buslines,
  });
  final String id;
  final String name;
  final GeoPoint location;
  final String? adcode;
  final String? citycode;
  final List<BusLineBasic>? buslines;
}

class BusLineBasic {
  const BusLineBasic({
    required this.id,
    required this.name,
    this.location,
    required this.startStop,
    required this.endStop,
  });
  final String id;
  final String name;
  final GeoPoint? location;
  final String startStop;
  final String endStop;
}

class BusLine {
  const BusLine({
    required this.id,
    required this.name,
    required this.type,
    required this.polyline,
    this.citycode,
    required this.startStop,
    required this.endStop,
    this.startTime,
    this.endTime,
    this.uicolor,
    this.timedesc,
    this.distance,
    this.loop,
    this.status,
    this.direc,
    this.company,
    this.basicPrice,
    this.totalPrice,
    this.bounds,
    this.busstops,
  });
  final String id;
  final String name;
  final String type;
  final String polyline;
  final String? citycode;
  final String startStop;
  final String endStop;
  final String? startTime;
  final String? endTime;
  final String? uicolor;
  final String? timedesc;
  final double? distance;
  final int? loop;
  final int? status;
  final String? direc;
  final String? company;
  final double? basicPrice;
  final double? totalPrice;
  final String? bounds;
  final List<BusStopBasic>? busstops;
}

class BusStopBasic {
  const BusStopBasic({
    required this.id,
    required this.name,
    required this.location,
    this.sequence,
  });
  final String id;
  final String name;
  final GeoPoint location;
  final int? sequence;
}

class TrafficInfo {
  const TrafficInfo({
    required this.status,
    required this.description,
    this.expedite,
    this.congested,
    this.blocked,
    this.unknown,
    this.roads,
  });
  final String status; // 0:unknown 1:smooth 2:slow 3:jam
  final String description;
  final double? expedite; // 畅通百分比
  final double? congested; // 缓行百分比
  final double? blocked; // 拥堵百分比
  final double? unknown; // 未知百分比
  final List<RoadTrafficInfo>? roads; // 详细道路列表 (extensions=all)
}

class RoadTrafficInfo {
  const RoadTrafficInfo({
    required this.name,
    required this.status,
    required this.direction,
    required this.speed,
    this.angle,
    this.lcodes,
    this.polyline,
  });
  final String name;
  final String status; // 0:未知;1:畅通;2:缓行;3:拥堵
  final String direction;
  final int speed; // km/hr
  final double? angle;
  final String? lcodes;
  final String? polyline;
}

class TrafficEvent {
  const TrafficEvent({
    required this.id,
    required this.eventType,
    required this.description,
    required this.roadName,
    required this.direction,
    required this.startTime,
    required this.endTime,
    this.distance,
    this.delayTime,
    this.lat,
    this.lng,
  });
  final String id;
  final String eventType;
  final String description;
  final String roadName;
  final String direction;
  final String startTime;
  final String endTime;
  final String? distance;
  final String? delayTime;
  final double? lat;
  final double? lng;
}

/// 轨迹纠偏坐标点
class GrasproadPoint {
  final double lng;
  final double lat;
  final double speed; // km/h
  final double angle; // 与正北方向夹角
  final int timestamp; // 秒，从1970年起的时间差

  const GrasproadPoint({
    required this.lng,
    required this.lat,
    required this.speed,
    required this.angle,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'x': lng,
    'y': lat,
    'sp': speed,
    'ag': angle,
    'tm': timestamp,
  };
}

/// 轨迹纠偏结果
class GrasproadResult {
  const GrasproadResult({
    required this.distance,
    required this.points,
    this.errcode,
    this.errmsg,
  });
  final double distance;
  final List<GeoPoint> points;
  final int? errcode;
  final String? errmsg;
}

class DistrictInfo {
  const DistrictInfo({
    required this.name,
    required this.adcode,
    required this.level, this.center,
    this.children,
  });
  final String name;
  final String adcode;
  final GeoPoint? center;
  final String level;
  final List<DistrictInfo>? children;
}

class AmapClient {

  AmapClient({required this.apiKey})
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
        ));
  static const _baseUrl = 'https://restapi.amap.com/v3';
  static const _baseUrlV4 = 'https://restapi.amap.com/v4';
  static const _baseUrlV5 = 'https://restapi.amap.com/v5';
  final String apiKey;
  final Dio _dio;

  Map<String, dynamic> _baseParams() => {'key': apiKey};

  // ── 地理编码：地址 → 坐标 ──
  Future<List<GeoResult>> geocode(String address, {String? city}) async {
    final params = _baseParams()
      ..['address'] = address
      ..['output'] = 'JSON';
    if (city != null && city.isNotEmpty) params['city'] = city;

    final data = await _get('/geocode/geo', params);
    final geos = data['geocodes'] as List<dynamic>? ?? [];
    return geos.map((g) {
      final locStr = _extractString(g['location']) ?? '0,0';
      final loc = locStr.split(',');
      return GeoResult(
        address: _extractString(g['formatted_address']) ?? '',
        name: _extractString(g['name']),
        location: GeoPoint(double.parse(loc[0]), double.parse(loc[1])),
        adcode: _extractString(g['adcode']),
        city: _extractString(g['city']),
      );
    }).toList();
  }

  // ── 逆地理编码：坐标 → 地址 ──
  Future<GeoResult?> regeocode(GeoPoint point) async {
    final params = _baseParams()
      ..['location'] = point.coords
      ..['output'] = 'JSON'
      ..['extensions'] = 'base';

    final data = await _get('/geocode/regeo', params);
    final regeo = data['regeocode'] as Map<String, dynamic>?;
    if (regeo == null) return null;

    final addr = regeo['addressComponent'] as Map<String, dynamic>?;
    return GeoResult(
      address: _extractString(regeo['formatted_address']) ?? '',
      adcode: _extractString(addr?['adcode']),
      city: _extractString(addr?['city']) ?? _extractString(addr?['province']),
      location: point,
    );
  }

  // ── POI 关键词搜索 V5 ──
  Future<PoiSearchResult> searchPoi(
    String keywords, {
    String? city,
    String? type,
    int page = 1,
    int offset = 20,
    String? region,
    bool cityLimit = false,
    List<String>? showFields,
  }) async {
    final params = <String, dynamic>{
      'key': apiKey,
      'keywords': keywords,
      'page_size': offset,
      'page_num': page,
    };
    if (type != null && type.isNotEmpty) params['types'] = type;
    if (city != null && city.isNotEmpty) params['region'] = city;
    if (region != null && region.isNotEmpty) params['region'] = region;
    if (cityLimit) params['city_limit'] = 'true';
    if (showFields != null && showFields.isNotEmpty) params['show_fields'] = showFields.join(',');

    final response = await _dio.get('$_baseUrlV5/place/text', queryParameters: params);
    final data = SafeResponse.asMap(response.data);
    final pois = (data['pois'] as List<dynamic>?)?.map((p) => _parsePoi(p)).toList() ?? [];
    return PoiSearchResult(
      count: int.tryParse(data['count']?.toString() ?? '0') ?? 0,
      pois: pois,
    );
  }

  // ── 周边搜索 V5 ──
  Future<PoiSearchResult> searchNearby(
    GeoPoint center,
    int radius, {
    String? keywords,
    String? type,
    int page = 1,
    int offset = 20,
    String? sortrule,
    String? region,
    bool cityLimit = false,
    List<String>? showFields,
  }) async {
    final params = <String, dynamic>{
      'key': apiKey,
      'location': center.coords,
      'radius': radius,
      'page_size': offset,
      'page_num': page,
    };
    if (keywords != null && keywords.isNotEmpty) params['keywords'] = keywords;
    if (type != null && type.isNotEmpty) params['types'] = type;
    if (sortrule != null && sortrule.isNotEmpty) params['sortrule'] = sortrule;
    if (region != null && region.isNotEmpty) params['region'] = region;
    if (cityLimit) params['city_limit'] = 'true';
    if (showFields != null && showFields.isNotEmpty) params['show_fields'] = showFields.join(',');

    final response = await _dio.get('$_baseUrlV5/place/around', queryParameters: params);
    final data = SafeResponse.asMap(response.data);
    final pois = (data['pois'] as List<dynamic>?)?.map((p) => _parsePoi(p)).toList() ?? [];
    return PoiSearchResult(
      count: int.tryParse(data['count']?.toString() ?? '0') ?? 0,
      pois: pois,
    );
  }

  // ── 多边形搜索 V5 ──
  Future<PoiSearchResult> searchPolygon(
    List<GeoPoint> polygon, {
    String? keywords,
    String? type,
    int page = 1,
    int offset = 20,
    List<String>? showFields,
  }) async {
    final params = <String, dynamic>{
      'key': apiKey,
      'polygon': polygon.map((p) => p.coords).join('|'),
      'page_size': offset,
      'page_num': page,
    };
    if (keywords != null && keywords.isNotEmpty) params['keywords'] = keywords;
    if (type != null && type.isNotEmpty) params['types'] = type;
    if (showFields != null && showFields.isNotEmpty) params['show_fields'] = showFields.join(',');

    final response = await _dio.get('$_baseUrlV5/place/polygon', queryParameters: params);
    final data = SafeResponse.asMap(response.data);
    final pois = (data['pois'] as List<dynamic>?)?.map((p) => _parsePoi(p)).toList() ?? [];
    return PoiSearchResult(
      count: int.tryParse(data['count']?.toString() ?? '0') ?? 0,
      pois: pois,
    );
  }

  // ── ID 搜索 V5 ──
  Future<PoiItem?> searchById(String id, {List<String>? showFields}) async {
    final params = <String, dynamic>{'key': apiKey, 'id': id};
    if (showFields != null && showFields.isNotEmpty) params['show_fields'] = showFields.join(',');

    final response = await _dio.get('$_baseUrlV5/place/detail', queryParameters: params);
    final data = SafeResponse.asMap(response.data);
    final pois = data['pois'] as List<dynamic>?;
    if (pois == null || pois.isEmpty) return null;
    return _parsePoi(pois.first);
  }

  // ── POI详情查询 ──
  Future<PoiDetail?> getPoiDetail(String poiId) async {
    final params = _baseParams()
      ..['id'] = poiId
      ..['output'] = 'JSON';

    final data = await _get('/place/detail', params);
    final dataMap = data['data'] as Map<String, dynamic>?;
    if (dataMap == null) return null;

    final locStr = _extractString(dataMap['location']) ?? '0,0';
    final loc = locStr.split(',');
    final photos = (dataMap['photos'] as List<dynamic>?)?.map((p) => _extractString(p['url']) ?? '').toList();

    return PoiDetail(
      id: dataMap['id'] as String? ?? '',
      name: dataMap['name'] as String? ?? '',
      address: dataMap['address'] as String? ?? '',
      location: GeoPoint(double.parse(loc[0]), double.parse(loc[1])),
      type: _extractString(dataMap['type']),
      tel: _extractString(dataMap['tel']),
      adcode: _extractString(dataMap['adcode']),
      city: _extractString(dataMap['city']),
      typecode: _extractString(dataMap['typecode']),
      rating: double.tryParse(dataMap['rating']?.toString() ?? ''),
      openingHours: _extractString(dataMap['opening_hours']),
      photos: photos,
      website: _extractString(dataMap['website']),
      email: _extractString(dataMap['email']),
      province: _extractString(dataMap['province']),
      district: _extractString(dataMap['district']),
      businessArea: _extractString(dataMap['business_area']),
    );
  }

  // ── 驾车路径规划 ──
  Future<RouteResult> drivingRoute(GeoPoint origin, GeoPoint destination,
      {List<GeoPoint>? waypoints, int strategy = 0}) async {
    final params = _baseParams()
      ..['origin'] = origin.coords
      ..['destination'] = destination.coords
      ..['strategy'] = strategy
      ..['extensions'] = 'base'
      ..['output'] = 'JSON';
    if (waypoints != null && waypoints.isNotEmpty) {
      params['waypoints'] = waypoints.map((p) => p.coords).join(';');
    }

    final data = await _get('/direction/driving', params);
    return _parseDirectionResult(data, origin, destination);
  }

  /// 驾车多路线规划 — 返回全部可选路径
  Future<List<RouteResult>> drivingRoutes(GeoPoint origin, GeoPoint destination,
      {List<GeoPoint>? waypoints, int strategy = 10}) async {
    final params = _baseParams()
      ..['origin'] = origin.coords
      ..['destination'] = destination.coords
      ..['strategy'] = strategy
      ..['extensions'] = 'base'
      ..['output'] = 'JSON';
    if (waypoints != null && waypoints.isNotEmpty) {
      params['waypoints'] = waypoints.map((p) => p.coords).join(';');
    }

    final data = await _get('/direction/driving', params);
    return _parseDirectionResults(data, origin, destination);
  }

  // ── 步行路径规划 ──
  Future<RouteResult> walkingRoute(GeoPoint origin, GeoPoint destination) async {
    final params = _baseParams()
      ..['origin'] = origin.coords
      ..['destination'] = destination.coords
      ..['output'] = 'JSON';

    final data = await _get('/direction/walking', params);
    return _parseDirectionResult(data, origin, destination);
  }

  // ── 骑行路径规划 (v3 API) ──
  Future<RouteResult> cyclingRoute(
    GeoPoint origin,
    GeoPoint destination,
  ) async {
    final params = _baseParams()
      ..['origin'] = origin.coords
      ..['destination'] = destination.coords
      ..['output'] = 'JSON';

    final data = await _get('/direction/bicycling', params);
    return _parseDirectionResult(data, origin, destination);
  }

  // ── 电动车路线规划 (v5 API) ──
  Future<RouteResult> electrobikeRoute(
    GeoPoint origin,
    GeoPoint destination, {
    int alternativeRoute = 0,
    bool showFields = false,
  }) async {
    final params = _baseParams()
      ..['origin'] = origin.coords
      ..['destination'] = destination.coords
      ..['output'] = 'JSON';
    if (alternativeRoute > 0) params['alternative_route'] = alternativeRoute;
    if (showFields) params['show_fields'] = 'cost,navi,polyline';

    final data = await _get('$_baseUrlV5/direction/electrobike', params);
    return _parseWalkCycleResultV5(data, origin, destination);
  }

  RouteResult _parseWalkCycleResultV5(Map<String, dynamic> data, GeoPoint origin, GeoPoint destination) {
    final route = data['route'] as Map<String, dynamic>?;
    if (route == null) return RouteResult(distance: 0, duration: '', origin: origin, destination: destination);

    final paths = route['paths'] as List<dynamic>? ?? [];
    if (paths.isEmpty) return RouteResult(distance: 0, duration: '', origin: origin, destination: destination);

    final path = paths[0] as Map<String, dynamic>;
    final steps = (path['steps'] as List<dynamic>?)?.map((s) {
      return RouteStep(
        instruction: _extractString(s['instruction']) ?? '',
        road: _extractString(s['road_name']) ?? '',
        distance: _extractString(s['step_distance']) ?? '',
        duration: _parseDuration(s['duration'] as num?),
      );
    }).toList();

    final costData = path['cost'] as Map<String, dynamic>?;
    final taxiCostStr = route['taxi_cost']?.toString();

    return RouteResult(
      distance: double.tryParse(path['distance']?.toString() ?? '0') ?? 0,
      duration: _parseDuration(path['duration'] as num?),
      steps: steps,
      cost: costData != null ? (costData['duration'] as num?)?.toDouble() : null,
      taxiCost: taxiCostStr,
      origin: origin,
      destination: destination,
      polyline: _extractString(path['polyline']),
    );
  }

  // ── 公交站 ID 查询 ──
  Future<BusStop?> getBusStopById(String stopId, {String? extensions}) async {
    final params = <String, dynamic>{'key': apiKey, 'id': stopId};
    if (extensions != null) params['extensions'] = extensions;
    final response = await _dio.get('$_baseUrl/bus/stopid', queryParameters: params);
    final data = SafeResponse.asMap(response.data);
    final stops = data['busstops'] as List<dynamic>?;
    if (stops == null || stops.isEmpty) return null;
    return _parseBusStop(stops.first);
  }

  // ── 公交站关键字查询 ──
  Future<List<BusStop>> searchBusStop(String keywords, {String? city, int page = 1, int offset = 20, String? extensions}) async {
    final params = <String, dynamic>{'key': apiKey, 'keywords': keywords, 'page': page, 'offset': offset};
    if (city != null && city.isNotEmpty) params['city'] = city;
    if (extensions != null) params['extensions'] = extensions;
    final response = await _dio.get('$_baseUrl/bus/stopname', queryParameters: params);
    final data = SafeResponse.asMap(response.data);
    final stops = data['busstops'] as List<dynamic>? ?? [];
    return stops.map((s) => _parseBusStop(s)).toList();
  }

  // ── 公交路线 ID 查询 ──
  Future<BusLine?> getBusLineById(String lineId, {String? extensions}) async {
    final params = <String, dynamic>{'key': apiKey, 'id': lineId};
    if (extensions != null) params['extensions'] = extensions;
    final response = await _dio.get('$_baseUrl/bus/lineid', queryParameters: params);
    final data = SafeResponse.asMap(response.data);
    final lines = data['buslines'] as List<dynamic>?;
    if (lines == null || lines.isEmpty) return null;
    return _parseBusLine(lines.first);
  }

  // ── 公交路线关键字查询 ──
  Future<List<BusLine>> searchBusLine(String keywords, {required String city, int page = 1, int offset = 20, String? extensions}) async {
    final params = <String, dynamic>{'key': apiKey, 'keywords': keywords, 'city': city, 'page': page, 'offset': offset};
    if (extensions != null) params['extensions'] = extensions;
    final response = await _dio.get('$_baseUrl/bus/linename', queryParameters: params);
    final data = SafeResponse.asMap(response.data);
    final lines = data['buslines'] as List<dynamic>? ?? [];
    return lines.map((l) => _parseBusLine(l)).toList();
  }

  BusStop _parseBusStop(dynamic s) {
    final locStr = _extractString(s['location']) ?? '0,0';
    final loc = locStr.split(',');
    final buslinesData = s['buslines'] as List<dynamic>?;
    return BusStop(
      id: s['id'] as String? ?? '',
      name: s['name'] as String? ?? '',
      location: GeoPoint(double.tryParse(loc[0]) ?? 0, double.tryParse(loc[1]) ?? 0),
      adcode: _extractString(s['adcode']),
      citycode: _extractString(s['citycode']),
      buslines: buslinesData?.map((l) => BusLineBasic(
        id: l['id'] as String? ?? '',
        name: l['name'] as String? ?? '',
        location: _parseGeoPoint(_extractString(l['location']) ?? '0,0'),
        startStop: _extractString(l['start_stop']) ?? '',
        endStop: _extractString(l['end_stop']) ?? '',
      )).toList(),
    );
  }

  BusLine _parseBusLine(dynamic l) {
    final stopsData = l['busstops'] as List<dynamic>?;
    return BusLine(
      id: l['id'] as String? ?? '',
      name: l['name'] as String? ?? '',
      type: _extractString(l['type']) ?? '',
      polyline: _extractString(l['polyline']) ?? '',
      citycode: _extractString(l['citycode']),
      startStop: _extractString(l['start_stop']) ?? '',
      endStop: _extractString(l['end_stop']) ?? '',
      startTime: _extractString(l['start_time']),
      endTime: _extractString(l['end_time']),
      uicolor: _extractString(l['uicolor']),
      timedesc: _extractString(l['timedesc']),
      distance: double.tryParse(l['distance']?.toString() ?? ''),
      loop: int.tryParse(l['loop']?.toString() ?? ''),
      status: int.tryParse(l['status']?.toString() ?? ''),
      direc: _extractString(l['direc']),
      company: _extractString(l['company']),
      basicPrice: double.tryParse(l['basic_price']?.toString() ?? ''),
      totalPrice: double.tryParse(l['total_price']?.toString() ?? ''),
      bounds: _extractString(l['bounds']),
      busstops: stopsData?.map((st) => BusStopBasic(
        id: st['id'] as String? ?? '',
        name: st['name'] as String? ?? '',
        location: _parseGeoPoint(_extractString(st['location']) ?? '0,0'),
        sequence: int.tryParse(st['sequence']?.toString() ?? ''),
      )).toList(),
    );
  }

  // ── 公交路径规划 ──
  Future<List<RouteResult>> transitRoute(GeoPoint origin, GeoPoint destination,
      {String? city, int strategy = 0}) async {
    final params = _baseParams()
      ..['origin'] = origin.coords
      ..['destination'] = destination.coords
      ..['strategy'] = strategy
      ..['output'] = 'JSON'
      ..['extensions'] = 'all';
    if (city != null && city.isNotEmpty) params['city'] = city;
    params['city1'] = city ?? '';
    params['city2'] = city ?? '';

    final data = await _get('/direction/transit/integrated', params);
    final routeData = data['route'] as Map<String, dynamic>?;
    if (routeData == null) return [];

    final transits = routeData['transits'] as List<dynamic>? ?? [];
    return transits.map((t) {
      final segments = (t['segments'] as List<dynamic>?)?.map((s) {
        // Amap transit API returns [] (empty list) for missing bus/walking, not null
        final bus = s['bus'] is Map<String, dynamic> ? s['bus'] as Map<String, dynamic> : null;
        final busType = _extractString(bus?['type']);
        final type = bus != null
            ? (busType?.contains('地铁') == true ? 'subway' : 'bus')
            : 'walk';
        final walking = s['walking'] is Map<String, dynamic> ? s['walking'] as Map<String, dynamic> : null;
        final stops = (bus?['busstops'] as List<dynamic>?)?.map((st) {
          final locStr = _extractString(st['location']) ?? '0,0';
          final loc = locStr.split(',');
          return TransitStop(
            name: _extractString(st['name']) ?? '',
            id: _extractString(st['id']) ?? '',
            location: GeoPoint(double.parse(loc[0]), double.parse(loc[1])),
            arrivalTime: _extractString(st['arrival_time']),
            departureTime: _extractString(st['departure_time']),
          );
        }).toList();

        return TransitSegment(
          type: type,
          lineName: _extractString(bus?['name']),
          departureStop: _extractString(bus?['departure_stop']?['name']),
          arrivalStop: _extractString(bus?['arrival_stop']?['name']),
          stopCount: int.tryParse(bus?['station_num']?.toString() ?? '0') ?? 0,
          distance: _extractString(walking?['distance']) ?? _extractString(s['distance']) ?? '',
          duration: _extractString(bus?['duration']) ?? _extractString(walking?['duration']) ?? '',
          stops: stops,
        );
      }).toList() ?? [];

      return RouteResult(
        distance: double.tryParse(t['distance']?.toString() ?? '0') ?? 0,
        duration: _formatDuration(int.tryParse(t['duration']?.toString() ?? '0') ?? 0),
        cost: double.tryParse(t['cost']?.toString() ?? ''),
        taxiCost: _extractString(t['taxi_cost']),
        transitSegments: segments,
        origin: origin,
        destination: destination,
      );
    }).toList();
  }

  // ── 实时公交到站 ──
  Future<List<BusArrival>> getBusArrival(String city, String stopName,
      {String? busName, int page = 1, int offset = 20}) async {
    final params = _baseParams()
      ..['city'] = city
      ..['keywords'] = stopName
      ..['output'] = 'JSON'
      ..['page'] = page
      ..['offset'] = offset
      ..['extensions'] = 'all';
    if (busName != null && busName.isNotEmpty) params['busName'] = busName;

    final data = await _get('/bus/stop', params);
    final stops = data['buslines'] as List<dynamic>? ?? [];
    return stops.map((s) {
      final lines = (s['busstops'] as List<dynamic>?)?.map((l) {
        return BusLineArrival(
          name: _extractString(l['name']) ?? '',
          terminus: _extractString(l['terminus']) ?? '',
          etaSeconds: int.tryParse(l['arrival_time']?.toString() ?? ''),
          etaText: _extractString(l['arrival_time_text']),
          distanceMeters: int.tryParse(l['distance']?.toString() ?? ''),
          busCount: int.tryParse(l['bus_count']?.toString() ?? ''),
          busPosition: _extractString(l['bus_position']),
        );
      }).toList() ?? [];

      return BusArrival(
        busName: _extractString(s['name']) ?? '',
        stopName: stopName,
        direction: _extractString(s['start_stop']) ?? '',
        lines: lines,
      );
    }).toList();
  }

  // ── 公交线路查询 ──
  Future<List<Map<String, dynamic>>> getBusLine(String city, String lineName,
      {int page = 1, int offset = 20}) async {
    final params = _baseParams()
      ..['city'] = city
      ..['keywords'] = lineName
      ..['output'] = 'JSON'
      ..['page'] = page
      ..['offset'] = offset
      ..['extensions'] = 'all';

    final data = await _get('/bus/line', params);
    return List<Map<String, dynamic>>.from(data['buslines'] as List? ?? []);
  }

  // ── 交通态势 (圆形区域) ──
  Future<TrafficInfo?> getTrafficStatus(
    GeoPoint point, {
    int radius = 1000,
    int level = 6,
    bool allExtensions = true,
  }) async {
    final params = _baseParams()
      ..['location'] = point.coords
      ..['radius'] = radius
      ..['level'] = level
      ..['output'] = 'JSON'
      ..['extensions'] = allExtensions ? 'all' : 'base';

    final data = await _get('/traffic/status/circle', params);
    final traffic = data['trafficinfo'] as Map<String, dynamic>?;
    if (traffic == null) return null;

    final evaluation = traffic['evaluation'] as Map<String, dynamic>?;
    final roadsRaw = traffic['roads'] as List<dynamic>?;
    final roads = roadsRaw?.map((r) => RoadTrafficInfo(
      name: r['name'] as String? ?? '',
      status: r['status']?.toString() ?? '0',
      direction: r['direction'] as String? ?? '',
      speed: int.tryParse(r['speed']?.toString() ?? '0') ?? 0,
      angle: double.tryParse(r['angle']?.toString() ?? ''),
      lcodes: r['lcodes'] as String?,
      polyline: r['polyline'] as String?,
    )).toList();

    return TrafficInfo(
      status: evaluation?['status']?.toString() ?? '0',
      description: evaluation?['description'] as String? ?? '',
      expedite: double.tryParse(evaluation?['expedite']?.toString() ?? ''),
      congested: double.tryParse(evaluation?['congested']?.toString() ?? ''),
      blocked: double.tryParse(evaluation?['blocked']?.toString() ?? ''),
      unknown: double.tryParse(evaluation?['unknown']?.toString() ?? ''),
      roads: roads,
    );
  }

  // ── 交通态势 (指定线路) ──
  Future<TrafficInfo?> getRoadTrafficStatus({
    required String roadName,
    required String adcode,
    int level = 6,
    bool allExtensions = true,
  }) async {
    final params = _baseParams()
      ..['name'] = roadName
      ..['adcode'] = adcode
      ..['level'] = level
      ..['output'] = 'JSON'
      ..['extensions'] = allExtensions ? 'all' : 'base';

    final data = await _get('/traffic/status/road', params);
    final traffic = data['trafficinfo'] as Map<String, dynamic>?;
    if (traffic == null) return null;

    final evaluation = traffic['evaluation'] as Map<String, dynamic>?;
    final roadsRaw = traffic['roads'] as List<dynamic>?;
    final roads = roadsRaw?.map((r) => RoadTrafficInfo(
      name: r['name'] as String? ?? '',
      status: r['status']?.toString() ?? '0',
      direction: r['direction'] as String? ?? '',
      speed: int.tryParse(r['speed']?.toString() ?? '0') ?? 0,
      angle: double.tryParse(r['angle']?.toString() ?? ''),
      lcodes: r['lcodes'] as String?,
      polyline: r['polyline'] as String?,
    )).toList();

    return TrafficInfo(
      status: evaluation?['status']?.toString() ?? '0',
      description: evaluation?['description'] as String? ?? '',
      expedite: double.tryParse(evaluation?['expedite']?.toString() ?? ''),
      congested: double.tryParse(evaluation?['congested']?.toString() ?? ''),
      blocked: double.tryParse(evaluation?['blocked']?.toString() ?? ''),
      unknown: double.tryParse(evaluation?['unknown']?.toString() ?? ''),
      roads: roads,
    );
  }

  // ── 交通态势 (矩形区域) ──
  Future<TrafficInfo?> getRectangleTrafficStatus({
    required GeoPoint southwest,
    required GeoPoint northeast,
    int level = 6,
    bool allExtensions = true,
  }) async {
    final params = _baseParams()
      ..['rectangle'] = '${southwest.coords};${northeast.coords}'
      ..['level'] = level
      ..['output'] = 'JSON'
      ..['extensions'] = allExtensions ? 'all' : 'base';

    final data = await _get('/traffic/status/rectangle', params);
    final traffic = data['trafficinfo'] as Map<String, dynamic>?;
    if (traffic == null) return null;

    final evaluation = traffic['evaluation'] as Map<String, dynamic>?;
    final roadsRaw = traffic['roads'] as List<dynamic>?;
    final roads = roadsRaw?.map((r) => RoadTrafficInfo(
      name: r['name'] as String? ?? '',
      status: r['status']?.toString() ?? '0',
      direction: r['direction'] as String? ?? '',
      speed: int.tryParse(r['speed']?.toString() ?? '0') ?? 0,
      angle: double.tryParse(r['angle']?.toString() ?? ''),
      lcodes: r['lcodes'] as String?,
      polyline: r['polyline'] as String?,
    )).toList();

    return TrafficInfo(
      status: evaluation?['status']?.toString() ?? '0',
      description: evaluation?['description'] as String? ?? '',
      expedite: double.tryParse(evaluation?['expedite']?.toString() ?? ''),
      congested: double.tryParse(evaluation?['congested']?.toString() ?? ''),
      blocked: double.tryParse(evaluation?['blocked']?.toString() ?? ''),
      unknown: double.tryParse(evaluation?['unknown']?.toString() ?? ''),
      roads: roads,
    );
  }

  // ── 行政区划查询 ──
  Future<List<DistrictInfo>> getDistricts(String keywords,
      {int subdistrict = 0}) async {
    final params = _baseParams()
      ..['keywords'] = keywords
      ..['subdistrict'] = subdistrict
      ..['output'] = 'JSON';

    final data = await _get('/config/district', params);
    final districts = data['districts'] as List<dynamic>? ?? [];
    return districts.map((d) => _parseDistrict(d)).toList();
  }

  // ── 未来路径规划 (v4/etd/driving) — 仅对企业开发者开放 ──
  Future<FutureRouteResult> getFutureRoute({
    required GeoPoint origin,
    required GeoPoint destination,
    required int firstTime, // Unix时间戳(秒)，必须是未来时间
    required int interval, // 秒
    required int count, // 最少1，最多48
    int strategy = 1,
    String? province,
    String? number,
    int carType = 0,
  }) async {
    final params = <String, dynamic>{
      'key': apiKey,
      'origin': origin.coords,
      'destination': destination.coords,
      'firsttime': firstTime,
      'interval': interval,
      'count': count,
      'strategy': strategy,
      'cartype': carType,
    };
    if (province != null && province.isNotEmpty) params['province'] = province;
    if (number != null && number.isNotEmpty) params['number'] = number;

    final response = await _dio.get('$_baseUrlV4/etd/driving', queryParameters: params);
    final data = SafeResponse.asMap(response.data);

    if (data['errcode'] != 0 && data['errcode'] != null) {
      throw AmapException(
        data['errcode']?.toString() ?? '-1',
        data['errmsg'] as String? ?? '未来路径规划失败',
      );
    }

    final resultData = data['data'] as Map<String, dynamic>?;
    if (resultData == null) {
      return const FutureRouteResult(paths: []);
    }

    final pathsRaw = resultData['paths'] as List<dynamic>? ?? [];
    final paths = pathsRaw.map((p) {
      final stepsRaw = p['steps'] as List<dynamic>? ?? [];
      final steps = stepsRaw.map((s) {
        final timeInfosRaw = s['time_infos'] as List<dynamic>?;
        final timeInfos = timeInfosRaw?.map((ti) {
          final elementsRaw = ti['elements'] as List<dynamic>? ?? [];
          final elements = elementsRaw.map((e) {
            final tmcsRaw = e['tmcs'] as List<dynamic>?;
            final tmcs = tmcsRaw?.map((t) => TmcInfo(
              status: t['status'] as String? ?? '',
              polyline: t['polyline'] as String?,
            )).toList();
            return FutureRouteElement(
              pathIndex: int.tryParse(e['pathindex']?.toString() ?? '0') ?? 0,
              duration: int.tryParse(e['duration']?.toString() ?? '0') ?? 0,
              tolls: double.tryParse(e['tolls']?.toString() ?? '0') ?? 0,
              restriction: int.tryParse(e['restriction']?.toString() ?? '0') ?? 0,
              tmcs: tmcs,
            );
          }).toList();
          return FutureRouteTrafficInfo(
            starttime: ti['starttime']?.toString() ?? '',
            elements: elements,
          );
        }).toList();

        return FutureRouteStep(
          adcode: s['adcode'] as String? ?? '',
          road: s['road'] as String? ?? '',
          distance: int.tryParse(s['distance']?.toString() ?? '0') ?? 0,
          toll: int.tryParse(s['toll']?.toString() ?? '0') ?? 0,
          polyline: s['polyline'] as String? ?? '',
          timeInfos: timeInfos,
        );
      }).toList();

      return FutureRoutePath(
        distance: int.tryParse(p['distance']?.toString() ?? '0') ?? 0,
        trafficLights: int.tryParse(p['traffic_lights']?.toString() ?? '0') ?? 0,
        steps: steps,
      );
    }).toList();

    return FutureRouteResult(
      paths: paths,
      errcode: data['errcode'] as int?,
      errmsg: data['errmsg'] as String?,
      errdetail: data['errdetail'] as String?,
    );
  }

  // ── 关键词输入提示 ──
  Future<List<InputTip>> inputTips(
    String keywords, {
    String? type,
    GeoPoint? location,
    String? city,
    bool citylimit = false,
    String datatype = 'all',
  }) async {
    final params = _baseParams()
      ..['keywords'] = keywords
      ..['output'] = 'JSON'
      ..['datatype'] = datatype;
    if (type != null && type.isNotEmpty) params['type'] = type;
    if (location != null) params['location'] = location.coords;
    if (city != null && city.isNotEmpty) params['city'] = city;
    if (citylimit) params['citylimit'] = true;

    final data = await _get('/assistant/inputtips', params);
    final tips = data['tips'] as List<dynamic>? ?? [];
    return tips.map((t) {
      final locStr = _extractString(t['location']);
      GeoPoint? loc;
      if (locStr != null && locStr.contains(',')) {
        final parts = locStr.split(',');
        if (parts.length >= 2) {
          loc = GeoPoint(double.tryParse(parts[0]) ?? 0, double.tryParse(parts[1]) ?? 0);
        }
      }
      return InputTip(
        name: _extractString(t['name']) ?? '',
        address: _extractString(t['address']) ?? '',
        id: _extractString(t['id']),
        adcode: _extractString(t['adcode']),
        type: _extractString(t['type']),
        location: loc,
        district: _extractString(t['district']) ?? '',
      );
    }).toList();
  }

  // ── 静态地图 URL ──
  String staticMapUrl({
    required GeoPoint center,
    int zoom = 14,
    int width = 400,
    int height = 300,
    int scale = 1,
    bool traffic = false,
    List<StaticMapMarker>? markers,
    List<StaticMapLabel>? labels,
    List<StaticMapPath>? paths,
  }) {
    final buf = StringBuffer('$_baseUrl/staticmap?key=$apiKey');
    buf.write('&location=${center.coords}&zoom=$zoom&size=$width*$height');
    if (scale == 2) buf.write('&scale=2');
    if (traffic) buf.write('&traffic=1');

    if (markers != null && markers.isNotEmpty) {
      buf.write('&markers=${markers.map((m) => m.toString()).join('|')}');
    }
    if (labels != null && labels.isNotEmpty) {
      buf.write('&labels=${labels.map((l) => l.toString()).join('|')}');
    }
    if (paths != null && paths.isNotEmpty) {
      buf.write('&paths=${paths.map((p) => p.toString()).join('|')}');
    }
    return buf.toString();
  }

  // ── 轨迹纠偏 (POST /v4/grasproad/driving) ──
  Future<GrasproadResult> grasproad(List<GrasproadPoint> points) async {
    final params = _baseParams();

    final response = await _dio.post(
      '$_baseUrlV4/grasproad/driving',
      queryParameters: params,
      data: points.map((p) => p.toJson()).toList(),
    );
    final data = SafeResponse.asMap(response.data);

    if (data['errcode'] != 0 && data['errcode'] != null) {
      throw AmapException(
        data['errcode']?.toString() ?? '-1',
        data['errmsg'] as String? ?? '轨迹纠偏失败',
      );
    }

    final resultData = data['data'] as Map<String, dynamic>?;
    if (resultData == null) {
      return const GrasproadResult(distance: 0, points: []);
    }

    final pointsData = resultData['points'] as List<dynamic>? ?? [];
    final pointsList = pointsData.map((p) {
      return GeoPoint(
        (p['x'] as num).toDouble(),
        (p['y'] as num).toDouble(),
      );
    }).toList();

    return GrasproadResult(
      distance: (resultData['distance'] as num?)?.toDouble() ?? 0,
      points: pointsList,
      errcode: data['errcode'] as int?,
      errmsg: data['errmsg'] as String?,
    );
  }

  // ── 内部方法 ──

  Future<Map<String, dynamic>> _get(String path, Map<String, dynamic> params) async {
    final response = await _dio.get('$_baseUrl$path', queryParameters: params);
    final data = SafeResponse.asMap(response.data);

    if (data['status'] != '1') {
      throw AmapException(
        data['infocode']?.toString() ?? '-1',
        data['info'] as String? ?? '未知错误',
      );
    }
    return data;
  }

  /// AMap API may return some fields as String or List<String>; normalize to String?.
  String? _extractString(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    if (v is List && v.isNotEmpty) return v.first.toString();
    return v.toString();
  }

  /// Extract suggestion text from the suggestion object.
  /// AMap returns suggestion.keywords as String[] and suggestion.cities as Object[].
  String? _suggestionText(dynamic suggestion) {
    if (suggestion == null) return null;
    if (suggestion is! Map) return null;
    final kw = suggestion['keywords'];
    if (kw is List && kw.isNotEmpty) {
      return kw.map((e) => e.toString()).join(', ');
    }
    return kw?.toString();
  }

  PoiItem _parsePoi(dynamic p) {
    final locStr = _extractString(p['location']) ?? '0,0';
    final loc = locStr.split(',');
    final entrLocStr = _extractString(p['entr_location']);
    final exitLocStr = _extractString(p['exit_location']);
    return PoiItem(
      id: p['id'] as String? ?? '',
      name: p['name'] as String? ?? '',
      address: p['address'] as String? ?? '',
      location: GeoPoint(double.parse(loc[0]), double.parse(loc[1])),
      type: _extractString(p['type']),
      tel: _extractString(p['tel']),
      adcode: _extractString(p['adcode']),
      city: _extractString(p['cityname']),
      distance: p['distance']?.toString(),
      typecode: _extractString(p['typecode']),
      rating: double.tryParse(p['rating']?.toString() ?? ''),
      openingHours: _extractString(p['opentime_today']) ?? _extractString(p['opentime_week']),
      parent: _extractString(p['parent']),
      pname: _extractString(p['pname']),
      adname: _extractString(p['adname']),
      pcode: _extractString(p['pcode']),
      citycode: _extractString(p['citycode']),
      cityname: _extractString(p['cityname']),
      alias: _extractString(p['alias']),
      businessArea: _extractString(p['business_area']),
      tag: _extractString(p['tag']),
      cost: double.tryParse(p['cost']?.toString() ?? ''),
      parkingType: _extractString(p['parking_type']),
      children: _parsePoiChildren(p['children']),
      naviEntrLocation: entrLocStr != null ? _parseGeoPoint(entrLocStr) : null,
      naviExitLocation: exitLocStr != null ? _parseGeoPoint(exitLocStr) : null,
    );
  }

  List<PoiChild>? _parsePoiChildren(dynamic children) {
    if (children == null) return null;
    final list = children as List<dynamic>;
    return list.map((c) {
      final locStr = _extractString(c['location']) ?? '0,0';
      return PoiChild(
        id: c['id'] as String? ?? '',
        name: c['name'] as String? ?? '',
        location: _parseGeoPoint(locStr),
        address: c['address'] as String? ?? '',
        subtype: _extractString(c['subtype']),
        typecode: _extractString(c['typecode']),
        sname: _extractString(c['sname']),
      );
    }).toList();
  }

  GeoPoint _parseGeoPoint(String locStr) {
    final parts = locStr.split(',');
    return GeoPoint(double.tryParse(parts[0]) ?? 0, double.tryParse(parts[1]) ?? 0);
  }

  RouteResult _parseDirectionResult(Map<String, dynamic> data,
      GeoPoint origin, GeoPoint destination) {
    final results = _parseDirectionResults(data, origin, destination);
    return results.isNotEmpty ? results.first : const RouteResult(distance: 0, duration: '');
  }

  List<RouteResult> _parseDirectionResults(Map<String, dynamic> data,
      GeoPoint origin, GeoPoint destination) {
    final routeData = data['route'] as Map<String, dynamic>?;
    if (routeData == null) return [];

    final paths = routeData['paths'] as List<dynamic>? ?? [];
    if (paths.isEmpty) return [];

    return paths.asMap().entries.map((e) {
      final idx = e.key;
      final path = e.value as Map<String, dynamic>;
      final steps = (path['steps'] as List<dynamic>?)?.map((s) {
        return RouteStep(
          instruction: _extractString(s['instruction']) ?? '',
          road: _extractString(s['road']) ?? '',
          distance: _extractString(s['distance']) ?? '',
          duration: _extractString(s['duration']) ?? '',
          orientation: _extractString(s['orientation']),
        );
      }).toList();

      return RouteResult(
        distance: double.tryParse(path['distance']?.toString() ?? '0') ?? 0,
        duration: _formatDuration(int.tryParse(path['duration']?.toString() ?? '0') ?? 0),
        cost: double.tryParse(path['cost']?.toString() ?? ''),
        taxiCost: _extractString(path['taxi_cost']),
        steps: steps,
        polyline: _extractString(path['polyline']) as String?,
        origin: origin,
        destination: destination,
      );
    }).toList();
  }

  DistrictInfo _parseDistrict(Map<String, dynamic> d) {
    final loc = (d['center'] as String?)?.split(',');
    return DistrictInfo(
      name: d['name'] as String? ?? '',
      adcode: d['adcode'] as String? ?? '',
      center: loc != null && loc.length >= 2
          ? GeoPoint(double.parse(loc[0]), double.parse(loc[1]))
          : null,
      level: d['level'] as String? ?? '',
      children: (d['districts'] as List<dynamic>?)
          ?.map((c) => _parseDistrict(c))
          .toList(),
    );
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '未知';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '$h小时$m分钟';
    return '$m分钟';
  }

  String _parseDuration(num? seconds) {
    if (seconds == null) return '';
    final s = seconds.toInt();
    if (s < 60) return '${s}秒';
    final m = s ~/ 60;
    if (m < 60) return '${m}分钟';
    final h = m ~/ 60;
    final rem = m % 60;
    return '${h}小时${rem > 0 ? '${rem}分钟' : ''}';
  }

  // ── 交通事件查询 (et-api.amap.com) ──
  Future<List<TrafficEvent>> getTrafficEvents({
    required String adcode,
    String? clientKey,
    String? eventType,
    bool isExpressway = false,
  }) async {
    final params = <String, dynamic>{
      'key': apiKey,
      'adcode': adcode,
      'isExpressway': isExpressway ? 1 : 0,
    };
    if (clientKey != null && clientKey.isNotEmpty) params['clientKey'] = clientKey;
    if (eventType != null && eventType.isNotEmpty) params['eventType'] = eventType;

    // et-api uses HTTP (not HTTPS) and a different base
    final response = await _dio.get(
      'https://et-api.amap.com/event/queryByAdcode',
      queryParameters: params,
    );
    final data = SafeResponse.asMap(response.data);

    if (data['status'] != '1') {
      throw AmapException(
        data['errcode']?.toString() ?? '-1',
        data['errmsg'] as String? ?? '未知错误',
      );
    }

    final events = data['events'] as List<dynamic>? ?? [];
    return events.map((e) {
      final locStr = _extractString(e['location']);
      double? lat, lng;
      if (locStr != null && locStr.contains(',')) {
        final parts = locStr.split(',');
        if (parts.length >= 2) {
          lng = double.tryParse(parts[0]);
          lat = double.tryParse(parts[1]);
        }
      }
      return TrafficEvent(
        id: _extractString(e['id']) ?? '',
        eventType: _extractString(e['eventType']) ?? '',
        description: _extractString(e['description']) ?? '',
        roadName: _extractString(e['roadName']) ?? '',
        direction: _extractString(e['direction']) ?? '',
        startTime: _extractString(e['startTime']) ?? '',
        endTime: _extractString(e['endTime']) ?? '',
        distance: _extractString(e['distance']),
        delayTime: _extractString(e['delayTime']),
        lat: lat,
        lng: lng,
      );
    }).toList();
  }
}
