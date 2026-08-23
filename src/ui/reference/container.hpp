// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "base.hpp"
#include "../base/container.hpp"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------
// reference container base widget class

template<class W, class R, LibreAudioOrientation orientation>
class LibreAudioReferenceContainerBaseWidget : public LibreAudioContainerBaseWidget<W, orientation>
{
public:
    using BaseWidget = LibreAudioContainerBaseWidget<W, orientation>;
    using Layout = typename BaseWidget::Layout;
    using ResizeEvent = typename BaseWidget::ResizeEvent;

    explicit LibreAudioReferenceContainerBaseWidget(LibreAudioWidget* const parent)
        : BaseWidget(parent) {}

    explicit LibreAudioReferenceContainerBaseWidget(LibreAudioTopLevelWidget* const parent)
        : BaseWidget(parent) {}

    explicit LibreAudioReferenceContainerBaseWidget(Window& windowToMapTo, LibreAudioUIWidgetInterface* const iface)
        : BaseWidget(windowToMapTo, iface) {}

protected:
    void updateSize(const bool updateChildren) override
    // void onResize(const ResizeEvent& ev) override
    {
        // BaseWidget::onResize(ev);

        const float fScaleFactor = this->fScaleFactor;
        const uint border = d_roundToUnsignedInt(R::border * fScaleFactor);
        const uint margin = d_roundToUnsignedInt(R::margin * fScaleFactor);
        const uint padding = d_roundToUnsignedInt(R::padding * fScaleFactor);

        if constexpr (std::is_same_v<W, LibreAudioTopLevelWidget>)
        {
            Layout::align(0, 0, BaseWidget::getWidth(), BaseWidget::getHeight(), padding, border + margin);
        }
        else
        {
            Layout::align(BaseWidget::getAbsoluteX(),
                          BaseWidget::getAbsoluteY(),
                          BaseWidget::getWidth(),
                          BaseWidget::getHeight(),
                          padding,
                          border + margin);
        }

        BaseWidget::updateSize(updateChildren);
    }

    // void updateSize() final
    // {
    // }
};

// --------------------------------------------------------------------------------------------------------------------
// reference container (sub) widget class

template<class R, LibreAudioOrientation orientation = kHorizontal>
class LibreAudioReferenceContainerWidget : public LibreAudioReferenceContainerBaseWidget<LibreAudioReferenceWidget<R>, R, orientation>
{
public:
    using BaseWidget = LibreAudioReferenceContainerBaseWidget<LibreAudioReferenceWidget<R>, R, orientation>;
    using Layout = typename BaseWidget::Layout;
    using PositionChangedEvent = typename BaseWidget::PositionChangedEvent;

    explicit LibreAudioReferenceContainerWidget(LibreAudioWidget* const parent)
        : BaseWidget(parent) {}

    explicit LibreAudioReferenceContainerWidget(LibreAudioTopLevelWidget* const parent)
        : BaseWidget(parent) {}

protected:
    void onPositionChanged(const PositionChangedEvent& ev) override
    {
        BaseWidget::onPositionChanged(ev);

        const float fScaleFactor = this->fScaleFactor;
        const uint border = d_roundToUnsignedInt(R::border * fScaleFactor);
        const uint margin = d_roundToUnsignedInt(R::margin * fScaleFactor);
        const uint padding = d_roundToUnsignedInt(R::padding * fScaleFactor);

        Layout::setAbsolutePos(ev.pos.getX(), ev.pos.getY(), padding, border + margin);
    }
};

// --------------------------------------------------------------------------------------------------------------------
// reference container top-level widget class

template<class R, LibreAudioOrientation orientation>
class LibreAudioReferenceContainerTopLevelWidget : public LibreAudioReferenceContainerBaseWidget<LibreAudioTopLevelWidget, R, orientation>
{
public:
    using BaseWidget = LibreAudioReferenceContainerBaseWidget<LibreAudioTopLevelWidget, R, orientation>;

    explicit LibreAudioReferenceContainerTopLevelWidget(Window& windowToMapTo, LibreAudioUIWidgetInterface* const iface)
        : BaseWidget(windowToMapTo, iface) {}
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO

