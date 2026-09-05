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

    [[nodiscard]] Corner getCorner() const noexcept override
    {
        __builtin_unreachable();
    }

protected:
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
        drawReferenceBackground<R, corner>();
    }

    void updateSize(const bool updateChildren) override
    {
        updateReferenceSize<R>();
        BaseWidget::updateSize(updateChildren);
    }
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DGL
