// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "button.hpp"
#include "../base/container.hpp"
#include "../base/interface.hpp"

#include "LibreAudioParameters.hpp"
#include "FaustParameters.hpp"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioBackgroundPillToggleCellWidget : public LibreAudioTextButtonWidget<LibreAudioButtonWidget::kCornerBoth,
                                                                                   LibreAudioReference::Widgets::PillToggle::Cell>
{
    using R = LibreAudioReference::Widgets::PillToggle::Cell;
    using BaseWidget = LibreAudioTextButtonWidget<LibreAudioButtonWidget::kCornerBoth,
                                                  LibreAudioReference::Widgets::PillToggle::Cell>;

public:
    explicit LibreAudioBackgroundPillToggleCellWidget(LibreAudioWidget* const parent,
                                                      ButtonEventHandler::Callback* const callback,
                                                      const FaustParameterEnumerationValue& scalePoint)
        : BaseWidget(parent, scalePoint.label),
          fScalePoint(scalePoint)
    {
        BaseWidget::setCallback(callback);
        BaseWidget::setCheckable(true);
        // BaseWidget::setId(scalePoint.value);
        BaseWidget::setName(scalePoint.label);
    }

    [[nodiscard]] int getValue() const noexcept
    {
        return fScalePoint.value;
    }

protected:
    [[nodiscard]] const Color& getBackgroundColor() const noexcept override
    {
        return BaseWidget::isChecked() ? R::backgroundColor〡selected : R::backgroundColor;
    }

    [[nodiscard]] const Color& getForegroundColor() const noexcept override
    {
        // if (! BaseWidget::isEnabled())
        //     return R::deactivatedColor;

        return BaseWidget::isChecked() ? R::color〡selected : R::color;
    }

private:
    const FaustParameterEnumerationValue& fScalePoint;
};

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioPillToggleWidget : public LibreAudioReferenceContainerWidget<LibreAudioReference::Widgets::PillToggle>,
                                   private ButtonEventHandler::Callback,
                                   private IdleCallback
{
    using R = LibreAudioReference::Widgets::PillToggle;

    std::vector<std::unique_ptr<LibreAudioBackgroundPillToggleCellWidget>> fCells;

public:
    explicit LibreAudioPillToggleWidget(LibreAudioWidget* const parent,
                                        const FaustParameter& parameter,
                                        const uint32_t id)
        : LibreAudioReferenceContainerWidget<R>(parent)
    {
        addIdleCallback(this);
        setId(id);
        setName(parameter.label);

        uint cellWidth = 0;
        fCells.reserve(parameter.scalePointCount);

        for (uint i = 0; i < parameter.scalePointCount; ++i)
        {
            std::unique_ptr<LibreAudioBackgroundPillToggleCellWidget> widget {
                new LibreAudioBackgroundPillToggleCellWidget(this, this, parameter.scalePoints[i])
            };
            cellWidth = std::max(cellWidth, widget->getWidth());
            widgets.push_back({ widget.get(), Fixed });
            fCells.emplace_back(std::move(widget));
        }

        // make all cells have the same width
        for (const std::unique_ptr<LibreAudioBackgroundPillToggleCellWidget>& cell : fCells)
            cell->setWidth(cellWidth);

        if (parameter.scalePointCount != 0)
            fCells.front()->setChecked(true, false);

        const uint border = d_roundToUnsignedInt(R::border * fScaleFactor);
        const uint margin = d_roundToUnsignedInt(R::margin * fScaleFactor);
        const uint padding = d_roundToUnsignedInt(R::padding * fScaleFactor);

        uint width = (border + margin) * 2;
        if (const uint numWidgets = widgets.size())
        {
            width += padding * (numWidgets - 1);

            for (const SubWidgetWithSizeHint& widgetWithSizeHint : widgets)
                width += widgetWithSizeHint.widget->getWidth();
        }

        uint pillHeight;
        if constexpr (R::height != 0)
            pillHeight = R::height * fScaleFactor;
        else if (! fCells.empty())
            pillHeight = d_roundToUnsignedInt(fCells.front()->getHeight());
        else
            pillHeight = d_roundToUnsignedInt(fScaleFactor);

        LibreAudioWidget::setSize(width, (border + margin) * 2 + pillHeight);
    }

private:
    void addWidget() = delete;

    void buttonClicked(SubWidget* const widget, int) final
    {
        LibreAudioBackgroundPillToggleCellWidget* const button = static_cast<LibreAudioBackgroundPillToggleCellWidget*>(widget);

        if (! button->isChecked())
        {
            button->setChecked(true, false);
            return;
        }

        for (const std::unique_ptr<LibreAudioBackgroundPillToggleCellWidget>& cell : fCells)
            if (cell.get() != button)
                cell->setChecked(false, false);

        const uint id = getId();
        fInterface->parameterControlPressed(id);
        fInterface->parameterControlModified(id, button->getValue());
        fInterface->parameterControlReleased(id);
    }

    void idleCallback() final
    {
        const int value = d_roundToIntPositive(fInterface->getParameterValue(getId()));

        for (const std::unique_ptr<LibreAudioBackgroundPillToggleCellWidget>& cell : fCells)
            cell->setChecked(cell->getValue() == value, false);
    }
};

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioPillAreaWidget : public LibreAudioReferenceContainerWidget<LibreAudioReference::Widgets::PillArea>
{
    using R = LibreAudioReference::Widgets::PillToggle;

    static constexpr const uint kMaxNumToggles = 2;

    std::vector<std::unique_ptr<LibreAudioPillToggleWidget>> fToggles;
    std::vector<std::unique_ptr<LibreAudioWidget>> fSpacers;

public:
    explicit LibreAudioPillAreaWidget(LibreAudioWidget* const parent)
        : LibreAudioReferenceContainerWidget(parent)
    {
        const std::vector<FaustParameter>& parameters = getFaustParameters();

        fToggles.reserve(kMaxNumToggles);
        fSpacers.reserve(kMaxNumToggles + 1);

        uint8_t numPills = 0;
        for (uint32_t i = 0, count = parameters.size(); i < count; ++i)
        {
            const FaustParameter& parameter = parameters[i];
            if (! parameter.isEnumerator || parameter.isOutput) {
                d_stdout("pill area skipped parameter %s", parameter.label);
                continue;
            }
            ++numPills;
        }

        if (numPills == 1)
            addSpacer();

        for (uint32_t i = 0, count = parameters.size(); i < count && widgets.size() < kMaxNumToggles * 2; ++i)
        {
            const FaustParameter& parameter = parameters[i];
            if (! parameter.isEnumerator || parameter.isOutput) {
                d_stdout("pill area skipped parameter %s", parameter.label);
                continue;
            }
            d_stdout("using pill for parameter %s", parameter.label);
            std::unique_ptr<LibreAudioPillToggleWidget> widget { new LibreAudioPillToggleWidget(this, parameter, kParametersMainStart + i) };
            widgets.push_back({ widget.get(), Fixed });
            fToggles.emplace_back(std::move(widget));

            if (numPills == 2)
            {
                numPills = 0;
                addSpacer();
            }
        }

        if (numPills == 1)
            addSpacer();

        const uint border = d_roundToUnsignedInt(R::border * fScaleFactor);
        const uint margin = d_roundToUnsignedInt(R::margin * fScaleFactor);
        uint pillHeight;

        if constexpr (R::height != 0)
            pillHeight = R::height * fScaleFactor;
        else if (! fToggles.empty())
            pillHeight = fToggles.front()->getHeight();
        else
            pillHeight = d_roundToUnsignedInt(fScaleFactor);

        LibreAudioWidget::setHeight((border + margin) * 2 + pillHeight);
    }

private:
    void addSpacer()
    {
        std::unique_ptr<LibreAudioWidget> spacer { new LibreAudioEmptyWidget(this) };
        widgets.push_back({ spacer.get(), Expanding });
        fSpacers.emplace_back(std::move(spacer));
    }

    void addWidget() = delete;
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
