package com.agent.my_agent_app

import android.content.Context
import android.speech.tts.TextToSpeech
import android.util.Log
import android.view.View
import com.amap.api.location.AMapLocation
import com.amap.api.location.AMapLocationClient
import com.amap.api.location.AMapLocationClientOption
import com.amap.api.location.AMapLocationListener
import com.amap.api.maps.AMap
import com.amap.api.maps.AMapOptions
import com.amap.api.maps.CameraUpdateFactory
import com.amap.api.maps.LocationSource
import com.amap.api.maps.MapView
import com.amap.api.maps.MapsInitializer
import com.amap.api.maps.model.LatLng
import com.amap.api.maps.model.LatLngBounds
import com.amap.api.maps.model.MarkerOptions
import com.amap.api.maps.model.MyLocationStyle
import com.amap.api.maps.model.PolylineOptions
import com.amap.api.navi.AMapNavi
import com.amap.api.navi.AMapNaviListener
import com.amap.api.navi.AMapHudView
import com.amap.api.navi.AMapHudViewListener
import com.amap.api.navi.ParallelRoadListener
import com.amap.api.navi.enums.NaviType
import com.amap.api.navi.enums.PathPlanningStrategy
import com.amap.api.navi.model.AimLessModeCongestionInfo
import com.amap.api.navi.model.AimLessModeStat
import com.amap.api.navi.model.AMapCalcRouteResult
import com.amap.api.navi.model.AMapCarInfo
import com.amap.api.navi.model.AMapLaneInfo
import com.amap.api.navi.model.AMapModelCross
import com.amap.api.navi.model.AMapNaviCameraInfo
import com.amap.api.navi.model.AMapNaviCross
import com.amap.api.navi.model.AMapNaviLocation
import com.amap.api.navi.model.AMapNaviPath
import com.amap.api.navi.model.AMapNaviRouteNotifyData
import com.amap.api.navi.model.AMapNaviTrafficFacilityInfo
import com.amap.api.navi.model.AMapServiceAreaInfo
import com.amap.api.navi.model.NaviInfo
import com.amap.api.navi.model.NaviLatLng
import android.graphics.BitmapFactory
import com.amap.api.maps.model.BitmapDescriptorFactory
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

class AmapNativeMapView(
    context: Context,
    private val channel: MethodChannel,
    private val apiKey: String? = null
) : PlatformView, LocationSource {

    init {
        // Priority: 1) static stored key (survives PlatformView recreation)
        //           2) creationParams key       3) SharedPreferences fallback
        when {
            !_storedApiKey.isNullOrBlank() -> {
                android.util.Log.i("MapDebug", ">>> AmapNativeMapView using stored static key=${_storedApiKey!!.take(8)}...")
            }
            !apiKey.isNullOrBlank() -> {
                _storedApiKey = apiKey
                MapsInitializer.setApiKey(apiKey)
                android.util.Log.i("MapDebug", ">>> AmapNativeMapView setting apiKey=${apiKey!!.take(8)}...")
            }
            else -> {
                android.util.Log.w("MapDebug", ">>> AmapNativeMapView with NO apiKey, trying fallback...")
                loadApiKeyFromPrefs(context)
            }
        }
    }

    companion object {
        /// Persists across Activity / PlatformView recreation within the same process.
        private var _storedApiKey: String? = null

        /// Pre-set API key from Flutter side early (before any map view is created).
        @JvmStatic
        fun preSetApiKey(key: String) {
            _storedApiKey = key
            MapsInitializer.setApiKey(key)
            android.util.Log.i("MapDebug", ">>> API key pre-set from Flutter")
        }

        /// Load AMap API key from SharedPreferences as fallback.
        /// Uses the same file as Flutter's shared_preferences plugin.
        @JvmStatic
        fun loadApiKeyFromPrefs(context: Context) {
            try {
                val prefs = context.getSharedPreferences(
                    context.packageName + "_preferences",
                    android.content.Context.MODE_PRIVATE
                )
                val key = prefs.getString("amap_native_api_key", null)
                if (!key.isNullOrBlank()) {
                    _storedApiKey = key
                    MapsInitializer.setApiKey(key)
                    android.util.Log.i("MapDebug", ">>> API key loaded from SharedPreferences fallback")
                } else {
                    android.util.Log.w("MapDebug", ">>> No API key found in SharedPreferences")
                }
            } catch (e: Exception) {
                android.util.Log.e("MapDebug", ">>> Failed to load API key from prefs: ${e.message}")
            }
        }
    }

    private val mapView: MapView = MapView(context)
    private var _destroyed = false
    private var aMap: AMap? = null
    private val markers = mutableListOf<com.amap.api.maps.model.Marker>()
    private val polylines = mutableListOf<com.amap.api.maps.model.Polyline>()
    private val polygons = mutableListOf<com.amap.api.maps.model.Polygon>()
    private val circles = mutableListOf<com.amap.api.maps.model.Circle>()
    private val arcs = mutableListOf<com.amap.api.maps.model.Arc>()
    private val texts = mutableListOf<com.amap.api.maps.model.Text>()
    private val groundOverlays = mutableListOf<com.amap.api.maps.model.GroundOverlay>()

    // LocationSource
    private var locationClient: AMapLocationClient? = null
    private var locationOption: AMapLocationClientOption? = null
    private var onLocationChangedListener: LocationSource.OnLocationChangedListener? = null

    // Navigation
    private var aMapNavi: AMapNavi? = null
    private lateinit var naviListener: AMapNaviListener
    private var lastNaviText: String = ""
    private var lastCrossInfo: Map<String, Any> = emptyMap()
    private var lastLaneInfo: Map<String, Any> = emptyMap()
    // 多路线存储
    private var _routeIds: IntArray? = null
    private var _currentRouteIndex: Int = 0

    // 导航策略选项
    private var _avoidCongestion = false
    private var _avoidHighway = false
    private var _avoidCost = false
    private var _highwayFirst = false

    // 车辆信息
    private var _vehicleType: String = "car" // car, truck, motorcycle, electric

    // TTS 语音播报
    private var _tts: TextToSpeech? = null
    private var _ttsInitialized = false
    private var _ttsMuted = false

    // HUD显示状态
    private var _hudView: AMapHudView? = null
    private var _isHudMode = false

    // 导航跟随状态：用户是否在主动拖动地图
    private var _isUserInteracting = false
    // 上次用户交互时间（毫秒），用于 GPS 跟随冷却
    private var _lastUserInteractionTime: Long = 0
    // 一次性定位请求标志（点击定位按钮时设为 true，收到定位后置为 false）
    private var _isOneTimeLocating = false
    // 位置自动跟随模式：启用时 GPS 更新会自动移动地图到当前位置
    private var _isFollowingLocation = false

    // 当前导航路线坐标点（用于箭头标记等）
    private var _currentRoutePoints: List<LatLng>? = null

    // 箭头标记缓存（复用 bitmap，避免重复绘制）
    private var _cachedArrowBitmap: android.graphics.Bitmap? = null
    private var _lastArrowColor: Int = 0

    // Composite map state — avoids unnecessary setMapType calls that reload tiles
    private var _isSatellite = false
    private var _isDark = false
    private var _is3D = false

    // 全览模式状态
    private var _isOverviewMode = false

    // 截图缓存数量上限（Agent 可通过 setMapCacheLimit 动态调整）
    private var _screenshotCacheLimit = 3

    /// Compute effective map type from satellite + dark without stomping each other.
    /// Amap SDK does not have a combined SATELLITE+NIGHT type, so satellite wins when both are on.
    private fun effectiveMapType(): Int = when {
        _isSatellite -> AMap.MAP_TYPE_SATELLITE
        _isDark -> AMap.MAP_TYPE_NIGHT
        else -> AMap.MAP_TYPE_NORMAL
    }

    private fun applyMapType() {
        val target = effectiveMapType()
        val current = aMap?.mapType ?: -1
        if (target == current) return  // no-op to avoid tile reload
        aMap?.mapType = target
    }

    // Current position marker — drawn manually for reliable visibility
    private var myLocationMarker: com.amap.api.maps.model.Marker? = null

    // Cached descriptor from Flutter-side icon generator (set before marker is created)
    private var _pendingMarkerAnchorX: Float = 0.5f
    private var _pendingMarkerAnchorY: Float = 0.85f

    // 缩放状态：Marker 固定屏幕像素 → 跟随 zoom 动态缩放
    private var _markerSourceBitmap: android.graphics.Bitmap? = null
    private var _lastZoom: Float = 15f
    private var _currentMarkerScale: Float = 1f
    private val _markerBaseScale: Float = 0.75f // 整体倍率（用户觉得图标偏大时调整）

    // 定位事件节流：避免 Dart↔Native IPC 过于频繁
    private var _lastLocationEventTime = 0L
    private val _locationThrottleMs = 500L

    // 相机变化节流
    private var _lastCameraEventTime = 0L
    private val _cameraThrottleMs = 200L

    init {
        Log.i("MapDebug", ">>> === AmapNativeMapView init START ===")

        // 导航监听器
        naviListener = createNaviListener()
        Log.i("MapDebug", ">>> naviListener created")

        try {
            mapView.onCreate(null)
            Log.i("MapDebug", ">>> mapView.onCreate done")
        } catch (e: Exception) {
            Log.e("MapCrash", ">>> mapView.onCreate FAILED: ${e.message}", e)
            _destroyed = true
        }
        try {
            aMap = mapView.map
            Log.i("MapDebug", ">>> mapView created, aMap=${aMap != null}")
        } catch (e: Exception) {
            Log.e("MapCrash", ">>> mapView.map access FAILED: ${e.message}", e)
            _destroyed = true
        }

        // 瓦片加载完成回调 → Flutter 端据此检测瓦片是否正常加载
        aMap?.setOnMapLoadedListener {
            if (aMap == null) return@setOnMapLoadedListener // 已销毁，防止崩溃
            Log.i("MapDebug", ">>> Map tiles loaded callback fired")
            try {
                channel.invokeMethod("onMapLoaded", null)
            } catch (_: Exception) {
                // 忽略通道关闭后的调用
            }
        }

        // 导航引擎延迟初始化 — 避免主线程卡顿和内存浪费（用户可能只看地图）
        // 在首次实际导航调用时通过 _ensureNavi() 初始化

        // ── 独立启动定位（不依赖 LocationSource.activate 的调用时机）──
        locationClient = AMapLocationClient(context).also { client ->
            locationOption = AMapLocationClientOption().apply {
                locationMode = AMapLocationClientOption.AMapLocationMode.Hight_Accuracy
                interval = 2000
                isOnceLocation = false
                isOnceLocationLatest = true
                isNeedAddress = true
                isGpsFirst = true
                gpsFirstTimeout = 25000
                isMockEnable = false
                isLocationCacheEnable = false
                isSensorEnable = true           // 罗盘/陀螺仪 → 方向角
                isBeidouFirst = true            // 优先北斗
                isWifiScan = true               // WiFi 扫描辅助定位
                httpTimeOut = 20000           // 网络超时
                deviceModeDistanceFilter = 5f // 最小 5 米才回调
                geoLanguage = AMapLocationClientOption.GeoLanguage.DEFAULT
            }
            client.setLocationOption(locationOption)
            client.setLocationListener(object : AMapLocationListener {
                override fun onLocationChanged(location: AMapLocation?) {
                    if (location == null || location.errorCode != 0) return
                    // 节流：500ms 内只处理一次（位置更新和相机移动共享节流）
                    val now = System.currentTimeMillis()
                    if (now - _lastLocationEventTime < _locationThrottleMs) return
                    _lastLocationEventTime = now

                    // 一次性定位请求：移动镜头到当前位置（点击定位按钮）
                    if (_isOneTimeLocating) {
                        _isOneTimeLocating = false
                        aMap?.moveCamera(CameraUpdateFactory.newLatLngZoom(
                            LatLng(location.latitude, location.longitude), 17f
                        ))
                        return
                    }

                    // 自动跟随模式时：GPS 更新移动地图到当前位置
                    // 如果用户 3 秒内操作过地图，禁止跟随
                    val timeSinceInteraction = now - _lastUserInteractionTime
                    if (_isFollowingLocation && timeSinceInteraction > 3000) {
                        aMap?.moveCamera(CameraUpdateFactory.newLatLngZoom(
                            LatLng(location.latitude, location.longitude), 17f
                        ))
                    }
                    // 更新自定义位置标记
                    updateMyLocationMarker(location)
                    // Send comprehensive location detail to Dart
                    val qualityReport = location.getLocationQualityReport()
                    channel.invokeMethod("onLocationDetail", mapOf(
                        "lat" to location.latitude,
                        "lng" to location.longitude,
                        "altitude" to location.altitude,
                        "accuracy" to location.accuracy,
                        "speed" to location.speed,
                        "bearing" to location.bearing,
                        "time" to location.time,
                        "address" to (location.address ?: ""),
                        "country" to (location.country ?: ""),
                        "province" to (location.province ?: ""),
                        "city" to (location.city ?: ""),
                        "district" to (location.district ?: ""),
                        "street" to (location.street ?: ""),
                        "streetNum" to (location.streetNum ?: ""),
                        "cityCode" to (location.cityCode ?: ""),
                        "adCode" to (location.adCode ?: ""),
                        "poiName" to (location.poiName ?: ""),
                        "aoiName" to (location.aoiName ?: ""),
                        "provider" to (location.provider ?: ""),
                        "locationType" to location.locationType,
                        "satellites" to location.satellites,
                        "gpsAccuracyStatus" to location.gpsAccuracyStatus,
                        "trustedLevel" to location.trustedLevel,
                        "coordType" to (location.coordType ?: ""),
                        "conScenario" to location.conScenario,
                        "buildingId" to (location.buildingId ?: ""),
                        "floor" to (location.floor ?: ""),
                        "description" to (location.description ?: ""),
                        "errorCode" to location.errorCode,
                        "errorInfo" to (location.errorInfo ?: ""),
                        // 质量报告（CM SDK 字段有限，直接 toString）
                        "qualityReportSummary" to (try { qualityReport?.toString() ?: "" } catch (_: Exception) { "" })
                    ))
                }
            })
            client.startLocation()
        }

        aMap?.apply {
            showBuildings(true)
            showIndoorMap(true)
            isTrafficEnabled = false
            mapType = AMap.MAP_TYPE_NORMAL
            // 限制缩放范围，避免加载无用高分辨率瓦片
            setMaxZoomLevel(19f)
            setMinZoomLevel(3f)

            // 定位跟随与旋转由手动 animateCamera 控制，关闭 SDK 内置跟随
            isMyLocationEnabled = false

            uiSettings.apply {
                isZoomControlsEnabled = true
                isScaleControlsEnabled = true
                isCompassEnabled = true
                isMyLocationButtonEnabled = false
            }

            setOnMapClickListener { latLng ->
                channel.invokeMethod("onMapClick", mapOf(
                    "lat" to latLng.latitude,
                    "lng" to latLng.longitude
                ))
            }

            setOnMarkerClickListener { marker ->
                if (marker === myLocationMarker) return@setOnMarkerClickListener true
                val snippet = marker.snippet ?: ""
                channel.invokeMethod("onMarkerClick", mapOf(
                    "title" to (marker.title ?: ""),
                    "snippet" to snippet,
                    "lat" to marker.position.latitude,
                    "lng" to marker.position.longitude
                ))
                false
            }

            setOnMarkerDragListener(object : com.amap.api.maps.AMap.OnMarkerDragListener {
                override fun onMarkerDragStart(marker: com.amap.api.maps.model.Marker) {
                    channel.invokeMethod("onMarkerDragStart", mapOf(
                        "lat" to marker.position.latitude,
                        "lng" to marker.position.longitude
                    ))
                }
                override fun onMarkerDrag(marker: com.amap.api.maps.model.Marker) {
                    channel.invokeMethod("onMarkerDrag", mapOf(
                        "lat" to marker.position.latitude,
                        "lng" to marker.position.longitude
                    ))
                }
                override fun onMarkerDragEnd(marker: com.amap.api.maps.model.Marker) {
                    channel.invokeMethod("onMarkerDragEnd", mapOf(
                        "lat" to marker.position.latitude,
                        "lng" to marker.position.longitude
                    ))
                }
            })

            setOnMapLongClickListener { latLng ->
                channel.invokeMethod("onMapLongClick", mapOf(
                    "lat" to latLng.latitude,
                    "lng" to latLng.longitude
                ))
            }

            setOnPOIClickListener { poi ->
                channel.invokeMethod("onPOIClick", mapOf(
                    "name" to (poi.name ?: ""),
                    "poiId" to (poi.poiId ?: ""),
                    "lat" to poi.coordinate.latitude,
                    "lng" to poi.coordinate.longitude
                ))
            }

            setOnCameraChangeListener(object : com.amap.api.maps.AMap.OnCameraChangeListener {
                override fun onCameraChange(cameraPosition: com.amap.api.maps.model.CameraPosition?) {
                    // 用户拖动地图时标记，GPS 更新时检查是否跳过跟随
                    _isUserInteracting = true
                    _lastUserInteractionTime = System.currentTimeMillis()
                }
                override fun onCameraChangeFinish(cameraPosition: com.amap.api.maps.model.CameraPosition?) {
                    if (cameraPosition == null) return
                    // 缩放变化 → 动态缩放定位图标
                    val currentZoom = cameraPosition.zoom
                    if (kotlin.math.abs(currentZoom - _lastZoom) >= 0.5f) {
                        _lastZoom = currentZoom
                        _updateMarkerZoomScale()
                    }
                    // 节流：200ms 内只发一次
                    val now = System.currentTimeMillis()
                    if (now - _lastCameraEventTime < _cameraThrottleMs) return
                    _lastCameraEventTime = now
                    val bounds = aMap?.projection?.visibleRegion?.latLngBounds
                    // 检测是否是用户手势（非导航触发）：通过 isGesture 标志判断
                    // 如果用户拖动了地图，通知 Flutter 暂停导航跟随
                    val isUserGesture = _isUserInteracting
                    _isUserInteracting = false // 重置
                    channel.invokeMethod("onCameraChange", mapOf(
                        "lat" to cameraPosition.target.latitude,
                        "lng" to cameraPosition.target.longitude,
                        "zoom" to cameraPosition.zoom,
                        "tilt" to cameraPosition.tilt,
                        "bearing" to cameraPosition.bearing,
                        "swLat" to (bounds?.southwest?.latitude ?: 0.0),
                        "swLng" to (bounds?.southwest?.longitude ?: 0.0),
                        "neLat" to (bounds?.northeast?.latitude ?: 0.0),
                        "neLng" to (bounds?.northeast?.longitude ?: 0.0),
                        "userInteracting" to isUserGesture
                    ))
                }
            })
        }

        try {
            mapView.onResume()
        } catch (e: Exception) {
            Log.e("MapCrash", ">>> mapView.onResume FAILED: ${e.message}", e)
            _destroyed = true
        }

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setApiKey" -> {
                    val key = call.argument<String>("key")
                    if (!key.isNullOrBlank()) {
                        _storedApiKey = key
                        MapsInitializer.setApiKey(key)
                    }
                    result.success(true)
                }
                "set3D" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    _is3D = enabled
                    if (enabled) {
                        aMap?.moveCamera(CameraUpdateFactory.changeTilt(55f))
                        aMap?.moveCamera(CameraUpdateFactory.zoomTo(17f))
                    } else {
                        aMap?.moveCamera(CameraUpdateFactory.changeTilt(0f))
                    }
                    result.success(true)
                }
                "setDark" -> {
                    _isDark = call.argument<Boolean>("enabled") ?: false
                    applyMapType()
                    result.success(true)
                }
                "setTraffic" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    aMap?.isTrafficEnabled = enabled
                    result.success(true)
                }
                "setSatellite" -> {
                    _isSatellite = call.argument<Boolean>("enabled") ?: false
                    applyMapType()
                    result.success(true)
                }
                "locate" -> {
                    // 标记为一次性定位，onLocationChanged 收到后会移动镜头
                    _isOneTimeLocating = true
                    // 如果已有最新定位，立即移动
                    val loc = locationClient?.lastKnownLocation
                    if (loc != null && loc.latitude != 0.0 && loc.longitude != 0.0) {
                        _isOneTimeLocating = false
                        aMap?.moveCamera(CameraUpdateFactory.newLatLngZoom(
                            LatLng(loc.latitude, loc.longitude), 17f
                        ))
                    }
                    result.success(true)
                }
                "addMarkers" -> {
                    val list = call.argument<List<Map<String, Any>>>("markers")
                    if (list != null) {
                        for (m in list) {
                            val lat = (m["lat"] as? Number)?.toDouble() ?: continue
                            val lng = (m["lng"] as? Number)?.toDouble() ?: continue
                            val title = m["title"] as? String ?: ""
                            val snippet = m["snippet"] as? String ?: ""
                            val opts = MarkerOptions()
                                .position(LatLng(lat, lng))
                                .title(title)
                                .snippet(snippet)
                            // Optional icon from Flutter (arrow markers, etc.)
                            val iconData = m["icon"] as? ByteArray
                            if (iconData != null) {
                                try {
                                    val bmp = BitmapFactory.decodeByteArray(iconData, 0, iconData.size)
                                    if (bmp != null) {
                                        opts.icon(BitmapDescriptorFactory.fromBitmap(bmp))
                                    }
                                } catch (_: Exception) {}
                            }
                            // Optional color (creates colored circle marker)
                            val markerColor = m["color"] as? Int
                            if (markerColor != null && iconData == null) {
                                val bmp = _createCircleBitmap(markerColor)
                                if (bmp != null) {
                                    opts.icon(BitmapDescriptorFactory.fromBitmap(bmp))
                                }
                            }
                            // Optional anchor
                            val anchorX = (m["anchorX"] as? Number)?.toFloat() ?: 0.5f
                            val anchorY = (m["anchorY"] as? Number)?.toFloat() ?: 1.0f
                            opts.anchor(anchorX, anchorY)
                            // Optional rotate angle
                            val rotate = (m["rotateAngle"] as? Number)?.toFloat() ?: 0f
                            opts.rotateAngle(rotate)
                            val marker = aMap?.addMarker(opts)
                            if (marker != null) markers.add(marker)
                        }
                    }
                    result.success(true)
                }
                "clearMarkers" -> {
                    for (m in markers) m.destroy()
                    markers.clear()
                    result.success(true)
                }
                "drawRoute" -> {
                    val points = call.argument<List<List<Double>>>("points")
                    if (points != null && points.isNotEmpty()) {
                        val color = (call.argument<Number>("color")?.toInt() ?: 0xFF4F6EF7.toInt())
                        val width = (call.argument<Number>("width")?.toFloat() ?: 12f)
                        val latLngs = points.mapNotNull { p ->
                            if (p.size >= 2) LatLng(p[0], p[1]) else null
                        }
                        val polyline = aMap?.addPolyline(
                            PolylineOptions()
                                .addAll(latLngs)
                                .color(color)
                                .width(width)
                        )
                        if (polyline != null) polylines.add(polyline)
                    }
                    result.success(true)
                }
                "clearRoutes" -> {
                    for (p in polylines) p.remove()
                    polylines.clear()
                    result.success(true)
                }
                "drawPolygon" -> {
                    val points = call.argument<List<List<Double>>>("points")
                    if (points != null && points.isNotEmpty()) {
                        val strokeColor = (call.argument<Number>("strokeColor")?.toInt() ?: 0xFF4F6EF7.toInt())
                        val fillColor = (call.argument<Number>("fillColor")?.toInt() ?: 0x334F6EF7.toInt())
                        val strokeWidth = (call.argument<Number>("strokeWidth")?.toFloat() ?: 4f)
                        val latLngs = points.mapNotNull { p ->
                            if (p.size >= 2) LatLng(p[0], p[1]) else null
                        }
                        val polygon = aMap?.addPolygon(
                            com.amap.api.maps.model.PolygonOptions()
                                .addAll(latLngs)
                                .strokeColor(strokeColor)
                                .fillColor(fillColor)
                                .strokeWidth(strokeWidth)
                        )
                        if (polygon != null) polygons.add(polygon)
                    }
                    result.success(true)
                }
                "clearPolygons" -> {
                    for (p in polygons) p.remove()
                    polygons.clear()
                    result.success(true)
                }
                "drawCircle" -> {
                    val lat = call.argument<Number>("lat")?.toDouble()
                    val lng = call.argument<Number>("lng")?.toDouble()
                    val radius = call.argument<Number>("radius")?.toDouble()
                    if (lat != null && lng != null && radius != null) {
                        val strokeColor = (call.argument<Number>("strokeColor")?.toInt() ?: 0xFF4F6EF7.toInt())
                        val fillColor = (call.argument<Number>("fillColor")?.toInt() ?: 0x334F6EF7.toInt())
                        val strokeWidth = (call.argument<Number>("strokeWidth")?.toFloat() ?: 4f)
                        val circle = aMap?.addCircle(
                            com.amap.api.maps.model.CircleOptions()
                                .center(LatLng(lat, lng))
                                .radius(radius)
                                .strokeColor(strokeColor)
                                .fillColor(fillColor)
                                .strokeWidth(strokeWidth)
                        )
                        if (circle != null) circles.add(circle)
                    }
                    result.success(true)
                }
                "clearCircles" -> {
                    for (c in circles) c.remove()
                    circles.clear()
                    result.success(true)
                }
                "getScreenshot" -> {
                    aMap?.getMapScreenShot(object : com.amap.api.maps.AMap.OnMapScreenShotListener {
                        override fun onMapScreenShot(bitmap: android.graphics.Bitmap?) {
                            if (bitmap == null) {
                                result.error("SCREENSHOT_FAILED", "截图失败", null)
                                return
                            }
                            // 压缩操作移到子线程，避免阻塞 GL 渲染线程
                            Thread {
                                try {
                                    val cacheDir = mapView.context.cacheDir
                                    clearOldScreenshots(cacheDir, keepCount = _screenshotCacheLimit)
                                    val file = java.io.File(cacheDir, "map_screenshot_${System.currentTimeMillis()}.png")
                                    java.io.FileOutputStream(file).use { out ->
                                        bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 90, out)
                                    }
                                    // 回到主线程回传结果
                                    android.os.Handler(android.os.Looper.getMainLooper()).post {
                                        result.success(file.absolutePath)
                                    }
                                } catch (e: Exception) {
                                    android.os.Handler(android.os.Looper.getMainLooper()).post {
                                        result.error("SCREENSHOT_ERROR", e.message, null)
                                    }
                                }
                            }.start()
                        }
                        override fun onMapScreenShot(bitmap: android.graphics.Bitmap?, status: Int) {}
                    })
                }
                "clearMapCache" -> {
                    val cacheDir = mapView.context.cacheDir
                    clearOldScreenshots(cacheDir, keepCount = 0)
                    result.success(true)
                }
                "refreshMap" -> {
                    aMap?.let { amap ->
                        val type = amap.mapType
                        amap.mapType = AMap.MAP_TYPE_NORMAL
                        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                            try { amap.mapType = type } catch (_: Exception) {}
                        }, 100)
                    }
                    result.success(true)
                }
                "setMapCacheLimit" -> {
                    val limit = call.argument<Int>("limit") ?: 3
                    _screenshotCacheLimit = limit.coerceAtLeast(0)
                    result.success(_screenshotCacheLimit)
                }
                "getMapCacheLimit" -> {
                    result.success(_screenshotCacheLimit)
                }
                "setLanguage" -> {
                    val lang = call.argument<String>("language") ?: "zh"
                    aMap?.setMapLanguage(lang)
                    result.success(true)
                }
                "measureDistance" -> {
                    val points = call.argument<List<List<Double>>>("points")
                    if (points != null && points.size >= 2) {
                        var total = 0.0
                        for (i in 0 until points.size - 1) {
                            val p1 = points[i]
                            val p2 = points[i + 1]
                            if (p1.size >= 2 && p2.size >= 2) {
                                total += com.amap.api.maps.AMapUtils.calculateLineDistance(
                                    LatLng(p1[0], p1[1]),
                                    LatLng(p2[0], p2[1])
                                )
                            }
                        }
                        result.success(total)
                    } else {
                        result.success(0.0)
                    }
                }
                "moveCamera" -> {
                    val lat = call.argument<Number>("lat")?.toDouble()
                    val lng = call.argument<Number>("lng")?.toDouble()
                    if (lat != null && lng != null) {
                        val zoom = (call.argument<Number>("zoom")?.toFloat() ?: 14f)
                        val animate = call.argument<Boolean>("animate") ?: true
                        if (animate) {
                            aMap?.animateCamera(CameraUpdateFactory.newLatLngZoom(LatLng(lat, lng), zoom))
                        } else {
                            aMap?.moveCamera(CameraUpdateFactory.newLatLngZoom(LatLng(lat, lng), zoom))
                        }
                    }
                    result.success(true)
                }
                "fitBounds" -> {
                    val lat1 = call.argument<Number>("lat1")?.toDouble()
                    val lng1 = call.argument<Number>("lng1")?.toDouble()
                    val lat2 = call.argument<Number>("lat2")?.toDouble()
                    val lng2 = call.argument<Number>("lng2")?.toDouble()
                    if (lat1 != null && lng1 != null && lat2 != null && lng2 != null) {
                        val padding = (call.argument<Number>("padding")?.toInt() ?: 120)
                        val bounds = LatLngBounds.builder()
                            .include(LatLng(lat1, lng1))
                            .include(LatLng(lat2, lng2))
                            .build()
                        aMap?.animateCamera(CameraUpdateFactory.newLatLngBounds(bounds, padding))
                    }
                    result.success(true)
                }
                // ── 导航 ──
                "calcNaviRoute" -> {
                    _ensureNavi()
                    val oLat = call.argument<Number>("originLat")?.toDouble()
                    val oLng = call.argument<Number>("originLng")?.toDouble()
                    val dLat = call.argument<Number>("destLat")?.toDouble()
                    val dLng = call.argument<Number>("destLng")?.toDouble()
                    // TODO: 途经点功能暂时禁用
                    // val waypointList = call.argument<List<List<Double>>>("waypoints")
                    // 可选：是否多路线
                    val multiRoute = call.argument<Boolean>("multiRoute") ?: false
                    if (oLat != null && oLng != null && dLat != null && dLng != null) {
                        val navi = aMapNavi
                        if (navi != null) {
                            val start = listOf(NaviLatLng(oLat, oLng))
                            val end = listOf(NaviLatLng(dLat, dLng))
                            // TODO: 途经点功能暂时禁用
                            // val waypoints = waypointList?.mapNotNull { wp ->
                            //     if (wp.size >= 2) NaviLatLng(wp[0], wp[1]) else null
                            // }?.take(10) // 最多10个途经点
                            // 计算导航策略
                            val strategy = try {
                                navi.strategyConvert(_avoidCongestion, _avoidHighway, _avoidCost, _highwayFirst, multiRoute)
                            } catch (_: Exception) { 0 }
                            navi.calculateDriveRoute(start, end, null, strategy) // waypoints → null
                            result.success(true)
                        } else {
                            result.error("NAVI_UNAVAILABLE", "导航引擎未初始化", null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "缺少起终点坐标", null)
                    }
                }
                "startNavi" -> {
                    _ensureNavi()
                    val navi = aMapNavi
                    if (navi != null) {
                        // naviType: 0=EMULATOR(模拟), 1=GPS(真实)
                        val naviTypeVal = call.argument<Int>("naviType") ?: 1
                        val naviType = when (naviTypeVal) {
                            0 -> NaviType.EMULATOR
                            else -> NaviType.GPS
                        }
                        navi.startNavi(naviType)
                        result.success(true)
                    } else {
                        result.error("NAVI_UNAVAILABLE", "导航引擎未初始化", null)
                    }
                }
                "stopNavi" -> {
                    aMapNavi?.stopNavi()
                    _isFollowingLocation = false
                    result.success(true)
                }
                // ── 步行导航 ──
                "startWalkNavi" -> {
                    _ensureNavi()
                    val oLat = call.argument<Number>("originLat")?.toDouble()
                    val oLng = call.argument<Number>("originLng")?.toDouble()
                    val dLat = call.argument<Number>("destLat")?.toDouble()
                    val dLng = call.argument<Number>("destLng")?.toDouble()
                    if (oLat != null && oLng != null && dLat != null && dLng != null) {
                        val navi = aMapNavi
                        if (navi != null) {
                            val start = NaviLatLng(oLat, oLng)
                            val end = NaviLatLng(dLat, dLng)
                            navi.calculateWalkRoute(start, end)
                            result.success(true)
                        } else {
                            result.error("NAVI_UNAVAILABLE", "导航引擎未初始化", null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "缺少起终点坐标", null)
                    }
                }
                // ── 骑行导航 ──
                "startCyclingNavi" -> {
                    _ensureNavi()
                    val oLat = call.argument<Number>("originLat")?.toDouble()
                    val oLng = call.argument<Number>("originLng")?.toDouble()
                    val dLat = call.argument<Number>("destLat")?.toDouble()
                    val dLng = call.argument<Number>("destLng")?.toDouble()
                    if (oLat != null && oLng != null && dLat != null && dLng != null) {
                        val navi = aMapNavi
                        if (navi != null) {
                            val start = NaviLatLng(oLat, oLng)
                            val end = NaviLatLng(dLat, dLng)
                            navi.calculateRideRoute(start, end)
                            result.success(true)
                        } else {
                            result.error("NAVI_UNAVAILABLE", "导航引擎未初始化", null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "缺少起终点坐标", null)
                    }
                }
                // ── HUD导航 ──
                "startHudNavi" -> {
                    _ensureNavi()
                    val navi = aMapNavi
                    if (navi != null) {
                        _isHudMode = true
                        // 通知 Flutter 侧切换到 HUD 模式
                        channel.invokeMethod("onHudModeChanged", mapOf("isHud" to true))
                        result.success(true)
                    } else {
                        result.error("NAVI_UNAVAILABLE", "导航引擎未初始化", null)
                    }
                }
                "stopHudNavi" -> {
                    _isHudMode = false
                    channel.invokeMethod("onHudModeChanged", mapOf("isHud" to false))
                    result.success(true)
                }
                // ── 弧线 ──
                "drawArc" -> {
                    val startLat = call.argument<Number>("startLat")?.toDouble()
                    val startLng = call.argument<Number>("startLng")?.toDouble()
                    val midLat = call.argument<Number>("midLat")?.toDouble()
                    val midLng = call.argument<Number>("midLng")?.toDouble()
                    val endLat = call.argument<Number>("endLat")?.toDouble()
                    val endLng = call.argument<Number>("endLng")?.toDouble()
                    if (startLat != null && startLng != null && midLat != null && midLng != null && endLat != null && endLng != null) {
                        val color = (call.argument<Number>("color")?.toInt() ?: 0xFF4F6EF7.toInt())
                        val width = (call.argument<Number>("width")?.toFloat() ?: 8f)
                        val arc = aMap?.addArc(
                            com.amap.api.maps.model.ArcOptions()
                                .point(LatLng(startLat, startLng), LatLng(midLat, midLng), LatLng(endLat, endLng))
                                .strokeColor(color)
                                .strokeWidth(width)
                        )
                        if (arc != null) arcs.add(arc)
                    }
                    result.success(true)
                }
                "clearArcs" -> {
                    for (a in arcs) a.remove()
                    arcs.clear()
                    result.success(true)
                }
                // ── 文字 ──
                "drawText" -> {
                    val lat = call.argument<Number>("lat")?.toDouble()
                    val lng = call.argument<Number>("lng")?.toDouble()
                    val text = call.argument<String>("text")
                    if (lat != null && lng != null && text != null) {
                        val fontSize = (call.argument<Number>("fontSize")?.toInt() ?: 16)
                        val fontColor = (call.argument<Number>("fontColor")?.toInt() ?: 0xFF000000.toInt())
                        val bgColor = (call.argument<Number>("bgColor")?.toInt() ?: 0x00000000.toInt())
                        val txt = aMap?.addText(
                            com.amap.api.maps.model.TextOptions()
                                .position(LatLng(lat, lng))
                                .text(text)
                                .fontSize(fontSize)
                                .fontColor(fontColor)
                                .backgroundColor(bgColor)
                        )
                        if (txt != null) texts.add(txt)
                    }
                    result.success(true)
                }
                "clearTexts" -> {
                    for (t in texts) t.remove()
                    texts.clear()
                    result.success(true)
                }
                // ── 图片层 ──
                "addGroundOverlay" -> {
                    val path = call.argument<String>("path") ?: ""
                    val swLat = call.argument<Number>("swLat")?.toDouble()
                    val swLng = call.argument<Number>("swLng")?.toDouble()
                    val neLat = call.argument<Number>("neLat")?.toDouble()
                    val neLng = call.argument<Number>("neLng")?.toDouble()
                    if (path.isNotEmpty() && swLat != null && swLng != null && neLat != null && neLng != null) {
                        try {
                            val descriptor = com.amap.api.maps.model.BitmapDescriptorFactory.fromFile(path)
                            val bounds = LatLngBounds(
                                LatLng(swLat, swLng),
                                LatLng(neLat, neLng)
                            )
                            val overlay = aMap?.addGroundOverlay(
                                com.amap.api.maps.model.GroundOverlayOptions()
                                    .anchor(0.5f, 0.5f)
                                    .positionFromBounds(bounds)
                                    .image(descriptor)
                            )
                            if (overlay != null) groundOverlays.add(overlay)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("OVERLAY_ERROR", e.message, null)
                        }
                    } else {
                        result.success(true)
                    }
                }
                "clearGroundOverlays" -> {
                    for (g in groundOverlays) g.remove()
                    groundOverlays.clear()
                    result.success(true)
                }
                // ── 标记拖拽开关 ──
                "setMarkerDraggable" -> {
                    // Toggle all current markers to draggable
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    for (m in markers) m.isDraggable = enabled
                    result.success(true)
                }
                // ── 地图设置 ──
                "showMapText" -> {
                    val show = call.argument<Boolean>("show") ?: true
                    aMap?.showMapText(show)
                    result.success(true)
                }
                "setLogoPosition" -> {
                    val pos = call.argument<Int>("position") ?: 0 // 0=左下, 1=中下, 2=右下
                    aMap?.uiSettings?.logoPosition = pos
                    result.success(true)
                }
                // ── 导航模式设置 ──
                "setNaviMapMode" -> {
                    // naviMode: 0=车头朝上, 1=正北朝上
                    val naviMode = call.argument<Int>("naviMode") ?: 0
                    if (naviMode == 1) {
                        // 正北朝上：bearing设为0
                        aMap?.animateCamera(CameraUpdateFactory.changeBearing(0f))
                    } else {
                        // 车头朝上：需要根据当前位置计算bearing
                        val loc = locationClient?.lastKnownLocation
                        if (loc != null && loc.bearing >= 0) {
                            aMap?.animateCamera(CameraUpdateFactory.changeBearing(loc.bearing))
                        }
                    }
                    result.success(true)
                }
                "setFollowCar" -> {
                    // 设置是否跟随车辆
                    val follow = call.argument<Boolean>("follow") ?: true
                    aMap?.uiSettings?.isMyLocationButtonEnabled = follow
                    result.success(true)
                }
                "setNaviFollowMode" -> {
                    // enabled: true=启用导航跟随（导航时自动跟随用户位置）
                    // enabled: false=禁用跟随，允许用户自由操作地图
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    _isUserInteracting = false
                    _isFollowingLocation = enabled
                    if (enabled) {
                        // 进入导航跟随模式：重新锁定到当前位置
                        val loc = locationClient?.lastKnownLocation
                        if (loc != null) {
                            aMap?.animateCamera(CameraUpdateFactory.newLatLngZoom(
                                com.amap.api.maps.model.LatLng(loc.latitude, loc.longitude), 17f
                            ))
                        }
                    }
                    result.success(true)
                }
                "recoverNaviFollow" -> {
                    // 恢复导航跟随（用户停止拖动地图后调用）
                    if (aMapNavi == null) { result.success(false); return@setMethodCallHandler }
                    _isUserInteracting = false
                    _isFollowingLocation = true
                    val loc = locationClient?.lastKnownLocation
                    if (loc != null) {
                        aMap?.animateCamera(CameraUpdateFactory.newLatLngZoom(
                            com.amap.api.maps.model.LatLng(loc.latitude, loc.longitude), 17f
                        ))
                    }
                    result.success(true)
                }
                // ── 多路线选择 ──
                "selectRoute" -> {
                    val index = call.argument<Int>("index") ?: 0
                    val navi = aMapNavi
                    if (navi != null && _routeIds != null && index >= 0 && index < _routeIds!!.size) {
                        _currentRouteIndex = index
                        try { navi.selectRouteId(_routeIds!![index]) } catch (_: Exception) {}
                        val path = navi.naviPath
                        if (path != null) {
                            drawNaviPathOnMap(path)
                            channel.invokeMethod("onNaviRouteCalculated", mapOf(
                                "distance" to path.allLength,
                                "duration" to path.allTime,
                                "tollCost" to path.tollCost,
                                "routeCount" to (_routeIds?.size ?: 1),
                                "routeSummary" to emptyList<Map<String, Any>>()
                            ))
                            result.success(true)
                        } else {
                            result.error("ROUTE_UNAVAILABLE", "路线不可用", null)
                        }
                    } else {
                        result.error("INVALID_INDEX", "路线索引无效", null)
                    }
                }
                "getRouteList" -> {
                    // 返回多路线摘要列表
                    val navi = aMapNavi
                    if (navi != null && _routeIds != null) {
                        val routeSummary = _routeIds!!.toList().mapIndexedNotNull { idx: Int, _: Int ->
                            val path = if (idx == 0) navi.naviPath else null
                            if (path != null) {
                                mapOf(
                                    "index" to idx,
                                    "distance" to path.allLength,
                                    "duration" to path.allTime,
                                    "tollCost" to path.tollCost
                                )
                            } else null
                        }
                        result.success(routeSummary)
                    } else {
                        result.success(emptyList<Map<String, Any>>())
                    }
                }
                // ── TTS 静音 ──
                "setNaviMuted" -> {
                    _ttsMuted = call.argument<Boolean>("muted") ?: false
                    if (_ttsMuted) _tts?.stop()
                    result.success(true)
                }
                // ── 导航策略设置 ──
                "setNaviStrategy" -> {
                    _avoidCongestion = call.argument<Boolean>("avoidCongestion") ?: false
                    _avoidHighway = call.argument<Boolean>("avoidHighway") ?: false
                    _avoidCost = call.argument<Boolean>("avoidCost") ?: false
                    _highwayFirst = call.argument<Boolean>("highwayFirst") ?: false
                    result.success(true)
                }
                // ── 车辆类型设置 ──
                "setVehicleType" -> {
                    val type = call.argument<String>("type") ?: "car"
                    _vehicleType = type
                    // 设置车辆信息到导航引擎
                    aMapNavi?.let { navi ->
                        when (type) {
                            "truck" -> {
                                val carInfo = com.amap.api.navi.model.AMapCarInfo()
                                carInfo.setCarType("1") // 0=小车, 1=货车
                                carInfo.setVehicleLength("12")
                                carInfo.setVehicleWidth("2.5")
                                carInfo.setVehicleHeight("4")
                                carInfo.setVehicleWeight("20")
                                carInfo.setVehicleLoad("10")
                                navi.setCarInfo(carInfo)
                            }
                            "motorcycle" -> {
                                val carInfo = com.amap.api.navi.model.AMapCarInfo()
                                carInfo.setCarType("2") // 摩托车
                                navi.setCarInfo(carInfo)
                            }
                            "electric" -> {
                                val carInfo = com.amap.api.navi.model.AMapCarInfo()
                                carInfo.setCarType("3") // 电动车
                                navi.setCarInfo(carInfo)
                            }
                            else -> {
                                val carInfo = com.amap.api.navi.model.AMapCarInfo()
                                carInfo.setCarType("0") // 小车
                                navi.setCarInfo(carInfo)
                            }
                        }
                    }
                    result.success(true)
                }
                // ── 获取导航步骤详情 ──
                "getNaviSteps" -> {
                    val navi = aMapNavi
                    if (navi != null && navi.naviPath != null) {
                        val guideList = navi.naviPath.naviGuideList
                        if (guideList != null) {
                            val steps = guideList.map { guide ->
                                mapOf(
                                    "name" to (guide.groupName ?: ""),
                                    "distance" to guide.groupLen,
                                    "iconType" to guide.groupIconType,
                                    "trafficLightsCount" to guide.trafficLightsCount,
                                    "instruction" to (guide.groupName ?: "")
                                )
                            }
                            result.success(steps)
                        } else {
                            result.success(emptyList<Map<String, Any>>())
                        }
                    } else {
                        result.success(emptyList<Map<String, Any>>())
                    }
                }
                // ── 全览模式 ──
                "displayOverview" -> {
                    _isOverviewMode = true
                    // 全览模式需要在导航View上调用，这里通过调整地图视野实现
                    val navi = aMapNavi
                    if (navi != null && navi.naviPath != null) {
                        val path = navi.naviPath
                        val bounds = LatLngBounds.builder()
                            .include(LatLng(path.startPoint.latitude, path.startPoint.longitude))
                            .include(LatLng(path.endPoint.latitude, path.endPoint.longitude))
                            .build()
                        aMap?.animateCamera(CameraUpdateFactory.newLatLngBounds(bounds, 100))
                    }
                    channel.invokeMethod("onOverviewModeChanged", mapOf("isOverview" to true))
                    result.success(true)
                }
                "recoverLockMode" -> {
                    _isOverviewMode = false
                    channel.invokeMethod("onOverviewModeChanged", mapOf("isOverview" to false))
                    result.success(true)
                }
                // ── 主辅路切换 ──
                "switchParallelRoad" -> {
                    val type = call.argument<Int>("type") ?: 1 // 1=主辅路切换, 2=高架上下
                    aMapNavi?.switchParallelRoad(type)
                    result.success(true)
                }
                // ── 平滑移动 ──
                "animateMarker" -> {
                    val markerIdx = call.argument<Int>("markerIndex")?.toInt() ?: -1
                    val path = call.argument<List<List<Double>>>("path")
                    val durationMs = call.argument<Long>("durationMs")?.toLong() ?: 3000L
                    if (path != null && path.size >= 2 && markerIdx >= 0 && markerIdx < markers.size) {
                        val marker = markers[markerIdx]
                        val latLngs = path.mapNotNull { p ->
                            if (p.size >= 2) LatLng(p[0], p[1]) else null
                        }
                        if (latLngs.isNotEmpty()) {
                            val handler = android.os.Handler(android.os.Looper.getMainLooper())
                            var step = 0
                            val stepDuration = durationMs / latLngs.size
                            val runnable = object : Runnable {
                                override fun run() {
                                    if (step < latLngs.size) {
                                        marker.position = latLngs[step]
                                        step++
                                        handler.postDelayed(this, stepDuration)
                                    }
                                }
                            }
                            handler.post(runnable)
                        }
                    }
                    result.success(true)
                }
                // ── 定位 SDK 信息 ──
                "getLocationVersion" -> {
                    result.success(locationClient?.version ?: "未知")
                }
                "getLocationDetail" -> {
                    val loc = locationClient?.lastKnownLocation
                    if (loc != null && loc.errorCode == 0) {
                        result.success(loc.description ?: "")
                    } else {
                        result.success("")
                    }
                }
                // ── 获取当前缩放级别（用于自定义比例尺） ──
                "getZoomLevel" -> {
                    result.success(aMap?.cameraPosition?.zoom?.toDouble() ?: 0.0)
                }
                // ── 生命周期恢复（权限授予后从 Settings 返回时调用） ──
                "resumeMap" -> {
                    try {
                        mapView.onResume()
                        locationClient?.startLocation()
                        result.success(true)
                    } catch (e: Exception) {
                        android.util.Log.e("MapDebug", ">>> resumeMap error: ${e.message}")
                        result.success(false)
                    }
                }
                "pauseMap" -> {
                    try {
                        locationClient?.stopLocation()
                        mapView.onPause()
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "updateUserMarkerIcon" -> {
                    val data = call.argument<ByteArray>("data")
                    val anchorX = (call.argument<Number>("anchorX")?.toFloat() ?: 0.5f)
                    val anchorY = (call.argument<Number>("anchorY")?.toFloat() ?: 0.85f)
                    if (data != null) {
                        try {
                            val bitmap = BitmapFactory.decodeByteArray(data, 0, data.size)
                            if (bitmap != null) {
                                _markerSourceBitmap = bitmap
                                _pendingMarkerAnchorX = anchorX
                                _pendingMarkerAnchorY = anchorY
                                _currentMarkerScale = 0f // 强制刷新缩放
                                _updateMarkerZoomScale()
                            }
                        } catch (e: Exception) {
                            Log.e("MapDebug", "updateUserMarkerIcon error: ${e.message}")
                        }
                    }
                    result.success(true)
                }
                "addArrowMarkers" -> {
                    // 从 Flutter 接收箭头位置+角度数据，原生端绘制图标，避免 PNG 跨线程拷贝
                    val positions = call.argument<List<List<Double>>>("positions") // [[lat, lng, heading], ...]
                    val color = (call.argument<Number>("color")?.toInt() ?: 0xFF4F6EF7.toInt())
                    if (positions != null && positions.isNotEmpty()) {
                        // 生成或复用箭头 bitmap
                        val arrowBmp = _getOrCreateArrowBitmap(color, 16)
                        if (arrowBmp != null) {
                            val desc = BitmapDescriptorFactory.fromBitmap(arrowBmp)
                            for (pos in positions) {
                                if (pos.size < 3) continue
                                val lat = pos[0]
                                val lng = pos[1]
                                val heading = pos[2].toFloat()
                                val opts = MarkerOptions()
                                    .position(LatLng(lat, lng))
                                    .icon(desc)
                                    .anchor(0.5f, 0.5f)
                                    .rotateAngle(heading)
                                val marker = aMap?.addMarker(opts)
                                if (marker != null) markers.add(marker)
                            }
                        }
                    }
                    result.success(true)
                }
                "getRoutePoints" -> {
                    // 返回当前导航路线坐标点列表 [[lat, lng], ...]
                    val pts = _currentRoutePoints
                    if (pts != null) {
                        val resultList = pts.map { listOf(it.latitude, it.longitude) }
                        result.success(resultList)
                    } else {
                        result.success(emptyList<List<Double>>())
                    }
                }
                else -> result.notImplemented()
            }
        }
        Log.i("MapDebug", ">>> === AmapNativeMapView init END ===")
    }

    // ── 导航监听器 ──

    private fun createNaviListener(): AMapNaviListener {
        return object : AMapNaviListener {
            // CM SDK: both overloads must be implemented
            override fun onCalculateRouteSuccess(result: AMapCalcRouteResult) {
                try {
                    val navi = aMapNavi ?: return
                    _routeIds = result.getRouteid()
                    _currentRouteIndex = 0
                    val ids = _routeIds
                    val routeSummary = mutableListOf<Map<String, Any>>()
                    if (ids != null) {
                        for (idx in ids.indices) {
                            try {
                                navi.selectRouteId(ids[idx])
                                val p = navi.naviPath
                                if (p != null) {
                                    routeSummary.add(mapOf(
                                        "index" to idx,
                                        "distance" to p.allLength,
                                        "duration" to p.allTime,
                                        "tollCost" to p.tollCost
                                    ))
                                }
                            } catch (_: Exception) {}
                        }
                        if (ids.isNotEmpty()) {
                            try { navi.selectRouteId(ids[0]) } catch (_: Exception) {}
                        }
                    }
                    if (routeSummary.isEmpty()) {
                        val path = navi.naviPath
                        if (path != null) {
                            routeSummary.add(mapOf(
                                "index" to 0,
                                "distance" to path.allLength,
                                "duration" to path.allTime,
                                "tollCost" to path.tollCost
                            ))
                        }
                    }
                    val path = navi.naviPath
                    if (path != null) {
                        drawNaviPathOnMap(path)
                    }
                    channel.invokeMethod("onNaviRouteCalculated", mapOf(
                        "distance" to (path?.allLength ?: 0),
                        "duration" to (path?.allTime ?: 0),
                        "tollCost" to (path?.tollCost ?: 0.0),
                        "routeCount" to (ids?.size ?: 1),
                        "routeSummary" to routeSummary
                    ))
                } catch (_: Exception) {}
            }
            override fun onCalculateRouteSuccess(routeIds: IntArray) {}
            override fun onCalculateRouteFailure(result: AMapCalcRouteResult) {
                channel.invokeMethod("onNaviRouteFailed", mapOf(
                    "errorCode" to result.errorCode
                ))
            }
            override fun onCalculateRouteFailure(errorCode: Int) {}
            override fun onArriveDestination() {
                channel.invokeMethod("onNaviArriveDestination", emptyMap<String, Any>())
            }
            override fun onNaviInfoUpdate(info: NaviInfo) {
                channel.invokeMethod("onNaviInfoUpdate", mapOf(
                    "roadName" to (info.currentRoadName ?: ""),
                    "distanceRemain" to info.pathRetainDistance,
                    "timeRemain" to info.pathRetainTime,
                    "nextRoad" to (info.nextRoadName ?: ""),
                    "iconType" to info.iconType,
                    "curStepDistance" to info.curStepRetainDistance,
                    "speed" to info.currentSpeed
                ))
            }
            override fun onInitNaviSuccess() {}
            override fun onInitNaviFailure() {}
            override fun onStartNavi(i: Int) {
                channel.invokeMethod("onNaviStarted", mapOf("type" to i))
            }
            override fun onTrafficStatusUpdate() {}
            override fun onEndEmulatorNavi() {}
            override fun onArrivedWayPoint(i: Int) {}
            override fun onPlayRing(i: Int) {}
            override fun onGpsOpenStatus(b: Boolean) {}
            override fun onGetNavigationText(i: Int, text: String) {
                Log.i("MapDebug", ">>> TTS text: type=$i, text=$text, ttsReady=$_ttsInitialized")
                lastNaviText = text
                channel.invokeMethod("onNaviTtsText", mapOf("text" to text, "type" to i))
                if (!_ttsMuted && _ttsInitialized && text.isNotEmpty()) {
                    _tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "navi_$i")
                }
            }
            override fun onGetNavigationText(text: String) {
                Log.i("MapDebug", ">>> TTS text (alt): text=$text, ttsReady=$_ttsInitialized")
                lastNaviText = text
                channel.invokeMethod("onNaviTtsText", mapOf("text" to text, "type" to 0))
                if (!_ttsMuted && _ttsInitialized && text.isNotEmpty()) {
                    _tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "navi_0")
                }
            }
            override fun onLocationChange(location: AMapNaviLocation) {}
            override fun onReCalculateRouteForYaw() {
                channel.invokeMethod("onNaviRecalculate", mapOf("type" to "yaw"))
            }
            override fun onReCalculateRouteForTrafficJam() {
                channel.invokeMethod("onNaviRecalculate", mapOf("type" to "traffic"))
            }
            override fun updateCameraInfo(cameras: Array<AMapNaviCameraInfo>) {}
            override fun updateIntervalCameraInfo(
                camera1: AMapNaviCameraInfo,
                camera2: AMapNaviCameraInfo,
                distance: Int
            ) {}
            override fun onServiceAreaUpdate(areas: Array<AMapServiceAreaInfo>) {}
            override fun showCross(cross: AMapNaviCross) {
                try {
                    val bmp = cross.bitmap
                    if (bmp != null) {
                        val stream = java.io.ByteArrayOutputStream()
                        bmp.compress(android.graphics.Bitmap.CompressFormat.PNG, 80, stream)
                        val bytes = stream.toByteArray()
                        lastCrossInfo = mapOf("visible" to true, "image" to bytes)
                    } else {
                        lastCrossInfo = mapOf("visible" to true)
                    }
                } catch (_: Exception) {
                    lastCrossInfo = mapOf("visible" to true)
                }
                channel.invokeMethod("onNaviCrossUpdate", lastCrossInfo)
            }
            override fun hideCross() {
                lastCrossInfo = mapOf("visible" to false)
                channel.invokeMethod("onNaviCrossUpdate", mapOf("visible" to false))
            }
            override fun showModeCross(cross: AMapModelCross) {}
            override fun hideModeCross() {}
            override fun showLaneInfo(lanes: Array<AMapLaneInfo>, lane: ByteArray, lane2: ByteArray) {
                lastLaneInfo = mapOf("visible" to true, "laneCount" to lanes.size, "image" to lane)
                channel.invokeMethod("onNaviLaneUpdate", lastLaneInfo)
            }
            override fun showLaneInfo(lane: AMapLaneInfo) {}
            override fun hideLaneInfo() {
                lastLaneInfo = mapOf("visible" to false)
                channel.invokeMethod("onNaviLaneUpdate", mapOf("visible" to false))
            }
            override fun notifyParallelRoad(type: Int) {
                channel.invokeMethod("onParallelRoad", mapOf("type" to type))
            }
            override fun OnUpdateTrafficFacility(facilities: Array<AMapNaviTrafficFacilityInfo>) {}
            override fun OnUpdateTrafficFacility(facility: AMapNaviTrafficFacilityInfo) {}
            override fun updateAimlessModeStatistics(stat: AimLessModeStat) {}
            override fun updateAimlessModeCongestionInfo(info: AimLessModeCongestionInfo) {}
            override fun onNaviRouteNotify(data: AMapNaviRouteNotifyData) {}
            override fun onGpsSignalWeak(weak: Boolean) {
                channel.invokeMethod("onGpsSignalWeak", mapOf("weak" to weak))
            }
        }
    }

    /// 延迟初始化导航引擎 — 仅在首次实际导航时创建，避免主线程卡顿和内存浪费。
    private fun _ensureNavi() {
        if (aMapNavi != null) return
        try {
            aMapNavi = AMapNavi.getInstance(mapView.context).apply {
                addAMapNaviListener(naviListener)
                setUseInnerVoice(false) // CM SDK 无内置 TTS，用系统 TTS 代替
            }
        } catch (_: Exception) {}
        // 初始化系统 TTS
        if (!_ttsInitialized) {
            try {
                _tts = TextToSpeech(mapView.context) { status ->
                    _ttsInitialized = (status == TextToSpeech.SUCCESS)
                    if (_ttsInitialized) {
                        val result = _tts?.setLanguage(java.util.Locale.CHINESE)
                        Log.i("MapDebug", ">>> TTS init OK, langResult=$result")
                    } else {
                        Log.e("MapDebug", ">>> TTS init FAILED, status=$status")
                    }
                }
            } catch (e: Exception) {
                Log.e("MapDebug", ">>> TTS init exception: ${e.message}")
            }
        }
    }

    private fun drawNaviPathOnMap(path: AMapNaviPath) {
        for (m in markers) m.destroy()
        markers.clear()
        for (p in polylines) p.remove()
        polylines.clear()
        for (p in polygons) p.remove()
        polygons.clear()
        for (c in circles) c.remove()
        circles.clear()
        for (a in arcs) a.remove()
        arcs.clear()
        for (t in texts) t.remove()
        texts.clear()
        for (g in groundOverlays) g.remove()
        groundOverlays.clear()

        // 起点标记（绿色 #34C759 — 高德语义：起点绿）
        val startBmp = _createCircleBitmap(0xFF34C759.toInt())
        if (startBmp != null) {
            aMap?.addMarker(MarkerOptions()
                .position(LatLng(path.startPoint.latitude, path.startPoint.longitude))
                .title("起点")
                .icon(BitmapDescriptorFactory.fromBitmap(startBmp))
                .anchor(0.5f, 0.5f)
            )?.let { markers.add(it) }
        } else {
            aMap?.addMarker(MarkerOptions()
                .position(LatLng(path.startPoint.latitude, path.startPoint.longitude))
                .title("起点")
            )?.let { markers.add(it) }
        }

        // 终点标记（红色 #FF3B30 — 高德语义：终点红）
        val endBmp = _createCircleBitmap(0xFFFF3B30.toInt())
        if (endBmp != null) {
            aMap?.addMarker(MarkerOptions()
                .position(LatLng(path.endPoint.latitude, path.endPoint.longitude))
                .title("终点")
                .icon(BitmapDescriptorFactory.fromBitmap(endBmp))
                .anchor(0.5f, 0.5f)
            )?.let { markers.add(it) }
        } else {
            aMap?.addMarker(MarkerOptions()
                .position(LatLng(path.endPoint.latitude, path.endPoint.longitude))
                .title("终点")
            )?.let { markers.add(it) }
        }

        // 导航路线点 → 地图折线
        val coordList = path.coordList
        if (coordList != null && coordList.isNotEmpty()) {
            val latLngs = coordList.map { LatLng(it.latitude, it.longitude) }
            _currentRoutePoints = latLngs
            val polyline = aMap?.addPolyline(
                PolylineOptions()
                    .addAll(latLngs)
                    .color(0xFF4F6EF7.toInt())
                    .width(16f)
            )
            if (polyline != null) polylines.add(polyline)
        }

        // 以用户位置为中心，保持当前缩放不变
        val currentZoom = aMap?.cameraPosition?.zoom ?: 15f
        val centerLat = locationClient?.lastKnownLocation?.latitude ?: path.startPoint.latitude
        val centerLng = locationClient?.lastKnownLocation?.longitude ?: path.startPoint.longitude
        aMap?.animateCamera(CameraUpdateFactory.newLatLngZoom(LatLng(centerLat, centerLng), currentZoom))
    }

    // ── 自定义当前位置标记（保证可见性，不依赖 SDK 内置定位图层）──

    private fun updateMyLocationMarker(location: AMapLocation) {
        val latLng = LatLng(location.latitude, location.longitude)
        val bearing = location.bearing // 方向角（0-360度，0=北）

        if (myLocationMarker == null) {
            android.util.Log.i("MapDebug", ">>> Creating myLocationMarker!")
            // 兜底图标：如果 Flutter 侧图标尚未到达
            val descriptor = if (_markerSourceBitmap != null) {
                // 由 _updateMarkerZoomScale 在下方创建时设置
                null
            } else {
                com.amap.api.maps.model.BitmapDescriptorFactory.fromResource(
                    com.agent.my_agent_app.R.drawable.ic_user_location_marker_fallback
                )
            }
            val anchorX = _pendingMarkerAnchorX
            val anchorY = _pendingMarkerAnchorY
            val fallbackIcon = com.amap.api.maps.model.BitmapDescriptorFactory.fromResource(
                com.agent.my_agent_app.R.drawable.ic_user_location_marker_fallback
            )
            myLocationMarker = aMap?.addMarker(
                MarkerOptions()
                    .position(latLng)
                    .icon(descriptor ?: fallbackIcon)
                    .anchor(anchorX, anchorY)
                    .zIndex(200f)
                    .rotateAngle(bearing)
                    .title("我的位置")
                    .snippet("当前位置")
            )
            android.util.Log.i("MapDebug", ">>> Marker created: $myLocationMarker")
            // 如果有原始位图，立刻按当前 zoom 缩放
            if (myLocationMarker != null && _markerSourceBitmap != null) {
                _currentMarkerScale = 0f
                _updateMarkerZoomScale()
                myLocationMarker?.setAnchor(anchorX, anchorY)
            }
        }
        myLocationMarker?.position = latLng
        myLocationMarker?.rotateAngle = bearing
        myLocationMarker?.isVisible = true
    }

    /// 根据当前地图 zoom 级别缩放用户定位 Marker 图标。
    /// 缩放档位（基准 zoom=15，整体 * _markerBaseScale）：
    ///   zoom<12 → 0.35   |  12→0.50  |  13→0.65
    ///   14→0.80  |  15→1.00(基准) |  16→1.15
    ///   17→1.30  |  18→1.45  |  19+→1.60
    private fun _updateMarkerZoomScale() {
        val src = _markerSourceBitmap ?: return
        val zoom = _lastZoom

        val rawScale = when {
            zoom >= 19f -> 1.60f
            zoom >= 18f -> 1.45f
            zoom >= 17f -> 1.30f
            zoom >= 16f -> 1.15f
            zoom >= 15f -> 1.00f  // 基准
            zoom >= 14f -> 0.80f
            zoom >= 13f -> 0.65f
            zoom >= 12f -> 0.50f
            else -> 0.35f
        }
        val scale = rawScale * _markerBaseScale

        if (scale == _currentMarkerScale) return
        _currentMarkerScale = scale

        try {
            val newW = (src.width * scale).toInt().coerceAtLeast(16)
            val newH = (src.height * scale).toInt().coerceAtLeast(16)
            val scaled = android.graphics.Bitmap.createScaledBitmap(src, newW, newH, true)
            val descriptor = com.amap.api.maps.model.BitmapDescriptorFactory.fromBitmap(scaled)
            myLocationMarker?.setIcon(descriptor)
        } catch (e: Exception) {
            Log.e("MapDebug", "zoom scale error: ${e.message}")
        }
    }

    /// 创建圆形 Marker 图标（白色外圈 + 彩色内圈）
    private fun _createCircleBitmap(color: Int, sizePx: Int = 32): android.graphics.Bitmap? {
        return try {
            val bmp = android.graphics.Bitmap.createBitmap(sizePx, sizePx, android.graphics.Bitmap.Config.ARGB_8888)
            val canvas = android.graphics.Canvas(bmp)
            val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                // 白色外圆
                this.color = android.graphics.Color.WHITE
                style = android.graphics.Paint.Style.FILL
            }
            canvas.drawCircle(sizePx / 2f, sizePx / 2f, sizePx / 2f, paint)
            // 彩色内圆
            paint.color = color // this `color` is the parameter — OK here, not in apply
            canvas.drawCircle(sizePx / 2f, sizePx / 2f, sizePx / 2f - 3f, paint)
            bmp
        } catch (_: Exception) { null }
    }

    /// 缓存箭头 Bitmap，避免重复绘制。
    /// 箭头朝上（0°=北），原生端通过 rotateAngle 控制方向。
    /// 白色填充 + 彩色描边（高德风格）。
    private fun _getOrCreateArrowBitmap(color: Int, sizePx: Int): android.graphics.Bitmap? {
        if (_cachedArrowBitmap != null && _lastArrowColor == color) {
            return _cachedArrowBitmap
        }
        _lastArrowColor = color
        _cachedArrowBitmap?.recycle()
        try {
            val bmp = android.graphics.Bitmap.createBitmap(sizePx, sizePx, android.graphics.Bitmap.Config.ARGB_8888)
            val canvas = android.graphics.Canvas(bmp)
            val half = sizePx / 2f
            val path = android.graphics.Path().apply {
                moveTo(half, 2f)      // 顶部中心
                lineTo(sizePx - 2f, sizePx - 2f) // 右下
                lineTo(half, sizePx * 0.65f)     // 底部中槽
                lineTo(2f, sizePx - 2f)          // 左下
                close()
            }
            // 白色填充
            val fillPaint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                this.color = android.graphics.Color.WHITE
                style = android.graphics.Paint.Style.FILL
            }
            canvas.drawPath(path, fillPaint)
            // 彩色描边（路线颜色）
            val strokePaint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                this.color = color
                style = android.graphics.Paint.Style.STROKE
                strokeWidth = 2.5f
                strokeJoin = android.graphics.Paint.Join.ROUND
            }
            canvas.drawPath(path, strokePaint)
            _cachedArrowBitmap = bmp
            return bmp
        } catch (_: Exception) {
            return null
        }
    }

    // ── LocationSource ──

    override fun activate(listener: LocationSource.OnLocationChangedListener) {
        onLocationChangedListener = listener
        // Location client is already running from init;
        // next update will be fed to this listener automatically
    }

    override fun deactivate() {
        onLocationChangedListener = null
        aMap?.setOnMapLoadedListener(null)
        // Don't destroy the client — it's managed independently
    }

    fun onResume() {
        if (_destroyed) return
        try {
            mapView.onResume()
        } catch (e: Exception) {
            Log.e("MapCrash", ">>> onResume mapView.onResume FAILED: ${e.message}", e)
        }
        locationClient?.startLocation()
    }

    fun onPause() {
        locationClient?.stopLocation()
        try {
            mapView.onPause()
        } catch (e: Exception) {
            Log.e("MapCrash", ">>> onPause mapView.onPause FAILED: ${e.message}", e)
        }
    }

    fun onDestroy() {
        if (_destroyed) return
        _destroyed = true
        aMapNavi?.removeAMapNaviListener(naviListener)
        aMapNavi?.stopNavi()
        _tts?.stop()
        _tts?.shutdown()
        _tts = null
        _ttsInitialized = false
        locationClient?.stopLocation()
        locationClient?.onDestroy()
        locationClient = null
        onLocationChangedListener = null
        for (m in markers) m.destroy()
        markers.clear()
        for (p in polylines) p.remove()
        polylines.clear()
        for (p in polygons) p.remove()
        polygons.clear()
        for (c in circles) c.remove()
        circles.clear()
        for (a in arcs) a.remove()
        arcs.clear()
        for (t in texts) t.remove()
        texts.clear()
        for (g in groundOverlays) g.remove()
        groundOverlays.clear()
        aMap?.setOnMapLoadedListener(null)
        aMap = null
        aMapNavi = null
        try {
            mapView.onDestroy()
        } catch (e: Exception) {
            Log.e("MapCrash", ">>> mapView.onDestroy FAILED: ${e.message}", e)
        }
        // 从 decorView 移除
        try {
            (mapView.parent as? android.view.ViewGroup)?.removeView(mapView)
        } catch (_: Exception) {}
    }

    override fun getView(): View = mapView

    override fun dispose() {
        if (_destroyed) return
        _destroyed = true
        aMapNavi?.removeAMapNaviListener(naviListener)
        aMapNavi?.stopNavi()
        _tts?.stop()
        _tts?.shutdown()
        _tts = null
        _ttsInitialized = false
        locationClient?.stopLocation()
        locationClient?.onDestroy()
        locationClient = null
        onLocationChangedListener = null
        for (m in markers) m.destroy()
        markers.clear()
        for (p in polylines) p.remove()
        polylines.clear()
        for (p in polygons) p.remove()
        polygons.clear()
        for (c in circles) c.remove()
        circles.clear()
        for (a in arcs) a.remove()
        arcs.clear()
        for (t in texts) t.remove()
        texts.clear()
        for (g in groundOverlays) g.remove()
        groundOverlays.clear()
        aMap?.setOnMapLoadedListener(null)
        aMap = null
        aMapNavi = null
        try {
            mapView.onDestroy()
        } catch (e: Exception) {
            Log.e("MapCrash", ">>> dispose mapView.onDestroy FAILED: ${e.message}", e)
        }
        // 从 decorView 移除
        try {
            (mapView.parent as? android.view.ViewGroup)?.removeView(mapView)
        } catch (_: Exception) {}
    }

    /// 删除旧截图文件，保留最新的 keepCount 张
    private fun clearOldScreenshots(cacheDir: java.io.File, keepCount: Int) {
        try {
            val files = cacheDir.listFiles { _, name -> name.startsWith("map_screenshot_") && name.endsWith(".png") }
                ?: return
            if (files.size <= keepCount) return
            // 按修改时间倒序，删除最旧的
            val sorted = files.sortedByDescending { it.lastModified() }
            sorted.drop(keepCount).forEach { it.delete() }
        } catch (_: Exception) {}
    }
}
