// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "base.hpp"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

template<const uchar* imageData, uint imageDataSize, uint imageScale = 2>
class LibreAudioImageWidget final : public LibreAudioWidget
{
public:
    explicit LibreAudioImageWidget(LibreAudioWidget* const parent)
        : LibreAudioWidget(parent)
    {
        updateImageSize();
        setSize(fImageWidth, fImageHeight);
    }

protected:
    void onNanoDisplay() final
    {
        const uint width = getWidth();
        const uint height = getHeight();

        beginPath();
        rect(0, 0, width, height);
        fillPaint(imagePattern((width - fImageWidth) * 0.5,
                               (height - fImageHeight) * 0.5,
                               fImageWidth,
                               fImageHeight,
                               0.f,
                               fImage,
                               1.f));
        fill();
    }

private:
    const NanoImage fImage { createImageFromMemory(imageData, imageDataSize, IMAGE_GENERATE_MIPMAPS) };
    double fImageWidth;
    double fImageHeight;

    void updateImageSize()
    {
        fImageWidth = fImage.getWidth() * fScaleFactor / imageScale;
        fImageHeight = fImage.getHeight() * fScaleFactor / imageScale;
    }
};


// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
