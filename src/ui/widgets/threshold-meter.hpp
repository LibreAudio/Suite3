// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../_lab/knob.hpp"

#include "../reference.hpp"

#include "FaustParameters.hpp"
#include "LibreAudioParameters.hpp"

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------

class ThresholdMeterWidget final : public LabKnobWidget
{
    using R = Reference::ThresholdMeter;
    using BaseWidget = LabKnobWidget;

public:
    ThresholdMeterWidget(LabWidget* const parent, const FaustParameter& parameter)
        : BaseWidget(parent, 0),
          fParameter(parameter)
    {
        updateReferenceSize<R>();

        setName(fParameter.label);
        setDefault(fParameter.init);
        setRange(fParameter.min, fParameter.max);
        setStep(fParameter.step);
        // setUsingLogScale(fParameter.isLogarithmic); // FIXME
        setValue(fParameter.init, false);
    }

private:
    const FaustParameter& fParameter;

    float fValueL = fParameter.min;
    float fValueR = fParameter.min;

    bool fDrawingBackground = false;

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
        // TODO
    }

    void onNanoDisplay() final
    {
        // ------------------------------------------------------------------------------------------------------------
        // draw background

        fDrawingBackground = true;
        drawReferenceBackground<R>();

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
