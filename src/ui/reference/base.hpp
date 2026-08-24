// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../base/base.hpp"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------
// reference widget class

template<class R>
class LibreAudioReferenceWidget : public LibreAudioWidget
{
public:
    explicit LibreAudioReferenceWidget(LibreAudioTopLevelWidget* const parent)
        : LibreAudioWidget(parent)
    {
        updateSize(false);
    }

    explicit LibreAudioReferenceWidget(LibreAudioWidget* const parent)
        : LibreAudioWidget(parent)
    {
        updateSize(false);
    }

protected:
    void onNanoDisplay() override
    {
        const float w = getWidth();
        const float h = getHeight();

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

        if constexpr (R::border != 0 && d_isNotZero(R::borderColor.alpha))
        {
            const float border = d_roundToIntPositive(R::border * fScaleFactor);
            const float borderh = border * 0.5f;

            const float sx = borderh;
            const float sy = borderh;
            const float ex = w - borderh;
            const float ey = h - borderh;

            beginPath();

            if constexpr (R::borderRadius != 0)
            {
                const float borderRadius = R::borderRadius * fScaleFactor;
                DISTRHO_SAFE_ASSERT_RETURN(borderRadius < w * 0.5f,);
                DISTRHO_SAFE_ASSERT_RETURN(borderRadius < h * 0.5f,);
                DISTRHO_SAFE_ASSERT_RETURN(borderRadius > border,);

                const float arcRadius = borderRadius - border;

                pathWinding(CW);
                moveTo(sx + borderRadius, sy);
                arcTo(sx, sy, sx, ey - borderRadius, arcRadius);
                lineTo(sx, ey - borderRadius);
                arcTo(sx, ey, sx + borderRadius, ey, arcRadius);
                lineTo(ex - borderRadius, ey);
                arcTo(ex, ey, ex, ey - borderRadius, arcRadius);
                lineTo(ex, sx + borderRadius);
                arcTo(ex, sy, ex - borderRadius, sy, arcRadius);
            }
            else
            {
                moveTo(sx, sy);
                lineTo(sx, ey);
                lineTo(ex, ey);
                lineTo(ex, sy);
            }

            closePath();
            strokeColor(R::borderColor);
            strokeWidth(border);
            stroke();
        }
    }

    void updateSize(const bool updateChildren) override
    {
        if constexpr (R::width != 0)
            setWidth(d_roundToUnsignedInt(R::width * fScaleFactor));

        if constexpr (R::height != 0)
            setHeight(d_roundToUnsignedInt(R::height * fScaleFactor));

        LibreAudioWidget::updateSize(updateChildren);
    }
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
