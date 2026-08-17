// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "base.hpp"

#include "EventHandlers.hpp"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioButtonWidget : public LibreAudioWidget,
                               public ButtonEventHandler
{
public:
    enum Corner : uint8_t {
        kCornerNone,
        kCornerLeft,
        kCornerRight,
        kCornerBoth,
    };

    explicit LibreAudioButtonWidget(LibreAudioWidget* const parent)
        : LibreAudioWidget(parent),
          ButtonEventHandler(this)
    {
    }

    [[nodiscard]] virtual Corner getCorner() const noexcept = 0;

private:
    bool onMouse(const Widget::MouseEvent& ev) final
    {
        if (mouseEvent(ev))
            return true;
        return LibreAudioWidget::onMouse(ev);
    }

    bool onMotion(const Widget::MotionEvent& ev) final
    {
        if (motionEvent(ev))
            return true;
        return LibreAudioWidget::onMotion(ev);
    }
};

// --------------------------------------------------------------------------------------------------------------------

template <class R, LibreAudioButtonWidget::Corner corner>
class LibreAudioReferenceButtonWidget : public LibreAudioButtonWidget
{
public:
    explicit LibreAudioReferenceButtonWidget(LibreAudioWidget* const parent)
        : LibreAudioButtonWidget(parent)
    {
        if constexpr (R::width != 0)
            LibreAudioWidget::setWidth(d_roundToUnsignedInt(R::width * this->fScaleFactor));

        if constexpr (R::height != 0)
            LibreAudioWidget::setHeight(d_roundToUnsignedInt(R::height * this->fScaleFactor));
    }

    [[nodiscard]] Corner getCorner() const noexcept final
    {
        return corner;
    }

protected:
    [[nodiscard]] virtual const Color& getBackgroundColor() const noexcept
    {
        if (isCheckable())
            return isChecked() ? R::color : R::backgroundColor;

        return R::backgroundColor;
    }

    [[nodiscard]] virtual const Color& getForegroundColor() const noexcept
    {
        if (! isEnabled())
            return R::color〡deactivated;

        if (isCheckable())
            return isChecked() ? R::backgroundColor : R::color;

        return R::color;
    }

    void onNanoDisplay() override
    {
        const float w = getWidth();
        const float h = getHeight();

        beginPath();

        if constexpr (corner != kCornerNone && R::borderRadius != 0)
            roundedRect(0, 0, w, h, R::borderRadius * fScaleFactor);
        else
            rect(0, 0, w, h);

        const Color& bgcolor = getBackgroundColor();

        if (d_isNotZero(bgcolor.alpha))
        {
            if constexpr ((corner == kCornerLeft || corner == kCornerRight) && R::borderRadius != 0)
            {
                DISTRHO_CUSTOM_SAFE_ASSERT_RETURN("Buttons with corners must have opaque color",
                                                  d_isEqual(bgcolor.alpha, 1.f),);
            }

            fillColor(bgcolor);
            fill();
        }

        if constexpr (R::border != 0 && d_isNotZero(R::borderColor.alpha))
        {
            strokeColor(R::borderColor);
            strokeWidth(R::border * 2 * this->fScaleFactor);
            stroke();
        }

        if constexpr (corner != kCornerNone && R::borderRadius != 0)
        {
            if constexpr (corner == kCornerLeft)
            {
                beginPath();
                rect(w * 0.5f, 0, w * 0.5f, h);
                fill();
            }
            if constexpr (corner == kCornerRight)
            {
                beginPath();
                rect(0, 0, w * 0.5f, h);
                fill();
            }
        }
    }
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
