import 'package:dio/dio.dart';
import 'safe_response.dart';

class WorldTimeException implements Exception {
  WorldTimeException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'WorldTime API error [$code]: $message';
}

class WorldTimeClient {

  WorldTimeClient()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ));
  static const _baseUrl = 'https://uapis.cn/api/v1/misc/worldtime';

  final Dio _dio;

  Future<Map<String, dynamic>> query(String city) async {
    final response = await _dio.get(_baseUrl, queryParameters: {'city': city});
    final data = SafeResponse.asMap(response.data);

    final code = data['code'] as String?;
    if (code != null && code != 'OK') {
      throw WorldTimeException(code, data['message']?.toString() ?? 'Unknown error / 未知错误');
    }

    return data;
  }
}
