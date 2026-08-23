// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "las-resources.h"

#include "../reference.hpp"
#include "../reference/container.hpp"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioMainAreaWidgetInterface
{
public:
    virtual ~LibreAudioMainAreaWidgetInterface() = default;
    [[nodiscard]] virtual Point<int> getMainAreaAbsolutePos() const noexcept = 0;
    [[nodiscard]] virtual Size<uint> getMainAreaSize() const noexcept = 0;
    [[nodiscard]] virtual float getMainAreaBorderRadius() const noexcept = 0;
};

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioRootWidgetInterface
{
public:
    virtual ~LibreAudioRootWidgetInterface() = default;
    [[nodiscard]] virtual Point<int> getMainAreaAbsolutePos() const noexcept = 0;
    [[nodiscard]] virtual Size<uint> getMainAreaSize() const noexcept = 0;
    [[nodiscard]] virtual float getMainAreaBorderRadius() const noexcept = 0;
    virtual void updateScaleFactorAndSize(float scaleFactor) = 0;
};

// --------------------------------------------------------------------------------------------------------------------

template <class TopBar, class MainArea>
class LibreAudioRootWidget : public LibreAudioReferenceContainerTopLevelWidget<LibreAudioReference::Window, kVertical>,
                             public LibreAudioRootWidgetInterface
{
    using R = LibreAudioReference::Window;
    using BaseWidget = LibreAudioReferenceContainerTopLevelWidget<R, kVertical>;

    std::unique_ptr<TopBar> fTopBar;
    std::unique_ptr<MainArea> fMainArea;

public:
    LibreAudioRootWidget(Window& window, LibreAudioUIWidgetInterface* const iface)
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

        fTopBar = addWidget<TopBar>();
        fMainArea = addWidget<MainArea, Expanding>();
    }

    ~LibreAudioRootWidget() = default;

    [[nodiscard]] Point<int> getMainAreaAbsolutePos() const noexcept final
    {
        return static_cast<LibreAudioMainAreaWidgetInterface*>(fMainArea.get())->getMainAreaAbsolutePos();
    }

    [[nodiscard]] Size<uint> getMainAreaSize() const noexcept final
    {
        return static_cast<LibreAudioMainAreaWidgetInterface*>(fMainArea.get())->getMainAreaSize();
    }

    [[nodiscard]] float getMainAreaBorderRadius() const noexcept final
    {
        return static_cast<LibreAudioMainAreaWidgetInterface*>(fMainArea.get())->getMainAreaBorderRadius();
    }

    void updateScaleFactorAndSize(const float scaleFactor) final
    {
        updateScaleFactor(scaleFactor);
        updateSize(true);
    }
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
