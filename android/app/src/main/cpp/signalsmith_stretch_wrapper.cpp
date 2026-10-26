#include <jni.h>
#include <android/log.h>
#include <vector>
#include <cmath>
#include <memory>

#define LOG_TAG "SignalsmithStretch"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Signalsmith-Audio stretch library (header-only)
// We'll download this header separately
#include "signalsmith-stretch.h"

class AudioProcessor {
private:
    std::unique_ptr<signalsmith::stretch::SignalsmithStretch<float>> stretcher;
    int sampleRate;
    int channels;
    float currentSpeed;
    float currentPitchShift;
    bool needsReset;
    
public:
    AudioProcessor() : sampleRate(44100), channels(2), currentSpeed(1.0f), 
                       currentPitchShift(0.0f), needsReset(false) {
        stretcher = std::make_unique<signalsmith::stretch::SignalsmithStretch<float>>();
        stretcher->presetDefault(channels, sampleRate);
    }
    
    void configure(int rate, int numChannels) {
        if (rate != sampleRate || numChannels != channels) {
            sampleRate = rate;
            channels = numChannels;
            stretcher->presetDefault(channels, sampleRate);
            needsReset = true;
        }
    }
    
    void setSpeed(float speed) {
        if (std::abs(currentSpeed - speed) > 0.001f) {
            currentSpeed = speed;
            needsReset = true;
        }
    }
    
    void setPitchShift(float semitones) {
        if (std::abs(currentPitchShift - semitones) > 0.01f) {
            currentPitchShift = semitones;
            needsReset = true;
        }
    }
    
    float getSpeed() const { return currentSpeed; }
    float getPitchShift() const { return currentPitchShift; }
    
    void reset() {
        stretcher->reset();
        needsReset = false;
    }
    
    void process(const float* input, float* output, int inputFrames, int outputFrames) {
        if (needsReset) {
            reset();
        }
        
        // Calculate the pitch scale factor (2^(semitones/12))
        float pitchScale = std::pow(2.0f, currentPitchShift / 12.0f);
        
        // Combined rate: speed affects time, pitch affects frequency
        // When chained: both change together proportionally
        float timeRatio = currentSpeed;
        float pitchRatio = pitchScale;
        
        stretcher->setTransposeFactor(pitchRatio, timeRatio);
        
        // Process audio through the stretcher
        // Input: interleaved samples [L, R, L, R, ...]
        // The library expects separate channel buffers
        std::vector<std::vector<float>> inputBuffers(channels);
        std::vector<std::vector<float>> outputBuffers(channels);
        
        for (int c = 0; c < channels; ++c) {
            inputBuffers[c].resize(inputFrames);
            outputBuffers[c].resize(outputFrames);
            
            // De-interleave
            for (int i = 0; i < inputFrames; ++i) {
                inputBuffers[c][i] = input[i * channels + c];
            }
        }
        
        // Process
        std::vector<float*> inputPtrs(channels);
        std::vector<float*> outputPtrs(channels);
        for (int c = 0; c < channels; ++c) {
            inputPtrs[c] = inputBuffers[c].data();
            outputPtrs[c] = outputBuffers[c].data();
        }
        
        stretcher->process(inputPtrs.data(), inputFrames, outputPtrs.data(), outputFrames);
        
        // Re-interleave
        for (int i = 0; i < outputFrames; ++i) {
            for (int c = 0; c < channels; ++c) {
                output[i * channels + c] = outputBuffers[c][i];
            }
        }
    }
};

static AudioProcessor* g_processor = nullptr;

extern "C" {

JNIEXPORT void JNICALL
Java_com_barcelomega_groundpipe_player_AudioStretchProcessor_nativeInit(JNIEnv* env, jobject obj) {
    if (g_processor == nullptr) {
        g_processor = new AudioProcessor();
        LOGI("AudioProcessor initialized");
    }
}

JNIEXPORT void JNICALL
Java_com_barcelomega_groundpipe_player_AudioStretchProcessor_nativeRelease(JNIEnv* env, jobject obj) {
    if (g_processor != nullptr) {
        delete g_processor;
        g_processor = nullptr;
        LOGI("AudioProcessor released");
    }
}

JNIEXPORT void JNICALL
Java_com_barcelomega_groundpipe_player_AudioStretchProcessor_nativeConfigure(
    JNIEnv* env, jobject obj, jint sampleRate, jint channels) {
    if (g_processor != nullptr) {
        g_processor->configure(sampleRate, channels);
        LOGI("Configured: rate=%d, channels=%d", sampleRate, channels);
    }
}

JNIEXPORT void JNICALL
Java_com_barcelomega_groundpipe_player_AudioStretchProcessor_nativeSetSpeed(
    JNIEnv* env, jobject obj, jfloat speed) {
    if (g_processor != nullptr) {
        g_processor->setSpeed(speed);
        LOGI("Speed set to %.2f", speed);
    }
}

JNIEXPORT void JNICALL
Java_com_barcelomega_groundpipe_player_AudioStretchProcessor_nativeSetPitchShift(
    JNIEnv* env, jobject obj, jfloat semitones) {
    if (g_processor != nullptr) {
        g_processor->setPitchShift(semitones);
        LOGI("Pitch shift set to %.1f semitones", semitones);
    }
}

JNIEXPORT void JNICALL
Java_com_barcelomega_groundpipe_player_AudioStretchProcessor_nativeReset(JNIEnv* env, jobject obj) {
    if (g_processor != nullptr) {
        g_processor->reset();
        LOGI("Processor reset");
    }
}

JNIEXPORT void JNICALL
Java_com_barcelomega_groundpipe_player_AudioStretchProcessor_nativeProcess(
    JNIEnv* env, jobject obj, jfloatArray inputArray, jfloatArray outputArray, 
    jint inputFrames, jint outputFrames) {
    
    if (g_processor == nullptr) {
        LOGE("Processor not initialized");
        return;
    }
    
    jfloat* input = env->GetFloatArrayElements(inputArray, nullptr);
    jfloat* output = env->GetFloatArrayElements(outputArray, nullptr);
    
    if (input != nullptr && output != nullptr) {
        g_processor->process(input, output, inputFrames, outputFrames);
    }
    
    if (input != nullptr) {
        env->ReleaseFloatArrayElements(inputArray, input, 0);
    }
    if (output != nullptr) {
        env->ReleaseFloatArrayElements(outputArray, output, 0);
    }
}

} // extern "C"
