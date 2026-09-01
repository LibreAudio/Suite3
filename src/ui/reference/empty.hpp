// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "base.hpp"

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------
// empty widget class, useful for making space and alignment of other widgets

class EmptyWidget final : public Widget
{
public:
    explicit EmptyWidget(Widget* const parent)
        : Widget(parent) {}

    explicit EmptyWidget(TopLevelWidget* const parent)
        : Widget(parent) {}

private:
    void onNanoDisplay() final
    {
    }
};

// --------------------------------------------------------------------------------------------------------------------

} /* namespace LibreAudio */
