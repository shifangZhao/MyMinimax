import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../route_planning_state.dart';
import '../../../../app/theme.dart';

/// Snap values for the 3-level bottom sheet (fraction of available height).
const _collapsedFraction = 0.0; // peek (route info summary)
const _halfFraction = 0.45; // half expanded (route details)
const _fullFraction = 1.0; // fully expanded (full route list)

/// Full route planning overlay covering the map.
/// Contains Modules 1–5 from the spec.
class RoutePlanningOverlay extends ConsumerStatefulWidget {
  final VoidCallback onClear;
  final void Function(String method, {Map<String, dynamic>? args}) send;
  final double currentZoom;
  final double currentLat;
  final double currentLng;

  const RoutePlanningOverlay({
    super.key,
    required this.onClear,
    required this.send,
    this.currentZoom = 15,
    this.currentLat = 39.9,
    this.currentLng = 116.4,
  });

  @override
  ConsumerState<RoutePlanningOverlay> createState() =>
      _RoutePlanningOverlayState();
}

class _RoutePlanningOverlayState extends ConsumerState<RoutePlanningOverlay> {
  // ── Address text controllers (Module 1) ──
  final _startCtrl = TextEditingController();
  final _destCtrl = TextEditingController();

  // ── Debounce ──
  Timer? _cameraDebounce;

  /// Waypoint 途经点控制器
  final _waypointCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _cameraDebounce?.cancel();
    _startCtrl.dispose();
    _destCtrl.dispose();
    _waypointCtrl.dispose();
    super.dispose();
  }

  /// Select a travel mode (Module 2).
  void _onModeSelected(TravelMode mode) {
    final rp = ref.read(routePlanProvider.notifier);
    rp.setTravelMode(mode);
    widget.send('clearRoutes');
    widget.send('clearMarkers');
    // If we have both start/dest coords, recalculate
    final state = ref.read(routePlanProvider);
    if (state.startLat != null &&
        state.startLng != null &&
        state.destLat != null &&
        state.destLng != null) {
      _calculateRoute();
    }
  }

  /// 弹出货车车辆信息编辑表单。
  void _showTruckVehicleSheet(bool isDark) {
    final state = ref.read(routePlanProvider);
    final vehicle = state.truckVehicle;
    final lengthCtrl = TextEditingController(text: vehicle.length.toString());
    final weightCtrl = TextEditingController(text: vehicle.weight.toString());
    final heightCtrl = TextEditingController(text: vehicle.height.toString());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? PixelTheme.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text('车辆信息', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF333333))),
              const SizedBox(height: 20),
              _truckField('车长 (米)', lengthCtrl, isDark),
              const SizedBox(height: 12),
              _truckField('车重 (吨)', weightCtrl, isDark),
              const SizedBox(height: 12),
              _truckField('车高 (米)', heightCtrl, isDark),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A73E8),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    final l = double.tryParse(lengthCtrl.text) ?? vehicle.length;
                    final w = double.tryParse(weightCtrl.text) ?? vehicle.weight;
                    final h = double.tryParse(heightCtrl.text) ?? vehicle.height;
                    final updated = TruckVehicle(length: l, weight: w, height: h);
                    ref.read(routePlanProvider.notifier).setTruckVehicle(updated);
                    // 持久化
                    SharedPreferences.getInstance().then((prefs) {
                      prefs.setString('truck_length', l.toString());
                      prefs.setString('truck_weight', w.toString());
                      prefs.setString('truck_height', h.toString());
                    });
                    Navigator.of(ctx).pop();
                    // 重新规划路线
                    final state2 = ref.read(routePlanProvider);
                    if (state2.startLat != null && state2.destLat != null) {
                      _calculateRoute();
                    }
                  },
                  child: const Text('保存', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _truckField(String label, TextEditingController ctrl, bool isDark) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(fontSize: 14, color: isDark ? Colors.white : const Color(0xFF333333)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : const Color(0xFF666666)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: isDark ? PixelTheme.darkElevated : Colors.grey.shade50,
      ),
    );
  }

  /// Trigger route calculation via native SDK.
  void _calculateRoute() {
    final state = ref.read(routePlanProvider);
    if (state.startLat == null ||
        state.startLng == null ||
        state.destLat == null ||
        state.destLng == null) return;

    if (state.travelMode == TravelMode.truck) {
      widget.send('calcTruckRoute', args: {
        'originLat': state.startLat,
        'originLng': state.startLng,
        'destLat': state.destLat,
        'destLng': state.destLng,
        'vehicleLength': state.truckVehicle.length,
        'vehicleWeight': state.truckVehicle.weight,
        'vehicleHeight': state.truckVehicle.height,
      });
      return;
    }

    final mode = state.travelMode.amapRouteType;
    switch (mode) {
      case 'driving':
        widget.send('calcNaviRoute', args: {
          'originLat': state.startLat,
          'originLng': state.startLng,
          'destLat': state.destLat,
          'destLng': state.destLng,
          'multiRoute': true,
        });
        return;
      case 'walking':
        widget.send('startWalkNavi', args: {
          'originLat': state.startLat,
          'originLng': state.startLng,
          'destLat': state.destLat,
          'destLng': state.destLng,
        });
        return;
      case 'cycling':
        widget.send('startCyclingNavi', args: {
          'originLat': state.startLat,
          'originLng': state.startLng,
          'destLat': state.destLat,
          'destLng': state.destLng,
        });
        return;
      default:
        widget.send('calcNaviRoute', args: {
          'originLat': state.startLat,
          'originLng': state.startLng,
          'destLat': state.destLat,
          'destLng': state.destLng,
          'multiRoute': true,
        });
    }
  }

  /// Load truck vehicle info from SharedPreferences.
  void _loadTruckVehiclePrefs() {
    SharedPreferences.getInstance().then((prefs) {
      final l = prefs.getString('truck_length');
      final w = prefs.getString('truck_weight');
      final h = prefs.getString('truck_height');
      if (l != null || w != null || h != null) {
        final current = ref.read(routePlanProvider).truckVehicle;
        ref.read(routePlanProvider.notifier).setTruckVehicle(TruckVehicle(
          length: double.tryParse(l ?? '') ?? current.length,
          weight: double.tryParse(w ?? '') ?? current.weight,
          height: double.tryParse(h ?? '') ?? current.height,
        ));
      }
    });
  }

  /// Auto-select default travel mode based on straight-line distance.
  void _applyDefaultMode(RoutePlanState state) {
    if (state.startLat == null || state.destLat == null) return;
    const R = 6371000.0;
    final dLat = (state.destLat! - state.startLat!) * math.pi / 180;
    final dLng = (state.destLng! - state.startLng!) * math.pi / 180;
    final sinDlat = math.sin(dLat / 2);
    final sinDlng = math.sin(dLng / 2);
    final a = sinDlat * sinDlat +
        math.cos(state.startLat! * math.pi / 180) *
        math.cos(state.destLat! * math.pi / 180) *
        sinDlng * sinDlng;
    final distance = 2 * R * math.asin(math.sqrt(a)); // meters

    TravelMode mode;
    if (distance < 1000) {
      mode = TravelMode.walking;
    } else if (distance < 5000) {
      mode = TravelMode.cycling;
    } else if (distance < 50000) {
      mode = TravelMode.driving;
    } else {
      mode = TravelMode.transit;
    }
    ref.read(routePlanProvider.notifier).setTravelMode(mode);
    // 自动触发路线计算
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _calculateRoute();
    });
  }

  /// Center camera on start point, keep current zoom.
  void _fitRouteBounds() {
    final state = ref.read(routePlanProvider);
    if (state.startLat != null && state.startLng != null) {
      widget.send('moveCamera', args: {
        'lat': state.startLat,
        'lng': state.startLng,
        'zoom': widget.currentZoom,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rp = ref.watch(routePlanProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Listen for route state changes → ETA label + cleanup
    ref.listen(routePlanProvider, (RoutePlanState? prev, RoutePlanState next) {
      if (prev == null) return;
      // Auto-select default mode when route planning is activated with coordinates
      if (!prev.isActive && next.isActive) {
        _loadTruckVehiclePrefs();
        if (next.startLat != null && next.destLat != null) {
          _applyDefaultMode(next);
        }
      }
    });

    // Update text controllers from state
    if (_startCtrl.text != rp.startAddress) {
      _startCtrl.text = rp.startAddress;
    }
    if (_destCtrl.text != rp.destAddress) {
      _destCtrl.text = rp.destAddress;
    }

    final showCard = rp.routeCalculated && rp.routes.isNotEmpty;
    return Stack(
      children: [
        // ── Module 1: Top address input bar ──
        _buildAddressBar(context, rp, isDark),

        // ── Module 3: Map overlay controls ──
        Positioned(
          right: 8,
          top: 180,
          child: _buildMapControls(isDark, rp),
        ),

        // ── Module 4: Bottom route card (shown after route calculated) ──
        if (showCard)
          _buildRouteCard(rp, isDark),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Module 1: Top address input bar
  // ═══════════════════════════════════════════════════════════════

  Widget _buildAddressBar(
      BuildContext context, RoutePlanState rp, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? PixelTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row: start input + swap + dest input + close
          Row(
            children: [
              // Vertical dot timeline
              SizedBox(
                width: 20,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: Color(0xFF10B981), shape: BoxShape.circle)),
                    Container(
                        width: 2,
                        height: 16,
                        color: isDark
                            ? PixelTheme.darkBorderDefault
                            : PixelTheme.pixelBorder),
                    Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: Color(0xFF4F6EF7), shape: BoxShape.circle)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Start & Dest inputs
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Start address
                    Text(
                      rp.startAddress.isNotEmpty ? rp.startAddress : '我的位置',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? PixelTheme.darkPrimaryText
                            : PixelTheme.primaryText,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Container(
                        height: 1,
                        color: isDark
                            ? PixelTheme.darkBorderDefault
                            : PixelTheme.pixelBorder),
                    const SizedBox(height: 2),
                    // Destination address
                    Text(
                      rp.destAddress,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? PixelTheme.darkPrimaryText
                            : PixelTheme.primaryText,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Swap button
              GestureDetector(
                onTap: () {
                  ref.read(routePlanProvider.notifier).swapAddresses();
                  widget.send('clearRoutes');
                  widget.send('clearMarkers');
                  _calculateRoute();
                  _fitRouteBounds();
                },
                child: Container(
                  width: 32,
                  height: 32,
                  margin: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(
                    color: isDark
                        ? PixelTheme.darkElevated
                        : PixelTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.swap_vert,
                      size: 18, color: Color(0xFF6B7280)),
                ),
              ),
              const SizedBox(width: 4),
              // Add waypoint button
              GestureDetector(
                onTap: () => _showWaypointDialog(isDark),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isDark
                        ? PixelTheme.darkElevated
                        : PixelTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.add,
                      size: 18, color: Color(0xFF6B7280)),
                ),
              ),
              const SizedBox(width: 4),
              // Close button
              GestureDetector(
                onTap: widget.onClear,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isDark
                        ? PixelTheme.darkElevated
                        : PixelTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.close,
                      size: 18, color: Color(0xFF6B7280)),
                ),
              ),
            ],
          ),
          // Waypoint row
          if (rp.waypoints.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '途经点: ${rp.waypoints.join(" → ")}',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? PixelTheme.darkTextMuted
                      : PixelTheme.textMuted,
                ),
              ),
            ),
          // ── 出行方式（在同一个卡片内） ──
          Container(height: 1, color: isDark ? PixelTheme.darkBorderDefault : PixelTheme.pixelBorder, margin: const EdgeInsets.symmetric(vertical: 6)),
          _buildModeRow(rp, isDark),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Module 2: Transport mode selector — 精简纯文字下划线版
  // ═══════════════════════════════════════════════════════════════

  final _modes = TravelMode.values;
  final _underlineColor = const Color(0xFF1A73E8);

  /// 出行方式横排（无背景卡片，嵌入地址栏使用）
  Widget _buildModeRow(RoutePlanState rp, bool isDark) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _modes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 20),
        itemBuilder: (_, index) {
          final mode = _modes[index];
          final selected = rp.travelMode == mode;
          return _modeItem(mode, selected, isDark);
        },
      ),
    );
  }

  Widget _modeItem(TravelMode mode, bool selected, bool isDark) {
    final textColor = selected
        ? (isDark ? Colors.white : const Color(0xFF333333))
        : (isDark ? Colors.white60 : const Color(0xFF666666));
    final underline = _underlineColor;

    return GestureDetector(
      onTap: () => _onModeSelected(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        height: 48,
        alignment: Alignment.center,
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(mode.icon, size: 18, color: textColor),
                  const SizedBox(width: 4),
                  Text(
                    mode.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                      color: textColor,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              AnimatedOpacity(
                opacity: selected ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: underline,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Module 3: Map overlay controls
  // ═══════════════════════════════════════════════════════════════

  Widget _buildMapControls(bool isDark, RoutePlanState rp) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _mapCtrlBtn(Icons.my_location, () {
          widget.send('locate');
        }, isDark),
        const SizedBox(height: 6),
        _mapCtrlBtn(Icons.add, () {
          widget.send('moveCamera', args: {
            'lat': widget.currentLat,
            'lng': widget.currentLng,
            'zoom': widget.currentZoom + 1,
          });
        }, isDark),
        const SizedBox(height: 6),
        _mapCtrlBtn(Icons.remove, () {
          widget.send('moveCamera', args: {
            'lat': widget.currentLat,
            'lng': widget.currentLng,
            'zoom': widget.currentZoom - 1,
          });
        }, isDark),
        if (rp.routeCalculated) ...[
          const SizedBox(height: 6),
          _mapCtrlBtn(Icons.fit_screen, _fitRouteBounds, isDark),
        ],
      ],
    );
  }

  Widget _mapCtrlBtn(IconData icon, VoidCallback onTap, bool isDark) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xF5151524)
              : const Color(0xF5FFFFFF),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Icon(icon, size: 18, color: isDark ? Colors.white70 : Colors.black54),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Module 4: Bottom route card
  // ═══════════════════════════════════════════════════════════════

  Widget _buildRouteCard(RoutePlanState rp, bool isDark) {
    final route = rp.routes[rp.selectedRouteIndex];
    final eta = DateTime.now().add(Duration(seconds: route.duration));
    final etaStr = '预计${eta.hour.toString().padLeft(2, '0')}:${eta.minute.toString().padLeft(2, '0')}到达';

    final naviLabel = switch (rp.travelMode) {
      TravelMode.cycling => '开始骑行导航',
      TravelMode.walking => '开始步行导航',
      TravelMode.driving => '开始驾车导航',
      TravelMode.transit => '开始公交导航',
      TravelMode.truck => '开始货车导航',
    };
    final accentColor = switch (rp.travelMode) {
      TravelMode.cycling || TravelMode.walking => const Color(0xFF10B981),
      TravelMode.truck => const Color(0xFFF59E0B),
      TravelMode.driving => PixelTheme.brandBlue,
      TravelMode.transit => const Color(0xFF8B5CF6),
    };

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(
          color: isDark ? PixelTheme.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          boxShadow: [
            BoxShadow(color: Colors.black26, blurRadius: 12, offset: const Offset(0, -3)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Info row: distance · time · ETA ──
            Row(
              children: [
                Icon(rp.travelMode.icon, size: 20, color: accentColor),
                const SizedBox(width: 8),
                Text(
                  '${route.distanceFormatted} · ${route.durationFormatted}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  etaStr,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // ── Start navigation button ──
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                  onPressed: () => _startNavigation(rp),
                  child: Text(naviLabel, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showWaypointDialog(bool isDark) {
    _waypointCtrl.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? PixelTheme.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text('添加途经点', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
          const SizedBox(height: 14),
          TextField(
            controller: _waypointCtrl,
            decoration: InputDecoration(
              hintText: '输入途经点名称或地址',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              prefixIcon: const Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          if (ref.watch(routePlanProvider).waypoints.isNotEmpty)
            ...ref.read(routePlanProvider).waypoints.asMap().entries.map((e) => ListTile(
              title: Text(e.value),
              trailing: IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () {
                final newList = List<String>.from(ref.read(routePlanProvider).waypoints)..removeAt(e.key);
                ref.read(routePlanProvider.notifier).setWaypoints(newList);
                widget.send('clearRoutes');
                widget.send('clearMarkers');
                _calculateRoute();
                Navigator.of(ctx).pop();
              }),
            )),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: () async {
                final text = _waypointCtrl.text.trim();
                if (text.isEmpty) return;
                final newList = List<String>.from(ref.read(routePlanProvider).waypoints)..add(text);
                ref.read(routePlanProvider.notifier).setWaypoints(newList);
                Navigator.of(ctx).pop();
                widget.send('clearRoutes');
                widget.send('clearMarkers');
                _calculateRoute();
              },
              child: const Text('添加'),
            ),
          ),
        ]),
      ),
    );
  }

  /// Start turn-by-turn navigation based on travel mode.
  void _startNavigation(RoutePlanState rp) {
    final mode = rp.travelMode.amapRouteType;
    switch (mode) {
      case 'cycling':
        widget.send('startCyclingNavi', args: {
          'originLat': rp.startLat,
          'originLng': rp.startLng,
          'destLat': rp.destLat,
          'destLng': rp.destLng,
        });
        break;
      case 'walking':
        widget.send('startWalkNavi', args: {
          'originLat': rp.startLat,
          'originLng': rp.startLng,
          'destLat': rp.destLat,
          'destLng': rp.destLng,
        });
        break;
      default:
        widget.send('startNavi', args: {'naviType': 1});
    }
    ref.read(routePlanProvider.notifier).setNavigating(true);
  }

}

/// Custom animated widget that rebuilds on animation ticks.
