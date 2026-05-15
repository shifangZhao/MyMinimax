import 'dart:math' as math;

/// Generates direction arrow position/angle data along a polyline.
///
/// Instead of rendering PNG bytes on the Flutter side, this produces lightweight
/// position+heading payloads that are sent through MethodChannel to the native
/// Android side, which renders arrow bitmaps via Canvas and caches them.
class ArrowPolyline {
  /// Calculate arrow marker positions and headings along a polyline.
  ///
  /// Returns a list of [lat, lng, heading] for each arrow position.
  /// heading is in degrees, 0 = north, clockwise (高德 SDK convention).
  static List<List<double>> calculateArrowPositions(
    List<List<double>> points, {
    double spacingMeters = 80,
  }) {
    if (points.length < 2) return [];

    final positions = <List<double>>[];
    double accumulated = 0;

    for (int i = 0; i < points.length - 1; i++) {
      final from = points[i];
      final to = points[i + 1];
      final dist = _calculateDistance(from, to);
      if (dist <= 0) continue;

      final heading = _calculateHeading(from, to);
      accumulated += dist;

      while (accumulated >= spacingMeters) {
        accumulated -= spacingMeters;
        final ratio = 1.0 - accumulated / dist;
        final lat = from[0] + (to[0] - from[0]) * ratio;
        final lng = from[1] + (to[1] - from[1]) * ratio;
        positions.add([lat, lng, heading]);
      }
    }

    return positions;
  }

  /// Haversine distance in meters between two [lat, lng] points.
  static double _calculateDistance(List<double> a, List<double> b) {
    const R = 6371000.0;
    final dLat = _toRadians(b[0] - a[0]);
    final dLng = _toRadians(b[1] - a[1]);
    final sinDlat = math.sin(dLat / 2);
    final sinDlng = math.sin(dLng / 2);
    final h = sinDlat * sinDlat +
        math.cos(_toRadians(a[0])) *
            math.cos(_toRadians(b[0])) *
            sinDlng * sinDlng;
    return 2 * R * math.asin(math.sqrt(h));
  }

  /// Heading in degrees (0 = north, clockwise) from point a to b.
  static double _calculateHeading(List<double> a, List<double> b) {
    final dLng = _toRadians(b[1] - a[1]);
    final lat1 = _toRadians(a[0]);
    final lat2 = _toRadians(b[0]);
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    final heading = math.atan2(y, x);
    return (_toDegrees(heading) + 360) % 360;
  }

  static double _toRadians(double deg) => deg * math.pi / 180;
  static double _toDegrees(double rad) => rad * 180 / math.pi;
}
