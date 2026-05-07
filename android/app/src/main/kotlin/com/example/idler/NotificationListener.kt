package com.example.idler

import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.annotation.RequiresApi
import android.util.Base64
import android.util.Log
import java.io.ByteArrayOutputStream

@RequiresApi(Build.VERSION_CODES.JELLY_BEAN_MR2)
class NotificationListener : NotificationListenerService() {
    
    companion object {
        private var instance: NotificationListener? = null
        private val notifications = mutableListOf<Map<String, String>>()
        private const val TAG = "NotificationListener"
        
        fun getNotifications(): List<Map<String, String>> {
            return notifications.toList()
        }

        fun isListenerActive(): Boolean {
            return instance != null
        }
        
        fun removeNotification(pkg: String, title: String, key: String? = null): Boolean {
            val notification = if (!key.isNullOrEmpty()) {
                notifications.find { it["key"] == key }
            } else {
                notifications.find { it["package"] == pkg && it["title"] == title }
            }
            val resolvedKey = notification?.get("key")
            
            if (resolvedKey != null && instance != null) {
                try {
                    Log.d(TAG, "Cancelling notification by key: $resolvedKey")
                    instance?.cancelNotification(resolvedKey)
                    notifications.removeAll { it["key"] == resolvedKey }
                    return true
                } catch (e: Exception) {
                    // Fallback to just removing from list
                }
            }
            
            val before = notifications.size
            notifications.removeAll { it["package"] == pkg && it["title"] == title }
            return notifications.size < before
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        Log.d(TAG, "onCreate: listener created")
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        Log.d(TAG, "onDestroy: listener destroyed")
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
        notifications.clear()
        Log.d(TAG, "onListenerConnected: listener connected, cleared cache")
        
        // Initial fetch of notifications
        val activeNotifications = try {
            activeNotifications
        } catch (e: Exception) {
            null
        }

        activeNotifications?.forEach { sbn ->
            processNotification(sbn)
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        Log.d(TAG, "onNotificationPosted: ${sbn.packageName} / ${sbn.key}")
        processNotification(sbn)
    }

    private fun processNotification(sbn: StatusBarNotification) {
        // Filter out media notifications
        if (isMediaNotification(sbn)) {
            return
        }
        
        val notification = sbn.notification
        val extras = notification.extras
        
        val title = extras.getString(android.app.Notification.EXTRA_TITLE) 
            ?: notification.tickerText?.toString() 
            ?: ""
        val text = extras.getString(android.app.Notification.EXTRA_TEXT) ?: ""
        
        if (title.isEmpty() && text.isEmpty()) {
            return
        }

        val iconBase64 = getAppIconBase64(sbn.packageName)
        
        // Remove existing with same key to avoid duplicates
        notifications.removeAll { it["key"] == sbn.key }
        
        // Keep only last 5 notifications
        if (notifications.size >= 5) {
            notifications.removeAt(0)
        }
        
        notifications.add(mapOf(
            "title" to title,
            "body" to text,
            "package" to sbn.packageName,
            "iconBase64" to iconBase64,
            "key" to sbn.key
        ))
    }

    private fun getAppIconBase64(packageName: String): String {
        return try {
            val drawable = packageManager.getApplicationIcon(packageName)
            val bitmap = Bitmap.createBitmap(
                drawable.intrinsicWidth.coerceAtLeast(1),
                drawable.intrinsicHeight.coerceAtLeast(1),
                Bitmap.Config.ARGB_8888
            )
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)

            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
        } catch (_: Exception) {
            ""
        }
    }
    
    private fun isMediaNotification(sbn: StatusBarNotification): Boolean {
        val packageName = sbn.packageName
        
        // Known media player packages to exclude
        val mediaPackages = setOf(
            "com.spotify.music",
            "com.google.android.music",
            "com.apple.android.music",
            "com.amazon.mp3",
            "com.pandora.android",
            "com.deezer.android",
            "com.google.android.youtube",
            "com.youtube.android.tv",
            "com.android.music",
            "com.sec.android.app.music"
        )
        
        if (packageName in mediaPackages) {
            return true
        }
        
        // Check for media-related notification extras
        val notification = sbn.notification
        val extras = notification.extras
        
        // Media notifications often have these extras
        val hasMediaActions = extras.containsKey("android.app.Notification.EXTRA_ACTIONS") ||
                             extras.containsKey("android.media.app.NotificationCompat.EXTRA_ACTIONS") ||
                             notification.actions?.isNotEmpty() == true
        
        val title = extras.getString(android.app.Notification.EXTRA_TITLE) ?: ""
        
        // Filter out notifications that look like they control media (playback control words)
        val mediaControlKeywords = listOf("playing", "paused", "stopped", "spotify", "music", "podcast")
        val lowerTitle = title.lowercase()
        if (mediaControlKeywords.any { lowerTitle.contains(it) }) {
            return true
        }
        
        return hasMediaActions
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        Log.d(TAG, "onNotificationRemoved: ${sbn.packageName} / ${sbn.key}")
        notifications.removeAll { it["key"] == sbn.key }
    }
}
