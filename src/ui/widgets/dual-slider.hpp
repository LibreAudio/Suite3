// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../_lab/base.hpp"

#include "../reference.hpp"

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------

class DualSliderWidget final : public LabReferenceWidget<Reference::Widgets::DualSlider>
{
    using R = Reference::Widgets::DualSlider;
    using BaseWidget = LabReferenceWidget<R>;

public:
    explicit DualSliderWidget(LabWidget* const parent)
        : BaseWidget(parent) {}

private:
    void onNanoDisplay() final
    {
        BaseWidget::onNanoDisplay();

        const float w = getWidth();
        const float h = getHeight();

        strokeWidth(3 * fScaleFactor);

        strokeColor(Reference::Colors::ink3);
        beginPath();
        moveTo(0, h * 0.75f);
        lineTo(w, h * 0.75f);
        stroke();

        strokeColor(R::color);
        beginPath();
        moveTo(30 * fScaleFactor, h * 0.5f);
        lineTo(30 * fScaleFactor, h);
        stroke();

        beginPath();
        moveTo(w - 60 * fScaleFactor, h * 0.5f);
        lineTo(w - 60 * fScaleFactor, h);
        stroke();

        fillColor(Reference::Colors::ink);
        fontSize(Reference::Common::fontSize * this->fScaleFactor);
        textAlign(ALIGN_CENTER | ALIGN_MIDDLE);
        textLetterSpacing(Reference::Common::letterSpacing * this->fScaleFactor);
        text(getWidth() * 0.5f, getHeight() * 0.5f, "This is a dual-slider");
    }
};

// --------------------------------------------------------------------------------------------------------------------

} /* namespace LibreAudio */
