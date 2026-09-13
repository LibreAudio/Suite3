// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../_lab/base.hpp"

#include "../reference.hpp"

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------

class DualSliderWidget final : public LabReferenceWidget<Reference::Widgets::Button>
{
    using R = Reference::Widgets::Button;
    using BaseWidget = LabReferenceWidget<R>;

public:
    explicit DualSliderWidget(LabWidget* const parent)
        : BaseWidget(parent)
    {
        setSize(90 * fScaleFactor, 30 * fScaleFactor);
    }

private:
    void onNanoDisplay() final
    {
        BaseWidget::onNanoDisplay();

        BaseWidget::fillColor(Reference::Colors::ink);
        BaseWidget::fontSize(Reference::Common::fontSize * this->fScaleFactor);
        BaseWidget::textAlign(BaseWidget::ALIGN_CENTER | BaseWidget::ALIGN_MIDDLE);
        BaseWidget::textLetterSpacing(Reference::Common::letterSpacing * this->fScaleFactor);
        BaseWidget::text(getWidth() * 0.5f, getHeight() * 0.5f, "This is a dual-slider");
    }

    void updateSize(const bool updateChildren) final
    {
        BaseWidget::setHeight(30 * fScaleFactor);
        BaseWidget::updateSize(updateChildren);
    }
};

// --------------------------------------------------------------------------------------------------------------------

} /* namespace LibreAudio */
