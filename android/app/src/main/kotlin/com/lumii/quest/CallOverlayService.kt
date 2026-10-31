package com.lumii.quest

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.Shader
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.WindowManager
import android.widget.ImageView
import java.net.HttpURLConnection
import java.net.URL

/**
 * Foreground service that shows a draggable, circular profile-picture bubble
 * over every app while a call is active.
 */
class CallOverlayService : Service() {

    companion object {
        private const val CHANNEL_ID = "lumii_call_overlay"
        private const val NOTIFICATION_ID = 2001

        fun show(context: Context, avatarUrl: String, name: String) {
            val intent = Intent(context, CallOverlayService::class.java)
            intent.putExtra("avatarUrl", avatarUrl)
            intent.putExtra("name", name)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun hide(context: Context) {
            context.stopService(Intent(context, CallOverlayService::class.java))
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var windowManager: WindowManager
    private var imageView: ImageView? = null
    private var layoutParams: WindowManager.LayoutParams? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val avatarUrl = intent?.getStringExtra("avatarUrl") ?: ""
        val name = intent?.getStringExtra("name") ?: "Lumii Call"

        startAsForeground(name)
        createOverlay(avatarUrl)

        return START_NOT_STICKY
    }

    private fun startAsForeground(name: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Lumii Call", NotificationManager.IMPORTANCE_LOW)
            )
        }

        val tapIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
            .setContentTitle("Lumii Call")
            .setContentText(name)
            .setSmallIcon(applicationInfo.icon)
            .setContentIntent(tapIntent)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createOverlay(avatarUrl: String) {
        val imageView = ImageView(this)
        imageView.scaleType = ImageView.ScaleType.CENTER_CROP

        val size = dpToPx(64)
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            size,
            size,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.TOP or Gravity.START
        params.x = dpToPx(8)
        params.y = dpToPx(140)

        windowManager.addView(imageView, params)
        this.imageView = imageView
        this.layoutParams = params

        enableDrag(imageView, params)

        if (avatarUrl.isNotEmpty()) {
            loadAvatar(avatarUrl) { bitmap ->
                imageView.setImageBitmap(toCircular(bitmap))
            }
        }
    }

    private fun enableDrag(imageView: ImageView, params: WindowManager.LayoutParams) {
        var startX = 0
        var startY = 0
        var touchStartX = 0f
        var touchStartY = 0f

        imageView.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    startX = params.x
                    startY = params.y
                    touchStartX = event.rawX
                    touchStartY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    params.x = startX + (event.rawX - touchStartX).toInt()
                    params.y = startY + (event.rawY - touchStartY).toInt()
                    windowManager.updateViewLayout(imageView, params)
                    true
                }
                else -> false
            }
        }
    }

    private fun loadAvatar(url: String, onLoaded: (Bitmap) -> Unit) {
        Thread {
            try {
                val connection = URL(url).openConnection() as HttpURLConnection
                connection.connectTimeout = 10000
                connection.readTimeout = 10000
                connection.connect()
                val bitmap = BitmapFactory.decodeStream(connection.inputStream)
                connection.disconnect()
                if (bitmap != null) {
                    mainHandler.post { onLoaded(bitmap) }
                }
            } catch (_: Exception) {
                // Ignore; leave the bubble empty.
            }
        }.start()
    }

    private fun toCircular(source: Bitmap): Bitmap {
        val size = minOf(source.width, source.height)
        val square = Bitmap.createBitmap(
            source,
            (source.width - size) / 2,
            (source.height - size) / 2,
            size,
            size
        )
        val output = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.shader = BitmapShader(square, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
        val rect = RectF(0f, 0f, size.toFloat(), size.toFloat())
        canvas.drawOval(rect, paint)
        return output
    }

    private fun dpToPx(dp: Int): Int = (dp * resources.displayMetrics.density).toInt()

    override fun onDestroy() {
        imageView?.let { windowManager.removeView(it) }
        imageView = null
        layoutParams = null
        super.onDestroy()
    }
}
