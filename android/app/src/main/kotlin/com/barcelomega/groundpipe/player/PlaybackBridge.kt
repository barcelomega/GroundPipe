package com.barcelomega.groundpipe.player

import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor

class PlaybackBridge(private val context: Context, messenger: BinaryMessenger) {

    companion object {
        var instance: PlaybackBridge? = null
    }

    @Volatile
    var isCurrentTrackLiked = false
        private set

    private val methodChannel = MethodChannel(messenger, "ngmusic/player")
    private val eventChannel = EventChannel(messenger, "ngmusic/player/events")

    private var eventSink: EventChannel.EventSink? = null
    private var controller: MediaController? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val mainExecutor = Executor { cmd -> mainHandler.post(cmd) }
    private var positionRunnable: Runnable? = null

    // Last requested values. Kept here so a request made before the playback
    // service exists is applied once it connects (e.g. on a cold start).
    private var speed = 1.0f
    private var pitch = 0.0f

    private val playerListener = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            emit(mapOf("type" to "playing", "value" to isPlaying))
            if (isPlaying) startPositionUpdates() else stopPositionUpdates()
        }

        override fun onPlaybackStateChanged(state: Int) {
            val s = when (state) {
                Player.STATE_IDLE      -> "idle"
                Player.STATE_BUFFERING -> "buffering"
                Player.STATE_READY     -> "ready"
                Player.STATE_ENDED     -> "ended"
                else                   -> "idle"
            }
            emit(mapOf("type" to "state", "value" to s))
            if (state == Player.STATE_READY) {
                val dur = controller?.duration?.takeIf { it > 0 } ?: 0L
                emit(mapOf("type" to "duration", "value" to dur))
            }
        }
    }

    init {
        instance = this

        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                connectController()
            }
            override fun onCancel(arguments: Any?) {
                eventSink = null
                stopPositionUpdates()
            }
        })

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> {
                    val url = call.argument<String>("url")
                        ?: return@setMethodCallHandler result.error("BAD_ARGS", "url required", null)
                    play(
                        url = url,
                        title = call.argument<String>("title") ?: "",
                        artist = call.argument<String>("artist") ?: "",
                        artworkUri = call.argument<String>("artworkUri")
                    )
                    result.success(null)
                }
                "pause"     -> { controller?.pause(); result.success(null) }
                "resume"    -> { controller?.play();  result.success(null) }
                "stop"      -> { controller?.stop();  result.success(null) }
                "seek"      -> {
                    val pos = call.argument<Number>("position")?.toLong() ?: 0L
                    controller?.seekTo(pos)
                    emit(mapOf("type" to "position", "value" to pos))
                    result.success(null)
                }
                "getPosition" -> result.success(controller?.currentPosition ?: 0L)
                "setLiked" -> {
                    isCurrentTrackLiked = call.argument<Boolean>("liked") ?: false
                    PlaybackService.instance?.setLiked(isCurrentTrackLiked)
                    result.success(null)
                }
                "setSpeed" -> {
                    speed = call.argument<Double>("speed")?.toFloat() ?: 1.0f
                    Log.i("PlaybackBridge", "setSpeed($speed), service=${PlaybackService.instance}")
                    PlaybackService.instance?.setSpeed(speed)
                    result.success(null)
                }
                "setPitch" -> {
                    pitch = call.argument<Double>("pitch")?.toFloat() ?: 0.0f
                    Log.i("PlaybackBridge", "setPitch($pitch), service=${PlaybackService.instance}")
                    PlaybackService.instance?.setPitchShift(pitch)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun connectController() {
        val token = SessionToken(context, ComponentName(context, PlaybackService::class.java))
        val future = MediaController.Builder(context, token).buildAsync()
        future.addListener({
            try {
                controller?.removeListener(playerListener)
                controller = future.get()
                controller?.addListener(playerListener)
                // Apply any speed/pitch requested before the service was ready.
                PlaybackService.instance?.setSpeed(speed)
                PlaybackService.instance?.setPitchShift(pitch)
            } catch (_: Exception) {}
        }, mainExecutor)
    }

    private fun play(url: String, title: String, artist: String, artworkUri: String?) {
        stopPositionUpdates()
        emit(mapOf("type" to "duration", "value" to 0L))
        emit(mapOf("type" to "position", "value" to 0L))
        val meta = MediaMetadata.Builder()
            .setTitle(title)
            .setArtist(artist)
            .apply { artworkUri?.let { setArtworkUri(Uri.parse(it)) } }
            .build()
        val mediaItem = MediaItem.Builder()
            .setUri(url)
            .setMediaMetadata(meta)
            .build()
        controller?.run {
            setMediaItem(mediaItem)
            // Replace the previous track's cached data now that the player
            // has released it, keeping only the track that is being started.
            PlaybackCache.clearExcept(Uri.parse(url).toString())
            prepare()
            play()
        }
        startPositionUpdates()
    }

    private fun startPositionUpdates() {
        stopPositionUpdates()
        val r = object : Runnable {
            override fun run() {
                val c = controller
                if (c?.isPlaying == true) {
                    emit(mapOf("type" to "position", "value" to c.currentPosition))
                }
                mainHandler.postDelayed(this, 500)
            }
        }
        positionRunnable = r
        r.run()
    }

    private fun stopPositionUpdates() {
        positionRunnable?.let { mainHandler.removeCallbacks(it) }
        positionRunnable = null
    }

    fun emitCommand(cmd: String) {
        emit(mapOf("type" to "command", "value" to cmd))
    }

    private fun emit(data: Any) {
        mainHandler.post { eventSink?.success(data) }
    }

    fun release() {
        instance = null
        stopPositionUpdates()
        controller?.removeListener(playerListener)
        controller = null
    }
}
