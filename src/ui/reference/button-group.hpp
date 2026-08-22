// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "button.hpp"
#include "container.hpp"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

template <class R>
class LibreAudioReferenceButtonGroupWidget : public LibreAudioReferenceContainerWidget<R>
{
public:
    explicit LibreAudioReferenceButtonGroupWidget(LibreAudioWidget* const parent)
        : LibreAudioReferenceContainerWidget<R>(parent)
    {
    }

    void done(ButtonEventHandler::Callback* const callback)
    {
        const uint border = d_roundToUnsignedInt(R::border * this->fScaleFactor);
        const uint margin = d_roundToUnsignedInt(R::margin * this->fScaleFactor);
        const uint padding = d_roundToUnsignedInt(R::padding * this->fScaleFactor);

        uint width = (border + margin) * 2;
        if (const uint numWidgets = this->widgets.size())
        {
            width += padding * (numWidgets - 1);

            for (const SubWidgetWithSizeHint& widgetWithSizeHint : this->widgets)
            {
                width += widgetWithSizeHint.widget->getWidth();
                static_cast<LibreAudioButtonWidget*>(widgetWithSizeHint.widget)->setCallback(callback);
            }

            if (numWidgets == 1)
            {
                DISTRHO_CUSTOM_SAFE_ASSERT(
                    "Single button must have corner = both",
                    static_cast<LibreAudioButtonWidget*>(this->widgets.front().widget)->getCorner() == LibreAudioButtonWidget::kCornerBoth);
            }
            else
            {
                DISTRHO_CUSTOM_SAFE_ASSERT(
                    "First button must have corner = left",
                    static_cast<LibreAudioButtonWidget*>(this->widgets.front().widget)->getCorner() == LibreAudioButtonWidget::kCornerLeft);
                DISTRHO_CUSTOM_SAFE_ASSERT(
                    "First button must have corner = right",
                    static_cast<LibreAudioButtonWidget*>(this->widgets.back().widget)->getCorner() == LibreAudioButtonWidget::kCornerRight);
            }
        }

        LibreAudioWidget::setWidth(width);
    }

protected:
    template<class B, typename = std::enable_if_t<std::is_base_of_v<LibreAudioButtonWidget, B>>>
    std::unique_ptr<LibreAudioButtonWidget> addButton(const uint id)
    {
        std::unique_ptr<LibreAudioButtonWidget> widget { new B(this) };
        widget->setId(id);
        this->widgets.push_back({ widget.get(), Fixed });
        if (widget->getSize().isNull())
            d_stderr2("Error: addButton called but widget '%s' does not have a known size", widget->getName());
        return widget;
    }

    void addWidget() = delete;

private:
    void onNanoDisplay() final
    {
        // TODO divider??
    }
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
