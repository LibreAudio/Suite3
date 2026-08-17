// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "base.hpp"

#include "EventHandlers.hpp"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------
// button widget class

class LibreAudioButtonWidget : public LibreAudioWidget,
                               public ButtonEventHandler
{
public:
    enum Corner : uint8_t {
        kCornerNone,
        kCornerLeft,
        kCornerRight,
        kCornerBoth,
    };

    explicit LibreAudioButtonWidget(LibreAudioWidget* const parent)
        : LibreAudioWidget(parent),
          ButtonEventHandler(this)
    {
    }

    [[nodiscard]] virtual Corner getCorner() const noexcept = 0;

private:
    bool onMouse(const Widget::MouseEvent& ev) final
    {
        if (mouseEvent(ev))
            return true;
        return LibreAudioWidget::onMouse(ev);
    }

    bool onMotion(const Widget::MotionEvent& ev) final
    {
        if (motionEvent(ev))
            return true;
        return LibreAudioWidget::onMotion(ev);
    }
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
