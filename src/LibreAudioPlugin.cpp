// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#include "LibreAudioPlugin.hpp"

#ifndef _DARKGLASS_DEVICE_PABLITO
#include "extra/ScopedDenormalDisable.hpp"
#endif

#include "FaustDSP.hpp"
#include "LibreAudioParameters.hpp"
#include "LibreAudioStates.hpp"

#ifndef _DARKGLASS_DEVICE_PABLITO
// TODO convert common IO to C++
#include "common_input-dsp.hpp"
#include "common_output-dsp.hpp"
#endif

#include <cassert>

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

static constexpr const float kParameterSmoothingTime = 0.05f; // in seconds

// --------------------------------------------------------------------------------------------------------------------

const std::vector<FaustParameter>& LibreAudioPlugin::kFaustParameters = getFaustParameters();

#ifndef _DARKGLASS_DEVICE_PABLITO
// TODO convert common IO to C++
const std::vector<FaustParameter>& LibreAudioPlugin::kFaustParametersIn = common_input::getFaustParameters();
const std::vector<FaustParameter>& LibreAudioPlugin::kFaustParametersOut = common_output::getFaustParameters();
#endif

// --------------------------------------------------------------------------------------------------------------------

LibreAudioPlugin::LibreAudioPlugin()
    : Plugin(kParametersMainStart  + kFaustParameters.size(), 0, kStateCount),
      kParameterCount(kParametersMainStart  + kFaustParameters.size()),
      fCommonParameterValues(new float[kCommonParameterCount]),
      fMainDSP(createDSP())
   #ifndef _DARKGLASS_DEVICE_PABLITO
    , fInputDSP(common_input::createDSP())
    , fOutputDSP(common_output::createDSP())
   #endif
{
    initCommonParameterValuesToDefault(fCommonParameterValues);

    const double sampleRate = getSampleRate();
    const int iSampleRate = d_roundToIntPositive(sampleRate);

    fGlobalDryValue.setSampleRate(sampleRate);
    fGlobalDryValue.setTimeConstant(kParameterSmoothingTime);
    fGlobalDryValue.setTargetValue(0.f);

    fGlobalWetValue.setSampleRate(sampleRate);
    fGlobalWetValue.setTimeConstant(kParameterSmoothingTime);
    fGlobalWetValue.setTargetValue(1.f);

    fMainDSP->init(iSampleRate);
   #ifndef _DARKGLASS_DEVICE_PABLITO
    fInputDSP->init(iSampleRate);
    fOutputDSP->init(iSampleRate);
   #endif

   #if DISTRHO_PLUGIN_WANT_LATENCY
    fMainDSP->compute(0, fCycleBuffer1, fCycleBuffer2);
    updateLatencyIfNeeded();
   #endif
}

LibreAudioPlugin::~LibreAudioPlugin()
{
    delete fMainDSP;
   #ifndef _DARKGLASS_DEVICE_PABLITO
    delete fInputDSP;
    delete fOutputDSP;
   #endif
    delete[] fCommonParameterValues;
    delete[] fInternalBuffer;
   #if DISTRHO_PLUGIN_WANT_LATENCY
    delete[] fLatencyBuffer[0];
    delete[] fLatencyBuffer[1];
   #endif
}

// --------------------------------------------------------------------------------------------------------------------
// Init

static void initParameterFromFaust(Parameter& parameter, const FaustParameter& faustParameter)
{
    parameter.hints = kParameterIsAutomatable;
    if (faustParameter.isBoolean)
        parameter.hints |= kParameterIsBoolean;
    if (faustParameter.isInteger)
        parameter.hints |= kParameterIsInteger;
    if (faustParameter.isLogarithmic)
        parameter.hints |= kParameterIsLogarithmic;
    if (faustParameter.isOutput)
        parameter.hints |= kParameterIsOutput;
    if (faustParameter.isTrigger)
        parameter.hints |= kParameterIsTrigger;
   #if LIBREAUDIO_WANT_SPEECH_DETECTION
    if (std::strcmp(faustParameter.symbol, "vad_ext") == 0)
        parameter.hints = kParameterIsOutput | kParameterIsHidden;
   #endif

    parameter.name = faustParameter.name;
    parameter.symbol = faustParameter.symbol;
    parameter.description = faustParameter.tooltip;
    parameter.unit = faustParameter.unit;
    parameter.ranges.def = faustParameter.init;
    parameter.ranges.min = faustParameter.min;
    parameter.ranges.max = faustParameter.max;

    if (std::strcmp(faustParameter.symbol, "input_ms_on") == 0)
    {
        ParameterEnumerationValue* const values = new ParameterEnumerationValue[2];
        values[0].label = "L/R";
        values[0].value = 0.f;
        values[1].label = "Mid/Side";
        values[1].value = 1.f;
        parameter.enumValues.restrictedMode = true;
        parameter.enumValues.count = 2;
        parameter.enumValues.values = values;
    }
    else if (std::strncmp(faustParameter.symbol, "input_phase_", 12) == 0)
    {
        ParameterEnumerationValue* const values = new ParameterEnumerationValue[2];
        values[0].label = "Normal";
        values[0].value = 0.f;
        values[1].label = "Inverted";
        values[1].value = 1.f;
        parameter.enumValues.restrictedMode = true;
        parameter.enumValues.count = 2;
        parameter.enumValues.values = values;
    }
}

void LibreAudioPlugin::initParameter(uint32_t index, Parameter& parameter)
{
    switch (index)
    {
    case kCommonParameterBypass:
        parameter.initDesignation(kParameterDesignationBypass);
        break;
    case kCommonParameterReset:
        parameter.initDesignation(kParameterDesignationReset);
        break;
   #if LIBREAUDIO_WANT_DRYWET
    case kCommonParameterDryWet:
        parameter.hints = kParameterIsAutomatable;
        parameter.name = "Dry / Wet";
        parameter.symbol = "dry_wet";
        parameter.unit = "%";
        parameter.ranges.def = 50.f;
        parameter.ranges.min = 0.f;
        parameter.ranges.max = 100.f;
        break;
   #endif
   #ifndef _DARKGLASS_DEVICE_PABLITO
    case kParametersInputStart ... kParametersInputEnd:
        parameter.groupId = kGroupInput;
        initParameterFromFaust(parameter, kFaustParametersIn[index - kParametersInputStart]);
        break;
    case kParametersOutputStart ... kParametersOutputEnd:
        parameter.groupId = kGroupOutput;
        initParameterFromFaust(parameter, kFaustParametersOut[index - kParametersOutputStart + kCommonIOParameters]);
        break;
   #endif
    default:
        DISTRHO_SAFE_ASSERT_RETURN(index < kParameterCount,);
       #ifndef _DARKGLASS_DEVICE_PABLITO
        parameter.groupId = kGroupMain;
       #endif
        initParameterFromFaust(parameter, kFaustParameters[index - kParametersMainStart]);
        break;
    }
}

#ifndef _DARKGLASS_DEVICE_PABLITO
void LibreAudioPlugin::initState(const uint32_t index, State& state)
{
    state.hints = kStateIsOnlyForUI;
    state.key = kStateKeys[index];

    switch (static_cast<States>(index))
    {
    case kStateCurrentSnapshot:
        state.label = "Snapshot";
        break;
    case kStateSnapshotValuesA:
        state.label = "Snapshot Values A";
        break;
    case kStateSnapshotValuesB:
        state.label = "Snapshot Values B";
        break;
    case kStateSnapshotValuesC:
        state.label = "Snapshot Values C";
        break;
    case kStateSnapshotValuesD:
        state.label = "Snapshot Values D";
        break;
    case kStateCount:
        break;
    }
}
#endif

void LibreAudioPlugin::initPortGroup(const uint32_t groupId, PortGroup& portGroup)
{
    switch (static_cast<Groups>(groupId))
    {
    case kGroupInput:
        portGroup.name = "Input";
        portGroup.symbol = "input";
        break;
    case kGroupOutput:
        portGroup.name = "Output";
        portGroup.symbol = "output";
        break;
    case kGroupMain:
        portGroup.name = DISTRHO_PLUGIN_NAME;
        portGroup.symbol = DISTRHO_PLUGIN_LABEL;
        portGroup.symbol.toBasic();
        break;
    }
}

// --------------------------------------------------------------------------------------------------------------------
// Internal data

float LibreAudioPlugin::getParameterValue(const uint32_t index) const
{
    switch (index)
    {
    case kParametersCommonStart ... kParametersCommonEnd:
        return fCommonParameterValues[index - kParametersCommonStart];
   #ifndef _DARKGLASS_DEVICE_PABLITO
    case kParametersInputStart ... kParametersInputEnd:
        return fInputDSP->get(index - kParametersInputStart);
    case kParametersOutputStart ... kParametersOutputEnd:
        return fOutputDSP->get(index - kParametersOutputStart + kCommonIOParameters);
   #endif
    default:
        DISTRHO_SAFE_ASSERT_RETURN(index < kParameterCount, 0.f);
        return fMainDSP->get(index - kParametersMainStart);
    }
}

void LibreAudioPlugin::setParameterValue(uint32_t index, const float value)
{
    // common handling first
    switch (index)
    {
    case kParametersCommonStart ... kParametersCommonEnd:
        fCommonParameterValues[index - kParametersCommonStart] = value;
        break;
   #ifndef _DARKGLASS_DEVICE_PABLITO
    case kParametersInputStart ... kParametersInputEnd:
        fInputDSP->set(index - kParametersInputStart, value);
        break;
    case kParametersOutputStart ... kParametersOutputEnd:
        fOutputDSP->set(index - kParametersOutputStart + kCommonIOParameters, value);
        break;
   #endif
    default:
        DISTRHO_SAFE_ASSERT_RETURN(index < kParameterCount,);
        fMainDSP->set(index - kParametersMainStart, value);
        break;
    }

    // custom behaviour
    switch (index)
    {
    case kCommonParameterBypass:
   #if LIBREAUDIO_WANT_DRYWET
    case kCommonParameterDryWet:
   #endif
        if (fMuting.load() == false)
            doUnmute();
        break;
   #ifndef _DARKGLASS_DEVICE_PABLITO
    case kParametersInputStart + common_input::kFaustParameterInput_ms_on:
        fOutputDSP->set(common_output::kFaustParameterInput_ms_on, value);
        break;
   #endif
    }
}

#ifndef _DARKGLASS_DEVICE_PABLITO
void LibreAudioPlugin::setState(const char*, const char*)
{
    // all states in LA plugins are UI-only
}
#endif

// --------------------------------------------------------------------------------------------------------------------
// Audio/MIDI Processing

void LibreAudioPlugin::activate()
{
    fCommonParameterValues[kCommonParameterReset] = 1.f;
}

void LibreAudioPlugin::run(const float** const inputs, float** const outputs, const uint32_t frames)
{
   #ifndef _DARKGLASS_DEVICE_PABLITO
    const ScopedDenormalDisable sdd;
   #endif

    if (d_isNotZero(fCommonParameterValues[kCommonParameterReset]))
    {
        if (fMuting.exchange(false))
            doUnmute();

        fCommonParameterValues[kCommonParameterReset] = 0.f;
        fGlobalDryValue.clearToTargetValue();
        fGlobalWetValue.clearToTargetValue();
        fMainDSP->instanceClear();
       #ifndef _DARKGLASS_DEVICE_PABLITO
        fInputDSP->instanceClear();
        fOutputDSP->instanceClear();
       #endif

       #if DISTRHO_PLUGIN_WANT_LATENCY
        fLatencyReadPos = -fLastKnownLatency;
        fLatencyWritePos = 0;
       #endif

       #if LIBREAUDIO_WANT_SPEECH_DETECTION
        fSpeechDetection.reset();
       #endif
    }

    float dry, wet;
   #if DISTRHO_PLUGIN_WANT_LATENCY
    float input;
    int32_t latencyReadPos = fLatencyReadPos;
    int32_t latencyWritePos = fLatencyWritePos;
   #endif

    for (uint32_t i = 0, cycleFrames; i < frames; i += kInternalBlockSize)
    {
        cycleFrames = std::min<uint32_t>(kInternalBlockSize, frames - i);
       #ifdef __GNUC__
        #pragma GCC poison frames
       #endif

        for (uint32_t c = 0; c < DISTRHO_PLUGIN_NUM_OUTPUTS; ++c)
            std::memcpy(fCycleBuffer1[c], inputs[c] + i, sizeof(float) * cycleFrames);

       #if DISTRHO_PLUGIN_WANT_LATENCY
        for (uint32_t j = 0; j < cycleFrames; ++j)
        {
            for (uint32_t c = 0; c < DISTRHO_PLUGIN_NUM_OUTPUTS; ++c)
                fLatencyBuffer[c][latencyWritePos] = inputs[c][i + j];

            if (++latencyWritePos == LIBREAUDIO_MAX_LATENCY_SAMPLES)
                latencyWritePos = 0;
        }
       #endif

       #if LIBREAUDIO_WANT_SPEECH_DETECTION
        const float vad = fSpeechDetection.process(fCycleBuffer1, cycleFrames);
        fMainDSP->set(leveler::kFaustParameterVad_ext, vad);
       #endif

       #ifndef _DARKGLASS_DEVICE_PABLITO
        fInputDSP->compute(cycleFrames, fCycleBuffer1, fCycleBuffer2);
        fMainDSP->compute(cycleFrames, fCycleBuffer2, fCycleBuffer1);
        fOutputDSP->compute(cycleFrames, fCycleBuffer1, fCycleBuffer2);
       #else
        fMainDSP->compute(cycleFrames, fCycleBuffer1, fCycleBuffer2);
       #endif

        for (uint32_t j = 0; j < cycleFrames; ++j)
        {
            dry = fGlobalDryValue.next();
            wet = fGlobalWetValue.next();

            for (uint32_t c = 0; c < DISTRHO_PLUGIN_NUM_OUTPUTS; ++c)
            {
               #if DISTRHO_PLUGIN_WANT_LATENCY
                input = latencyReadPos >= 0 ? fLatencyBuffer[c][latencyReadPos] * dry : 0.f;
                outputs[c][i + j] = fCycleBuffer2[c][j] * wet + input;
               #else
                outputs[c][i + j] = fCycleBuffer2[c][j] * wet + inputs[c][i + j] * dry;
               #endif
            }

           #if DISTRHO_PLUGIN_WANT_LATENCY
            if (++latencyReadPos == LIBREAUDIO_MAX_LATENCY_SAMPLES)
                latencyReadPos = 0;
           #endif
        }

        if (fMuting.load() && d_isZero(fGlobalDryValue.peek()) && d_isZero(fGlobalWetValue.peek()))
            unmute();
    }

   #if DISTRHO_PLUGIN_WANT_LATENCY
    if (! updateLatencyIfNeeded())
    {
        fLatencyReadPos = latencyReadPos;
        fLatencyWritePos = latencyWritePos;
    }
   #endif
}

// --------------------------------------------------------------------------------------------------------------------
// Callbacks (optional)

void LibreAudioPlugin::sampleRateChanged(const double newSampleRate)
{
    fGlobalDryValue.setSampleRate(newSampleRate);
    fGlobalWetValue.setSampleRate(newSampleRate);

    const int sampleRate = d_roundToIntPositive(newSampleRate);
    fMainDSP->instanceConstants(sampleRate);
   #ifndef _DARKGLASS_DEVICE_PABLITO
    fInputDSP->instanceConstants(sampleRate);
    fOutputDSP->instanceConstants(sampleRate);
   #endif

   #if DISTRHO_PLUGIN_WANT_LATENCY
    fMainDSP->compute(0, fCycleBuffer1, fCycleBuffer2);
    updateLatencyIfNeeded();
   #endif
}

// --------------------------------------------------------------------------------------------------------------------

void LibreAudioPlugin::mute()
{
    fMuting.store(true);
    doMute();
}

void LibreAudioPlugin::unmute()
{
    fMuting.store(false);
    doUnmute();
}

inline void LibreAudioPlugin::doMute()
{
    // assert(fMuting.load());

    // do not mute if bypassed
    if (d_isZero(fCommonParameterValues[kCommonParameterBypass]))
    {
        fGlobalDryValue.setTargetValue(0.f);
        fGlobalWetValue.setTargetValue(0.f);
    }
}

inline void LibreAudioPlugin::doUnmute()
{
    // assert(fMuting.load() == false);

    // NOTE can trigger clicky operation here

    if (d_isZero(fCommonParameterValues[kCommonParameterBypass]))
    {
        // enabled, use full wet
       #if LIBREAUDIO_WANT_DRYWET
        const float wet = fCommonParameterValues[kCommonParameterDryWet] * 0.01f;
        fGlobalDryValue.setTargetValue(1.f - wet);
        fGlobalWetValue.setTargetValue(wet);
       #else
        fGlobalDryValue.setTargetValue(0.f);
        fGlobalWetValue.setTargetValue(1.f);
       #endif
    }
    else
    {
        // bypassed, use full dry
        fGlobalDryValue.setTargetValue(1.f);
        fGlobalWetValue.setTargetValue(0.f);
    }
}

#if DISTRHO_PLUGIN_WANT_LATENCY
bool LibreAudioPlugin::updateLatencyIfNeeded()
{
    const uint32_t latency = fMainDSP->latency();
    DISTRHO_SAFE_ASSERT_UINT2_RETURN(latency < LIBREAUDIO_MAX_LATENCY_SAMPLES,
                                     latency,
                                     LIBREAUDIO_MAX_LATENCY_SAMPLES, true);

    if (fLastKnownLatency == latency)
        return false;

    for (uint32_t c = 0; c < ARRAY_SIZE(fLatencyBuffer); ++c)
        std::memset(fLatencyBuffer[c], 0, sizeof(float) * latency);

    fLastKnownLatency = latency;
    fLatencyReadPos = -latency;
    fLatencyWritePos = 0;
    setLatency(latency);

    return true;
}
#endif

// --------------------------------------------------------------------------------------------------------------------

Plugin* createPlugin()
{
    return new LibreAudioPlugin();
}

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
