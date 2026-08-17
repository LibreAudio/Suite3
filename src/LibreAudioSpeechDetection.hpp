// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>

#include "rnnoise.h"

template<int numChannels>
class LibreAudioSpeechDetection
{
    // rnnoise block size
    static constexpr const uint32_t rnnoiseFrameSize = 480;
    static constexpr const uint32_t rnnoiseFrameSizeF = rnnoiseFrameSize * sizeof(float);

    // rnnoise handles
    DenoiseState* rnnoise[numChannels] = {};

    // buffers for rnnoise block processing
    uint32_t bufferInPos = 0;
    float* bufferIn[numChannels] = {};
    float* bufferOut = new float[rnnoiseFrameSize];

    // current speech detection value
    float vad = 0.f;

public:
    LibreAudioSpeechDetection()
    {
        for (int c = 0; c < numChannels; ++c)
        {
            bufferIn[c] = new float[rnnoiseFrameSize];
            rnnoise[c] = rnnoise_create(nullptr);
        }
    }

    ~LibreAudioSpeechDetection()
    {
        delete[] bufferOut;

        for (int c = 0; c < numChannels; ++c)
        {
            delete[] bufferIn[c];
            rnnoise_destroy(rnnoise[c]);
        }
    }

    float process(const float* const inputs[numChannels], const uint32_t frames)
    {
        // optimize for non-denormal usage
        for (int c = 0; c < numChannels; ++c)
        {
            for (uint32_t i = 0; i < frames; ++i)
            {
                if (!std::isfinite(inputs[c][i]))
                    __builtin_unreachable();
            }
        }

        // process in rnnoise block-size chunks
        for (uint32_t offset = 0; offset != frames;)
        {
            const uint32_t framesCycle = std::min(rnnoiseFrameSize - bufferInPos, frames - offset);
            const uint32_t framesCycleF = framesCycle * sizeof(float);

            // copy input data into buffer
            for (int c = 0; c < numChannels; ++c)
                std::memcpy(bufferIn[c] + bufferInPos, inputs[c] + offset, framesCycleF);

            // run rnnoise once input buffer is full
            if ((bufferInPos += framesCycle) == rnnoiseFrameSize)
            {
                bufferInPos = 0;

                // run rnnoise
                vad = 0.f;
                for (int c = 0; c < numChannels; ++c)
                    vad = std::max(vad, rnnoise_process_frame(rnnoise[c], bufferOut, bufferIn[c]));
            }

            offset += framesCycle;
        }

        return vad;
    }

    void reset()
    {
        bufferInPos = 0;
        vad = 0.f;
    }
};
