// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "DistrhoPlugin.hpp"
#include "extra/ValueSmoother.hpp"

#include "FaustParameters.hpp"

#include <atomic>

#if LIBREAUDIO_WANT_SPEECH_DETECTION
#include "LibreAudioSpeechDetection.hpp"
#endif

struct FaustDSP;

/* TODO
 * - convert common IO to C++
 */

// --------------------------------------------------------------------------------------------------------------------

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioPlugin : public Plugin
{
   #ifdef LIBREAUDIO_BLOCK_SIZE
    static constexpr const uint32_t kInternalBlockSize = LIBREAUDIO_BLOCK_SIZE;
   #else
    static constexpr const uint32_t kInternalBlockSize = 32;
   #endif

public:
    LibreAudioPlugin();
    ~LibreAudioPlugin() override;

protected:
   /* -----------------------------------------------------------------------------------------------------------------
    * Information */

   /**
      Get the plugin version, in hexadecimal.
    */
    uint32_t getVersion() const noexcept final
    {
        return d_version(VERSION_MAJOR, VERSION_MINOR, VERSION_PATCH);
    }

   /* -----------------------------------------------------------------------------------------------------------------
    * Init */

   /**
      Initialize the parameter @a index.
      This function will be called once, shortly after the plugin is created.
    */
    void initParameter(uint32_t index, Parameter& parameter) final;

  #ifndef _DARKGLASS_DEVICE_PABLITO
   /**
      Initialize the state @a index.
      This function will be called once, shortly after the plugin is created.
    */
    void initState(uint32_t index, State& state) final;
  #endif

   /**
      Initialize the port group @a groupId.
      This function will be called once,
      shortly after the plugin is created and all audio ports and parameters have been enumerated.
    */
    void initPortGroup(uint32_t groupId, PortGroup& portGroup) final;

   /* -----------------------------------------------------------------------------------------------------------------
    * Internal data */

   /**
      Get the current value of a parameter.
      The host may call this function from any context, including realtime processing.
    */
    float getParameterValue(uint32_t index) const final;

   /**
      Change a parameter value.
      The host may call this function from any context, including realtime processing.
      When a parameter is marked as automatable, you must ensure no non-realtime operations are performed.
      @note This function will only be called for parameter inputs.
    */
    void setParameterValue(uint32_t index, float value) final;

  #ifndef _DARKGLASS_DEVICE_PABLITO
   /**
      Change an internal state @a key to @a value.
    */
    void setState(const char* key, const char* value) final;
  #endif

   /* -----------------------------------------------------------------------------------------------------------------
    * Audio/MIDI Processing */

   /**
      Activate this plugin.
    */
    void activate() final;

   /**
      Run/process function for plugins without MIDI input.
      @note Some parameters might be null if there are no audio inputs or outputs.
    */
    void run(const float** inputs, float** outputs, uint32_t frames) final;

   /* -----------------------------------------------------------------------------------------------------------------
    * Callbacks (optional) */

   /**
      Optional callback to inform the plugin about a sample rate change.
      This function will only be called when the plugin is deactivated.
    */
    void sampleRateChanged(const double newSampleRate) final;

private:
    static const std::vector<FaustParameter>& kFaustParameters;

   #ifndef _DARKGLASS_DEVICE_PABLITO
    // TODO convert common IO to C++
    static const std::vector<FaustParameter>& kFaustParametersIn;
    static const std::vector<FaustParameter>& kFaustParametersOut;
   #endif

    const uint32_t kParameterCount;
    float* const fCommonParameterValues;

    LinearValueSmoother fGlobalDryValue;
    LinearValueSmoother fGlobalWetValue;

   #if LIBREAUDIO_WANT_SPEECH_DETECTION
    LibreAudioSpeechDetection<2> fSpeechDetection;
   #endif

    float* const fInternalBuffer = new float[kInternalBlockSize * 4];
    float* fCycleBuffer1[2] = {
        fInternalBuffer + kInternalBlockSize * 0,
        fInternalBuffer + kInternalBlockSize * 1,
    };
    float* fCycleBuffer2[2] = {
        fInternalBuffer + kInternalBlockSize * 2,
        fInternalBuffer + kInternalBlockSize * 3,
    };

   #if DISTRHO_PLUGIN_WANT_LATENCY
    float* fLatencyBuffer[2] = {
        new float[LIBREAUDIO_MAX_LATENCY_SAMPLES],
        new float[LIBREAUDIO_MAX_LATENCY_SAMPLES],
    };
    int32_t fLatencyReadPos = 0;
    int32_t fLatencyWritePos = 0;
    uint32_t fLastKnownLatency = 0;
   #endif

    // click-free mute/unmute status
    std::atomic<bool> fMuting { false };

    FaustDSP* const fMainDSP;
   #ifndef _DARKGLASS_DEVICE_PABLITO
    FaustDSP* const fInputDSP;
    FaustDSP* const fOutputDSP;
   #endif

    void mute();
    void unmute();

    void doMute();
    void doUnmute();

   #if DISTRHO_PLUGIN_WANT_LATENCY
    // called when deactivated or during run()
    bool updateLatencyIfNeeded();
   #endif

    DISTRHO_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(LibreAudioPlugin)
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
