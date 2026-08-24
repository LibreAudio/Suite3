// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../base/base.hpp"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------
// reference widget class

template<class R>
class LibreAudioReferenceWidget : public LibreAudioWidget
{
public:
    explicit LibreAudioReferenceWidget(LibreAudioTopLevelWidget* const parent)
        : LibreAudioWidget(parent)
    {
        updateSize(false);
    }

    explicit LibreAudioReferenceWidget(LibreAudioWidget* const parent)
        : LibreAudioWidget(parent)
    {
        updateSize(false);
    }

protected:
    void onNanoDisplay() override
    {
        drawReferenceBackground<R>();
    }

    void updateSize(const bool updateChildren) override
    {
        if constexpr (R::width != 0)
            setWidth(d_roundToUnsignedInt(R::width * fScaleFactor));

        if constexpr (R::height != 0)
            setHeight(d_roundToUnsignedInt(R::height * fScaleFactor));

        LibreAudioWidget::updateSize(updateChildren);
    }
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
