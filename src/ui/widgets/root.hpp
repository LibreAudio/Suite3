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
    virtual void updateScaleFactorAndSize() = 0;
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

    void updateScaleFactorAndSize() final
    {
        fScaleFactor = std::min(static_cast<double>(getWidth()) / DISTRHO_UI_DEFAULT_WIDTH,
                                static_cast<double>(getHeight()) / DISTRHO_UI_DEFAULT_HEIGHT);
        updateScaleFactor(fScaleFactor);
        updateSize(true);
    }

private:
    void onResize(const ResizeEvent& ev) final
    {
        BaseWidget::onResize(ev);
        updateScaleFactorAndSize();
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
