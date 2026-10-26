package com.barcelomega.groundpipe.player

import android.content.Context
import android.os.Handler
import android.util.Log
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.audio.AudioRendererEventListener
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.audio.MediaCodecAudioRenderer
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.common.util.UnstableApi

@UnstableApi
class StretchRenderersFactory(
    context: Context,
    private val audioProcessor: StretchAudioProcessor
) : DefaultRenderersFactory(context) {

    override fun buildAudioSink(
        context: Context,
        enableFloatOutput: Boolean,
        enableAudioTrackPlaybackParams: Boolean
    ): AudioSink {
        return DefaultAudioSink.Builder(context)
            .setEnableFloatOutput(enableFloatOutput)
            .setEnableAudioTrackPlaybackParams(enableAudioTrackPlaybackParams)
            .setAudioProcessors(arrayOf(audioProcessor))
            .build()
    }

    override fun buildAudioRenderers(
        context: Context,
        extensionRendererMode: Int,
        mediaCodecSelector: MediaCodecSelector,
        enableDecoderFallback: Boolean,
        audioSink: AudioSink,
        eventHandler: Handler,
        eventListener: AudioRendererEventListener,
        out: ArrayList<Renderer>
    ) {
        Log.i("StretchRenderersFactory", "buildAudioRenderers called")
        val renderer = object : MediaCodecAudioRenderer(
            context,
            mediaCodecSelector,
            enableDecoderFallback,
            eventHandler,
            eventListener,
            audioSink
        ) {
            override fun onStreamChanged(
                formats: Array<androidx.media3.common.Format>,
                startPositionUs: Long,
                offsetUs: Long,
                mediaPeriodId: androidx.media3.exoplayer.source.MediaSource.MediaPeriodId
            ) {
                super.onStreamChanged(formats, startPositionUs, offsetUs, mediaPeriodId)
                Log.i("StretchRenderersFactory", "onStreamChanged called")
                audioProcessor.onStreamStarted()
            }
        }
        out.add(renderer)
    }
}
