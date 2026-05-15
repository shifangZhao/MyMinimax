import 'worldtime_client.dart';

/// Fetches the WorldTime API once and caches the offset between API time and
/// device time.  Subsequent calls to [now] return the device time corrected by
/// that offset — accurate even if the device clock drifts, without making a
/// network call on every access.
class TimeOffsetService {
  TimeOffsetService._();
  static final TimeOffsetService instance = TimeOffsetService._();

  Duration _offset = Duration.zero;
  bool _calibrated = false;
  String? _weekday;
  String? _timezone;

  bool get isCalibrated => _calibrated;

  /// Call once at startup.  Compensates for network round-trip time (RTT/2)
  /// so the offset isn't skewed by latency.  Fails silently — uncalibrated
  /// [now] falls back to the device clock.
  Future<void> calibrate() async {
    try {
      final t0 = DateTime.now();                      // before request
      final client = WorldTimeClient();
      final data = await client.query(t0.timeZoneName);
      final t1 = DateTime.now();                      // after response received

      final datetime = data['datetime'] as String? ?? '';
      if (datetime.length >= 19) {
        final apiDt = DateTime.tryParse(datetime);    // server time at request processing
        if (apiDt != null) {
          final rtt = t1.difference(t0);
          // Compensate half the RTT — apiDt was captured ~RTT/2 before t1
          final correctedServerTime = apiDt.add(
            Duration(microseconds: rtt.inMicroseconds ~/ 2),
          );
          _offset = correctedServerTime.difference(t1);
          _calibrated = true;
        }
      }
      _weekday = data['weekday'] as String?;
      _timezone = data['timezone'] as String?;
    } catch (_) {
      _calibrated = false;
    }
  }

  /// Returns the current time corrected by the API offset.
  DateTime now() => DateTime.now().add(_offset);

  /// Weekday string from the most recent API response (e.g. "Friday").
  String? get weekday => _weekday;

  /// Timezone string from the most recent API response (e.g. "Asia/Shanghai").
  String? get timezone => _timezone;
}
