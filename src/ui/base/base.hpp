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

    friend class LibreAudioBaseWidget<NanoSubWidget>;
    // friend class LibreAudioBaseWidget<NanoTopLevelWidget>;

private:
    // FIXME remove this
    std::vector<IdleCallback*> fCallbacks;
};

// --------------------------------------------------------------------------------------------------------------------
// reference widget class

using LibreAudioWidget = LibreAudioBaseWidget<NanoSubWidget>;

template <class R>
class LibreAudioReferenceWidget : public LibreAudioBaseWidget<NanoSubWidget>
{
public:
    explicit LibreAudioReferenceWidget(LibreAudioBaseWidget<NanoSubWidget>* const parent)
        : LibreAudioBaseWidget(parent)
    {
        _initSize();
    }

    explicit LibreAudioReferenceWidget(LibreAudioBaseWidget<NanoTopLevelWidget>* const parent)
        : LibreAudioBaseWidget(parent)
    {
        _initSize();
    }

protected:
    void onNanoDisplay() override
    {
        const float w = getWidth();
        const float h = getHeight();

        beginPath();

        if constexpr (R::borderRadius != 0)
            roundedRect(0, 0, w, h, R::borderRadius * fScaleFactor);
        else
            rect(0, 0, w, h);

        if constexpr (d_isNotZero(R::backgroundColor.alpha))
        {
            fillColor(R::backgroundColor);
            fill();
        }

        if constexpr (R::border != 0 && d_isNotZero(R::borderColor.alpha))
        {
            strokeColor(R::borderColor);
            strokeWidth(R::border * 2 * fScaleFactor);
            stroke();
        }
    }

private:
    void _initSize()
    {
        if constexpr (R::width != 0)
            setWidth(d_roundToUnsignedInt(R::width * fScaleFactor));

        if constexpr (R::height != 0)
            setHeight(d_roundToUnsignedInt(R::height * fScaleFactor));
    }
};

// --------------------------------------------------------------------------------------------------------------------
// top-level widget class

class LibreAudioTopLevelWidget : public LibreAudioBaseWidget<NanoTopLevelWidget>
{
public:
    explicit LibreAudioTopLevelWidget(Window& windowToMapTo, LibreAudioUIWidgetInterface* const iface)
        : LibreAudioBaseWidget(windowToMapTo, iface) {}

protected:
    void onNanoDisplay() override
    {
    }
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
