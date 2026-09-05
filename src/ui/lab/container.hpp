// lab: Libre Audio Base-Widgets
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: ISC

#pragma once

#include "empty.hpp"

#include "Layout.hpp"

#include <memory>
#include <type_traits>

START_NAMESPACE_DGL

// --------------------------------------------------------------------------------------------------------------------
// widget container, with an horizontal or vertical layout for child widgets

template<class BaseWidget, Orientation orientation>
class ContainerBaseWidgetOf : public BaseWidget,
                              public std::conditional_t<orientation == kHorizontal, HorizontalLayout, VerticalLayout>
{
public:
    using Layout = std::conditional_t<orientation == kHorizontal, HorizontalLayout, VerticalLayout>;

    explicit ContainerBaseWidgetOf(LabWidget* const parent)
        : BaseWidget(parent) {}

    explicit ContainerBaseWidgetOf(LabTopLevelWidget* const parent)
        : BaseWidget(parent) {}

    explicit ContainerBaseWidgetOf(Window& windowToMapTo, LabUIWidgetInterface* const iface)
        : BaseWidget(windowToMapTo, iface) {}

protected:
    template<class W = LabEmptyWidget>
    std::shared_ptr<W> addSpacer()
    {
        std::shared_ptr<W> widget { new W(this) };
        Layout::widgets.push_back({ widget.get(), Expanding });
        return widget;
    }

    template<class W,
             SizeHint sizeHint = Fixed,
             typename = std::enable_if_t<std::is_base_of_v<LabWidget, W>>>
    std::shared_ptr<W> addWidget()
    {
        std::shared_ptr<W> widget { new W(this) };
        Layout::widgets.push_back({ widget.get(), sizeHint });
        if (sizeHint == Fixed && widget->getSize().isNull())
            d_stderr2("Error: addWidget called with Fixed sizeHint but widget %u: '%s' does not have a known size",
                      widget->getId(),
                      widget->getName());
        return widget;
    }
};

// --------------------------------------------------------------------------------------------------------------------
// reference container base widget class

template<class W, class R, Orientation orientation>
class ReferenceContainerBaseWidgetOf : public ContainerBaseWidgetOf<W, orientation>
{
public:
    using BaseWidget = ContainerBaseWidgetOf<W, orientation>;
    using Layout = typename BaseWidget::Layout;
    using ResizeEvent = typename BaseWidget::ResizeEvent;

    explicit ReferenceContainerBaseWidgetOf(LabWidget* const parent)
        : BaseWidget(parent) {}

    explicit ReferenceContainerBaseWidgetOf(LabTopLevelWidget* const parent)
        : BaseWidget(parent) {}

    explicit ReferenceContainerBaseWidgetOf(Window& windowToMapTo, LabUIWidgetInterface* const iface)
        : BaseWidget(windowToMapTo, iface) {}

protected:
    void updateSize(const bool updateChildren) override
    {
        const float fScaleFactor = this->fScaleFactor;
        const uint width = BaseWidget::getWidth();
        const uint height = BaseWidget::getHeight();
        const uint border = d_roundToUnsignedInt(R::border * fScaleFactor);
        const uint margin = d_roundToUnsignedInt(R::margin * fScaleFactor);
        const uint padding = d_roundToUnsignedInt(R::padding * fScaleFactor);

        if constexpr (orientation == kHorizontal)
            Layout::setWidth(width, padding, border + margin);
        else
            Layout::setHeight(height, padding, border + margin);

        BaseWidget::updateSize(updateChildren);

        if constexpr (std::is_same_v<W, LabTopLevelWidget>)
        {
            Layout::align(0, 0, width, height, padding, border + margin);
        }
        else
        {
            Layout::align(BaseWidget::getAbsoluteX(),
                          BaseWidget::getAbsoluteY(),
                          width,
                          height,
                          padding,
                          border + margin);
        }

        BaseWidget::updateSize(updateChildren);
    }
};

// --------------------------------------------------------------------------------------------------------------------
// reference container (sub) widget class

template<class R, Orientation orientation = kHorizontal>
class ReferenceContainerWidget : public ReferenceContainerBaseWidgetOf<LabReferenceWidget<R>, R, orientation>
{
public:
    using BaseWidget = ReferenceContainerBaseWidgetOf<LabReferenceWidget<R>, R, orientation>;
    using Layout = typename BaseWidget::Layout;
    using PositionChangedEvent = typename BaseWidget::PositionChangedEvent;

    explicit ReferenceContainerWidget(LabWidget* const parent)
        : BaseWidget(parent) {}

    explicit ReferenceContainerWidget(LabTopLevelWidget* const parent)
        : BaseWidget(parent) {}

// protected:
//     void onPositionChanged(const PositionChangedEvent& ev) override
//     {
//         BaseWidget::onPositionChanged(ev);
//
//         const float fScaleFactor = this->fScaleFactor;
//         const uint border = d_roundToUnsignedInt(R::border * fScaleFactor);
//         const uint margin = d_roundToUnsignedInt(R::margin * fScaleFactor);
//         const uint padding = d_roundToUnsignedInt(R::padding * fScaleFactor);
//
//         Layout::setAbsolutePos(ev.pos.getX(), ev.pos.getY(), padding, border + margin);
//     }
};

// --------------------------------------------------------------------------------------------------------------------
// reference container top-level widget class

template<class R, Orientation orientation>
class ReferenceContainerTopLevelWidget : public ReferenceContainerBaseWidgetOf<LabTopLevelWidget, R, orientation>
{
public:
    using BaseWidget = ReferenceContainerBaseWidgetOf<LabTopLevelWidget, R, orientation>;

    explicit ReferenceContainerTopLevelWidget(Window& windowToMapTo, LabUIWidgetInterface* const iface)
        : BaseWidget(windowToMapTo, iface) {}
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DGL
