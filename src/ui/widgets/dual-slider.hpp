// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../_lab/base.hpp"

#include "../reference.hpp"

#include LIBREAUDIO_PLUGIN_PARAMETERS_INCLUDE

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------

template <FaustParameterIndex kParameterIdA, FaustParameterIndex kParameterIdB>
class DualSliderWidget final : public LabReferenceWidget<Reference::Widgets::DualSlider>
{
    using R = Reference::Widgets::DualSlider;
    using BaseWidget = LabReferenceWidget<R>;

    static constexpr const FaustParameter& kParameterA = kFaustParameters[kParameterIdA];
    static constexpr const FaustParameter& kParameterB = kFaustParameters[kParameterIdB];
    static_assert(kParameterA.max <= kParameterB.max, "param A vs B max mismatch");
    static_assert(kParameterA.min <= kParameterB.min, "param A vs B min mismatch");

    static constexpr const float kMaximum = d_max(kParameterA.max, kParameterB.max);
    static constexpr const float kMinimum = d_min(kParameterA.min, kParameterB.min);

public:
    explicit DualSliderWidget(LabWidget* const parent)
        : BaseWidget(parent) {}

    bool setValueA(const float value, const bool sendCallback) noexcept
    {
        if (d_isEqual(fValueA, value))
            return false;

        fAreaA = {};
        fValueA = value;
        this->repaint();

        if (sendCallback)
            fInterface->parameterControlModified(kParametersMainStart + kParameterIdA, value);

        return true;
    }

    bool setValueB(const float value, const bool sendCallback) noexcept
    {
        if (d_isEqual(fValueB, value))
            return false;

        fValueB = value;
        this->repaint();

        if (sendCallback)
            fInterface->parameterControlModified(kParametersMainStart + kParameterIdB, value);

        return true;
    }

private:
    Rectangle<int> fAreaA;
    Rectangle<int> fAreaB;

    float fValueA = kParameterA.init;
    float fValueB = kParameterB.init;

    void onNanoDisplay() final
    {
        const float w = getWidth();
        const float h = getHeight();

        // ------------------------------------------------------------------------------------------------------------
        // draw background

        BaseWidget::onNanoDisplay();

        // ------------------------------------------------------------------------------------------------------------
        // draw dual-slider background

        strokeWidth(3 * fScaleFactor);

        strokeColor(Reference::Colors::ink3);
        beginPath();
        moveTo(0, h * 0.75f);
        lineTo(w, h * 0.75f);
        stroke();

        // ------------------------------------------------------------------------------------------------------------
        // draw dual-slider accent

        strokeColor(R::color);

        {
            const float xhp = (fValueA - kMinimum) / (kMaximum - kMinimum) * w;
            const float xlp = (fValueB - kMinimum) / (kMaximum - kMinimum) * w;

            beginPath();
            moveTo(xhp, h * 0.5f);
            lineTo(xhp, h);
            stroke();

            beginPath();
            moveTo(xlp, h * 0.5f);
            lineTo(xlp, h);
            stroke();

            beginPath();
            moveTo(xhp, h * 0.75f);
            lineTo(xlp, h * 0.75f);
            stroke();
        }

        // ------------------------------------------------------------------------------------------------------------
        // draw text

        fillColor(Reference::Colors::ink);
        fontSize(Reference::Common::fontSize * this->fScaleFactor);
        textAlign(ALIGN_CENTER | ALIGN_MIDDLE);
        textLetterSpacing(Reference::Common::letterSpacing * this->fScaleFactor);
        text(getWidth() * 0.5f, getHeight() * 0.5f, "This is a dual-slider");

        beginPath();
        rect(fAreaA.getX(), fAreaA.getY(), fAreaA.getWidth(), fAreaA.getHeight());
        fillColor(Reference::Colors::acc2);
        fill();
    }

    bool dragging = false;
    double lastX = -1;
    double lastY = -1;
    Point<double> lastMotionPos;
    FaustParameterIndex selectedParameter = kParameterIdA;

    bool onMouse(const Widget::MouseEvent& ev) final
    {
        if (ev.button != 1)
            return false;

        if (ev.press)
        {
            if (fAreaA.contains(ev.pos))
                selectedParameter = kParameterIdA;
            else if (fAreaB.contains(ev.pos))
                selectedParameter = kParameterIdB;
            else
                return false;

            lastX = ev.pos.getX();
            lastY = ev.pos.getY();

            dragging = true;
            this->repaint();

            fInterface->parameterControlPressed(kParametersMainStart +selectedParameter);
            // if (callback != nullptr)
            //     callback->knobDragStarted(this);

            return true;
        }
        else if (dragging)
        {
            dragging = false;
            this->repaint();

            fInterface->parameterControlReleased(kParametersMainStart +selectedParameter);
            // if (callback != nullptr)
            //     callback->knobDragFinished(widget);

            return true;
        }

        return false;
    }

    bool onMotion(const Widget::MotionEvent& ev) final
    {
        if (! dragging)
            return false;

        if (d_isZero(ev.pos.getX() - lastX))
            return true;

        const double pc = static_cast<double>(ev.pos.getX()) / getWidth();
        float value = std::clamp<float>(kMinimum + pc * (kMaximum - kMinimum), kMinimum, kMaximum);

        if (selectedParameter == kParameterIdA)
        {
            value = std::clamp(value, kParameterA.min, kParameterA.max);
            setValueA(value, true);
        }
        else
        {
            value = std::clamp(value, kParameterB.min, kParameterB.max);
            setValueB(value, true);
        }

        lastX = ev.pos.getX();
        lastY = ev.pos.getY();

        return true;
    }

    void updateSize(const bool updateChildren) final
    {
        fAreaA = {};
        fAreaB = {};
        BaseWidget::updateSize(updateChildren);
    }
};

// --------------------------------------------------------------------------------------------------------------------

} /* namespace LibreAudio */
