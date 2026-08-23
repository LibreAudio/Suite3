// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "las-resources.h"

#include "../reference.hpp"
#include "../reference/container.hpp"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioRootWidgetInterface
{
public:
    virtual ~LibreAudioRootWidgetInterface() = default;
    virtual void updateScaleFactorAndSize(float scaleFactor) = 0;
};

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioRootBaseWidget : public LibreAudioReferenceContainerTopLevelWidget<LibreAudioReference::Window, kVertical>,
                                 public LibreAudioRootWidgetInterface
{
    using BaseWidget = LibreAudioReferenceContainerTopLevelWidget<LibreAudioReference::Window, kVertical>;

public:
    LibreAudioRootBaseWidget(Window& window, LibreAudioUIWidgetInterface* const iface)
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

    void updateScaleFactorAndSize(const float scaleFactor) final
    {
        updateScaleFactor(scaleFactor);

        if (fFirstUpdate)
        {
            fFirstUpdate = false;
            updateSize(true);
        }
    }

private:
    bool fFirstUpdate = true;

    void onResize(const ResizeEvent& ev) final
    {
        DISTRHO_SAFE_ASSERT(! fFirstUpdate);

        BaseWidget::onResize(ev);
        updateSize(true);
    }
};

template <class TopBar, class MainArea>
class LibreAudioRootWidget : public LibreAudioRootBaseWidget
{
protected:
    std::unique_ptr<TopBar> fTopBar;
    std::unique_ptr<MainArea> fMainArea;

public:
    LibreAudioRootWidget(Window& window, LibreAudioUIWidgetInterface* const iface)
        : LibreAudioRootBaseWidget(window, iface)
    {
        fTopBar = addWidget<TopBar>();
        fMainArea = addWidget<MainArea, Expanding>();
    }
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
