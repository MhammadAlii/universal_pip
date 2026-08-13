package com.mo_dev.universal_pip

import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import java.util.concurrent.CopyOnWriteArraySet

open class UniversalPipActivity : FlutterActivity() {
    private var moveTaskToBackgroundAfterPipExit = false

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        UniversalPipModeDispatcher.notifyChanged(isInPictureInPictureMode)

        if (!isInPictureInPictureMode) {
            moveTaskToBackgroundIfRequested()
        }
    }

    /**
     * Removes the system PiP window without finishing this activity.
     *
     * Android has no direct leave-PiP API. Bringing the existing single-task
     * activity forward makes Android restore it from PiP; once that transition
     * completes, the task is moved to the background. The Flutter activity and
     * engine therefore remain alive for the next time the user opens the app.
     */
    fun hidePictureInPictureAndKeepTask(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            !isInPictureInPictureMode
        ) {
            return false
        }

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, this::class.java)
        launchIntent.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP,
        )

        moveTaskToBackgroundAfterPipExit = true
        return try {
            startActivity(launchIntent)

            // Some OEMs omit or delay the PiP callback after relaunching the
            // current task. This fallback only backgrounds an activity that is
            // already out of PiP, so it can never dismiss/finish the task.
            window.decorView.postDelayed(
                { moveTaskToBackgroundIfRequested() },
                PIP_EXIT_CALLBACK_FALLBACK_DELAY_MS,
            )
            true
        } catch (_: Exception) {
            moveTaskToBackgroundAfterPipExit = false
            false
        }
    }

    private fun moveTaskToBackgroundIfRequested() {
        if (!moveTaskToBackgroundAfterPipExit) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            isInPictureInPictureMode
        ) {
            return
        }

        moveTaskToBackgroundAfterPipExit = false
        window.decorView.post { moveTaskToBack(true) }
    }

    // Fires the instant the user navigates away (home/recents/app switch)
    // while this activity is still fully resumed and visible — unlike
    // Flutter's hidden/paused AppLifecycleState, which only arrive after
    // the activity has already started pausing/stopping. Entering PiP from
    // here is the officially reliable timing; entering it later (from
    // hidden/paused) can silently no-op on some OS versions until the
    // activity is resumed again.
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        UniversalPipModeDispatcher.notifyUserLeaveHint()
    }

    private companion object {
        const val PIP_EXIT_CALLBACK_FALLBACK_DELAY_MS = 300L
    }
}

internal interface UniversalPipModeListener {
    fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean)
    fun onUserLeaveHint() {}
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

    fun notifyUserLeaveHint() {
        listeners.forEach { listener -> listener.onUserLeaveHint() }
    }
}
