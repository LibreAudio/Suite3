// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "empty.hpp"

#include "Layout.hpp"

#include <memory>
#include <type_traits>

START_NAMESPACE_DISTRHO

class LibreAudioUIWidgetInterface;

// --------------------------------------------------------------------------------------------------------------------
// widget container, with an horizontal or vertical layout for child widgets

enum LibreAudioOrientation {
    kHorizontal,
    kVertical,
};

template<class BaseWidget, LibreAudioOrientation orientation>
class LibreAudioContainerBaseWidget : public BaseWidget,
                                      public std::conditional_t<orientation == kHorizontal, HorizontalLayout, VerticalLayout>
{
public:
    using Layout = std::conditional_t<orientation == kHorizontal, HorizontalLayout, VerticalLayout>;

    explicit LibreAudioContainerBaseWidget(LibreAudioWidget* const parent)
        : BaseWidget(parent) {}

    explicit LibreAudioContainerBaseWidget(LibreAudioTopLevelWidget* const parent)
        : BaseWidget(parent) {}

    explicit LibreAudioContainerBaseWidget(Window& windowToMapTo, LibreAudioUIWidgetInterface* const iface)
        : BaseWidget(windowToMapTo, iface) {}

protected:
    template<class R = LibreAudioEmptyReference>
    std::unique_ptr<LibreAudioEmptyWidget<R>> addSpacer()
    {
        std::unique_ptr<LibreAudioEmptyWidget<R>> widget { new LibreAudioEmptyWidget<R>(this) };
        Layout::widgets.push_back({ widget.get(), Expanding });
        return widget;
    }

    template<class W,
             SizeHint sizeHint = Fixed,
             typename = std::enable_if_t<std::is_base_of_v<LibreAudioWidget, W>>>
    std::unique_ptr<W> addWidget()
    {
        std::unique_ptr<W> widget { new W(this) };
        Layout::widgets.push_back({ widget.get(), sizeHint });
        if (sizeHint == Fixed && widget->getSize().isNull())
            d_stderr2("Error: addWidget called with Fixed sizeHint but widget '%s' does not have a known size",
                      widget->getName());
        return widget;
    }
};

// --------------------------------------------------------------------------------------------------------------------

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
    void onResize(const ResizeEvent& ev) override
    {
        BaseWidget::onResize(ev);

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
    }
};

// --------------------------------------------------------------------------------------------------------------------

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
