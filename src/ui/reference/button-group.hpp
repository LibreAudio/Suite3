// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../base/button.hpp"
#include "container.hpp"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

template <class R>
class LibreAudioReferenceButtonGroupWidget : public LibreAudioReferenceContainerWidget<R>,
                                             private ButtonEventHandler::Callback,
                                             private IdleCallback
{
    using BaseWidget = LibreAudioReferenceContainerWidget<R>;

public:
    explicit LibreAudioReferenceButtonGroupWidget(LibreAudioWidget* const parent)
        : BaseWidget(parent)
    {
        BaseWidget::addIdleCallback(this);
    }

    void done()
    {
        idleCallback();
        updateSize(true);
    }

protected:
    template<class B, typename = std::enable_if_t<std::is_base_of_v<LibreAudioButtonWidget, B>>>
    std::shared_ptr<LibreAudioButtonWidget> addButton(const uint id)
    {
        std::shared_ptr<LibreAudioButtonWidget> widget { new B(this) };
        widget->setCallback(this);
        widget->setCheckable(true);
        widget->setId(id);
        this->widgets.push_back({ widget.get(), Fixed });
        fWidgets.push_back(widget);
        if (widget->getSize().isNull())
            d_stderr2("Error: addButton called but widget %u: '%s' does not have a known size", id, widget->getName());
        return widget;
    }

    void addSpacer() = delete;
    void addWidget() = delete;

private:
    void onNanoDisplay() final
    {
        // TODO divider??
    }

    void buttonClicked(SubWidget* const widget, int) final
    {
        this->fInterface->buttonClicked(widget->getId());
        idleCallback();
    }

    void idleCallback() final
    {
        for (const std::shared_ptr<LibreAudioButtonWidget>& widget : fWidgets)
        {
            widget->setChecked(this->fInterface->isButtonChecked(widget->getId()), false);
            widget->setEnabled(this->fInterface->isButtonEnabled(widget->getId()));
        }
    }

    void updateSize(const bool updateChildren) final
    {
        DISTRHO_SAFE_ASSERT(updateChildren);

        // update children size first
        LibreAudioWidget::updateSize(true);

        // set width and height
        const uint border = d_roundToUnsignedInt(R::border * this->fScaleFactor);
        const uint margin = d_roundToUnsignedInt(R::margin * this->fScaleFactor);
        const uint padding = d_roundToUnsignedInt(R::padding * this->fScaleFactor);

        uint width = (border + margin) * 2;

        if (const uint numWidgets = fWidgets.size())
        {
            width += padding * (numWidgets - 1);

            for (const std::shared_ptr<LibreAudioButtonWidget>& widget : fWidgets)
                width += widget->getWidth();

            if (numWidgets == 1)
            {
                DISTRHO_CUSTOM_SAFE_ASSERT(
                    "Single button must have corner = both",
                    fWidgets.front()->getCorner() == LibreAudioButtonWidget::kCornerBoth);
            }
            else
            {
                DISTRHO_CUSTOM_SAFE_ASSERT(
                    "First button must have corner = left",
                    fWidgets.front()->getCorner() == LibreAudioButtonWidget::kCornerLeft);
                DISTRHO_CUSTOM_SAFE_ASSERT(
                    "First button must have corner = right",
                    fWidgets.back()->getCorner() == LibreAudioButtonWidget::kCornerRight);
            }
        }

        LibreAudioWidget::setWidth(width);

        // update everything else
        BaseWidget::updateSize(false);
    }

    std::list<std::shared_ptr<LibreAudioButtonWidget>> fWidgets;
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
