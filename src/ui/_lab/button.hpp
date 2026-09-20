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

protected:
    [[nodiscard]] const Color& getForegroundColor() const noexcept
    {
        if (! isEnabled())
            return R::color〡deactivated;

        if (isCheckable())
            return isChecked() ? R::backgroundColor : R::color;

        return R::color;
    }

    template <class TR>
    void drawReferenceText(const char* const text)
    {
        if (! isEnabled())
            return drawReferenceText<TR, TR::color〡deactivated>(text);

        if (isCheckable() && isChecked())
            return drawReferenceText<TR, TR::backgroundColor>(text);

        return drawReferenceText<TR, TR::color>(text);
    }

    template <class TR, const Color& color>
    void drawReferenceText(const char* const text)
    {
        if constexpr (d_isNotZero(color.alpha))
        {
            const float w = getWidth();
            const float h = getHeight();

            fillColor(color);
            fontSize(TR::fontSize * fScaleFactor);
            textAlign(ALIGN_CENTER | ALIGN_MIDDLE);
            textLetterSpacing(TR::letterSpacing * fScaleFactor);
            BaseWidget::text(w * 0.5f, h * 0.5f, text);
        }
    }

    void onNanoDisplay() override
    {
        if (isCheckable() && isChecked())
            drawReferenceBackground<R, R::color, corner>();
        else
            drawReferenceBackground<R, R::backgroundColor, corner>();

        drawReferenceBorder<R, R::borderColor>();
    }

    void updateSize(const bool updateChildren) override
    {
        updateReferenceSize<R>();
        BaseWidget::updateSize(updateChildren);
    }
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DGL
