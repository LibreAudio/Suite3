// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "Application.hpp"
#include "NanoVG.hpp"

START_NAMESPACE_DISTRHO

class LibreAudioUIWidgetInterface;

// --------------------------------------------------------------------------------------------------------------------
// base widget class

template <class BaseWidget>
class LibreAudioBaseWidget : public BaseWidget
{
public:
    explicit LibreAudioBaseWidget(LibreAudioBaseWidget<NanoSubWidget>* const parent)
        : BaseWidget(parent),
          fInterface(parent->fInterface),
          fScaleFactor(parent->fScaleFactor) {}

    explicit LibreAudioBaseWidget(LibreAudioBaseWidget<NanoTopLevelWidget>* const parent)
        : BaseWidget(parent),
          fInterface(parent->fInterface),
          fScaleFactor(parent->fScaleFactor) {}

    explicit LibreAudioBaseWidget(Window& windowToMapTo, LibreAudioUIWidgetInterface* const iface)
        : BaseWidget(windowToMapTo),
          fInterface(iface),
          fScaleFactor(windowToMapTo.getScaleFactor()) {}

    ~LibreAudioBaseWidget() override
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
    LibreAudioUIWidgetInterface* const fInterface;
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

    void updateScaleFactor(const float scaleFactor)
    {
        fScaleFactor = scaleFactor;

        const std::list<SubWidget*> children = BaseWidget::getChildren();

        for (SubWidget* const child : children)
            static_cast<LibreAudioBaseWidget<NanoSubWidget>*>(child)->updateScaleFactor(scaleFactor);
    }

    virtual void updateSize(const bool updateChildren = true)
    {
        if (! updateChildren)
            return;

        const std::list<SubWidget*> children = BaseWidget::getChildren();

        for (SubWidget* const child : children)
            static_cast<LibreAudioBaseWidget<NanoSubWidget>*>(child)->updateSize(true);
    }

private:
    // FIXME remove this
    std::vector<IdleCallback*> fCallbacks;

    friend class LibreAudioBaseWidget<NanoSubWidget>;
    friend class LibreAudioBaseWidget<NanoTopLevelWidget>;
};

// --------------------------------------------------------------------------------------------------------------------
// top-level widget class

class LibreAudioTopLevelWidget : public LibreAudioBaseWidget<NanoTopLevelWidget>
{
public:
    explicit LibreAudioTopLevelWidget(Window& windowToMapTo, LibreAudioUIWidgetInterface* const iface)
        : LibreAudioBaseWidget(windowToMapTo, iface) {}

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

class LibreAudioWidget : public LibreAudioBaseWidget<NanoSubWidget>
{
public:
    explicit LibreAudioWidget(LibreAudioTopLevelWidget* const parent)
        : LibreAudioBaseWidget(parent) {}

    explicit LibreAudioWidget(LibreAudioWidget* const parent)
        : LibreAudioBaseWidget(parent) {}
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
