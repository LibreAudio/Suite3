// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "base.hpp"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

template<const float rgba[4]>
class LibreAudioColorWidget final : public LibreAudioWidget
{
    static constexpr const Color fColor = { rgba[0], rgba[1], rgba[2], rgba[3] };

public:
    explicit LibreAudioColorWidget(LibreAudioWidget* const parent)
        : LibreAudioWidget(parent) {}

protected:
    void onNanoDisplay() final
    {
        beginPath();
        rect(0, 0, getWidth(), getHeight());
        fillColor(fColor);
        fill();
    }
};


// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
