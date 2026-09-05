// lab: Libre Audio Base-Widgets
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: ISC

#pragma once

#include "base.hpp"

START_NAMESPACE_DGL

// --------------------------------------------------------------------------------------------------------------------

template<const uchar* imageData, uint imageDataSize, uint imageScale = 2>
class LabImageWidget final : public LabWidget
{
    using BaseWidget = LabWidget;

public:
    explicit LabImageWidget(LabWidget* const parent)
        : LabWidget(parent)
    {
        updateSize(false);
    }

private:
    const NanoImage fImage { createImageFromMemory(imageData, imageDataSize, IMAGE_GENERATE_MIPMAPS) };
    float fImageWidth;
    float fImageHeight;

    void onNanoDisplay() final
    {
        const float w = getWidth();
        const float h = getHeight();

        beginPath();
        rect(0, 0, w, h);
        fillPaint(imagePattern((w - fImageWidth) * 0.5f,
                               (h - fImageHeight) * 0.5f,
                               fImageWidth,
                               fImageHeight,
                               0.f,
                               fImage,
                               1.f));
        fill();
    }

    void updateSize(const bool updateChildren) final
    {
        fImageWidth = fImage.getWidth() * fScaleFactor / imageScale;
        fImageHeight = fImage.getHeight() * fScaleFactor / imageScale;

        const uint width = getWidth();
        const uint height = getHeight();

        if (width == height)
            setSize(fImageWidth, fImageHeight);
        else if (width > height)
            setHeight(fImageHeight);
        else
            setWidth(fImageWidth);

        BaseWidget::updateSize(updateChildren);
    }
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DGL
