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

enum LibreAudioOrientation : bool {
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
    template<class W = LibreAudioEmptyWidget>
    std::shared_ptr<W> addSpacer()
    {
        std::shared_ptr<W> widget { new W(this) };
        Layout::widgets.push_back({ widget.get(), Expanding });
        return widget;
    }

    template<class W,
             SizeHint sizeHint = Fixed,
             typename = std::enable_if_t<std::is_base_of_v<LibreAudioWidget, W>>>
    std::shared_ptr<W> addWidget()
    {
        std::shared_ptr<W> widget { new W(this) };
        Layout::widgets.push_back({ widget.get(), sizeHint });
        if (sizeHint == Fixed && widget->getSize().isNull())
            d_stderr2("Error: addWidget called with Fixed sizeHint but widget '%s' does not have a known size",
                      widget->getName());
        return widget;
    }
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
