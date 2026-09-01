// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

// NOTE this is the file that gets imported by DPF in a custom include
// to keep build times reasonable we only include the necessary files for a LibreAudioUIWidget widget

#pragma once

#include "NanoVG.hpp"
#include "reference/interface.hpp"

// --------------------------------------------------------------------------------------------------------------------

namespace LibreAudio {

class UIWidget : public DGL_NAMESPACE::NanoTopLevelWidget,
                 public UIWidgetInterface
{
public:
    explicit UIWidget(Window& window)
        : DGL_NAMESPACE::NanoTopLevelWidget(window) {}
};

}

// --------------------------------------------------------------------------------------------------------------------

START_NAMESPACE_DISTRHO

using LibreAudioUIWidget = LibreAudio::UIWidget;

END_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------
