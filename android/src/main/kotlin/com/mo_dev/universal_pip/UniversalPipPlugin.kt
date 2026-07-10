package com.mo_dev.universal_pip

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Rect
import android.os.Build
import android.util.Rational
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.plugins.lifecycle.FlutterLifecycleAdapter
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

class UniversalPipPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware {
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel

    private var activity: Activity? = null
    private var lifecycle: Lifecycle? = null
    private var eventSink: EventChannel.EventSink? = null
    private var pipEnabled = false
    private var aspectRatio = 16.0 / 9.0
    private var sourceRectHint: Rect? = null

    private val lifecycleObserver =
        LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME || event == Lifecycle.Event.ON_PAUSE) {
                emitPipMode()
            }
        }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(binding.binaryMessenger, "universal_pip/methods")
        eventChannel = EventChannel(binding.binaryMessenger, "universal_pip/events")
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        lifecycle = FlutterLifecycleAdapter.getActivityLifecycle(binding).also {
            it.addObserver(lifecycleObserver)
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        detachActivity()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSystemPipSupported" -> result.success(isPipSupported())
            "configureSystemPip" -> {
                pipEnabled = call.argument<Boolean>("enabled") == true
                aspectRatio = call.argument<Double>("aspectRatio") ?: aspectRatio
                updatePipParams()
                result.success(null)
            }
            "updateSourceRectHint" -> {
                sourceRectHint = sourceRectFromCall(call)
                updatePipParams()
                result.success(null)
            }
            "enterSystemPip" -> result.success(enterPip())
            "exitSystemPip" -> result.success(exitPip())
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        emitPipMode()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun detachActivity() {
        lifecycle?.removeObserver(lifecycleObserver)
        lifecycle = null
        activity = null
    }

    private fun enterPip(): Boolean {
        val currentActivity = activity ?: return false
        if (!pipEnabled || !isPipSupported()) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            currentActivity.isInPictureInPictureMode
        ) {
            emitPipMode()
            return true
        }

        return try {
            val entered = currentActivity.enterPictureInPictureMode(buildPipParams())
            emitPipMode()
            entered
        } catch (_: Exception) {
            false
        }
    }

    private fun exitPip(): Boolean {
        val currentActivity = activity ?: return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            !currentActivity.isInPictureInPictureMode
        ) {
            emitPipMode()
            return false
        }

        return try {
            val intent = Intent(currentActivity, currentActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            currentActivity.startActivity(intent)
            emitPipMode()
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun updatePipParams() {
        val currentActivity = activity ?: return
        if (!isPipSupported()) return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        try {
            currentActivity.setPictureInPictureParams(buildPipParams())
        } catch (_: Exception) {
            // Some devices reject PiP params until the activity is fully resumed.
        }
    }

    private fun buildPipParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(aspectRatio.toRational())

        sourceRectHint?.let { builder.setSourceRectHint(it) }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(pipEnabled)
        }

        return builder.build()
    }

    private fun isPipSupported(): Boolean {
        val currentActivity = activity ?: return false
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            currentActivity.packageManager.hasSystemFeature(
                PackageManager.FEATURE_PICTURE_IN_PICTURE
            )
    }

    private fun sourceRectFromCall(call: MethodCall): Rect? {
        val left = call.argument<Int>("left")
        val top = call.argument<Int>("top")
        val right = call.argument<Int>("right")
        val bottom = call.argument<Int>("bottom")
        return if (
            left != null &&
            top != null &&
            right != null &&
            bottom != null &&
            right > left &&
            bottom > top
        ) {
            Rect(left, top, right, bottom)
        } else {
            null
        }
    }

    private fun emitPipMode() {
        val currentActivity = activity
        val isInPip =
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                currentActivity?.isInPictureInPictureMode == true
        eventSink?.success(isInPip)
    }

    private fun Double.toRational(): Rational {
        val safeRatio = coerceIn(0.42, 2.39)
        val width = 1000
        val height = (width / safeRatio).roundToInt().coerceAtLeast(1)
        return Rational(width, height)
    }
}
