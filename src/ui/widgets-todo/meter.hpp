// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../base/knob.hpp"
#include "../reference.hpp"

#include "LibreAudioParameters.hpp"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

enum LibreAudioMeterWidgetType {
    Input,
    Output
};

template<LibreAudioMeterWidgetType type>
class LibreAudioMeterWidget final : public LibreAudioKnobWidget
{
    using R = LibreAudioReference::Meter;

    static constexpr const uint kParameterL = type == Input
        ? kParametersInputStart + common_input::kFaustParameterInput_peak_l
        : kParametersOutputStart + common_output::kFaustParameterOutput_peak_l - 1;
    static constexpr const uint kParameterR = type == Input
        ? kParametersInputStart + common_input::kFaustParameterInput_peak_r
        : kParametersOutputStart + common_output::kFaustParameterOutput_peak_r - 1;
    static constexpr const uint kParameterMeter = type == Input
        ? kParametersInputStart + common_input::kFaustParameterInput_trim
        : kParametersOutputStart + common_output::kFaustParameterOutput_trim - 1;

    static const FaustParameter& getFaustParameter()
    {
        if constexpr (type == Input)
            return common_input::getFaustParameters().at(common_input::kFaustParameterInput_trim);
        else
            return common_output::getFaustParameters().at(common_output::kFaustParameterOutput_trim);
    }

public:
    LibreAudioMeterWidget(LibreAudioWidget* const parent)
        : LibreAudioKnobWidget(parent, getFaustParameter(), kParameterMeter)
    {
        if constexpr (R::width != 0)
            LibreAudioWidget::setWidth(d_roundToUnsignedInt(R::width * fScaleFactor));

        if constexpr (R::height != 0)
            LibreAudioWidget::setHeight(d_roundToUnsignedInt(R::height * fScaleFactor));
    }

private:
    // FIXME non-hardcoded
    static constexpr const float min = -70.0;
    static constexpr const float max = 12.0;

    static constexpr const float linearPointDB = -12.f;
    static constexpr const float linearPointPC = 0.48f;

    // NOTE major tick at 0dB, these are minor ticks
    static constexpr const float ticks[] = { +12, +6, -12, -24, -36, -48 };

    float fValueL = min;
    float fValueR = min;

    constexpr inline float db2height(const float db, const float height) const noexcept
    {
        if (db >= linearPointDB)
        {
            const float normalized = 1.f - d_clamp((db - linearPointDB) / (max - linearPointDB), 0.f, 1.f);
            return (1.f - linearPointPC) * height * normalized;
        }

        const float normalized = 1.f - d_clamp(db / (min - linearPointDB), 0.f, 1.f);
        return height - linearPointPC * height * normalized;
    }

    void idleCallback() final
    {
        if (const float valueL = std::clamp(fInterface->getParameterValue(kParameterL), min, max);
            d_isNotEqual(fValueL, valueL))
        {
            fValueL = valueL;
            repaint();
        }

        if (const float valueR = std::clamp(fInterface->getParameterValue(kParameterR), min, max);
            d_isNotEqual(fValueR, valueR))
        {
            fValueR = valueR;
            repaint();
        }
    }

    void onNanoDisplay() final
    {
        const float w = getWidth();
        const float h = getHeight();

        const float border = (R::border + R::margin) * fScaleFactor;
        const float startx = border;
        const float starty = border;
        const float endx = w - startx;
        const float endy = h - border;
        const float mheight = h - starty;

        // ------------------------------------------------------------------------------------------------------------
        // draw background

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

        scissor(R::border * fScaleFactor,
                R::border * fScaleFactor,
                w - R::border * 2 * fScaleFactor,
                h - R::border * 2 * fScaleFactor);

        // ------------------------------------------------------------------------------------------------------------
        // draw meters

        {
            const float tc = startx + (w - startx * 2) * 0.5f;
            const float tw = R::Track::width * fScaleFactor - 0.5f * fScaleFactor;

            fillPaint(linearGradient(0, 0, 0, h, R::Track::colorGradientStart, R::Track::colorGradientStop));

            if (d_isNotEqual(fValueL, min))
            {
                const float lh = db2height(fValueL, mheight);

                beginPath();
                rect(startx, startx + lh, tw, endy - lh);
                fill();
            }

            if (d_isNotEqual(fValueR, min))
            {
                const float rh = db2height(fValueR, mheight);

                beginPath();
                rect(tc + fScaleFactor * 0.5f, startx + rh, tw, endy - rh);
                fill();
            }
        }

        // ------------------------------------------------------------------------------------------------------------
        // draw border

        if constexpr (R::border != 0 && d_isNotZero(R::borderColor.alpha))
        {
            beginPath();

            if constexpr (R::borderRadius != 0)
                roundedRect(0, 0, w, h, R::borderRadius * fScaleFactor);
            else
                rect(0, 0, w, h);

            strokeColor(R::borderColor);
            strokeWidth(R::border * 2 * fScaleFactor);
            stroke();
        }

        // ------------------------------------------------------------------------------------------------------------
        // draw ticks

        strokeWidth(R::Tick::height * fScaleFactor);

        // major
        {
            strokeColor(R::Tick::colorMaj);
            const float tpos = db2height(0, mheight);
            beginPath();
            moveTo(startx, starty + tpos);
            lineTo(endx, starty + tpos);
            stroke();
        }

        // minor
        strokeColor(R::Tick::color);
        for (float tick : ticks)
        {
            const float tpos = db2height(tick, mheight);
            beginPath();
            moveTo(startx, starty + tpos);
            lineTo(endx, starty + tpos);
            stroke();
        }

        // ------------------------------------------------------------------------------------------------------------
        // draw slider

        {
            const float tpos = db2height(fInterface->getParameterValue(kParameterMeter), mheight);

            strokeColor(R::Slider::color);
            strokeWidth(R::Slider::height * fScaleFactor);

            beginPath();
            moveTo(0, starty + tpos);
            lineTo(w, starty + tpos);
            stroke();

            beginPath();
            rect(0, starty + tpos, w, endy - starty);
            fillPaint(linearGradient(0, 0, 0, h, R::Slider::colorGradientStart, R::Slider::colorGradientStop));
            fill();
        }

        // ------------------------------------------------------------------------------------------------------------
        // draw labels

    }
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
