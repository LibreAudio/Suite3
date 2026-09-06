// lab: Libre Audio Base-Widgets
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: ISC

#pragma once

#include "base.hpp"

#include "EventHandlers.hpp"

START_NAMESPACE_DGL

// --------------------------------------------------------------------------------------------------------------------

class ToggleSwitchBaseWidget : public LabWidget,
                               public ButtonEventHandler,
                               private ButtonEventHandler::Callback,
                               private IdleCallback
{
    using BaseWidget = LabWidget;

public:
    explicit ToggleSwitchBaseWidget(LabWidget* const parent, const uint id, const char* const name)
        : BaseWidget(parent),
          ButtonEventHandler(this)
    {
        addIdleCallback(this);
        setCallback(this);
        setCheckable(true);
        setId(id);
        setName(name);
    }

protected:
    void idleCallback() override
    {
        if (setChecked(d_isNotZero(fInterface->getParameterValue(getId())), false))
            parameterChangedByHost();
    }

    virtual void parameterChangedByHost() {}

private:
    void buttonClicked(SubWidget*, int) final
    {
        fInterface->parameterControlModified(getId(), isChecked() ? 1.f : 0.f);
    }

    void stateChanged(const State state, const State oldState) final
    {
        if ((state & kButtonStateActive) == (oldState & kButtonStateActive))
            return;

        if ((state & kButtonStateActive) != 0)
            fInterface->parameterControlPressed(getId());
        else
            fInterface->parameterControlReleased(getId());
    }

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

template<class R>
class ReferenceToggleSwitchWidget : public ToggleSwitchBaseWidget
{
    static_assert(R::fontSize != 0, "Font size must not be 0");
    static_assert(R::width != 0, "Switch width must be provided");
    static_assert(R::height != 0, "Switch height must be provided");
    static_assert(R::Switch::width != 0, "Switch inner width must be provided");
    static_assert(R::Switch::height != 0, "Switch inner height must be provided");

    using BaseWidget = ToggleSwitchBaseWidget;

public:
    explicit ReferenceToggleSwitchWidget(LabWidget* const parent, const uint id, const char* const name)
        : BaseWidget(parent, id, name)
    {
        updateReferenceSize<R>();
    }

protected:
    [[nodiscard]] const Color& getBackgroundColor() const noexcept override
    {
        return R::backgroundColor;
    }

    [[nodiscard]] const Color& getBorderColor() const noexcept override
    {
        return R::borderColor;
    }

    void onNanoDisplay() override
    {
        drawReferenceBackground<R>();

        const float w = getWidth();
        const float h = getHeight();

        const float sw_w = R::Switch::width * this->fScaleFactor;
        const float sw_h = R::Switch::height * this->fScaleFactor;
        const float sw_x = (w - sw_w) * 0.5f;
        const float sw_y = sw_w * 0.5f;
        const float sw_margin = (R::Switch::border + R::Switch::margin) * this->fScaleFactor;

        beginPath();

        if constexpr (d_isNotZero(R::Switch::borderRadius))
            roundedRect(sw_x, sw_y, sw_w, sw_h, R::Switch::borderRadius * this->fScaleFactor);
        else
            rect(sw_x, sw_y, sw_w, sw_h);

        fillColor(isChecked() ? R::color : R::color.withAlpha(0.4f));
        fill();

        // TODO border
        if constexpr (R::Switch::border != 0 && d_isNotZero(R::Switch::borderColor.alpha))
        {
            strokeWidth(R::Switch::border * this->fScaleFactor);
            strokeColor(R::Switch::borderColor);
            stroke();
        }

        const float cir_r = sw_h * 0.5f - sw_margin;
        const float cir_x1 = sw_x + sw_margin + cir_r;
        const float cir_x2 = w - cir_x1;
        const float cir_y = sw_y + sw_h * 0.5f;

        beginPath();
        circle(isChecked() ? cir_x2 : cir_x1, cir_y, cir_r);
        fillColor(R::Switch::Ball::backgroundColor);
        fill();

        // TODO border
        if constexpr (d_isNotZero(R::Switch::Ball::borderColor.alpha))
        {
            if constexpr (R::Switch::Ball::border != 0)
            {
                strokeWidth(R::Switch::Ball::border * this->fScaleFactor);
                strokeColor(R::Switch::Ball::borderColor);
                stroke();
            }
        }

        if constexpr (R::Switch::Ball::dotSize != 0)
        {
            beginPath();
            circle(isChecked() ? cir_x2 : cir_x1, cir_y, R::Switch::Ball::dotSize * this->fScaleFactor);
            fillColor(isChecked() ? R::color : R::Switch::Ball::borderColor);
            fill();
        }

        fillColor(R::color);
        fontSize(R::fontSize * this->fScaleFactor);
        textAlign(ALIGN_CENTER | ALIGN_BOTTOM);
        text(w * 0.5f, h, getName());
    }

    void updateSize(const bool updateChildren) override
    {
        updateReferenceSize<R>();
        BaseWidget::updateSize(updateChildren);
    }
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DGL
