// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../reference.hpp"
#include "../lab/base.hpp"

#include "DistrhoPluginInfo.h"

#include <cctype>

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------

class TopBarNameWidget final : public LabWidget
{
    using R = Reference::TopBar::PluginName;
    using BaseWidget = LabWidget;

    char fName[sizeof(DISTRHO_PLUGIN_NAME) - 3];

public:
    TopBarNameWidget(LabWidget* const parent)
        : BaseWidget(parent)
    {
        std::memcpy(fName, _constexpr_DISTRHO_PLUGIN_NAME + 3, sizeof(DISTRHO_PLUGIN_NAME) - 3);
        fName[sizeof(DISTRHO_PLUGIN_NAME) - 4] = '\0';

        for (uint i = 0; i < sizeof(DISTRHO_PLUGIN_NAME) - 3; ++i)
            fName[i] = std::toupper(fName[i]);

        updateSize(false);
    }

private:
    void onNanoDisplay() final
    {
        fillColor(R::color);
        fontSize(R::fontSize * fScaleFactor);
        textAlign(ALIGN_CENTER | ALIGN_MIDDLE);
        textLetterSpacing(R::letterSpacing * fScaleFactor);
        text(getWidth() * 0.5f, getHeight() * 0.5f, fName);
    }

    void updateSize(const bool updateChildren) final
    {
        Rectangle<float> bounds;
        fontSize(R::fontSize * fScaleFactor);
        textAlign(0);
        textLetterSpacing(R::letterSpacing * fScaleFactor);
        textBounds(0, 0, fName, nullptr, bounds);
        setWidth(bounds.getWidth());

        BaseWidget::updateSize(updateChildren);
    }
};

// --------------------------------------------------------------------------------------------------------------------

} /* namespace LibreAudio */
