/// PII / credential detection hook — runs beforeSend.
///
/// Scans the user message for sensitive patterns (phone numbers, ID cards,
/// emails, API keys, IPs) and auto-masks them so they never leave the device.
library;

import '../hook_pipeline.dart';

// ---- Patterns ----

final _patterns = <_PiiPattern>[
  // Ordered: broader patterns after narrower ones

  // Chinese ID card (18-digit)
  _PiiPattern(
    label: '身份证号',
    re: RegExp(r'\b\d{6}(?:19|20)\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])\d{3}[\dXx]\b'),
  ),

  // Chinese mobile phone
  _PiiPattern(
    label: '手机号',
    re: RegExp(r'\b1[3-9]\d{9}\b'),
  ),

  // Email
  _PiiPattern(
    label: '邮箱',
    re: RegExp(r'\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\b'),
  ),

  // API key / token patterns
  _PiiPattern(
    label: 'API密钥',
    re: RegExp(r"""(?:api[_-]?key|apikey|secret|token|password|passwd)\s*[:=]\s*['"]?\s*[^\s'"]{8,}""",
        caseSensitive: false),
  ),

  // Bearer token
  _PiiPattern(
    label: '令牌',
    re: RegExp(r'bearer\s+[a-zA-Z0-9\-._~+/]+=*', caseSensitive: false),
  ),

  // sk- prefixed keys (OpenAI / Minimax style)
  _PiiPattern(
    label: '密钥',
    re: RegExp(r'\bsk-[a-zA-Z0-9]{16,}\b'),
  ),

  // IPv4
  _PiiPattern(
    label: 'IP地址',
    re: RegExp(r'\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b'),
  ),
];

// ---- Model ----

class _PiiPattern {
  const _PiiPattern({required this.label, required this.re});
  final String label;
  final RegExp re;
}

/// Fixed-size LRU to avoid re-masking the same content repeatedly.
class _MaskedCache {
  static const _maxSize = 64;
  final _entries = <String, String>{};
  final _keys = <String>[];

  String? get(String key) => _entries[key];

  void put(String key, String value) {
    if (_entries.containsKey(key)) return;
    if (_keys.length >= _maxSize) {
      final removed = _keys.removeAt(0);
      _entries.remove(removed);
    }
    _keys.add(key);
    _entries[key] = value;
  }
}

final _cache = _MaskedCache();

// ---- Hook ----

Future<void> piiDetectHook(HookContext ctx) async {
  final raw = ctx.data['message'] as String?;
  if (raw == null || raw.isEmpty) return;

  final cached = _cache.get(raw);
  if (cached != null) {
    ctx.data['message'] = cached;
    return;
  }

  var masked = raw;
  final found = <String>[];

  for (final p in _patterns) {
    masked = masked.replaceAllMapped(p.re, (m) {
      found.add(p.label);
      return '[已隐藏: ${p.label}]';
    });
  }

  if (found.isNotEmpty) {
    _cache.put(raw, masked);
    ctx.data['message'] = masked;
    ctx.data['pii_masked'] = true;
    ctx.data['pii_types'] = found.toSet().toList();
  }
}
