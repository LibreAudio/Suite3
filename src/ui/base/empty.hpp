// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "base.hpp"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------
// empty widget class, useful for making space and alignment of other widgets

class LibreAudioEmptyWidget final : public LibreAudioWidget
{
public:
    explicit LibreAudioEmptyWidget(LibreAudioWidget* const parent)
        : LibreAudioWidget(parent) {}

    explicit LibreAudioEmptyWidget(LibreAudioTopLevelWidget* const parent)
        : LibreAudioWidget(parent) {}

private:
    void onNanoDisplay() final
    {
    }
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
