// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "las-resources.h"

#include "../reference.hpp"
#include "../lab/root.hpp"

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------

class RootBaseWidget : public ReferenceRootWidget<Reference::Window, kVertical>
{
    using BaseWidget = ReferenceRootWidget<Reference::Window, kVertical>;

public:
    RootBaseWidget(Window& window, LabUIWidgetInterface* const iface)
        : BaseWidget(window, iface)
    {
        createFontFromMemory("regular",
                             FONTS_INTER_18PT_REGULAR_TTF_DATA,
                             FONTS_INTER_18PT_REGULAR_TTF_LEN,
                             false);
        createFontFromMemory("mono",
                             FONTS_SPLINESANSMONO_REGULAR_TTF_DATA,
                             FONTS_SPLINESANSMONO_REGULAR_TTF_LEN,
                             false);
    }
};

template <class TopBar, class MainArea>
class RootWidget : public RootBaseWidget
{
protected:
    std::shared_ptr<TopBar> fTopBar = addWidget<TopBar>();
    std::shared_ptr<MainArea> fMainArea = addWidget<MainArea, Expanding>();

public:
    RootWidget(Window& window, LabUIWidgetInterface* const iface)
        : RootBaseWidget(window, iface) {}
};

// --------------------------------------------------------------------------------------------------------------------

} /* namespace LibreAudio */
