// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../_lab/base.hpp"

#include "../reference.hpp"

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------

class PillToggleFrameWidget final : public LabReferenceWidget<Reference::Zero>
{
    using R = Reference::Zero;
    using BaseWidget = LabReferenceWidget<R>;

public:
    PillToggleFrameWidget(LabWidget* const parent)
        : BaseWidget(parent) {}
private:
    void onNanoDisplay() final
    {
        BaseWidget::onNanoDisplay();

        BaseWidget::fillColor(Reference::Colors::ink);
        BaseWidget::fontSize(Reference::Common::fontSize);
        BaseWidget::textAlign(BaseWidget::ALIGN_CENTER | BaseWidget::ALIGN_MIDDLE);
        BaseWidget::textLetterSpacing(Reference::Common::letterSpacing * this->fScaleFactor);
        BaseWidget::text(getWidth() * 0.5f, getHeight() * 0.5f, "This is a pill-toggle frame");
    }
};

// --------------------------------------------------------------------------------------------------------------------

} /* namespace LibreAudio */
