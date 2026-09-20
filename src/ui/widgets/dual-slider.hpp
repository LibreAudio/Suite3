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
class DualSliderWidget final : public LabReferenceWidget<Reference::Widgets::DualSlider>,
                               private IdleCallback
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
        : BaseWidget(parent)
    {
        addIdleCallback(this);
    }

    bool setValueA(const float value, const bool sendCallback) noexcept
    {
        if (d_isEqual(fValueA, value))
            return false;

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
    float fValueA = kParameterA.init;
    float fValueB = kParameterB.init;

    inline float logscale(const float v) const
    {
        const float b = std::log(kMaximum / kMinimum) / (kMaximum - kMinimum);
        const float a = kMaximum / std::exp(kMaximum * b);
        return a * std::exp(b * v);
    }

    inline float invlogscale(const float v) const
    {
        const float b = std::log(kMaximum / kMinimum) / (kMaximum - kMinimum);
        const float a = kMaximum / std::exp(kMaximum * b);
        return std::log(v / a) / b;
    }

    void idleCallback() final
    {
        // NOTE this only triggers updates if the value doesnt match
        setValueA(fInterface->getParameterValue(kParametersMainStart + kParameterIdA), false);
        setValueB(fInterface->getParameterValue(kParametersMainStart + kParameterIdB), false);
    }

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

        strokeColor(R::color〡deactivated);
        beginPath();
        moveTo(0, h * 0.75f);
        lineTo(w, h * 0.75f);
        stroke();

        // ------------------------------------------------------------------------------------------------------------
        // draw dual-slider accent

        strokeColor(R::color);

        {
            const float xhp = (invlogscale(fValueA) - kMinimum) / (kMaximum - kMinimum) * w;
            const float xlp = (invlogscale(fValueB) - kMinimum) / (kMaximum - kMinimum) * w;

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

        float xa, xb;
        char textBuffer[24];

        fillColor(R::Name::color);
        fontFace("regular");
        fontSize(R::Name::fontSize * fScaleFactor);;

        std::snprintf(textBuffer,
                      sizeof(textBuffer),
                      "%.8s ",
                      *kParameterA.shortlabel != '\0' ? kParameterA.shortlabel :
                      *kParameterA.label != '\0' ? kParameterA.label : kParameterA.name);
        textBuffer[sizeof(textBuffer) - 1] = '\0';
        textAlign(ALIGN_LEFT | ALIGN_TOP);
        xa = text(0, 0, textBuffer);

        std::snprintf(textBuffer,
                      sizeof(textBuffer),
                      " %.8s",
                      *kParameterB.shortlabel != '\0' ? kParameterB.shortlabel :
                      *kParameterB.label != '\0' ? kParameterB.label : kParameterB.name);
        textBuffer[sizeof(textBuffer) - 1] = '\0';
        textAlign(ALIGN_RIGHT | ALIGN_TOP);
        xb = text(w, 0, textBuffer);

        fillColor(R::Value::color);
        fontFace("mono");
        fontSize(R::Value::fontSize * fScaleFactor);;

        std::snprintf(textBuffer, sizeof(textBuffer), "%.0f Hz", fValueA);
        textAlign(ALIGN_LEFT | ALIGN_TOP);
        text(xa, 0, textBuffer);

        std::snprintf(textBuffer, sizeof(textBuffer), "%.0f Hz", fValueB);
        textAlign(ALIGN_RIGHT | ALIGN_TOP);
        text(w - xa, 0, textBuffer);
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
            if (! contains(ev.pos))
                return false;

            const float pc = static_cast<double>(ev.pos.getX()) / getWidth();
            const float normA = (invlogscale(fValueA) - kMinimum) / (kMaximum - kMinimum);
            const float normB = (invlogscale(fValueB) - kMinimum) / (kMaximum - kMinimum);

            selectedParameter = std::abs(pc - normA) < std::abs(pc - normB) ? kParameterIdA : kParameterIdB;
            lastX = ev.pos.getX();
            lastY = ev.pos.getY();

            dragging = true;
            this->repaint();

            fInterface->parameterControlPressed(kParametersMainStart + selectedParameter);
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

        value = logscale(value);

        if (selectedParameter == kParameterIdA)
        {
            value = std::clamp(value, kParameterA.min, std::min(kParameterA.max, fValueB));
            setValueA(value, true);
        }
        else
        {
            value = std::clamp(value, std::max(kParameterB.min, fValueA), kParameterB.max);
            setValueB(value, true);
        }

        lastX = ev.pos.getX();
        lastY = ev.pos.getY();

        return true;
    }
};

// --------------------------------------------------------------------------------------------------------------------

} /* namespace LibreAudio */
