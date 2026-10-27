package com.barcelomega.groundpipe.player

import android.content.Context
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink

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
            // Signalsmith processes PCM16. Platform speed adjustment would
            // bypass the chain's timing or apply speed a second time.
            .setEnableFloatOutput(false)
            .setEnableAudioTrackPlaybackParams(false)
            .setAudioProcessorChain(StretchAudioProcessorChain(audioProcessor))
            .build()
    }
}
