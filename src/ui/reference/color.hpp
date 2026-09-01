// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "base.hpp"

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------

template<const float rgba[4]>
class ColorWidget final : public Widget
{
    static constexpr const Color kColor = { rgba[0], rgba[1], rgba[2], rgba[3] };

public:
    explicit ColorWidget(Widget* const parent)
        : Widget(parent) {}

    explicit ColorWidget(TopLevelWidget* const parent)
        : Widget(parent) {}

protected:
    void onNanoDisplay() final
    {
        beginPath();
        rect(0, 0, getWidth(), getHeight());
        fillColor(kColor);
        fill();
    }
};


// --------------------------------------------------------------------------------------------------------------------

} /* namespace LibreAudio */
