package com.example.idler

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.SystemClock
import android.provider.Settings
import android.text.TextUtils
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.idler/notifications"
    private val PREFS_NAME = "IdlerPrefs"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        val sharedPrefs: SharedPreferences = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getActiveNotifications" -> {
                        val notifications = NotificationListener.getNotifications()
                        result.success(notifications)
                    }
                    "isNotificationServiceEnabled" -> {
                        result.success(isNotificationServiceEnabled())
                    }
                    "isNotificationListenerConnected" -> {
                        try {
                            val active = NotificationListener.isListenerActive()
                            result.success(active)
                        } catch (e: Exception) {
                            result.error("error", e.message, null)
                        }
                    }
                    "openNotificationSettings" -> {
                        try {
                            val intent = Intent(android.provider.Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("error", e.message, null)
                        }
                    }
                    "openApp" -> {
                        val pkg = call.argument<String>("package")
                        if (pkg == null) {
                            result.error("invalid", "package missing", null)
                        } else {
                            val launch = packageManager.getLaunchIntentForPackage(pkg)
                            if (launch != null) {
                                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(launch)
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        }
                    }
                    "openGoogleHome" -> {
                        try {
                            val intent = packageManager.getLaunchIntentForPackage("com.google.android.apps.chromecast.app")
                            if (intent != null) {
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                result.success(true)
                            } else {
                                val marketIntent = Intent(Intent.ACTION_VIEW, android.net.Uri.parse("market://details?id=com.google.android.apps.chromecast.app"))
                                marketIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(marketIntent)
                                result.success(false)
                            }
                        } catch (e: Exception) {
                            result.error("error", e.message, null)
                        }
                    }
                    "openAssistant" -> {
                        try {
                            val intent = Intent(Intent.ACTION_VOICE_COMMAND)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            // Fallback to searching for assistant package
                            try {
                                val intent = Intent(Intent.ACTION_MAIN)
                                intent.setPackage("com.google.android.apps.googleassistant")
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                result.success(true)
                            } catch (e2: Exception) {
                                result.error("error", e2.message, null)
                            }
                        }
                    }
                    "dismissNotification" -> {
                        val key = call.argument<String>("key")
                        val pkg = call.argument<String>("package")
                        val title = call.argument<String>("title")
                        if ((key == null || key.isEmpty()) && (pkg == null || title == null)) {
                            result.error("invalid", "key or package/title missing", null)
                        } else {
                            val removed = NotificationListener.removeNotification(pkg ?: "", title ?: "", key)
                            result.success(removed)
                        }
                    }
                    "getMediaProgress" -> {
                        result.success(getMediaProgress())
                    }
                    "resetNotificationListener" -> {
                        try {
                            resetNotificationListener()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("error", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isNotificationServiceEnabled(): Boolean {
        val pkgName = packageName
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        if (!flat.isNullOrEmpty()) {
            val names = flat.split(":")
            for (name in names) {
                val cn = ComponentName.unflattenFromString(name)
                if (cn != null) {
                    if (TextUtils.equals(pkgName, cn.packageName)) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private fun getMediaProgress(): Map<String, Any> {
        return try {
            val sessionManager = getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
            val componentName = ComponentName(this, NotificationListener::class.java)
            val controllers = sessionManager.getActiveSessions(componentName)

            val controller = controllers.firstOrNull { isActiveMediaController(it) }
                ?: controllers.firstOrNull()

            val playbackState = controller?.playbackState
            val metadata = controller?.metadata
            val durationMs = metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L
            val positionMs = calculatePositionMs(playbackState, durationMs)

            mapOf(
                "positionMs" to positionMs,
                "durationMs" to durationMs,
                "isPlaying" to (playbackState?.state == PlaybackState.STATE_PLAYING),
            )
        } catch (_: Exception) {
            mapOf(
                "positionMs" to 0L,
                "durationMs" to 0L,
                "isPlaying" to false,
            )
        }
    }

    private fun isActiveMediaController(controller: MediaController): Boolean {
        val state = controller.playbackState?.state
        return state == PlaybackState.STATE_PLAYING ||
            state == PlaybackState.STATE_BUFFERING ||
            state == PlaybackState.STATE_PAUSED
    }

    private fun calculatePositionMs(
        playbackState: PlaybackState?,
        durationMs: Long,
    ): Long {
        if (playbackState == null) {
            return 0L
        }

        val maxDuration = if (durationMs > 0L) durationMs else Long.MAX_VALUE
        val basePosition = playbackState.position.coerceAtLeast(0L)

        return if (playbackState.state == PlaybackState.STATE_PLAYING) {
            val elapsed = SystemClock.elapsedRealtime() - playbackState.lastPositionUpdateTime
            val speed = if (playbackState.playbackSpeed > 0f) playbackState.playbackSpeed else 1f
            (basePosition + (elapsed * speed).toLong()).coerceAtMost(maxDuration)
        } else {
            basePosition.coerceAtMost(maxDuration)
        }
    }

    private fun resetNotificationListener() {
        val componentName = ComponentName(this, NotificationListener::class.java)
        val pm = packageManager
        try {
            // Disable the component
            pm.setComponentEnabledSetting(
                componentName,
                android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                android.content.pm.PackageManager.DONT_KILL_APP
            )
            // Re-enable the component, forcing the system to rebind it
            Thread.sleep(100)
            pm.setComponentEnabledSetting(
                componentName,
                android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                android.content.pm.PackageManager.DONT_KILL_APP
            )
        } catch (e: Exception) {
            // Silent fallback
        }
    }
}
