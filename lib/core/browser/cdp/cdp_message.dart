import 'dart:convert';

/// Chrome DevTools Protocol wire-level models.
///
/// CDP uses JSON-RPC 2.0 over WebSocket:
///   Request  → {"id": N, "method": "Domain.method", "params": {...}}
///   Response → {"id": N, "result": {...}} or {"id": N, "error": {...}}
///   Event    → {"method": "Domain.event", "params": {...}}
///
/// Session-scoped commands add a `sessionId` field to the request.

class CdpRequest {

  const CdpRequest({
    required this.id,
    required this.method,
    this.params,
    this.sessionId,
  });
  final int id;
  final String method;
  final Map<String, dynamic>? params;
  final String? sessionId;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'id': id,
      'method': method,
    };
    if (params != null && params!.isNotEmpty) m['params'] = params;
    if (sessionId != null) m['sessionId'] = sessionId;
    return m;
  }

  @override
  String toString() => 'CdpRequest(#$id $method)';
}

class CdpResponse {

  const CdpResponse({
    required this.id,
    this.result,
    this.error,
    this.rawJson,
  });

  factory CdpResponse.fromJson(Map<String, dynamic> json) {
    return CdpResponse(
      id: json['id'] as int,
      result: json['result'] as Map<String, dynamic>?,
      error: json['error'] != null
          ? CdpError.fromJson(json['error'] as Map<String, dynamic>)
          : null,
      rawJson: jsonEncode(json),
    );
  }
  final int id;
  final Map<String, dynamic>? result;
  final CdpError? error;
  final String? rawJson;

  bool get isError => error != null;

  @override
  String toString() => 'CdpResponse(#$id ${isError ? "ERR:$error" : "OK"})';
}

class CdpError {

  const CdpError({required this.code, required this.message, this.data});

  factory CdpError.fromJson(Map<String, dynamic> json) {
    return CdpError(
      code: json['code'] as int,
      message: json['message'] as String,
      data: json['data'] as String?,
    );
  }
  final int code;
  final String message;
  final String? data;

  @override
  String toString() => 'CdpError($code: $message)';
}

class CdpEvent {

  const CdpEvent({
    required this.method,
    this.params,
    this.sessionId,
  });

  factory CdpEvent.fromJson(Map<String, dynamic> json) {
    return CdpEvent(
      method: json['method'] as String,
      params: json['params'] as Map<String, dynamic>?,
      sessionId: json['sessionId'] as String?,
    );
  }
  final String method;
  final Map<String, dynamic>? params;
  final String? sessionId;

  String get domain => method.split('.').first;
  String get eventName => method.split('.').last;

  @override
  String toString() => 'CdpEvent($method)';
}

/// Dispatch helper: routes incoming JSON strings to Request/Response/Event.
CdpMessageType classifyCdpMessage(String jsonStr) {
  try {
    final m = jsonDecode(jsonStr) as Map<String, dynamic>;
    if (m.containsKey('method') && !m.containsKey('id')) {
      return CdpMessageType.event(CdpEvent.fromJson(m));
    }
    if (m.containsKey('id') && m.containsKey('method')) {
      return CdpMessageType.request(CdpRequest(
        id: m['id'] as int,
        method: m['method'] as String,
        params: m['params'] as Map<String, dynamic>?,
        sessionId: m['sessionId'] as String?,
      ));
    }
    if (m.containsKey('id')) {
      return CdpMessageType.response(CdpResponse.fromJson(m));
    }
  } catch (_) {}
  return const CdpMessageType.unknown();
}

sealed class CdpMessageType {
  const CdpMessageType();

  const factory CdpMessageType.request(CdpRequest r) = _CdpRequestMessage;
  const factory CdpMessageType.response(CdpResponse r) = _CdpResponseMessage;
  const factory CdpMessageType.event(CdpEvent e) = _CdpEventMessage;
  const factory CdpMessageType.unknown() = _CdpUnknownMessage;

  bool get isRequest => this is _CdpRequestMessage;
  bool get isResponse => this is _CdpResponseMessage;
  bool get isEvent => this is _CdpEventMessage;
  bool get isUnknown => this is _CdpUnknownMessage;

  CdpRequest? get asRequest => isRequest ? (this as _CdpRequestMessage).value : null;
  CdpResponse? get asResponse => isResponse ? (this as _CdpResponseMessage).value : null;
  CdpEvent? get asEvent => isEvent ? (this as _CdpEventMessage).value : null;
}

class _CdpRequestMessage extends CdpMessageType {
  const _CdpRequestMessage(this.value);
  final CdpRequest value;
}

class _CdpResponseMessage extends CdpMessageType {
  const _CdpResponseMessage(this.value);
  final CdpResponse value;
}

class _CdpEventMessage extends CdpMessageType {
  const _CdpEventMessage(this.value);
  final CdpEvent value;
}

class _CdpUnknownMessage extends CdpMessageType {
  const _CdpUnknownMessage();
}
