import 'package:dio/dio.dart';
import 'safe_response.dart';

class WeatherException implements Exception {
  WeatherException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'Weather API error [$code]: $message';
}

class WeatherClient {

  WeatherClient()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ));
  static const _baseUrl = 'https://uapis.cn/api/v1/misc/weather';

  final Dio _dio;

  Future<Map<String, dynamic>> query({
    String? city,
    String? adcode,
    bool extended = true,
    bool forecast = true,
    bool hourly = false,
    bool minutely = false,
    bool indices = false,
    String lang = 'zh',
  }) async {
    final params = <String, dynamic>{
      if (city != null && city.isNotEmpty) 'city': city,
      if (adcode != null && adcode.isNotEmpty) 'adcode': adcode,
      'extended': extended,
      'forecast': forecast,
      'hourly': hourly,
      'minutely': minutely,
      'indices': indices,
      'lang': lang,
    };

    final response = await _dio.get(_baseUrl, queryParameters: params);
    final data = SafeResponse.asMap(response.data);

    final codeValue = data['code'];
    final code = codeValue is String ? codeValue : codeValue?.toString();
    if (code != null && code != 'OK') {
      final msgValue = data['message'];
      final msg = msgValue is String ? msgValue : msgValue?.toString() ?? 'Unknown error / 未知错误';
      throw WeatherException(code, msg);
    }

    return data;
  }
}
