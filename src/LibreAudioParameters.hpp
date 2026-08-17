// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "src/DistrhoDefines.h"

#ifndef _DARKGLASS_DEVICE_PABLITO
#include "common_input-parameters.hpp"
#include "common_output-parameters.hpp"
#endif

// --------------------------------------------------------------------------------------------------------------------

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

inline constexpr const uint32_t kCommonIOParameters = 1;

enum CommonParameters {
    kCommonParameterBypass,
    kCommonParameterReset,
   #if LIBREAUDIO_WANT_DRYWET
    kCommonParameterDryWet,
   #endif
    kCommonParameterCount
};

enum Groups {
    kGroupInput,
    kGroupOutput,
    kGroupMain,
};

enum Parameters {
    kParametersCommonStart,
    kParametersCommonEnd = kParametersCommonStart + kCommonParameterCount - 1,
   #ifndef _DARKGLASS_DEVICE_PABLITO
    kParametersInputStart,
    kParametersInputEnd = kParametersInputStart + common_input::kFaustParameterCount - 1,
    kParametersOutputStart,
    kParametersOutputEnd = kParametersOutputStart + common_output::kFaustParameterCount - 1 - kCommonIOParameters,
   #endif
    kParametersMainStart,
};

inline void initCommonParameterValuesToDefault(float values[kCommonParameterCount])
{
    for (uint32_t i = 0; i < kCommonParameterCount; ++i)
    {
        switch (static_cast<CommonParameters>(i))
        {
        case kCommonParameterBypass:
        case kCommonParameterReset:
            values[i] = 0.f;
            break;
       #if LIBREAUDIO_WANT_DRYWET
        case kCommonParameterDryWet:
            values[i] = 50.f;
       #endif
            break;
        case kCommonParameterCount:
            break;
        }
    }
}

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
