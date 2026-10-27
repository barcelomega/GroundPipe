package com.barcelomega.groundpipe.player

import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.ln

@UnstableApi
class StretchAudioProcessor(
    private val createEngine: () -> StretchEngine = { AudioStretchProcessor() }
) : AudioProcessor {
    companion object {
        private const val TAG = "StretchAudioProcessor"
    }

    private var inputAudioFormat = AudioProcessor.AudioFormat.NOT_SET
    private var outputAudioFormat = AudioProcessor.AudioFormat.NOT_SET
    private var buffer = AudioProcessor.EMPTY_BUFFER
    private var isActive = false
    private var isEndOfStream = false

    private var stretchProcessor: StretchEngine? = null
    private var speed = 1.0f
    private var pitchShift = 0.0f
    private var inputFramesProcessed = 0L
    private var outputFramesProduced = 0L
    private var outputFrameRemainder = 0.0
    
    private var inputBuffer = FloatArray(0)
    private var outputBuffer = FloatArray(0)

    fun applyPlaybackParameters(parameters: PlaybackParameters): PlaybackParameters {
        ensureProcessor()
        val applied = if (stretchProcessor != null) {
            PlaybackParameters(
                parameters.speed.coerceIn(0.2f, 3.0f),
                parameters.pitch.coerceIn(0.5f, 2.0f)
            )
        } else {
            PlaybackParameters.DEFAULT
        }
        speed = applied.speed
        pitchShift = (12.0 * ln(applied.pitch.toDouble()) / ln(2.0)).toFloat()
        stretchProcessor?.setSpeed(speed)
        stretchProcessor?.setPitchShift(pitchShift)
        return applied
    }

    fun getMediaDuration(playoutDuration: Long): Long {
        return if (outputFramesProduced > 0L) {
            (playoutDuration.toDouble() * inputFramesProcessed / outputFramesProduced).toLong()
        } else {
            (playoutDuration.toDouble() * speed).toLong()
        }
    }

    private fun recordFrames(input: Int, output: Int) {
        inputFramesProcessed += input
        outputFramesProduced += output
    }
    
    private fun ensureProcessor() {
        if (stretchProcessor == null) {
            val processor = createEngine()
            if (processor.isInitialized()) {
                // Default to 48kHz stereo until configure is called
                val sampleRate = if (inputAudioFormat.sampleRate > 0) inputAudioFormat.sampleRate else 48000
                val channelCount = if (inputAudioFormat.channelCount > 0) inputAudioFormat.channelCount else 2
                processor.configure(sampleRate, channelCount)
                processor.setSpeed(speed)
                processor.setPitchShift(pitchShift)
                stretchProcessor = processor
                isActive = true
                Log.i(TAG, "Created processor eagerly: ${sampleRate}Hz, ${channelCount}ch")
            }
        }
    }

    override fun configure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        Log.i(TAG, "configure called: $inputAudioFormat")
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT) {
            throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        }

        this.inputAudioFormat = inputAudioFormat
        // Return 16-bit PCM to keep compatibility with other processors
        this.outputAudioFormat = inputAudioFormat
        
        // Recreate processor with actual audio format
        stretchProcessor?.release()
        stretchProcessor = null
        val processor = createEngine()
        if (processor.isInitialized()) {
            processor.configure(inputAudioFormat.sampleRate, inputAudioFormat.channelCount)
            processor.setSpeed(speed)
            processor.setPitchShift(pitchShift)
            stretchProcessor = processor
            isActive = true
            Log.i(TAG, "Processor configured: ${inputAudioFormat.sampleRate}Hz, ${inputAudioFormat.channelCount}ch")
        } else {
            isActive = false
            Log.w(TAG, "Processor init failed")
        }
        
        return this.outputAudioFormat
    }

    override fun isActive(): Boolean {
        // Always active so ExoPlayer routes audio through us
        // We'll do passthrough when speed=1.0 and pitch=0
        Log.d(TAG, "isActive called, returning true")
        return true
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        Log.d(TAG, "queueInput called: ${inputBuffer.remaining()} bytes, processor=$stretchProcessor, speed=$speed, pitch=$pitchShift")
        
        val size = inputBuffer.remaining()
        if (size == 0) {
            // Empty buffer, nothing to process
            return
        }
        
        // Passthrough if processor not yet initialized
        if (stretchProcessor == null) {
            if (buffer.capacity() < size) {
                buffer = ByteBuffer.allocateDirect(size).order(ByteOrder.nativeOrder())
            }
            buffer.clear()
            buffer.put(inputBuffer)
            buffer.flip()
            val frames = size / (2 * inputAudioFormat.channelCount)
            recordFrames(frames, frames)
            return
        }
        
        // Passthrough when no effects applied
        if (speed == 1.0f && pitchShift == 0.0f) {
            if (buffer.capacity() < size) {
                buffer = ByteBuffer.allocateDirect(size).order(ByteOrder.nativeOrder())
            }
            buffer.clear()
            buffer.put(inputBuffer)
            buffer.flip()
            val frames = size / (2 * inputAudioFormat.channelCount)
            recordFrames(frames, frames)
            return
        }

        Log.v(TAG, "queueInput: ${inputBuffer.remaining()} bytes, speed=$speed, pitch=$pitchShift")

        // Input is 16-bit PCM (2 bytes per sample)
        val frameCount = inputBuffer.remaining() / (2 * inputAudioFormat.channelCount)
        if (frameCount == 0) return

        val totalSamples = frameCount * inputAudioFormat.channelCount
        if (this.inputBuffer.size < totalSamples) {
            this.inputBuffer = FloatArray(totalSamples)
        }

        // Convert 16-bit PCM to float [-1.0, 1.0]
        val inputStart = inputBuffer.position()
        val shortBuffer = inputBuffer.asShortBuffer()
        for (i in 0 until totalSamples) {
            this.inputBuffer[i] = shortBuffer.get() / 32768.0f
        }
        inputBuffer.position(inputBuffer.position() + totalSamples * 2)

        // These frames are actual audio, not spare allocation capacity. Adding
        // padding here changes both the audible tempo and the reported time.
        // Carry fractional frames so rounding cannot accumulate across buffers.
        val exactOutputFrames = frameCount / speed.toDouble() + outputFrameRemainder
        val outputFrameCount = exactOutputFrames.toInt()
        outputFrameRemainder = exactOutputFrames - outputFrameCount
        val outputSamples = outputFrameCount * inputAudioFormat.channelCount
        
        if (outputBuffer.size < outputSamples) {
            outputBuffer = FloatArray(outputSamples)
        }

        try {
            stretchProcessor?.process(this.inputBuffer, outputBuffer, frameCount, outputFrameCount)

            val actualOutputSamples = outputFrameCount * inputAudioFormat.channelCount
            // Output as 16-bit PCM (2 bytes per sample)
            val outputByteCount = actualOutputSamples * 2
            
            if (buffer.capacity() < outputByteCount) {
                buffer = ByteBuffer.allocateDirect(outputByteCount).order(ByteOrder.nativeOrder())
            }

            buffer.clear()
            val outShortBuffer = buffer.asShortBuffer()
            // Convert float [-1.0, 1.0] back to 16-bit PCM
            for (i in 0 until actualOutputSamples) {
                val sample = (outputBuffer[i] * 32767.0f).toInt().coerceIn(-32768, 32767)
                outShortBuffer.put(sample.toShort())
            }
            buffer.limit(outputByteCount)
            recordFrames(frameCount, outputFrameCount)
        } catch (e: Exception) {
            Log.e(TAG, "Error processing audio", e)
            // Preserve the input and its time mapping if a buffer cannot be
            // stretched. Never return stale output from the previous buffer.
            inputBuffer.position(inputStart)
            if (buffer.capacity() < size) {
                buffer = ByteBuffer.allocateDirect(size).order(ByteOrder.nativeOrder())
            }
            buffer.clear()
            buffer.put(inputBuffer)
            buffer.flip()
            recordFrames(frameCount, frameCount)
            outputFrameRemainder = 0.0
        }
    }

    override fun queueEndOfStream() {
        isEndOfStream = true
        Log.d(TAG, "queueEndOfStream called")
    }

    override fun getOutput(): ByteBuffer {
        val outputBuffer = buffer
        Log.d(TAG, "getOutput called, returning ${outputBuffer.remaining()} bytes")
        buffer = AudioProcessor.EMPTY_BUFFER
        return outputBuffer
    }

    override fun isEnded(): Boolean {
        val ended = isEndOfStream && buffer === AudioProcessor.EMPTY_BUFFER
        Log.d(TAG, "isEnded called, returning $ended (EOS=$isEndOfStream, buffer empty=${buffer === AudioProcessor.EMPTY_BUFFER})")
        return ended
    }

    override fun flush() {
        Log.d(TAG, "flush called")
        buffer = AudioProcessor.EMPTY_BUFFER
        isEndOfStream = false
        inputFramesProcessed = 0L
        outputFramesProduced = 0L
        outputFrameRemainder = 0.0
        stretchProcessor?.reset()
    }

    override fun reset() {
        flush()
        stretchProcessor?.release()
        stretchProcessor = null
        inputAudioFormat = AudioProcessor.AudioFormat.NOT_SET
        outputAudioFormat = AudioProcessor.AudioFormat.NOT_SET
        isActive = false
        isEndOfStream = false
    }

}
