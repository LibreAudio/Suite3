// lab: Libre Audio Base-Widgets
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: ISC

#pragma once

#include "button.hpp"
#include "container.hpp"

START_NAMESPACE_DGL

// --------------------------------------------------------------------------------------------------------------------

template <class R>
class ReferenceButtonGroupWidget : public ReferenceContainerWidget<R>,
                                   private ButtonEventHandler::Callback,
                                   private IdleCallback
{
    using BaseWidget = ReferenceContainerWidget<R>;

public:
    explicit ReferenceButtonGroupWidget(LabWidget* const parent)
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
    template<class B,
             SizeHint sizeHint = Fixed,
             typename... Args,
             typename = std::enable_if_t<std::is_base_of_v<ButtonBaseWidget, B>>>
    std::shared_ptr<B> addButton(const uint id, const char* const name, Args... args)
    {
        std::shared_ptr<B> widget { new B(this, args...) };
        widget->setCallback(this);
        widget->setCheckable(true);
        widget->setId(id);
        widget->setName(name);
        this->widgets.push_back({ widget.get(), sizeHint });
        fWidgets.push_back(widget);
        if (widget->getSize().isNull())
            d_stderr2("Error: addButton called but widget %u: '%s' does not have a known size", id, name);
        return widget;
    }

    void addSpacer() = delete;
    void addWidget() = delete;

protected:
    void updateSize(const bool updateChildren) override
    {
        DISTRHO_SAFE_ASSERT(updateChildren);

        // update children size first
        BaseWidget::updateSize(true);

        // set width and height
        const uint border = d_roundToUnsignedInt(R::border * this->fScaleFactor);
        const uint margin = d_roundToUnsignedInt(R::margin * this->fScaleFactor);
        const uint padding = d_roundToUnsignedInt(R::padding * this->fScaleFactor);

        uint width = (border + margin) * 2;

        if (const uint numWidgets = fWidgets.size())
        {
            width += padding * (numWidgets - 1);

            for (const std::shared_ptr<ButtonBaseWidget>& widget : fWidgets)
                width += widget->getWidth();

            if (numWidgets == 1)
            {
                DISTRHO_CUSTOM_SAFE_ASSERT(
                    "Single button must have corner = both",
                    fWidgets.front()->getCorner() == kCornerBoth);
            }
            else
            {
                DISTRHO_CUSTOM_SAFE_ASSERT(
                    "First button must have corner = left",
                    fWidgets.front()->getCorner() == kCornerLeft || fWidgets.front()->getCorner() == kCornerBoth);
                DISTRHO_CUSTOM_SAFE_ASSERT(
                    "First button must have corner = right",
                    fWidgets.back()->getCorner() == kCornerRight || fWidgets.back()->getCorner() == kCornerBoth);
            }
        }

        LabWidget::setWidth(width);

        // update everything else
        BaseWidget::updateSize(false);
    }

    std::list<std::shared_ptr<ButtonBaseWidget>> fWidgets;

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
        for (const std::shared_ptr<ButtonBaseWidget>& widget : fWidgets)
        {
            widget->setChecked(this->fInterface->isButtonChecked(widget->getId()), false);
            widget->setEnabled(this->fInterface->isButtonEnabled(widget->getId()));
        }
    }
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DGL
