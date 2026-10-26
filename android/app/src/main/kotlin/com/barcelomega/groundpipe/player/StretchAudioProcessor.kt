package com.barcelomega.groundpipe.player

import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import java.nio.ByteOrder

@UnstableApi
class StretchAudioProcessor : AudioProcessor {
    companion object {
        private const val TAG = "StretchAudioProcessor"
    }

    private var inputAudioFormat = AudioProcessor.AudioFormat.NOT_SET
    private var outputAudioFormat = AudioProcessor.AudioFormat.NOT_SET
    private var buffer = AudioProcessor.EMPTY_BUFFER
    private var isActive = false
    private var pendingInputAudioFormat = AudioProcessor.AudioFormat.NOT_SET
    private var isEndOfStream = false

    private var stretchProcessor: AudioStretchProcessor? = null
    private var speed = 1.0f
    private var pitchShift = 0.0f
    
    private var inputBuffer = FloatArray(0)
    private var outputBuffer = FloatArray(0)

    fun setSpeed(speed: Float) {
        this.speed = speed
        ensureProcessor()
        stretchProcessor?.setSpeed(speed)
        Log.i(TAG, "setSpeed($speed), processor=$stretchProcessor")
    }

    fun setPitchShift(semitones: Float) {
        this.pitchShift = semitones
        ensureProcessor()
        stretchProcessor?.setPitchShift(semitones)
        Log.i(TAG, "setPitchShift($semitones), processor=$stretchProcessor")
    }
    
    private fun ensureProcessor() {
        if (stretchProcessor == null) {
            val processor = AudioStretchProcessor()
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

        pendingInputAudioFormat = inputAudioFormat
        this.inputAudioFormat = inputAudioFormat
        // Return 16-bit PCM to keep compatibility with other processors
        this.outputAudioFormat = inputAudioFormat
        
        // Recreate processor with actual audio format
        stretchProcessor?.release()
        val processor = AudioStretchProcessor()
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
        val shortBuffer = inputBuffer.asShortBuffer()
        for (i in 0 until totalSamples) {
            this.inputBuffer[i] = shortBuffer.get() / 32768.0f
        }
        inputBuffer.position(inputBuffer.position() + totalSamples * 2)

        // Calculate output frame count based on speed
        val outputFrameCount = (frameCount / speed).toInt() + 128 // Extra frames for safety
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
        } catch (e: Exception) {
            Log.e(TAG, "Error processing audio", e)
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
        stretchProcessor?.reset()
    }

    override fun reset() {
        flush()
        stretchProcessor?.release()
        stretchProcessor = null
        inputAudioFormat = AudioProcessor.AudioFormat.NOT_SET
        outputAudioFormat = AudioProcessor.AudioFormat.NOT_SET
        pendingInputAudioFormat = AudioProcessor.AudioFormat.NOT_SET
        isActive = false
        isEndOfStream = false
    }

    fun onStreamStarted() {
        Log.i(TAG, "onStreamStarted: pending=$pendingInputAudioFormat, current=$inputAudioFormat")
        if (pendingInputAudioFormat != AudioProcessor.AudioFormat.NOT_SET && 
            pendingInputAudioFormat != inputAudioFormat) {
            
            inputAudioFormat = pendingInputAudioFormat
            // Keep 16-bit PCM format
            outputAudioFormat = inputAudioFormat

            // Always create processor, check speed/pitch in process()
            try {
                stretchProcessor?.release()
                val processor = AudioStretchProcessor()
                if (processor.isInitialized()) {
                    processor.apply {
                        configure(inputAudioFormat.sampleRate, inputAudioFormat.channelCount)
                        setSpeed(speed)
                        setPitchShift(pitchShift)
                    }
                    stretchProcessor = processor
                    isActive = true
                    Log.i(TAG, "Processor configured: ${inputAudioFormat.sampleRate}Hz, ${inputAudioFormat.channelCount}ch, speed=$speed, pitch=$pitchShift")
                } else {
                    Log.w(TAG, "Native processor not initialized, passthrough mode")
                    isActive = false
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to initialize audio processor", e)
                isActive = false
            }
        }
    }
}
