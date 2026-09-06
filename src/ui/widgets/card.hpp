// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../lab/button.hpp"
#include "../reference.hpp"

#include "las-resources.h"

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------

template<class R = Reference::Widgets::Card>
class LabCardWidget : public ReferenceButtonWidget<R, kCornerBoth>
{
    using BaseWidget = ReferenceButtonWidget<R, kCornerBoth>;

public:
    explicit LabCardWidget(LabWidget* const parent, const char* const title, const char* const subtitle)
        : BaseWidget(parent),
          fTitle(title),
          fSubtitle(subtitle)
    {
        BaseWidget::updateSize(false);
    }

private:
    const char* const fTitle;
    const char* const fSubtitle;

    void onNanoDisplay() final
    {
        BaseWidget::onNanoDisplay();

        const float w = BaseWidget::getWidth();
        const float h = BaseWidget::getHeight();

        const uint margin = d_roundToUnsignedInt(R::margin * this->fScaleFactor);

        BaseWidget::fillColor(this->getForegroundColor());
        BaseWidget::fontSize(R::fontSize * this->fScaleFactor);
        BaseWidget::textAlign(BaseWidget::ALIGN_CENTER | BaseWidget::ALIGN_TOP);
        BaseWidget::textLetterSpacing(R::letterSpacing * this->fScaleFactor);
        BaseWidget::text(w * 0.5f, margin, fTitle);

        BaseWidget::textAlign(BaseWidget::ALIGN_CENTER | BaseWidget::ALIGN_MIDDLE);
        BaseWidget::text(w * 0.5f, h * 0.5f + margin * 0.5f, fSubtitle);
    }
};

// --------------------------------------------------------------------------------------------------------------------

} /* namespace LibreAudio */
