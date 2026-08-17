// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../base/button.hpp"
#include "../reference.hpp"

#include "las-resources.h"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

template<LibreAudioButtonWidget::Corner corner, const uchar* imageData, uint imageDataSize, class R = LibreAudioReference::Widgets::Button>
class LibreAudioImageButtonWidget : public LibreAudioReferenceButtonWidget<R, corner>
{
    using BaseWidget = LibreAudioReferenceButtonWidget<R, corner>;
    static constexpr const int imageScale = 2;

public:
    explicit LibreAudioImageButtonWidget(LibreAudioWidget* const parent)
        : BaseWidget(parent)
    {
        const uint margin = (R::border + R::margin) * this->fScaleFactor;

        updateImageSize();
        LibreAudioWidget::setSize(fImageWidth + margin * 2, fImageHeight + margin * 2);
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

    void updateImageSize()
    {
        fImageWidth = fImage.getWidth() * this->fScaleFactor / imageScale;
        fImageHeight = fImage.getHeight() * this->fScaleFactor / imageScale;
    }
};

// --------------------------------------------------------------------------------------------------------------------

template<LibreAudioButtonWidget::Corner corner, const uchar* image1Data, uint imageData1Size, const uchar* image2Data, uint imageData2Size, class R = LibreAudioReference::Widgets::Button>
class LibreAudioDualImageButtonWidget : public LibreAudioReferenceButtonWidget<R, corner>
{
    using BaseWidget = LibreAudioReferenceButtonWidget<R, corner>;
    static constexpr const int imageScale = 2;

public:
    explicit LibreAudioDualImageButtonWidget(LibreAudioWidget* const parent)
        : LibreAudioReferenceButtonWidget<R, corner>(parent)
    {
        const uint margin = (R::border + R::margin) * this->fScaleFactor;

        updateImageSize();
        BaseWidget::setCheckable(true);
        BaseWidget::setSize(fImageWidth + margin * 2, fImageHeight + margin * 2);
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

    void updateImageSize()
    {
        fImageWidth = fImage1.getWidth() * this->fScaleFactor / imageScale;
        fImageHeight = fImage1.getHeight() * this->fScaleFactor / imageScale;
    }
};

// --------------------------------------------------------------------------------------------------------------------

template<LibreAudioButtonWidget::Corner corner, class R = LibreAudioReference::Widgets::Button>
class LibreAudioTextButtonWidget : public LibreAudioReferenceButtonWidget<R, corner>
{
    using BaseWidget = LibreAudioReferenceButtonWidget<R, corner>;

public:
    explicit LibreAudioTextButtonWidget(LibreAudioWidget* const parent, const char* const text)
        : BaseWidget(parent),
          fText(text)
    {
        const uint margin = d_roundToUnsignedInt(R::margin * this->fScaleFactor) * 2;

        Rectangle<float> bounds;
        BaseWidget::fontSize(R::fontSize * this->fScaleFactor);
        BaseWidget::textAlign(0);
        BaseWidget::textLetterSpacing(R::letterSpacing * this->fScaleFactor);
        BaseWidget::textBounds(0, 0, fText, nullptr, bounds);
        BaseWidget::setWidth(bounds.getWidth() + margin);
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
};

// --------------------------------------------------------------------------------------------------------------------

template<LibreAudioButtonWidget::Corner corner, const char _text[], class R = LibreAudioReference::Widgets::Button>
class LibreAudioStaticTextButtonWidget : public LibreAudioTextButtonWidget<corner, R>
{
    using BaseWidget = LibreAudioTextButtonWidget<corner, R>;

public:
    explicit LibreAudioStaticTextButtonWidget(LibreAudioWidget* const parent)
        : BaseWidget(parent, _text) {}
};

// --------------------------------------------------------------------------------------------------------------------

template<LibreAudioButtonWidget::Corner corner>
class LibreAudioBypassButtonWidget final : public LibreAudioImageButtonWidget<corner, IMAGES_POWER_PNG_DATA, IMAGES_POWER_PNG_LEN, LibreAudioReference::Widgets::Button〡Bypass>
{
    using R = LibreAudioReference::Widgets::Button〡Bypass;
    using BaseWidget = LibreAudioImageButtonWidget<corner, IMAGES_POWER_PNG_DATA, IMAGES_POWER_PNG_LEN, R>;

public:
    explicit LibreAudioBypassButtonWidget(LibreAudioWidget* const parent)
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

END_NAMESPACE_DISTRHO
