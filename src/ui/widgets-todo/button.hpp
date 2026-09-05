// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../lab/button.hpp"
#include "../reference.hpp"

#include "las-resources.h"

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------

template<Corner corner, const uchar* imageData, uint imageDataSize, class R = Reference::Widgets::Button>
class ImageButtonWidget : public ReferenceButtonWidget<R, corner>
{
    using BaseWidget = ReferenceButtonWidget<R, corner>;

    static constexpr const int imageScale = 2;

public:
    explicit ImageButtonWidget(LabWidget* const parent)
        : BaseWidget(parent)
    {
        updateSize(false);
    }

private:
    const NanoImage fImage { NanoVG::createImageFromMemory(imageData, imageDataSize, NanoVG::IMAGE_GENERATE_MIPMAPS) };
    double fImageWidth;
    double fImageHeight;

    void onNanoDisplay() final
    {
        BaseWidget::onNanoDisplay();
    
        const float w = BaseWidget::getWidth();
        const float h = BaseWidget::getHeight();

        BaseWidget::save();
        BaseWidget::globalTint(this->getForegroundColor());

        BaseWidget::beginPath();
        BaseWidget::rect((w - fImageWidth) * 0.5,  (h - fImageHeight) * 0.5, fImageWidth, fImageHeight);
        BaseWidget::fillPaint(BaseWidget::imagePattern((w - fImageWidth) * 0.5,
                                                       (h - fImageHeight) * 0.5,
                                                       fImageWidth,
                                                       fImageHeight,
                                                       0.f,
                                                       fImage,
                                                       1.f));
        BaseWidget::fill();
    
        BaseWidget::restore();
    }

    void updateSize(const bool updateChildren) final
    {
        fImageWidth = fImage.getWidth() * this->fScaleFactor / imageScale;
        fImageHeight = fImage.getHeight() * this->fScaleFactor / imageScale;

        const uint margin = d_roundToUnsignedInt((R::border + R::margin) * this->fScaleFactor);
        const uint marginx2 = margin * 2;
        // const uint width = d_roundToUnsignedInt(fImageWidth) + margin * 2;
        // const uint width = d_roundToUnsignedInt(fImageHeight) + margin * 2;

        const uint width = BaseWidget::getWidth();
        const uint height = BaseWidget::getHeight();

        if (width == height)
            BaseWidget::setSize(d_roundToUnsignedInt(fImageWidth) + marginx2,
                                d_roundToUnsignedInt(fImageHeight) + marginx2);
        else if (width > height)
            BaseWidget::setHeight(d_roundToUnsignedInt(fImageHeight) + marginx2);
        else
            BaseWidget::setWidth(d_roundToUnsignedInt(fImageWidth) + marginx2);

        // BaseWidget::setSize(fImageWidth + marginx2, fImageHeight + marginx2);

        BaseWidget::updateSize(updateChildren);
    }
};

// --------------------------------------------------------------------------------------------------------------------

template<Corner corner, const uchar* image1Data, uint imageData1Size, const uchar* image2Data, uint imageData2Size, class R = Reference::Widgets::Button>
class DualImageButtonWidget : public ReferenceButtonWidget<R, corner>
{
    using BaseWidget = ReferenceButtonWidget<R, corner>;

    static constexpr const int imageScale = 2;

public:
    explicit DualImageButtonWidget(LabWidget* const parent)
        : BaseWidget(parent)
    {
        BaseWidget::setCheckable(true);

        updateSize(false);
    }

private:
    const NanoImage fImage1 { NanoVG::createImageFromMemory(image1Data, imageData1Size, NanoVG::IMAGE_GENERATE_MIPMAPS) };
    const NanoImage fImage2 { NanoVG::createImageFromMemory(image2Data, imageData2Size, NanoVG::IMAGE_GENERATE_MIPMAPS) };
    double fImageWidth;
    double fImageHeight;

    void onNanoDisplay() final
    {
        BaseWidget::onNanoDisplay();
    
        const float w = BaseWidget::getWidth();
        const float h = BaseWidget::getHeight();
    
        BaseWidget::save();
        BaseWidget::globalTint(this->getForegroundColor());
    
        BaseWidget::beginPath();
        BaseWidget::rect((w - fImageWidth) * 0.5,  (h - fImageHeight) * 0.5, fImageWidth, fImageHeight);
        BaseWidget::fillPaint(BaseWidget::imagePattern((w - fImageWidth) * 0.5,
                               (h - fImageHeight) * 0.5,
                               fImageWidth,
                               fImageHeight,
                               0.f,
                               BaseWidget::isChecked() ? fImage1 : fImage2,
                               1.f));
        BaseWidget::fill();
    
        BaseWidget::restore();
    }

    void updateSize(const bool updateChildren) final
    {
        fImageWidth = fImage1.getWidth() * this->fScaleFactor / imageScale;
        fImageHeight = fImage1.getHeight() * this->fScaleFactor / imageScale;

        const uint margin = (R::border + R::margin) * this->fScaleFactor;
        const uint marginx2 = margin * 2;

        const uint width = BaseWidget::getWidth();
        const uint height = BaseWidget::getHeight();

        if (width == height)
            BaseWidget::setSize(d_roundToUnsignedInt(fImageWidth) + marginx2,
                                      d_roundToUnsignedInt(fImageHeight) + marginx2);
        else if (width > height)
            BaseWidget::setHeight(d_roundToUnsignedInt(fImageHeight) + marginx2);
        else
            BaseWidget::setWidth(d_roundToUnsignedInt(fImageWidth) + marginx2);

        // BaseWidget::setSize(fImageWidth + marginx2, fImageHeight + marginx2);

        BaseWidget::updateSize(updateChildren);
    }
};

// --------------------------------------------------------------------------------------------------------------------

template<Corner corner, class R = Reference::Widgets::Button>
class TextButtonWidget : public ReferenceButtonWidget<R, corner>
{
    using BaseWidget = ReferenceButtonWidget<R, corner>;

public:
    explicit TextButtonWidget(LabWidget* const parent, const char* const text)
        : BaseWidget(parent),
          fText(text)
    {
        updateSize(false);
    }

private:
    const char* const fText;

    void onNanoDisplay() final
    {
        BaseWidget::onNanoDisplay();
    
        const float w = BaseWidget::getWidth();
        const float h = BaseWidget::getHeight();
    
        BaseWidget::fillColor(this->getForegroundColor());
        BaseWidget::fontSize(R::fontSize * this->fScaleFactor);
        BaseWidget::textAlign(BaseWidget::ALIGN_CENTER | BaseWidget::ALIGN_MIDDLE);
        BaseWidget::textLetterSpacing(R::letterSpacing * this->fScaleFactor);
        BaseWidget::text(w * 0.5f, h * 0.5f, fText);
    }

    void updateSize(const bool updateChildren) final
    {
        const uint margin = d_roundToUnsignedInt(R::margin * this->fScaleFactor) * 2;

        Rectangle<float> bounds;
        BaseWidget::fontSize(R::fontSize * this->fScaleFactor);
        BaseWidget::textAlign(0);
        BaseWidget::textLetterSpacing(R::letterSpacing * this->fScaleFactor);
        BaseWidget::textBounds(0, 0, fText, nullptr, bounds);
        BaseWidget::setWidth(bounds.getWidth() + margin);

        BaseWidget::updateSize(updateChildren);
    }
};

// --------------------------------------------------------------------------------------------------------------------

template<Corner corner, const char _text[], class R = Reference::Widgets::Button>
class StaticTextButtonWidget : public TextButtonWidget<corner, R>
{
    using BaseWidget = TextButtonWidget<corner, R>;

public:
    explicit StaticTextButtonWidget(LabWidget* const parent)
        : BaseWidget(parent, _text) {}
};

// --------------------------------------------------------------------------------------------------------------------

template<Corner corner>
class BypassButtonWidget final : public ImageButtonWidget<corner, IMAGES_POWER_PNG_DATA, IMAGES_POWER_PNG_LEN, Reference::Widgets::Button〡Bypass>
{
    using R = Reference::Widgets::Button〡Bypass;
    using BaseWidget = ImageButtonWidget<corner, IMAGES_POWER_PNG_DATA, IMAGES_POWER_PNG_LEN, R>;

public:
    explicit BypassButtonWidget(LabWidget* const parent)
        : BaseWidget(parent)
    {
        BaseWidget::setCheckable(true);
    }

private:
    [[nodiscard]] const Color& getBackgroundColor() const noexcept final
    {
        return BaseWidget::isChecked() ? R::backgroundColorBypass : R::backgroundColor;
    }

    [[nodiscard]] const Color& getForegroundColor() const noexcept final
    {
        return BaseWidget::isChecked() || BaseWidget::isHovered() ? R::colorBypass : R::color;
    }
};

// --------------------------------------------------------------------------------------------------------------------

} /* namespace LibreAudio */
