// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../_lab/button.hpp"

#include "../reference.hpp"

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------

class ComboBoxWidget final : public ReferenceButtonWidget<Reference::Widgets::Button, kCornerBoth>
{
    using R = Reference::Widgets::Button;
    using BaseWidget = ReferenceButtonWidget<R, kCornerBoth>;

public:
    explicit ComboBoxWidget(LabWidget* const parent, const uint id, const char* const name)
        : BaseWidget(parent)
    {
        setId(id);
        setName(name);
        setSize(90 * fScaleFactor, 30 * fScaleFactor);
    }

    explicit ComboBoxWidget(LabWidget* const parent, const uint id, const FaustParameter& parameter)
        : BaseWidget(parent)
    {
        setId(id);
        setName(parameter.name);
        setSize(90 * fScaleFactor, 30 * fScaleFactor);
    }

private:
    void onNanoDisplay() final
    {
        BaseWidget::onNanoDisplay();

        BaseWidget::fillColor(BaseWidget::isEnabled() ? Reference::Colors::ink : Reference::Colors::ink3);
        BaseWidget::fontSize(Reference::Common::fontSize);
        BaseWidget::textAlign(BaseWidget::ALIGN_CENTER | BaseWidget::ALIGN_MIDDLE);
        BaseWidget::textLetterSpacing(Reference::Common::letterSpacing * this->fScaleFactor);
        BaseWidget::text(getWidth() * 0.5f, getHeight() * 0.5f, "combo-box");
    }
};

// --------------------------------------------------------------------------------------------------------------------

} /* namespace LibreAudio */
