package com.mo_dev.universal_pip

import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity
import java.util.concurrent.CopyOnWriteArraySet

open class UniversalPipActivity : FlutterActivity() {
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        UniversalPipModeDispatcher.notifyChanged(isInPictureInPictureMode)
    }
}

internal interface UniversalPipModeListener {
    fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean)
}

internal object UniversalPipModeDispatcher {
    private val listeners = CopyOnWriteArraySet<UniversalPipModeListener>()

    fun addListener(listener: UniversalPipModeListener) {
        listeners.add(listener)
    }

    fun removeListener(listener: UniversalPipModeListener) {
        listeners.remove(listener)
    }

    fun notifyChanged(isInPictureInPictureMode: Boolean) {
        listeners.forEach { listener ->
            listener.onPictureInPictureModeChanged(isInPictureInPictureMode)
        }
    }
}
