/// Decodes an AMap-encoded polyline string into a list of [lat, lng] pairs.
///
/// AMap uses a variant of Google's polyline encoding:
/// - Each character encodes a 6-bit chunk (char code minus 63)
/// - The 6th bit (0x20) is a sign flag for negative values
/// - 5-bit chunks are accumulated into coordinate deltas
/// - Final coordinates are deltas divided by 1e5 from the previous point
List<List<double>> decodeAmapPolyline(String encoded) {
  if (encoded.isEmpty) return [];

  final points = <List<double>>[];
  int index = 0;
  final len = encoded.length;
  double lat = 0.0;
  double lng = 0.0;

  while (index < len) {
    // Decode latitude delta
    int latDelta = 0;
    int shift = 0;
    while (index < len) {
      final b = encoded.codeUnitAt(index) - 63;
      index++;
      latDelta |= (b & 0x1F) << shift;
      shift += 5;
      if ((b & 0x20) == 0) break;
    }
    if ((latDelta & 0x01) != 0) {
      latDelta = ~(latDelta >> 1);
    } else {
      latDelta = latDelta >> 1;
    }

    // Decode longitude delta
    int lngDelta = 0;
    shift = 0;
    while (index < len) {
      final b = encoded.codeUnitAt(index) - 63;
      index++;
      lngDelta |= (b & 0x1F) << shift;
      shift += 5;
      if ((b & 0x20) == 0) break;
    }
    if ((lngDelta & 0x01) != 0) {
      lngDelta = ~(lngDelta >> 1);
    } else {
      lngDelta = lngDelta >> 1;
    }

    lat += latDelta / 1e5;
    lng += lngDelta / 1e5;
    points.add([lat, lng]);
  }

  return points;
}
