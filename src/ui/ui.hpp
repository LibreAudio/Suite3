// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

// NOTE this is the file that gets imported by DPF in a custom include
// to keep build times reasonable we only include the necessary files for a LibreAudioUIWidget widget

#pragma once

#include "NanoVG.hpp"
#include "base/interface.hpp"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioUIWidget : public NanoTopLevelWidget,
                           public LibreAudioUIWidgetInterface
{
public:
    explicit LibreAudioUIWidget(Window& window)
        : NanoTopLevelWidget(window) {}
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
