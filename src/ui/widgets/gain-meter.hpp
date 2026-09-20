// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../_lab/knob.hpp"

#include "DistrhoPluginInfo.h"

#if ! LIBREAUDIO_WANT_COMMON_IO
#error Cannot include this file for plugins without common IO
#endif

#include "../reference.hpp"

#include "LibreAudioParameters.hpp"

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------

enum MeterWidgetType : bool {
    Input,
    Output
};

template<MeterWidgetType type>
class GainMeterWidget final : public LabKnobWidget
{
    using R = Reference::GainMeter;
    using BaseWidget = LabKnobWidget;

    static constexpr const uint kParameterIdMeterL = type == Input
        ? kParametersInputStart + common_input::kFaustParameterInput_peak_l
        : kParametersOutputStart + common_output::kFaustParameterOutput_peak_l - kCommonIOParameters;
    static constexpr const uint kParameterIdMeterR = type == Input
        ? kParametersInputStart + common_input::kFaustParameterInput_peak_r
        : kParametersOutputStart + common_output::kFaustParameterOutput_peak_r - kCommonIOParameters;
    static constexpr const uint kParameterIdGain = type == Input
        ? kParametersInputStart + common_input::kFaustParameterInput_trim
        : kParametersOutputStart + common_output::kFaustParameterOutput_trim - kCommonIOParameters;

    static constexpr const FaustParameter& kParameterMeterL = type == Input
        ? common_input::kFaustParameters[common_input::kFaustParameterInput_peak_l]
        : common_output::kFaustParameters[common_output::kFaustParameterOutput_peak_l];
    static constexpr const FaustParameter& kParameterMeterR = type == Input
        ? common_input::kFaustParameters[common_input::kFaustParameterInput_peak_r]
        : common_output::kFaustParameters[common_output::kFaustParameterOutput_peak_r];
    static constexpr const FaustParameter& kParameterGain = type == Input
        ? common_input::kFaustParameters[common_input::kFaustParameterInput_trim]
        : common_output::kFaustParameters[common_output::kFaustParameterOutput_trim];

    static_assert(kParameterGain.max <= kParameterMeterL.max, "gain vs meter max mismatch");
    static_assert(kParameterGain.min >= kParameterMeterL.min, "gain vs meter min mismatch");
    static_assert(kParameterMeterL.max == kParameterMeterR.max, "meter L vs R max mismatch");
    static_assert(kParameterMeterL.min == kParameterMeterR.min, "meter L vs R min mismatch");

    static constexpr const float linearPointDB = -12.f;
    static constexpr const float linearPointPC = 0.48f;

    // NOTE major tick at 0dB, these are minor ticks
    static constexpr const float ticks[] = { +12, +6, -12, -24, -36, -48 };

public:
    GainMeterWidget(LabWidget* const parent)
        : BaseWidget(parent, kParameterIdGain)
    {
        updateReferenceSize<R>();

        setName(kParameterGain.label);
        setDefault(kParameterGain.init);
        setRange(kParameterGain.min, kParameterGain.max);
        setStep(kParameterGain.step);
        // setUsingLogScale(kParameterGain.isLogarithmic); // FIXME
        setValue(kParameterGain.init, false);
    }

private:
    float fValueL = kParameterGain.min;
    float fValueR = kParameterGain.min;

    bool fDrawingBackground = false;

    [[nodiscard]] float db2height(const float db, const float height) noexcept
    {
        if (db >= linearPointDB)
        {
            const float normalized = 1.f - d_clamp((db - linearPointDB) / (kParameterGain.max - linearPointDB), 0.f, 1.f);
            return d_roundToIntPositive(linearPointPC * height * normalized);
        }

        const float normalized = 1.f - d_clamp((db - linearPointDB) / (kParameterGain.min - linearPointDB), 0.f, 1.f);
        return d_roundToIntPositive(height - (1.f - linearPointPC) * height * normalized);
    }

    [[nodiscard]] const Color& getBackgroundColor() const noexcept final
    {
        return fDrawingBackground ? R::backgroundColor : Reference::Colors::transparent;
    }

    [[nodiscard]] const Color& getBorderColor() const noexcept final
    {
        return !fDrawingBackground ? R::borderColor : Reference::Colors::transparent;
    }

    [[nodiscard]] Corner getCorner() const noexcept final
    {
        return kCornerBoth;
    }

    void idleCallback() final
    {
        if (const float valueL = std::clamp(fInterface->getParameterValue(kParameterIdMeterL), kParameterMeterL.min, kParameterMeterL.max);
            d_isNotEqual(fValueL, valueL))
        {
            fValueL = valueL;
            repaint();
        }

        if (const float valueR = std::clamp(fInterface->getParameterValue(kParameterIdMeterR), kParameterMeterR.min, kParameterMeterR.max);
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

        fDrawingBackground = true;
        drawReferenceBackground<R>();

        // ------------------------------------------------------------------------------------------------------------
        // prevent drawing over the border

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

            if (d_isNotEqual(fValueL, kParameterGain.min))
            {
                const float lh = db2height(fValueL, mheight);

                beginPath();
                rect(startx, startx + lh, tw, endy - lh);
                fill();
            }

            if (d_isNotEqual(fValueR, kParameterGain.min))
            {
                const float rh = db2height(fValueR, mheight);

                beginPath();
                rect(tc + fScaleFactor * 0.5f, startx + rh, tw, endy - rh);
                fill();
            }
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
            const float tposx = R::border * fScaleFactor;
            const float tposy = starty + db2height(fInterface->getParameterValue(kParameterIdGain), mheight);

            strokeColor(R::Slider::color);
            strokeWidth(R::Slider::height * fScaleFactor);

            beginPath();
            moveTo(tposx, tposy);
            lineTo(w - tposx, tposy);
            stroke();

            beginPath();
            rect(tposx, tposy, w - tposx * 2, endy - starty);
            fillPaint(linearGradient(0, 0, 0, h, R::Slider::colorGradientStart, R::Slider::colorGradientStop));
            fill();
        }

        // ------------------------------------------------------------------------------------------------------------
        // draw labels

        if ((getState() & kKnobStateDraggingHover) != 0)
        {
            fillColor(R::Unit::color);
            fontFace("regular");
            fontSize(R::Unit::fontSize * fScaleFactor);
            textAlign(ALIGN_CENTER | ALIGN_BOTTOM);
            // textLetterSpacing(R::Value::letterSpacing * fScaleFactor);
            text(w * 0.5f, endy, kParameterGain.unit);

            char textBuffer[24];

            if (isInteger())
                std::snprintf(textBuffer, sizeof(textBuffer), "%d", d_roundToInt(getValue()));
            else
                std::snprintf(textBuffer, sizeof(textBuffer), "%.1f", getValue());
            textBuffer[sizeof(textBuffer) - 1] = '\0';

            fillColor(R::Value::color);
            fontFace("mono");
            fontSize(R::Value::fontSize * fScaleFactor);
            textAlign(ALIGN_CENTER | ALIGN_TOP);
            // textLetterSpacing(R::Value::letterSpacing * fScaleFactor);
            text(w * 0.5f, starty, textBuffer);
        }

        // ------------------------------------------------------------------------------------------------------------
        // draw border

        fDrawingBackground = false;
        drawReferenceBackground<R>();
    }

    void updateSize(const bool updateChildren) final
    {
        updateReferenceSize<R>();
        BaseWidget::updateSize(updateChildren);
    }
};

// --------------------------------------------------------------------------------------------------------------------

} /* namespace LibreAudio */
