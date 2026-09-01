// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "Application.hpp"
#include "NanoVG.hpp"

namespace LibreAudio {

class UIWidgetInterface;

// --------------------------------------------------------------------------------------------------------------------

enum Corner : uint8_t {
    kCornerNone,
    kCornerLeft,
    kCornerRight,
    kCornerBoth,
};

enum Orientation : bool {
    kHorizontal,
    kVertical,
};

// --------------------------------------------------------------------------------------------------------------------
// base widget class

template <class BaseWidget>
class BaseWidgetOf : public BaseWidget
{
public:
    explicit BaseWidgetOf(BaseWidgetOf<NanoSubWidget>* const parent)
        : BaseWidget(parent),
          fInterface(parent->fInterface),
          fScaleFactor(parent->fScaleFactor) {}

    explicit BaseWidgetOf(BaseWidgetOf<NanoTopLevelWidget>* const parent)
        : BaseWidget(parent),
          fInterface(parent->fInterface),
          fScaleFactor(parent->fScaleFactor) {}

    explicit BaseWidgetOf(Window& windowToMapTo, UIWidgetInterface* const iface)
        : BaseWidget(windowToMapTo),
          fInterface(iface),
          fScaleFactor(windowToMapTo.getScaleFactor()) {}

    ~BaseWidgetOf() override
    {
        for (IdleCallback* callback : fCallbacks)
        {
            if constexpr (std::is_same_v<BaseWidget, NanoSubWidget>)
                BaseWidget::getWindow().removeIdleCallback(callback);
            else
                BaseWidget::removeIdleCallback(callback);
        }
    }

    void addIdleCallback(IdleCallback* const callback)
    {
        fCallbacks.push_back(callback);

        if constexpr (std::is_same_v<BaseWidget, NanoSubWidget>)
            BaseWidget::getWindow().addIdleCallback(callback);
        else
            BaseWidget::addIdleCallback(callback);
    }

    [[nodiscard]] double getTime() const
    {
        return BaseWidget::getApp().getTime();
    }

    [[nodiscard]] bool timeEllapsed(const double lastTime, const double wantedTime, const double timeNow) const noexcept
    {
        return d_isNotZero(lastTime) ? timeNow - lastTime >= wantedTime : false;
    }

    [[nodiscard]] bool timeEllapsed(const double lastTime, const double wantedTime) const
    {
        return timeEllapsed(lastTime, wantedTime, getTime());
    }

    [[nodiscard]] bool timeNotEllapsed(const double lastTime, const double wantedTime, const double timeNow) const noexcept
    {
        return d_isNotZero(lastTime) ? timeNow - lastTime < wantedTime : false;
    }

    [[nodiscard]] bool timeNotEllapsed(const double lastTime, const double wantedTime) const
    {
        return timeNotEllapsed(lastTime, wantedTime, getTime());
    }

protected:
    UIWidgetInterface* const fInterface;
    float fScaleFactor;

    template <class R>
    void drawReferenceBackground()
    {
        const float w = BaseWidget::getWidth();
        const float h = BaseWidget::getHeight();

        BaseWidget::beginPath();

        if constexpr (R::borderRadius != 0)
            BaseWidget::roundedRect(0, 0, w, h, R::borderRadius * fScaleFactor);
        else
            BaseWidget::rect(0, 0, w, h);

        if constexpr (d_isNotZero(R::backgroundColor.alpha))
        {
            BaseWidget::fillColor(R::backgroundColor);
            BaseWidget::fill();
        }

        if constexpr (R::border != 0 && d_isNotZero(R::borderColor.alpha))
        {
            const float border = d_roundToIntPositive(R::border * fScaleFactor);
            const float borderh = border * 0.5f;

            const float sx = borderh;
            const float sy = borderh;
            const float ex = w - borderh;
            const float ey = h - borderh;

            BaseWidget::beginPath();

            if constexpr (R::borderRadius != 0)
            {
                const float borderRadius = R::borderRadius * fScaleFactor;
                DISTRHO_SAFE_ASSERT_RETURN(borderRadius < w * 0.5f,);
                DISTRHO_SAFE_ASSERT_RETURN(borderRadius < h * 0.5f,);
                DISTRHO_SAFE_ASSERT_RETURN(borderRadius > border,);

                const float arcRadius = borderRadius - border;

                BaseWidget::moveTo(sx + borderRadius, sy);
                BaseWidget::arcTo(sx, sy, sx, ey - borderRadius, arcRadius);
                BaseWidget::lineTo(sx, ey - borderRadius);
                BaseWidget::arcTo(sx, ey, sx + borderRadius, ey, arcRadius);
                BaseWidget::lineTo(ex - borderRadius, ey);
                BaseWidget::arcTo(ex, ey, ex, ey - borderRadius, arcRadius);
                BaseWidget::lineTo(ex, sx + borderRadius);
                BaseWidget::arcTo(ex, sy, ex - borderRadius, sy, arcRadius);
            }
            else
            {
                BaseWidget::moveTo(sx, sy);
                BaseWidget::lineTo(sx, ey);
                BaseWidget::lineTo(ex, ey);
                BaseWidget::lineTo(ex, sy);
            }

            BaseWidget::closePath();
            BaseWidget::strokeColor(R::borderColor);
            BaseWidget::strokeWidth(border);
            BaseWidget::stroke();
        }
    }

    template <class R>
    void updateReferenceSize()
    {
        if constexpr (R::width != 0)
            BaseWidget::setWidth(d_roundToUnsignedInt(R::width * fScaleFactor));

        if constexpr (R::height != 0)
            BaseWidget::setHeight(d_roundToUnsignedInt(R::height * fScaleFactor));
    }

    void updateScaleFactor(const float scaleFactor)
    {
        fScaleFactor = scaleFactor;

        const std::list<SubWidget*> children = BaseWidget::getChildren();

        for (SubWidget* const child : children)
            static_cast<BaseWidgetOf<NanoSubWidget>*>(child)->updateScaleFactor(scaleFactor);
    }

    virtual void updateSize(const bool updateChildren = true)
    {
        if (! updateChildren)
            return;

        const std::list<SubWidget*> children = BaseWidget::getChildren();

        for (SubWidget* const child : children)
            static_cast<BaseWidgetOf<NanoSubWidget>*>(child)->updateSize(true);
    }

private:
    // FIXME remove this
    std::vector<IdleCallback*> fCallbacks;

    friend class BaseWidgetOf<NanoSubWidget>;
    friend class BaseWidgetOf<NanoTopLevelWidget>;
};

// --------------------------------------------------------------------------------------------------------------------
// top-level widget class

class TopLevelWidget : public BaseWidgetOf<NanoTopLevelWidget>
{
    using BaseWidget = BaseWidgetOf<NanoTopLevelWidget>;

public:
    explicit TopLevelWidget(Window& windowToMapTo, UIWidgetInterface* const iface)
        : BaseWidget(windowToMapTo, iface) {}

    void setWidth() = delete;
    void setHeight() = delete;
    void setSize() = delete;

protected:
    void onNanoDisplay() override
    {
    }
};

// --------------------------------------------------------------------------------------------------------------------
// (sub) widget class

class Widget : public BaseWidgetOf<NanoSubWidget>
{
    using BaseWidget = BaseWidgetOf<NanoSubWidget>;

public:
    explicit Widget(TopLevelWidget* const parent)
        : BaseWidget(parent) {}

    explicit Widget(Widget* const parent)
        : BaseWidget(parent) {}
};

// --------------------------------------------------------------------------------------------------------------------
// reference (sub) widget class

template<class R>
class ReferenceWidget : public Widget
{
public:
    explicit ReferenceWidget(TopLevelWidget* const parent)
        : Widget(parent)
    {
        updateSize(false);
    }

    explicit ReferenceWidget(Widget* const parent)
        : Widget(parent)
    {
        updateSize(false);
    }

protected:
    void onNanoDisplay() override
    {
        drawReferenceBackground<R>();
    }

    void updateSize(const bool updateChildren) override
    {
        updateReferenceSize<R>();
        Widget::updateSize(updateChildren);
    }
};

// --------------------------------------------------------------------------------------------------------------------

} /* namespace LibreAudio */
