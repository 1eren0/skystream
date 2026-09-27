package com.lingjhf.vlc_player

import android.util.Log
import org.videolan.libvlc.MediaPlayer

/// libVLC's crop, which libvlc-android 3.x does not expose in Java.
///
/// Backed by a small JNI shim - src/main/cpp/vlc_player_geometry.c - that
/// calls libvlc_video_set_crop_geometry with the player's native pointer.
/// Without the shim, Zoom still plays; its subtitles are laid out for the
/// whole picture instead of the part on screen.
internal object VlcNativeGeometry {
    private val available: Boolean = try {
        System.loadLibrary("vlc_player_geometry")
        true
    } catch (error: UnsatisfiedLinkError) {
        Log.w("VlcPlayer", "libVLC crop is unavailable: ${error.message}")
        false
    }

    /// Crops [player]'s picture to [geometry] - a `W:H` shape, or a `WxH+X+Y`
    /// region in video pixels - or lifts the crop when it is null. False when
    /// the crop could not be set.
    fun setCrop(player: MediaPlayer, geometry: String?): Boolean {
        if (!available) {
            return false
        }
        val instance = player.instance
        if (instance == 0L) {
            return false
        }
        return nativeSetCropGeometry(instance, geometry)
    }

    @JvmStatic
    private external fun nativeSetCropGeometry(player: Long, geometry: String?): Boolean
}
