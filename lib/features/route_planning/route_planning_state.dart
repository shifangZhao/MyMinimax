import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Travel modes supported in route planning.
enum TravelMode {
  walking('步行', Icons.directions_walk),
  cycling('骑行', Icons.directions_bike),
  driving('驾车', Icons.directions_car),
  transit('公交', Icons.directions_bus),
  truck('货车', Icons.local_shipping);

  final String label;
  final IconData icon;
  const TravelMode(this.label, this.icon);

  String get amapRouteType => switch (this) {
    TravelMode.driving || TravelMode.truck => 'driving',
    TravelMode.walking => 'walking',
    TravelMode.cycling => 'cycling',
    TravelMode.transit => 'transit',
  };
}

/// 货车车辆信息（车长/车重/车高）。
class TruckVehicle {
  final double length; // 米
  final double weight; // 吨
  final double height; // 米

  const TruckVehicle({
    this.length = 4.2,
    this.weight = 1.5,
    this.height = 1.8,
  });

  TruckVehicle copyWith({double? length, double? weight, double? height}) {
    return TruckVehicle(
      length: length ?? this.length,
      weight: weight ?? this.weight,
      height: height ?? this.height,
    );
  }
}

/// Information about a single route option.
class RouteInfo {
  final int index;
  final double distance; // meters
  final int duration; // seconds
  final double tollCost; // yuan
  final List<List<double>> polylinePoints; // [[lat, lng], ...]
  final String? polyline; // original encoded polyline
  final List<Map<String, dynamic>> steps; // navi steps

  const RouteInfo({
    required this.index,
    required this.distance,
    required this.duration,
    this.tollCost = 0,
    this.polylinePoints = const [],
    this.polyline,
    this.steps = const [],
  });

  String get distanceFormatted {
    if (distance >= 1000) return '${(distance / 1000).toStringAsFixed(1)}公里';
    return '${distance.toInt()}米';
  }

  String get durationFormatted {
    if (duration < 60) return '${duration}秒';
    final min = duration ~/ 60;
    if (min < 60) return '${min}分钟';
    final h = min ~/ 60;
    final m = min % 60;
    return '${h}小时${m}分钟';
  }
}

/// Full state for the route planning screen.
class RoutePlanState {
  /// Whether route planning UI is active.
  final bool isActive;

  /// Current selected travel mode.
  final TravelMode travelMode;

  /// Start point address / name.
  final String startAddress;
  final double? startLat;
  final double? startLng;

  /// Destination address / name.
  final String destAddress;
  final double? destLat;
  final double? destLng;

  /// Waypoints.
  final List<String> waypoints;

  /// Whether route has been calculated.
  final bool routeCalculated;

  /// Available routes.
  final List<RouteInfo> routes;

  /// Currently selected route index.
  final int selectedRouteIndex;

  /// Bottom sheet state (0.0 = collapsed, 0.5 = half, 1.0 = full).
  final double sheetFraction;

  /// Whether the sheet is being dragged (to suppress camera updates).
  final bool sheetAnimating;

  /// Whether turn-by-turn navigation is active.
  final bool isNavigating;

  /// 货车车辆信息（车长米/车重吨/车高米）。
  final TruckVehicle truckVehicle;

  const RoutePlanState({
    this.isActive = false,
    this.travelMode = TravelMode.cycling,
    this.startAddress = '',
    this.startLat,
    this.startLng,
    this.destAddress = '',
    this.destLat,
    this.destLng,
    this.waypoints = const [],
    this.routeCalculated = false,
    this.routes = const [],
    this.selectedRouteIndex = 0,
    this.sheetFraction = 0.0,
    this.sheetAnimating = false,
    this.isNavigating = false,
    this.truckVehicle = const TruckVehicle(),
  });

  RoutePlanState copyWith({
    bool? isActive,
    TravelMode? travelMode,
    String? startAddress,
    double? startLat,
    double? startLng,
    String? destAddress,
    double? destLat,
    double? destLng,
    List<String>? waypoints,
    bool? routeCalculated,
    List<RouteInfo>? routes,
    int? selectedRouteIndex,
    double? sheetFraction,
    bool? sheetAnimating,
    bool? isNavigating,
    TruckVehicle? truckVehicle,
  }) {
    return RoutePlanState(
      isActive: isActive ?? this.isActive,
      travelMode: travelMode ?? this.travelMode,
      startAddress: startAddress ?? this.startAddress,
      startLat: startLat ?? this.startLat,
      startLng: startLng ?? this.startLng,
      destAddress: destAddress ?? this.destAddress,
      destLat: destLat ?? this.destLat,
      destLng: destLng ?? this.destLng,
      waypoints: waypoints ?? this.waypoints,
      routeCalculated: routeCalculated ?? this.routeCalculated,
      routes: routes ?? this.routes,
      selectedRouteIndex: selectedRouteIndex ?? this.selectedRouteIndex,
      sheetFraction: sheetFraction ?? this.sheetFraction,
      sheetAnimating: sheetAnimating ?? this.sheetAnimating,
      isNavigating: isNavigating ?? this.isNavigating,
      truckVehicle: truckVehicle ?? this.truckVehicle,
    );
  }
}

/// Riverpod provider for route planning state.
final routePlanProvider = StateNotifierProvider<RoutePlanNotifier, RoutePlanState>(
  (ref) => RoutePlanNotifier(),
);

class RoutePlanNotifier extends StateNotifier<RoutePlanState> {
  RoutePlanNotifier() : super(const RoutePlanState());

  /// Activate route planning with start/destination.
  void activate({
    String startAddress = '我的位置',
    double? startLat,
    double? startLng,
    required String destAddress,
    required double destLat,
    required double destLng,
    TravelMode mode = TravelMode.cycling,
  }) {
    state = RoutePlanState(
      isActive: true,
      travelMode: mode,
      startAddress: startAddress,
      startLat: startLat,
      startLng: startLng,
      destAddress: destAddress,
      destLat: destLat,
      destLng: destLng,
    );
  }

  /// Dismiss route planning.
  void dismiss() {
    state = const RoutePlanState();
  }

  /// Switch travel mode.
  void setTravelMode(TravelMode mode) {
    state = state.copyWith(
      travelMode: mode,
      routeCalculated: false,
      routes: [],
    );
  }

  /// Set route calculation results.
  void setRoutes(List<RouteInfo> routes) {
    state = state.copyWith(
      routes: routes,
      routeCalculated: routes.isNotEmpty,
      selectedRouteIndex: 0,
    );
  }

  /// Select a different route.
  void selectRoute(int index) {
    if (index >= 0 && index < state.routes.length) {
      state = state.copyWith(selectedRouteIndex: index);
    }
  }

  /// Update bottom sheet fraction.
  void setSheetFraction(double fraction) {
    state = state.copyWith(
      sheetFraction: fraction.clamp(0.0, 1.0),
      sheetAnimating: true,
    );
  }

  /// Sheet animation finished.
  void sheetAnimationEnded() {
    state = state.copyWith(sheetAnimating: false);
  }

  /// Set waypoints list.
  void setWaypoints(List<String> waypoints) {
    state = state.copyWith(waypoints: waypoints);
  }

  /// Set navigating state.
  void setNavigating(bool navigating) {
    state = state.copyWith(isNavigating: navigating);
  }

  /// Swap start and destination.
  void swapAddresses() {
    state = state.copyWith(
      startAddress: state.destAddress,
      startLat: state.destLat,
      startLng: state.destLng,
      destAddress: state.startAddress,
      destLat: state.startLat,
      destLng: state.startLng,
      routeCalculated: false,
      routes: [],
    );
  }

  /// Update start address (e.g., after GPS fix).
  void updateStartAddress(String address, double lat, double lng) {
    state = state.copyWith(
      startAddress: address,
      startLat: lat,
      startLng: lng,
    );
  }

  /// Set truck vehicle info.
  void setTruckVehicle(TruckVehicle v) {
    state = state.copyWith(truckVehicle: v);
  }
}
