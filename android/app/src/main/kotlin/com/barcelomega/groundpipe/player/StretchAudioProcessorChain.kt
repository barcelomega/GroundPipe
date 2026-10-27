package com.barcelomega.groundpipe.player

import androidx.media3.common.PlaybackParameters
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.AudioProcessorChain
import androidx.media3.common.util.UnstableApi

/** Lets Media3 map stretched output time back to the original track's time. */
@UnstableApi
class StretchAudioProcessorChain(
    private val processor: StretchAudioProcessor
) : AudioProcessorChain {
    override fun getAudioProcessors(): Array<AudioProcessor> = arrayOf(processor)

    // Media3 calls this on the playback thread after draining the old buffers,
    // and creates a position checkpoint for the new speed. Do not also run Sonic.
    override fun applyPlaybackParameters(parameters: PlaybackParameters): PlaybackParameters =
        processor.applyPlaybackParameters(parameters)

    override fun getMediaDuration(playoutDuration: Long): Long =
        processor.getMediaDuration(playoutDuration)

    override fun applySkipSilenceEnabled(skipSilenceEnabled: Boolean): Boolean = false

    override fun getSkippedOutputFrameCount(): Long = 0L
}
