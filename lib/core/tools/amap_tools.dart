import '../../features/tools/domain/tool.dart';
import 'tool_registry.dart';
import 'tool_module.dart';
import 'tool_groups.dart';

class AmapTools implements ToolModule {
  static final AmapTools module = AmapTools._();
  AmapTools._();

  // ---- ToolModule interface ----
  @override
  String get name => 'amap';

  @override
  bool get isDynamic => false;

  @override
  Map<String, ToolGroup> get groupAssignments => const {
    'geocode': ToolGroup.map, 'regeocode': ToolGroup.map,
    'search_places': ToolGroup.map, 'search_nearby': ToolGroup.map,
    'plan_driving_route': ToolGroup.map, 'plan_transit_route': ToolGroup.map,
    'plan_walking_route': ToolGroup.map, 'plan_cycling_route': ToolGroup.map,
    'plan_electrobike_route': ToolGroup.map, 'get_bus_arrival': ToolGroup.map,
    'get_traffic_status': ToolGroup.map, 'get_traffic_events': ToolGroup.map,
    'bus_stop_by_id': ToolGroup.map, 'search_bus_stop': ToolGroup.map,
    'bus_line_by_id': ToolGroup.map, 'search_bus_line': ToolGroup.map,
    'get_district_info': ToolGroup.map, 'static_map': ToolGroup.map,
    'distance_calc': ToolGroup.map, 'map_screenshot': ToolGroup.map,
    'set_map_cache_limit': ToolGroup.map, 'coordinate_converter': ToolGroup.map,
    'poi_detail': ToolGroup.map, 'grasproad': ToolGroup.map,
    'future_route': ToolGroup.map, 'map_agent': ToolGroup.map,
  };

  @override
  List<ToolDefinition> get definitions => [
        // ── 基础：地理编码 ──
        ToolDefinition(
          name: 'geocode',
          description: '将地址转换为经纬度坐标。返回地址、坐标、行政区划代码、城市名。',
          category: ToolCategory.map,
          baseRisk: 0.01,
          tags: ['map', 'network'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'address': {'type': 'string', 'description': '地址，越详细结果越精确'},
              'city': {'type': 'string', 'description': '城市名，缩小搜索范围（可选）'},
            },
            'required': ['address'],
          },
        ),
        ToolDefinition(
          name: 'regeocode',
          description: '将经纬度坐标转换为结构化地址（省/市/区/街道/门牌号）。',
          category: ToolCategory.map,
          baseRisk: 0.01,
          tags: ['map', 'network'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'lng': {'type': 'number', 'description': '经度'},
              'lat': {'type': 'number', 'description': '纬度'},
            },
            'required': ['lng', 'lat'],
          },
        ),

        // ── POI 搜索 ──
        ToolDefinition(
          name: 'search_places',
          description: '按关键词搜索地点。可选限定城市和 POI 类型。返回名称、地址、坐标、电话、类型，最多 20 条。',
          category: ToolCategory.map,
          baseRisk: 0.02,
          tags: ['map', 'network', 'search'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'keywords': {'type': 'string', 'description': '搜索关键词'},
              'city': {'type': 'string', 'description': '限定城市，不传则全国搜索'},
              'type': {'type': 'string', 'description': 'POI 类型，如 餐饮服务、住宿服务（可选）'},
            },
            'required': ['keywords'],
          },
        ),
        ToolDefinition(
          name: 'search_nearby',
          description: '搜索指定位置周边的 POI。不传坐标则使用设备当前位置。',
          category: ToolCategory.map,
          baseRisk: 0.02,
          tags: ['map', 'network', 'search'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'lng': {'type': 'number', 'description': '中心点经度，不传则用设备位置'},
              'lat': {'type': 'number', 'description': '中心点纬度，不传则用设备位置'},
              'radius': {'type': 'integer', 'description': '搜索半径（米），默认 1000，最大 50000'},
              'keywords': {'type': 'string', 'description': '关键词，不传则返回所有类型（可选）'},
            },
            'required': [],
          },
        ),

        // ── 路线规划 ──
        ToolDefinition(
          name: 'plan_driving_route',
          description: '规划驾车路线。返回距离、预计时间、路线步骤。',
          category: ToolCategory.map,
          baseRisk: 0.02,
          tags: ['map', 'network', 'route'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'origin_lng': {'type': 'number', 'description': '起点经度'},
              'origin_lat': {'type': 'number', 'description': '起点纬度'},
              'dest_lng': {'type': 'number', 'description': '终点经度'},
              'dest_lat': {'type': 'number', 'description': '终点纬度'},
              'strategy': {'type': 'integer', 'description': '0=速度优先（默认），1=费用优先，2=距离优先，3=不走快速路'},
            },
            'required': ['origin_lng', 'origin_lat', 'dest_lng', 'dest_lat'],
          },
        ),
        ToolDefinition(
          name: 'plan_transit_route',
          description: '规划公交/地铁路线。返回多条换乘方案，含总距离、用时、费用、换乘段详情。',
          category: ToolCategory.map,
          baseRisk: 0.02,
          tags: ['map', 'network', 'route', 'transit'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'origin_lng': {'type': 'number', 'description': '起点经度'},
              'origin_lat': {'type': 'number', 'description': '起点纬度'},
              'dest_lng': {'type': 'number', 'description': '终点经度'},
              'dest_lat': {'type': 'number', 'description': '终点纬度'},
              'city': {'type': 'string', 'description': '城市名'},
              'strategy': {'type': 'integer', 'description': '0=最快（默认），2=最少换乘，3=最少步行，5=不坐地铁'},
            },
            'required': ['origin_lng', 'origin_lat', 'dest_lng', 'dest_lat'],
          },
        ),
        ToolDefinition(
          name: 'plan_walking_route',
          description: '规划步行路线。返回距离、预计时间、步行步骤。',
          category: ToolCategory.map,
          baseRisk: 0.02,
          tags: ['map', 'network', 'route'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'origin_lng': {'type': 'number', 'description': '起点经度'},
              'origin_lat': {'type': 'number', 'description': '起点纬度'},
              'dest_lng': {'type': 'number', 'description': '终点经度'},
              'dest_lat': {'type': 'number', 'description': '终点纬度'},
            },
            'required': ['origin_lng', 'origin_lat', 'dest_lng', 'dest_lat'],
          },
        ),
        ToolDefinition(
          name: 'plan_cycling_route',
          description: '规划骑行路线。返回距离、预计时间、路线步骤。',
          category: ToolCategory.map,
          baseRisk: 0.02,
          tags: ['map', 'network', 'route'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'origin_lng': {'type': 'number', 'description': '起点经度'},
              'origin_lat': {'type': 'number', 'description': '起点纬度'},
              'dest_lng': {'type': 'number', 'description': '终点经度'},
              'dest_lat': {'type': 'number', 'description': '终点纬度'},
            },
            'required': ['origin_lng', 'origin_lat', 'dest_lng', 'dest_lat'],
          },
        ),

        // ── 电动车路线 ──
        ToolDefinition(
          name: 'plan_electrobike_route',
          description: '规划电动车路线。返回距离、预计时间、路线步骤。',
          category: ToolCategory.map,
          baseRisk: 0.02,
          tags: ['map', 'network', 'route'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'origin_lng': {'type': 'number', 'description': '起点经度'},
              'origin_lat': {'type': 'number', 'description': '起点纬度'},
              'dest_lng': {'type': 'number', 'description': '终点经度'},
              'dest_lat': {'type': 'number', 'description': '终点纬度'},
            },
            'required': ['origin_lng', 'origin_lat', 'dest_lng', 'dest_lat'],
          },
        ),

        // ── 实时公交 ──
        ToolDefinition(
          name: 'get_bus_arrival',
          description: '查询实时公交到站信息。返回线路名、方向、预计到站时间、距离站台米数。数据覆盖取决于城市。',
          category: ToolCategory.map,
          baseRisk: 0.02,
          tags: ['map', 'network', 'transit', 'realtime'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'city': {'type': 'string', 'description': '城市名，必填'},
              'stop_name': {'type': 'string', 'description': '公交站名'},
              'line_name': {'type': 'string', 'description': '公交线路名，不传则返回经过该站的所有线路（可选）'},
            },
            'required': ['city', 'stop_name'],
          },
        ),

        // ── 公交站点/线路查询 ──
        ToolDefinition(
          name: 'bus_stop_by_id',
          description: '根据公交站点 ID 查询站点详细信息，包括途经线路。站点 ID 来自 search_bus_stop。',
          category: ToolCategory.map,
          baseRisk: 0.01,
          tags: ['map', 'network', 'transit'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'city': {'type': 'string', 'description': '城市名，必填'},
              'stop_id': {'type': 'string', 'description': '公交站点 ID'},
            },
            'required': ['city', 'stop_id'],
          },
        ),
        ToolDefinition(
          name: 'search_bus_stop',
          description: '按关键词搜索公交站点。返回站点名、ID、坐标、途经线路。',
          category: ToolCategory.map,
          baseRisk: 0.02,
          tags: ['map', 'network', 'transit', 'search'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'city': {'type': 'string', 'description': '城市名，必填'},
              'keywords': {'type': 'string', 'description': '站点名称关键词'},
            },
            'required': ['city', 'keywords'],
          },
        ),
        ToolDefinition(
          name: 'bus_line_by_id',
          description: '根据公交线路 ID 查询线路详情，包括起止站、首末班时间、途经站点列表。线路 ID 来自 search_bus_line。',
          category: ToolCategory.map,
          baseRisk: 0.01,
          tags: ['map', 'network', 'transit'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'city': {'type': 'string', 'description': '城市名，必填'},
              'line_id': {'type': 'string', 'description': '公交线路 ID'},
            },
            'required': ['city', 'line_id'],
          },
        ),
        ToolDefinition(
          name: 'search_bus_line',
          description: '按关键词搜索公交线路。返回线路名、ID、起止站。',
          category: ToolCategory.map,
          baseRisk: 0.02,
          tags: ['map', 'network', 'transit', 'search'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'city': {'type': 'string', 'description': '城市名，必填'},
              'keywords': {'type': 'string', 'description': '线路名称关键词，如"1路"、"地铁1号线"'},
            },
            'required': ['city', 'keywords'],
          },
        ),

        // ── 交通路况 ──
        ToolDefinition(
          name: 'get_traffic_status',
          description: '查询实时交通状况。支持圆形区域、指定线路、矩形区域三种模式。',
          category: ToolCategory.map,
          baseRisk: 0.02,
          tags: ['map', 'network', 'realtime'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'type': {'type': 'string', 'description': '查询模式：circle（圆形，默认）/ road（线路）/ rectangle（矩形）'},
              // 圆形模式
              'lng': {'type': 'number', 'description': '中心点经度（圆形模式）'},
              'lat': {'type': 'number', 'description': '中心点纬度（圆形模式）'},
              'radius': {'type': 'integer', 'description': '查询半径米（圆形模式），默认 1000'},
              // 线路模式
              'road_name': {'type': 'string', 'description': '道路名称（线路模式）'},
              'adcode': {'type': 'string', 'description': '城市编码（线路模式）'},
              // 矩形模式
              'sw_lng': {'type': 'number', 'description': '矩形左下经度（矩形模式）'},
              'sw_lat': {'type': 'number', 'description': '矩形左下纬度（矩形模式）'},
              'ne_lng': {'type': 'number', 'description': '矩形右上经度（矩形模式）'},
              'ne_lat': {'type': 'number', 'description': '矩形右上纬度（矩形模式）'},
              // 通用
              'level': {'type': 'integer', 'description': '道路等级：1=高速，6=所有道路（默认）'},
              'extensions': {'type': 'string', 'description': 'base=简略（默认），all=详细'},
            },
            'required': [],
          },
        ),

        // ── 交通事件查询 ──
        ToolDefinition(
          name: 'get_traffic_events',
          description: '查询指定区域的交通事件。返回事件类型、描述、路段、方向、起止时间。',
          category: ToolCategory.map,
          baseRisk: 0.02,
          tags: ['map', 'network', 'realtime'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'adcode': {'type': 'string', 'description': '行政区划代码，必填'},
              'event_type': {'type': 'string', 'description': '事件类型（可选）'},
              'is_expressway': {'type': 'boolean', 'description': '是否只查高速，默认 false'},
            },
            'required': ['adcode'],
          },
        ),

        // ── 行政区划 ──
        ToolDefinition(
          name: 'get_district_info',
          description: '查询行政区划信息。返回 adcode、行政中心坐标、下级区划列表。',
          category: ToolCategory.map,
          baseRisk: 0.01,
          tags: ['map', 'network'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'keywords': {'type': 'string', 'description': '行政区名称'},
              'subdistrict': {'type': 'integer', 'description': '下级区划层级：0=本级（默认），1=下一级，2=下两级'},
            },
            'required': ['keywords'],
          },
        ),

        // ── 静态地图 ──
        ToolDefinition(
          name: 'static_map',
          description: '生成静态地图图片。支持标记点和路线叠加，最多 5 个标记点。',
          category: ToolCategory.map,
          baseRisk: 0.01,
          tags: ['map', 'network', 'image'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'lng': {'type': 'number', 'description': '地图中心点经度'},
              'lat': {'type': 'number', 'description': '地图中心点纬度'},
              'zoom': {'type': 'integer', 'description': '缩放级别 1-17，默认 14'},
              'width': {'type': 'integer', 'description': '图片宽度（像素），默认 600'},
              'height': {'type': 'integer', 'description': '图片高度（像素），默认 400'},
              'markers': {'type': 'array', 'description': '标记点列表，每项含 lat/lng/label', 'items': {'type': 'object'}},
            },
            'required': ['lng', 'lat'],
          },
        ),

        // ── 距离计算 ──
        ToolDefinition(
          name: 'distance_calc',
          description: '计算两点之间的直线距离（米）。非路线距离，如需行驶距离请用路线规划工具。',
          category: ToolCategory.map,
          baseRisk: 0.005,
          tags: ['map', 'utility'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'origin_lng': {'type': 'number', 'description': '起点经度'},
              'origin_lat': {'type': 'number', 'description': '起点纬度'},
              'dest_lng': {'type': 'number', 'description': '终点经度'},
              'dest_lat': {'type': 'number', 'description': '终点纬度'},
            },
            'required': ['origin_lng', 'origin_lat', 'dest_lng', 'dest_lat'],
          },
        ),

        // ── 地图截图 ──
        ToolDefinition(
          name: 'map_screenshot',
          description: '截取当前地图页面，保存为 PNG 文件。不要用 browser_screenshot 截地图。',
          category: ToolCategory.map,
          baseRisk: 0.02,
          tags: ['map', 'utility', 'file'],
          inputSchema: {'type': 'object', 'properties': {}, 'required': []},
        ),

        // ── 地图截图缓存上限 ──
        ToolDefinition(
          name: 'set_map_cache_limit',
          description: '设置地图截图缓存文件保留数量上限。',
          category: ToolCategory.map,
          baseRisk: 0.0,
          tags: ['map', 'config'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'limit': {'type': 'integer', 'description': '缓存上限，范围 1~50'},
            },
            'required': ['limit'],
          },
        ),

        // ── 坐标转换 ──
        ToolDefinition(
          name: 'coordinate_converter',
          description: '坐标转换。支持 GPS(WGS-84) 与高德(GCJ-02) 互转。',
          category: ToolCategory.map,
          baseRisk: 0.005,
          tags: ['map', 'utility'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'lng': {'type': 'number', 'description': '原始经度'},
              'lat': {'type': 'number', 'description': '原始纬度'},
              'type': {'type': 'string', 'description': '转换方向：gps2gcj 或 gcj2gps，默认 gps2gcj'},
            },
            'required': ['lng', 'lat'],
          },
        ),

        // ── POI详情查询 ──
        ToolDefinition(
          name: 'poi_detail',
          description: '查询 POI 详细信息。传入 search_places 或 search_nearby 返回的 POI ID。返回电话、评分、营业时间、照片、网址。',
          category: ToolCategory.map,
          baseRisk: 0.01,
          tags: ['map', 'network', 'poi'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'poi_id': {'type': 'string', 'description': 'POI ID，来自 search_places 或 search_nearby'},
            },
            'required': ['poi_id'],
          },
        ),

        // ── 轨迹纠偏 ──
        ToolDefinition(
          name: 'grasproad',
          description: '将 GPS 坐标点纠偏到真实道路上。传入坐标点数组，返回纠偏后的道路坐标序列和总距离。',
          category: ToolCategory.map,
          baseRisk: 0.02,
          tags: ['map', 'network', 'route'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'points': {
                'type': 'array',
                'description': '坐标点数组，每项含 lng/lat/speed/angle/timestamp',
                'items': {
                  'type': 'object',
                  'properties': {
                    'lng': {'type': 'number'}, 'lat': {'type': 'number'},
                    'speed': {'type': 'number'}, 'angle': {'type': 'number'},
                    'timestamp': {'type': 'integer'},
                  },
                  'required': ['lng', 'lat', 'speed', 'angle', 'timestamp'],
                },
              },
            },
            'required': ['points'],
          },
        ),

        // ── 未来路径规划 ──
        ToolDefinition(
          name: 'future_route',
          description: '查询未来 7 天的出行路线规划。需企业高级服务权限，普通用户调用会返回权限错误。',
          category: ToolCategory.map,
          baseRisk: 0.08,
          tags: ['map', 'network', 'route', 'advanced'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'origin_lng': {'type': 'number', 'description': '起点经度'},
              'origin_lat': {'type': 'number', 'description': '起点纬度'},
              'dest_lng': {'type': 'number', 'description': '终点经度'},
              'dest_lat': {'type': 'number', 'description': '终点纬度'},
              'first_time': {'type': 'integer', 'description': '第一个出发时间，Unix 时间戳（秒）'},
              'interval': {'type': 'integer', 'description': '时间间隔（秒）'},
              'count': {'type': 'integer', 'description': '时间点个数，最多 48'},
              'strategy': {'type': 'integer', 'description': '路线策略：1=躲避拥堵（默认），2=不走高速，3=避免收费'},
              'province': {'type': 'string', 'description': '车牌省份缩写（可选）'},
              'number': {'type': 'string', 'description': '车牌号（可选）'},
              'car_type': {'type': 'integer', 'description': '车辆类型：0=普通（默认），1=纯电动，2=插电混动'},
            },
            'required': ['origin_lng', 'origin_lat', 'dest_lng', 'dest_lat', 'first_time', 'interval', 'count'],
          },
        ),

        // ── 地图 Agent ──
        ToolDefinition(
          name: 'map_agent',
          description: '出行规划入口，自动组合多个地图工具完成复杂任务。单步操作直接用单体工具。',
          category: ToolCategory.map,
          baseRisk: 0.08,
          tags: ['map', 'agent', 'primary', 'network'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'task': {'type': 'string', 'description': '出行任务描述，包含目的地、出发地、约束条件等'},
            },
            'required': ['task'],
          },
        ),
      ];
}
