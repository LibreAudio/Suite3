// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../_lab/button.hpp"
#include "../_lab/button-group.hpp"

#include "../reference.hpp"

#include "las-resources.h"

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------

class LabCardWidget : public ReferenceButtonWidget<Reference::Widgets::Card, kCornerBoth>
{
    using R = Reference::Widgets::Card;
    using BaseWidget = ReferenceButtonWidget<R, kCornerBoth>;

public:
    explicit LabCardWidget(LabWidget* const parent, const char* const subtitle)
        : BaseWidget(parent),
          fSubtitle(subtitle)
    {
        BaseWidget::updateSize(false);
    }

    explicit LabCardWidget(LabWidget* const parent, const char* const title, const char* const subtitle)
        : BaseWidget(parent),
          fSubtitle(subtitle)
    {
        setName(title);
        BaseWidget::updateSize(false);
    }

private:
    const char* const fSubtitle;

    [[nodiscard]] const Color& getBackgroundColor() const noexcept final
    {
        return BaseWidget::isCheckable() && BaseWidget::isChecked() ? R::backgroundColor〡selected : R::backgroundColor;
    }

    [[nodiscard]] const Color& getBorderColor() const noexcept final
    {
        return BaseWidget::isCheckable() && BaseWidget::isChecked() ? R::borderColor〡selected : R::borderColor;
    }

    void onNanoDisplay() final
    {
        BaseWidget::onNanoDisplay();

        const float w = BaseWidget::getWidth();
        const float h = BaseWidget::getHeight();
        const bool isChecked = BaseWidget::isChecked();

        const uint margin = d_roundToUnsignedInt(R::margin * this->fScaleFactor);

        BaseWidget::fillColor(isChecked ? R::Title::color〡selected : R::Title::color);
        BaseWidget::fontSize(R::Title::fontSize * this->fScaleFactor);
        BaseWidget::textAlign(BaseWidget::ALIGN_CENTER | BaseWidget::ALIGN_TOP);
        BaseWidget::textLetterSpacing(R::Title::letterSpacing * this->fScaleFactor);
        BaseWidget::text(w * 0.5f, margin, getName());

        BaseWidget::fillColor(R::Subtitle::color);
        BaseWidget::fontSize(R::Subtitle::fontSize * this->fScaleFactor);
        BaseWidget::textAlign(BaseWidget::ALIGN_CENTER | BaseWidget::ALIGN_MIDDLE);
        BaseWidget::textLetterSpacing(R::Subtitle::letterSpacing * this->fScaleFactor);
        BaseWidget::text(w * 0.5f, h * 0.5f + margin * 0.5f, fSubtitle);
    }
};

// --------------------------------------------------------------------------------------------------------------------

class CardGroupWidget final : public ReferenceButtonGroupWidget<Reference::Widgets::CardGroup>
{
    using R = Reference::Widgets::CardGroup;
    using BaseWidget = ReferenceButtonGroupWidget<R>;

public:
    explicit CardGroupWidget(LabWidget* const parent)
        : BaseWidget(parent)
    {
    }

    std::shared_ptr<LabCardWidget> addCard(const uint id, const char* const title, const char* const subtitle)
    {
        return BaseWidget::addButton<LabCardWidget, Expanding>(id, title, subtitle);
    }

private:
    void updateSize(const bool updateChildren) final
    {
        DISTRHO_SAFE_ASSERT(updateChildren);

        // update children size first
        BaseWidget::updateSize(true);

        const uint border = d_roundToUnsignedInt(R::border * fScaleFactor);
        const uint margin = d_roundToUnsignedInt(R::margin * fScaleFactor);
        uint cardsHeight;

        if constexpr (R::height != 0)
            cardsHeight = d_roundToUnsignedInt(R::height * fScaleFactor);
        else if (! fWidgets.empty())
            cardsHeight = fWidgets.front()->getHeight();
        else
            cardsHeight = d_roundToUnsignedInt(fScaleFactor);

        LabWidget::setHeight((border + margin) * 2 + cardsHeight);

        // update everything else
        LabWidget::updateSize(updateChildren);
    }
};

// --------------------------------------------------------------------------------------------------------------------

} /* namespace LibreAudio */
