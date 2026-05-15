package com.agent.my_agent_app

import android.content.Context
import android.location.LocationManager
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class LocationHandler(private val context: Context) {
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getCurrentPosition" -> getCurrentPosition(result)
            else -> result.notImplemented()
        }
    }

    private fun getCurrentPosition(result: MethodChannel.Result) {
        try {
            val lm = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager

            val gpsEnabled = lm.isProviderEnabled(LocationManager.GPS_PROVIDER)
            val networkEnabled = lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)

            if (!gpsEnabled && !networkEnabled) {
                result.error("UNAVAILABLE", "定位服务未开启，请在设置中开启 GPS 或网络定位", null)
                return
            }

            // Step 1: try cached location (fast path)
            var bestLocation: android.location.Location? = null

            try {
                val gpsLoc = lm.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                if (gpsLoc != null && isBetterLocation(gpsLoc, bestLocation)) {
                    bestLocation = gpsLoc
                }
            } catch (_: SecurityException) {}

            try {
                val netLoc = lm.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                if (netLoc != null && isBetterLocation(netLoc, bestLocation)) {
                    bestLocation = netLoc
                }
            } catch (_: SecurityException) {}

            try {
                val passiveLoc = lm.getLastKnownLocation(LocationManager.PASSIVE_PROVIDER)
                if (passiveLoc != null && isBetterLocation(passiveLoc, bestLocation)) {
                    bestLocation = passiveLoc
                }
            } catch (_: SecurityException) {}

            if (bestLocation != null) {
                result.success(locationToMap(bestLocation))
                return
            }

            // Step 2: cache miss — actively request fresh location with timeout
            requestFreshLocation(lm, gpsEnabled, networkEnabled, result)
        } catch (e: SecurityException) {
            result.error("PERMISSION", "位置权限未授予", null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun requestFreshLocation(
        lm: LocationManager,
        gpsEnabled: Boolean,
        networkEnabled: Boolean,
        result: MethodChannel.Result
    ) {
        val handler = android.os.Handler(Looper.getMainLooper())
        var settled = false

        var listener: android.location.LocationListener? = null

        val cleanup = {
            listener?.let { try { lm.removeUpdates(it) } catch (_: Exception) {} }
        }

        listener = object : android.location.LocationListener {
            override fun onLocationChanged(location: android.location.Location) {
                if (!settled) {
                    settled = true
                    cleanup()
                    handler.removeCallbacksAndMessages(null)
                    result.success(locationToMap(location))
                }
            }
            override fun onStatusChanged(provider: String?, status: Int, extras: android.os.Bundle?) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}
        }

        // Timeout after 15 seconds
        handler.postDelayed({
            if (!settled) {
                settled = true
                cleanup()
                result.error("TIMEOUT", "定位超时，请确保在室外或有网络覆盖", null)
            }
        }, 15000)

        try {
            val locListener = listener!!
            if (gpsEnabled) {
                lm.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER,
                    0L,       // minTime: deliver ASAP
                    0f,       // minDistance: deliver ASAP
                    locListener,
                    Looper.getMainLooper()
                )
            }
            if (networkEnabled) {
                lm.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER,
                    0L,
                    0f,
                    locListener,
                    Looper.getMainLooper()
                )
            }
        } catch (e: SecurityException) {
            settled = true
            handler.removeCallbacksAndMessages(null)
            result.error("PERMISSION", "位置权限未授予", null)
        }
    }

    private fun locationToMap(loc: android.location.Location): Map<String, Any> {
        return mapOf(
            "latitude" to loc.latitude,
            "longitude" to loc.longitude,
            "accuracy" to loc.accuracy.toDouble(),
            "provider" to (loc.provider ?: "unknown"),
            "timestamp" to loc.time
        )
    }

    private fun isBetterLocation(
        newLoc: android.location.Location,
        existing: android.location.Location?
    ): Boolean {
        if (existing == null) return true
        val timeDelta = newLoc.time - existing.time
        val isNewer = timeDelta > 120000
        val isMoreAccurate = newLoc.accuracy < existing.accuracy
        return isNewer || (isMoreAccurate && timeDelta > -120000)
    }
}
