package com.barcelomega.groundpipe.player

import android.util.Log

class AudioStretchProcessor {
    companion object {
        private const val TAG = "AudioStretchProcessor"
        private var libraryLoaded = false
        
        init {
            try {
                System.loadLibrary("groundpipe_native")
                libraryLoaded = true
                Log.i(TAG, "Native library loaded successfully")
            } catch (e: UnsatisfiedLinkError) {
                Log.e(TAG, "Failed to load native library", e)
            }
        }
    }
    
    private var initialized = false
    
    init {
        if (libraryLoaded) {
            try {
                nativeInit()
                initialized = true
            } catch (e: UnsatisfiedLinkError) {
                Log.e(TAG, "Failed to initialize native processor", e)
            }
        }
    }
    
    fun isInitialized(): Boolean = initialized
    
    fun release() {
        nativeRelease()
    }
    
    fun configure(sampleRate: Int, channels: Int) {
        nativeConfigure(sampleRate, channels)
    }
    
    fun setSpeed(speed: Float) {
        Log.i(TAG, "setSpeed($speed)")
        nativeSetSpeed(speed)
    }
    
    fun setPitchShift(semitones: Float) {
        Log.i(TAG, "setPitchShift($semitones)")
        nativeSetPitchShift(semitones)
    }
    
    fun reset() {
        nativeReset()
    }
    
    fun process(input: FloatArray, output: FloatArray, inputFrames: Int, outputFrames: Int) {
        nativeProcess(input, output, inputFrames, outputFrames)
    }
    
    private external fun nativeInit()
    private external fun nativeRelease()
    private external fun nativeConfigure(sampleRate: Int, channels: Int)
    private external fun nativeSetSpeed(speed: Float)
    private external fun nativeSetPitchShift(semitones: Float)
    private external fun nativeReset()
    private external fun nativeProcess(input: FloatArray, output: FloatArray, inputFrames: Int, outputFrames: Int)
}
