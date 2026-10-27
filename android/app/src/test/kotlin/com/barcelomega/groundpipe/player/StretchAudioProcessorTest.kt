package com.barcelomega.groundpipe.player

import androidx.media3.common.C
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import org.junit.Assert.*
import org.junit.Test

@UnstableApi
class StretchAudioProcessorTest {
    private class FakeEngine(private val initialized: Boolean = true) : StretchEngine {
        var requestedSpeed = 1f
        var requestedPitch = 0f
        var channels = 2
        var failProcessing = false

        override fun isInitialized() = initialized
        override fun release() {}
        override fun configure(sampleRate: Int, channels: Int) { this.channels = channels }
        override fun setSpeed(speed: Float) { requestedSpeed = speed }
        override fun setPitchShift(semitones: Float) { requestedPitch = semitones }
        override fun reset() {}
        override fun process(
            input: FloatArray, output: FloatArray, inputFrames: Int, outputFrames: Int
        ) {
            if (failProcessing) error("Simulated native processing failure")
            output.fill(0f, 0, outputFrames * channels)
        }
    }

    private class Pipeline(val engine: FakeEngine = FakeEngine()) {
        val processor = StretchAudioProcessor { engine }
        val chain = StretchAudioProcessorChain(processor)

        init {
            processor.configure(AudioProcessor.AudioFormat(48_000, 2, C.ENCODING_PCM_16BIT))
        }

        fun parameters(speed: Float, pitch: Float = 1f): PlaybackParameters {
            val applied = chain.applyPlaybackParameters(PlaybackParameters(speed, pitch))
            // This is Media3's sequence at startup, on seek and at speed checkpoints.
            processor.flush()
            return applied
        }

        fun process(frames: Int): Int {
            val input = ByteBuffer.allocateDirect(frames * 4).order(ByteOrder.nativeOrder())
            processor.queueInput(input)
            assertFalse("All input must be consumed", input.hasRemaining())
            return processor.output.remaining() / 4
        }
    }

    @Test
    fun halfSpeedProducesDoubleAudioAndHalfMediaTime() {
        val pipeline = Pipeline()
        assertEquals(0.5f, pipeline.parameters(0.5f).speed, 0f)
        assertEquals(96_000, pipeline.process(48_000))
        assertEquals(500_000L, pipeline.chain.getMediaDuration(1_000_000L))
        assertEquals(1_000_000L, pipeline.chain.getMediaDuration(2_000_000L))
        assertEquals(0.5f, pipeline.engine.requestedSpeed, 0f)
    }

    @Test
    fun doubleSpeedProducesHalfAudioAndDoubleMediaTime() {
        val pipeline = Pipeline()
        assertEquals(2f, pipeline.parameters(2f).speed, 0f)
        assertEquals(24_000, pipeline.process(48_000))
        assertEquals(2_000_000L, pipeline.chain.getMediaDuration(1_000_000L))
    }

    @Test
    fun pitchAloneDoesNotChangeDurationOrAddPaddingFrames() {
        val pipeline = Pipeline()
        pipeline.parameters(speed = 1f, pitch = 2f)
        assertEquals(48_000, pipeline.process(48_000))
        assertEquals(1_000_000L, pipeline.chain.getMediaDuration(1_000_000L))
        assertEquals(12f, pipeline.engine.requestedPitch, 0.0001f)
    }

    @Test
    fun fractionalFramesDoNotAccumulateDriftAcrossSmallBuffers() {
        for (speed in listOf(0.2f, 0.75f, 1.25f, 3f)) {
            val pipeline = Pipeline()
            pipeline.parameters(speed)
            var outputFrames = 0L
            repeat(3_000) { outputFrames += pipeline.process(1024) }
            val expectedFrames = 3_000L * 1024 / speed.toDouble()
            assertTrue("Rounding drift at $speed", abs(outputFrames - expectedFrames) <= 1.01)
            val expectedTime = 1_000_000 * speed.toDouble()
            assertEquals(expectedTime, pipeline.chain.getMediaDuration(1_000_000L).toDouble(), 10.0)
        }
    }

    @Test
    fun seekAndSpeedChangeResetTheMappingWithoutReusingEarlierFrames() {
        val pipeline = Pipeline()
        pipeline.parameters(0.5f)
        pipeline.process(48_000)
        assertEquals(500_000L, pipeline.chain.getMediaDuration(1_000_000L))

        // Drained old audio is anchored by DefaultAudioSink's position checkpoint.
        pipeline.processor.queueEndOfStream()
        assertTrue(pipeline.processor.isEnded)
        pipeline.parameters(2f)
        assertFalse(pipeline.processor.isEnded)
        assertEquals(2_000_000L, pipeline.chain.getMediaDuration(1_000_000L))
        pipeline.process(48_000)
        assertEquals(2_000_000L, pipeline.chain.getMediaDuration(1_000_000L))

        // Seeking clears the frame counters but retains the selected speed.
        pipeline.processor.flush()
        assertEquals(2_000_000L, pipeline.chain.getMediaDuration(1_000_000L))
        pipeline.process(12_000)
        assertEquals(2_000_000L, pipeline.chain.getMediaDuration(1_000_000L))

        pipeline.parameters(1f)
        assertEquals(48_000, pipeline.process(48_000))
        assertEquals(1_000_000L, pipeline.chain.getMediaDuration(1_000_000L))
    }

    @Test
    fun unavailableNativeEngineReportsNormalSpeedForPassthrough() {
        val pipeline = Pipeline(FakeEngine(initialized = false))
        assertEquals(PlaybackParameters.DEFAULT, pipeline.parameters(0.5f, 2f))
        assertEquals(48_000, pipeline.process(48_000))
        assertEquals(1_000_000L, pipeline.chain.getMediaDuration(1_000_000L))
    }

    @Test
    fun processingFailurePreservesInputAndMapsTheActualOutputDuration() {
        val pipeline = Pipeline()
        pipeline.parameters(0.5f)
        pipeline.engine.failProcessing = true
        assertEquals(48_000, pipeline.process(48_000))
        assertEquals(1_000_000L, pipeline.chain.getMediaDuration(1_000_000L))
    }

    @Test
    fun chainDoesNotApplyAnotherSpeedProcessorOrSkipFrames() {
        val pipeline = Pipeline()
        assertArrayEquals(arrayOf<AudioProcessor>(pipeline.processor), pipeline.chain.audioProcessors)
        assertFalse(pipeline.chain.applySkipSilenceEnabled(true))
        assertEquals(0L, pipeline.chain.skippedOutputFrameCount)
    }
}
