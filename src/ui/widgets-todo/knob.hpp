// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../base/knob.hpp"
#include "../reference.hpp"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

template <class R>
class LibreAudioDrawableKnobWidget final : public LibreAudioKnobWidget
{
    static constexpr const double kTimeForShowingHostParameterChanges = 1;
    static constexpr const double kTimeForValueFadeout = 0.1;

public:
    LibreAudioDrawableKnobWidget(LibreAudioWidget* const parent, const FaustParameter& parameter, const uint32_t id)
        : LibreAudioKnobWidget(parent, parameter, id)
    {
        if constexpr (R::width != 0)
            LibreAudioWidget::setWidth(d_roundToUnsignedInt(R::width * fScaleFactor));

        if constexpr (R::height != 0)
            LibreAudioWidget::setHeight(d_roundToUnsignedInt(R::height * fScaleFactor));

        fKnobStyle.bipolar = d_isZero(parameter.init) && parameter.min < 0 && parameter.max > 0;
        fKnobStyle.invert = d_isEqual(parameter.init, parameter.max);

        Rectangle<float> bounds;
        fontFace("mono");
        fontSize(R::Unit::fontSize * this->fScaleFactor);
        textAlign(0);
        // textLetterSpacing(R::Unit::letterSpacing * this->fScaleFactor);
        textBounds(0, 0, fParameter.unit, nullptr, bounds);

        fUnitTextSpacing = std::abs(bounds.getX() * 2);
        fUnitTextWidth = bounds.getWidth();
    }

private:
    void onNanoDisplay() final
    {
        const float w = getWidth();
        const float h = getHeight();
        const float cx = w * 0.5f;
        const float cy = R::width * 0.5f * fScaleFactor;

        char textBuffer[24];

        if (const double timeNow = getTime();
            (getState() & kKnobStateDraggingHover) != 0 ||
            timeNotEllapsed(fLastParameterChangedByHostTime, kTimeForShowingHostParameterChanges, timeNow) ||
            timeNotEllapsed(fLastStateChangedTime, kTimeForValueFadeout, timeNow))
        {
            if (isInteger())
                std::snprintf(textBuffer, sizeof(textBuffer), "%d", d_roundToInt(getValue()));
            else
                std::snprintf(textBuffer, sizeof(textBuffer), "%.2f", getValue());
            textBuffer[sizeof(textBuffer) - 1] = '\0';

            textAlign(ALIGN_CENTER | ALIGN_BOTTOM);

            fillColor(isEnabled() ? R::Value::color : fKnobStyle.colorDisabled);
            fontFace("mono");
            fontSize(R::Value::fontSize * fScaleFactor);

            if (*fParameter.unit == '\0')
            {
                // no unit, draw value in the center
                text(w * 0.5f, h, textBuffer);
            }
            else
            {
                // has unit, put value on the left
                textAlign(ALIGN_RIGHT | ALIGN_BOTTOM);
                text(w - fUnitTextWidth - fUnitTextSpacing, h, textBuffer);

                // then unit on the right
                fillColor(isEnabled() ? R::Unit::color : fKnobStyle.colorDisabled);
                fontSize(R::Unit::fontSize * fScaleFactor);
                textAlign(ALIGN_LEFT | ALIGN_BOTTOM);
                text(w - fUnitTextWidth, h, fParameter.unit);
            }
        }
        else
        {
            fillColor(isEnabled() ? R::Name::color : fKnobStyle.colorDisabled);
            fontSize(R::Name::fontSize * fScaleFactor);
            textAlign(ALIGN_CENTER | ALIGN_BOTTOM);

            std::snprintf(textBuffer,
                          sizeof(textBuffer),
                          "%.8s",
                          *fParameter.label != '\0' ? fParameter.label : fParameter.name);
            textBuffer[sizeof(textBuffer) - 1] = '\0';
            text(w * 0.5f, h, textBuffer);
        }

#if 1
        const float size = w;

        constexpr float MIN_A = -150.0f;
        constexpr float MAX_A = 150.0f;
        constexpr float SWEEP = MAX_A - MIN_A;
        constexpr float rBody = 30.0f;
        constexpr float AW = 12.0f;
        constexpr float rArc = rBody + AW * 0.5f;
        const float S = size / 100.0f;

        const float norm = getNormalizedValue();
        const float valAngle   = MIN_A + norm * SWEEP;
        const float startAngle = fKnobStyle.invert ? MAX_A : (fKnobStyle.bipolar ? 0.0f : MIN_A);

        const Color& accent = isEnabled() ? fKnobStyle.colorAccent : fKnobStyle.colorDisabled;

        save();
        translate(cx, cy);
        scale(S, S);
        translate(-50.0f, -50.0f);

        // /* --- gutter track: full sweep, accent-tinted inset ----------------- */
        // color-mix(in srgb, accent 40%, #0a0a0d)
        const Color gutter = Color(Color(0x0a, 0x0a, 0x0d), accent, 0.4f);
        knobBand(50, 50, rArc, AW, MIN_A, MAX_A, nullptr, gutter);

        /* --- value fill: flat accent, recessed into the gutter -------------- */
        knobBand(50, 50, rArc, AW, startAngle, valAngle, nullptr, accent);

        /* inset shadow (SVG filter #gutter-inset): darken both band edges */
        {
            constexpr float insetDepth = 1.5f;
            const float rIn = rArc - AW * 0.5f;
            const float rOut = rArc + AW * 0.5f;
            const Color dark = Color(0, 0, 0, 70.f / 255.f);
            const Color clear = Color(0, 0, 0, 0.f);

            Paint insetIn = radialGradient(50, 50, rIn, rIn + insetDepth, dark, clear);
            knobBand(50, 50, rArc, AW, startAngle, valAngle, &insetIn, accent);

            Paint insetOut = radialGradient(50, 50, rOut - insetDepth, rOut, clear, dark);
            knobBand(50, 50, rArc, AW, startAngle, valAngle, &insetOut, accent);
        }

        /* --- cast shadow under the cap, clipped to the gutter band --------- */
        /* full-alpha core out to rBody+0.5, then a short blur to transparent */
        Paint sh = radialGradient(50, 53, rBody + 0.5f, rBody + 3.2f,
                                  Color(0, 0, 0, 70.f / 255.f), Color(0, 0, 0, 0));
        knobBand(50, 50, rArc, AW, MIN_A, MAX_A, &sh, Color(0, 0, 0, 0));

        /* --- knob body: vertical gradient + dark rim ----------------------- */
        Paint body = linearGradient(50, 50 - rBody, 50, 50 + rBody,
                                       Color(0x4a,0x4a,0x51), Color(0x3a,0x3a,0x41));
        beginPath();
        circle(50, 50, rBody);
        fillPaint(body);
        fill();
        strokeColor(Color(0x0d,0x0d,0x0f));
        strokeWidth(1.0f);
        stroke();

        /* --- top bevel highlight (screen-blend approximated by additive-ish
        *     white with low alpha along the upper rim) --------------------- */
        Paint bevel = linearGradient(50, 50 - rBody, 50, 50,
                                     Color(255, 255, 255, 140.f / 255.f), Color(255, 255, 255, 0));
        beginPath();
        circle(50, 49.4f, rBody - 0.9f);
        strokeWidth(1.0f);
        strokePaint(bevel);
        stroke();

        /* --- pointer line -------------------------------------------------- */
        float lx0, ly0, lx1, ly1;
        knobPt(50, 50, 17, valAngle, lx0, ly0);
        knobPt(50, 50, 24, valAngle, lx1, ly1);
        beginPath();
        moveTo(lx0, ly0);
        lineTo(lx1, ly1);
        strokeColor(accent);
        strokeWidth(size > 100.0f ? 2.0f : 2.0f * 100.0f / size);
        lineCap(ROUND);
        stroke();

        restore();
#endif
    }

    void idleCallback() final
    {
        LibreAudioKnobWidget::idleCallback();

        if (timeEllapsed(fLastParameterChangedByHostTime, kTimeForShowingHostParameterChanges))
        {
            fLastParameterChangedByHostTime = 0.0;
            repaint();
        }

        if (timeEllapsed(fLastStateChangedTime, kTimeForValueFadeout))
        {
            fLastStateChangedTime = 0.0;
            repaint();
        }
    }

    void parameterChangedByHost() final
    {
        fLastParameterChangedByHostTime = getTime();
    }

    void stateChanged(const State state, const State oldState) final
    {
        LibreAudioKnobWidget::stateChanged(state, oldState);

        fLastStateChangedTime = getTime();
    }

    double fLastParameterChangedByHostTime = 0.0;
    double fLastStateChangedTime = 0.0;

    float fUnitTextSpacing;
    float fUnitTextWidth;

#if 1
    struct KnobStyle {
        Color colorAccent;
        Color colorDisabled;
        bool bipolar;
        bool invert;
    };
    KnobStyle fKnobStyle = {
        .colorAccent = {0xc3, 0xd9, 0xff},
        .colorDisabled = {0x5d, 0x5d, 0x66},
        .bipolar = true,
        .invert = false,
    };

    static inline constexpr float knobRad(float deg)
    {
        return (deg - 90.f) * M_PI / 180.f;
    }

    static inline void knobPt(float cx, float cy, float r, float deg, float& x, float& y)
    {
        const float a = deg * M_PI / 180.f;
        x = cx + r * std::sin(a);
        y = cy - r * std::cos(a);
    }

    void knobBand(float cx, float cy, float rArc, float w, float a0, float a1, Paint* paint, Color solid)
    {
        float lo = a0 < a1 ? a0 : a1;
        float hi = a0 < a1 ? a1 : a0;
        if (hi - lo < 0.05f)
            return;

        beginPath();
        arc(cx, cy, rArc, knobRad(lo), knobRad(hi), CW);
        strokeWidth(w);
        lineCap(BUTT);

        if (paint)
            strokePaint(*paint);
        else
            strokeColor(solid);

        stroke();
    }
#endif
};

using LibreAudioEasyKnobWidget = LibreAudioDrawableKnobWidget<LibreAudioReference::Widgets::EasyKnob>;
using LibreAudioSmallKnobWidget = LibreAudioDrawableKnobWidget<LibreAudioReference::Widgets::Knob>;

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
