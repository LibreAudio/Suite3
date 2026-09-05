// lab: Libre Audio Base-Widgets
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: ISC

#pragma once

#include "base.hpp"

#include "EventHandlers.hpp"

START_NAMESPACE_DGL

// --------------------------------------------------------------------------------------------------------------------

class ButtonBaseWidget : public LabWidget,
                         public ButtonEventHandler
{
    using BaseWidget = LabWidget;

public:
    explicit ButtonBaseWidget(LabWidget* const parent)
        : BaseWidget(parent),
          ButtonEventHandler(this) {}

    [[nodiscard]] virtual Corner getCorner() const noexcept = 0;

protected:
    [[nodiscard]] virtual const Color& getBackgroundColor() const noexcept = 0; // TODO remove
    [[nodiscard]] virtual const Color& getForegroundColor() const noexcept = 0; // TODO remove

private:
    bool onMouse(const MouseEvent& ev) final
    {
        if (mouseEvent(ev))
            return true;
        return BaseWidget::onMouse(ev);
    }

    bool onMotion(const MotionEvent& ev) final
    {
        if (motionEvent(ev))
            return true;
        return BaseWidget::onMotion(ev);
    }
};

// --------------------------------------------------------------------------------------------------------------------
// reference button widget class

template<class R, Corner corner>
class ReferenceButtonWidget : public ButtonBaseWidget
{
    using BaseWidget = ButtonBaseWidget;

public:
    explicit ReferenceButtonWidget(LabWidget* const parent)
        : BaseWidget(parent) {}

    [[nodiscard]] Corner getCorner() const noexcept final
    {
        return corner;
    }

protected:
    [[nodiscard]] const Color& getBackgroundColor() const noexcept override
    {
        if (isCheckable())
            return isChecked() ? R::color : R::backgroundColor;

        return R::backgroundColor;
    }

    [[nodiscard]] const Color& getForegroundColor() const noexcept override
    {
        if (! isEnabled())
            return R::color〡deactivated;

        if (isCheckable())
            return isChecked() ? R::backgroundColor : R::color;

        return R::color;
    }

    void onNanoDisplay() override
    {
        // TODO use drawReferenceBackground<R>();

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

    void updateSize(const bool updateChildren) override
    {
        updateReferenceSize<R>();
        BaseWidget::updateSize(updateChildren);
    }
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DGL
