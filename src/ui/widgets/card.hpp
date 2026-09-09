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
        return BaseWidget::isCheckable() && BaseWidget::isChecked() ? R::borderColor〡selected :
            BaseWidget::isHovered() ? R::glowColor : R::borderColor;
    }

    void onNanoDisplay() final
    {
        const float w = BaseWidget::getWidth();
        const float h = BaseWidget::getHeight();
        const bool isChecked = BaseWidget::isChecked();

        if (isChecked)
        {
            const float f = std::min(w, h) * 0.125f;
            const float f2 = f * 2;
            const float f4 = f * 4;

            BaseWidget::beginPath();

            if constexpr (R::borderRadius != 0)
                BaseWidget::roundedRect(-f2, -f2, w + f4, h + f4, R::borderRadius * fScaleFactor);
            else
                BaseWidget::rect(-f2, -f2, w + f4, h + f4);

            BaseWidget::fillPaint(BaseWidget::boxGradient(-f * 0.5f,
                                                          -f * 0.5f,
                                                          w + f,
                                                          h + f,
                                                          R::borderRadius * fScaleFactor * 2.f,
                                                          f2,
                                                          Color(R::glowColor, 0.125f),
                                                          Reference::Colors::transparent));
            BaseWidget::fill();
        }

        BaseWidget::onNanoDisplay();

        if (BaseWidget::isHovered())
        {
            BaseWidget::beginPath();

            if constexpr (R::borderRadius != 0)
                BaseWidget::roundedRect(0, 0, w, h, R::borderRadius * fScaleFactor);
            else
                BaseWidget::rect(0, 0, w, h);

            // BaseWidget::fillPaint(BaseWidget::boxGradient(0,
            //                                               0,
            //                                               w + std::min(w, h) * 0.25f,
            //                                               h + std::min(w, h) * 0.25f,
            //                                               R::borderRadius * fScaleFactor,
            //                                               std::min(w, h),
            //                                               Reference::Colors::transparent,
            //                                               R::glowColor));

            BaseWidget::fillPaint(BaseWidget::radialGradient(w, w, std::min(w, h), std::max(w, h) * 2.5f,
                                                             Reference::Colors::transparent, R::glowColor));

            BaseWidget::fill();
        }

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
