package com.barcelomega.groundpipe.player

import android.app.PendingIntent
import android.content.Intent
import android.os.Bundle
import android.util.Log
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.NoOpCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.session.CommandButton
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import com.barcelomega.groundpipe.MainActivity
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import java.io.File

@UnstableApi
class PlaybackService : MediaSessionService() {

    companion object {
        @Volatile
        var instance: PlaybackService? = null
            private set

        private val LIKE_COMMAND = SessionCommand(
            "com.barcelomega.groundpipe.action.LIKE",
            Bundle.EMPTY
        )

        private fun likePreferences(liked: Boolean): List<CommandButton> {
            val button = CommandButton.Builder(
                if (liked) CommandButton.ICON_HEART_FILLED
                else CommandButton.ICON_HEART_UNFILLED
            )
                .setSessionCommand(LIKE_COMMAND)
                .setDisplayName(if (liked) "Unlike" else "Like")
                .setSlots(CommandButton.SLOT_OVERFLOW)
                .build()
            return listOf(button)
        }
    }

    private var mediaSession: MediaSession? = null
    private var mediaCache: SimpleCache? = null
    private var liked = false
    private var stretchProcessor: StretchAudioProcessor? = null

    override fun onCreate() {
        super.onCreate()

        // Keep playback data in the app cache directory. Only the current
        // track is retained; PlaybackBridge clears the previous one when the
        // user switches tracks.
        val cache = SimpleCache(
            File(cacheDir, "player_media"),
            NoOpCacheEvictor(),
            StandaloneDatabaseProvider(this)
        )
        PlaybackCache.cache = cache
        PlaybackCache.clearAll()
        mediaCache = cache

        val httpFactory = DefaultHttpDataSource.Factory()
            .setUserAgent(
                "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 " +
                    "(KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36"
            )
            .setDefaultRequestProperties(
                mapOf("Referer" to "https://www.newgrounds.com/")
            )
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(20_000)
            .setReadTimeoutMs(20_000)

        val upstream = DefaultDataSource.Factory(this, httpFactory)
        val cacheFactory = CacheDataSource.Factory()
            .setCache(cache)
            .setUpstreamDataSourceFactory(upstream)
            .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)

        val processor = StretchAudioProcessor()
        stretchProcessor = processor
        
        val innerPlayer = ExoPlayer.Builder(this)
            .setRenderersFactory(StretchRenderersFactory(this, processor))
            .setMediaSourceFactory(DefaultMediaSourceFactory(cacheFactory))
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                    .setUsage(C.USAGE_MEDIA)
                    .build(),
                true
            )
            .setHandleAudioBecomingNoisy(true)
            .build()

        val interceptPlayer = CommandInterceptPlayer(innerPlayer).apply {
            onNextRequested = { PlaybackBridge.instance?.emitCommand("next") }
            onPrevRequested = { PlaybackBridge.instance?.emitCommand("prev") }
        }

        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        liked = PlaybackBridge.instance?.isCurrentTrackLiked ?: false
        val session = MediaSession.Builder(this, interceptPlayer)
            .setSessionActivity(pendingIntent)
            .setCallback(object : MediaSession.Callback {
                override fun onConnect(
                    session: MediaSession,
                    controller: MediaSession.ControllerInfo
                ): MediaSession.ConnectionResult {
                    val commands =
                        MediaSession.ConnectionResult.DEFAULT_SESSION_COMMANDS.buildUpon()
                            .add(LIKE_COMMAND)
                            .build()
                    return MediaSession.ConnectionResult.AcceptedResultBuilder(session)
                        .setAvailableSessionCommands(commands)
                        .build()
                }

                override fun onPostConnect(
                    session: MediaSession,
                    controller: MediaSession.ControllerInfo
                ) {
                    session.setMediaButtonPreferences(likePreferences(liked))
                }

                override fun onCustomCommand(
                    session: MediaSession,
                    controller: MediaSession.ControllerInfo,
                    customCommand: SessionCommand,
                    args: Bundle
                ): ListenableFuture<SessionResult> {
                    if (customCommand.customAction == LIKE_COMMAND.customAction) {
                        PlaybackBridge.instance?.emitCommand("like")
                        return Futures.immediateFuture(
                            SessionResult(SessionResult.RESULT_SUCCESS)
                        )
                    }
                    return Futures.immediateFuture(
                        SessionResult(SessionResult.RESULT_ERROR_NOT_SUPPORTED)
                    )
                }
            })
            .build()

        mediaSession = session
        instance = this
        session.setMediaButtonPreferences(likePreferences(liked))
    }

    fun setLiked(liked: Boolean) {
        if (this.liked == liked) return
        this.liked = liked
        mediaSession?.setMediaButtonPreferences(likePreferences(liked))
    }

    fun setSpeed(speed: Float) {
        Log.i("PlaybackService", "setSpeed($speed), processor=$stretchProcessor")
        stretchProcessor?.setSpeed(speed)
    }

    fun setPitchShift(semitones: Float) {
        Log.i("PlaybackService", "setPitchShift($semitones), processor=$stretchProcessor")
        stretchProcessor?.setPitchShift(semitones)
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo) = mediaSession

    override fun onDestroy() {
        if (instance === this) instance = null
        mediaSession?.run { player.release(); release() }
        mediaSession = null
        stretchProcessor?.reset()
        stretchProcessor = null
        PlaybackCache.cache = null
        mediaCache?.release()
        mediaCache = null
        super.onDestroy()
    }
}
