import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

class Kuaidi100Client {

  Kuaidi100Client({required this.customer, required this.key})
      : _dio = Dio(BaseOptions(
          baseUrl: 'https://poll.kuaidi100.com',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ));
  final String customer;
  final String key;
  final Dio _dio;

  /// 安全提取响应体为 Map
  static Map<String, dynamic> _asMap(dynamic obj) {
    if (obj is Map<String, dynamic>) return obj;
    if (obj is String) {
      try {
        final decoded = jsonDecode(obj);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  /// 安全提取子字段为 Map
  static Map<String, dynamic> _mapField(Map<String, dynamic> map, String key) {
    final v = map[key];
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  /// 安全提取子字段为 List<Map>
  static List<Map<String, dynamic>> _listField(Map<String, dynamic> map, String key) {
    final v = map[key];
    if (v == null) return [];
    if (v is List) {
      return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    return [];
  }

  /// String 字段安全提取
  static String _strField(Map<String, dynamic> map, String key, [String fallback = '']) {
    final v = map[key];
    if (v == null) return fallback;
    return v.toString();
  }

  /// 查询快递轨迹
  Future<Map<String, dynamic>> query(String num, {String com = '', String phone = ''}) async {
    final paramObj = <String, dynamic>{
      'num': num,
      'resultv2': '4',
    };
    if (com.isNotEmpty) paramObj['com'] = com;
    if (phone.isNotEmpty) paramObj['phone'] = phone;

    final paramJson = jsonEncode(paramObj);
    final sign = _md5('$paramJson$key$customer').toUpperCase();

    final response = await _dio.post(
      '/poll/query.do',
      data: {
        'customer': customer,
        'sign': sign,
        'param': paramJson,
      },
      options: Options(
        contentType: 'application/x-www-form-urlencoded',
        responseType: ResponseType.json,
      ),
    );

    return _asMap(response.data);
  }

  /// 查询快递轨迹并格式化为可读文本
  Future<String> queryFormatted(String num, {String com = '', String phone = ''}) async {
    final data = await query(num, com: com, phone: phone);

    if (data.isEmpty) return '查询失败: 服务器返回了空响应';
    if (data['result'] == false || data['returnCode'] != null && data['returnCode'].toString() != '200') {
      final code = data['returnCode']?.toString() ?? 'unknown';
      final msg = data['message']?.toString() ?? '未知错误';
      return _errorMessage(code, msg);
    }

    return _formatResult(data);
  }

  static String _formatResult(Map<String, dynamic> data) {
    final buf = StringBuffer();
    final state = _strField(data, 'state', '?');
    final com = _strField(data, 'com', '?');
    final nu = _strField(data, 'nu', '?');
    final isCheck = _strField(data, 'ischeck') == '1';

    buf.writeln('📦 快递单号: $nu');
    buf.writeln('🚚 快递公司: $com');
    buf.writeln('📌 当前状态: ${_stateLabel(state)}');
    if (isCheck) buf.writeln('✅ 已签收');

    final arrival = _strField(data, 'arrivalTime');
    if (arrival.isNotEmpty) buf.writeln('⏱ 预计到达: $arrival');
    final remain = _strField(data, 'remainTime');
    if (remain.isNotEmpty) buf.writeln('⏳ 还需: $remain');

    // 路由信息
    final route = _mapField(data, 'routeInfo');
    if (route.isNotEmpty) {
      final from = _mapField(route, 'from');
      final to = _mapField(route, 'to');
      if (from.isNotEmpty) buf.writeln('📍 发件: ${_strField(from, 'name')}');
      if (to.isNotEmpty) buf.writeln('📍 收件: ${_strField(to, 'name')}');
    }

    buf.writeln();
    buf.writeln('━━━ 物流轨迹 ━━━');

    final list = _listField(data, 'data');
    for (final item in list) {
      final time = _strField(item, 'time');
      final context = _strField(item, 'context');
      final status = _strField(item, 'status');
      final displayTime = time.length >= 16 ? time.substring(5, 16) : time;
      buf.write('[$displayTime]');
      if (status.isNotEmpty) buf.write(' [$status]');
      buf.writeln(' $context');
    }

    if (list.isEmpty) {
      buf.writeln('(暂无轨迹明细)');
    }

    return buf.toString();
  }

  static String _stateLabel(String state) {
    switch (state) {
      case '0': return '在途';
      case '1': return '揽收';
      case '2': return '疑难';
      case '3': return '签收';
      case '4': return '退签';
      case '5': return '派件';
      case '6': return '退回';
      case '7': return '转投';
      case '8': return '清关';
      default: return '状态$state';
    }
  }

  static String _errorMessage(String code, String message) {
    switch (code) {
      case '400': return '快递单号或公司编码有误，请检查后重试（$message）';
      case '408': return '验证码错误，请提供收件人或寄件人电话号码后四位（顺丰、中通必须）';
      case '500': return '暂无物流信息，可能尚未发货或单号有误';
      case '501': return '服务器暂时异常，请稍后重试';
      case '502': return '服务器繁忙，请稍后重试';
      case '503': return '鉴权失败，请检查快递100的 customer 和 key 配置';
      case '601': return 'API 额度已用完，请充值';
      default: return '查询失败 (code=$code): $message';
    }
  }

  /// 订阅快递单号
  Future<Map<String, dynamic>> subscribe(String num,
      {String com = '', String phone = '', String? callbackUrl, String from = '', String to = ''}) async {
    final parameters = <String, dynamic>{'resultv2': '4'};
    if (callbackUrl != null && callbackUrl.isNotEmpty) parameters['callbackurl'] = callbackUrl;
    if (phone.isNotEmpty) parameters['phone'] = phone;

    final paramObj = <String, dynamic>{
      'number': num,
      'key': key,
      'parameters': parameters,
    };
    if (com.isNotEmpty) {
      paramObj['company'] = com;
    } else {
      parameters['autoCom'] = '1';
    }
    if (from.isNotEmpty) paramObj['from'] = from;
    if (to.isNotEmpty) paramObj['to'] = to;

    final paramJson = jsonEncode(paramObj);
    final sign = _md5('$paramJson$key$customer').toUpperCase();

    final response = await _dio.post('/poll', data: {
      'schema': 'json',
      'param': paramJson,
    }, options: Options(
      contentType: 'application/x-www-form-urlencoded',
      responseType: ResponseType.json,
    ));

    return _asMap(response.data);
  }

  Future<String> subscribeFormatted(String num,
      {String com = '', String phone = '', String? callbackUrl, String from = '', String to = ''}) async {
    final data = await subscribe(num, com: com, phone: phone, callbackUrl: callbackUrl, from: from, to: to);

    if (data['result'] == true) {
      return '✅ 订阅成功：快递单号 $num 已开始监控，状态变化时可通过 express_track 查询最新进展';
    }

    final code = data['returnCode']?.toString() ?? 'unknown';
    final msg = data['message']?.toString() ?? '未知错误';
    if (code == '501') {
      return '⚠️ 该单号已订阅过。可直接用 express_track 查询最新状态。';
    }
    return '订阅失败: $msg (code=$code)';
  }

  /// 查询快递地图轨迹
  Future<Map<String, dynamic>> mapTrack(String num, String com,
      {required String from, required String to, String phone = ''}) async {
    final paramObj = <String, dynamic>{
      'com': com,
      'num': num,
      'from': from,
      'to': to,
      'resultv2': '5',
    };
    if (phone.isNotEmpty) paramObj['phone'] = phone;

    final paramJson = jsonEncode(paramObj);
    final sign = _md5('$paramJson$key$customer').toUpperCase();

    final response = await _dio.post('/poll/maptrack.do', data: {
      'customer': customer,
      'sign': sign,
      'param': paramJson,
    }, options: Options(
      contentType: 'application/x-www-form-urlencoded',
      responseType: ResponseType.json,
    ));

    return _asMap(response.data);
  }

  Future<String> mapTrackFormatted(String num, String com,
      {required String from, required String to, String phone = ''}) async {
    final data = await mapTrack(num, com, from: from, to: to, phone: phone);

    if (data.isEmpty) return '查询失败: 服务器返回了空响应';
    if (data['result'] == false) {
      final code = data['returnCode']?.toString() ?? 'unknown';
      return _errorMessage(code, data['message']?.toString() ?? '未知错误');
    }

    final buf = StringBuffer();
    buf.writeln(_formatResult(data));

    final trailUrl = _strField(data, 'trailUrl');
    if (trailUrl.isNotEmpty) {
      buf.writeln();
      buf.writeln('🗺 地图轨迹: $trailUrl');
    }

    final predicted = _listField(data, 'predictedRoute');
    if (predicted.isNotEmpty) {
      buf.writeln();
      buf.writeln('━━━ 预计路由节点 ━━━');
      for (final n in predicted) {
        final nodeState = _strField(n, 'state');
        final nodeType = _strField(n, 'type');
        final stateIcon = nodeState == '已经过节点' ? '✅' : (nodeState == '当前停留节点' ? '📍' : '🔮');
        final typeIcon = nodeType == '转运中心' ? '🏭' : '📦';
        buf.write('$stateIcon$typeIcon ${_strField(n, 'name')}');
        final loc = _strField(n, 'location');
        if (loc.isNotEmpty) buf.write(' ($loc)');
        final at = _strField(n, 'arriveTime');
        if (at.isNotEmpty) buf.write(' → $at');
        buf.writeln();
      }
    }

    return buf.toString();
  }

  String _md5(String input) => md5.convert(utf8.encode(input)).toString();
}
