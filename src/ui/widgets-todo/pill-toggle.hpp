// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "button.hpp"
#include "../reference/container.hpp"
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
        : BaseWidget(parent, scalePoint.label)
    {
        BaseWidget::setCallback(callback);
        BaseWidget::setCheckable(true);
        BaseWidget::setId(scalePoint.value);
        BaseWidget::setName(scalePoint.label);
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
};

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioPillToggleWidget : public LibreAudioReferenceContainerWidget<LibreAudioReference::Widgets::PillToggle>,
                                   private ButtonEventHandler::Callback,
                                   private IdleCallback
{
    using R = LibreAudioReference::Widgets::PillToggle;
    using BaseWidget = LibreAudioReferenceContainerWidget<R>;

    std::list<std::unique_ptr<LibreAudioBackgroundPillToggleCellWidget>> fCells;

public:
    explicit LibreAudioPillToggleWidget(LibreAudioWidget* const parent,
                                        const FaustParameter& parameter,
                                        const uint32_t id)
        : BaseWidget(parent)
    {
        addIdleCallback(this);
        setId(id);
        setName(parameter.label);

        for (uint i = 0; i < parameter.scalePointCount; ++i)
        {
            std::unique_ptr<LibreAudioBackgroundPillToggleCellWidget> widget {
                new LibreAudioBackgroundPillToggleCellWidget(this, this, parameter.scalePoints[i])
            };
            widgets.push_back({ widget.get(), Fixed });
            fCells.emplace_back(std::move(widget));
        }

        if (parameter.scalePointCount != 0)
            fCells.front()->setChecked(true, false);

        updateSize(true);
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
        fInterface->parameterControlModified(id, button->getId());
        fInterface->parameterControlReleased(id);
    }

    void idleCallback() final
    {
        const uint value = d_roundToUnsignedInt(fInterface->getParameterValue(getId()));

        for (const std::unique_ptr<LibreAudioBackgroundPillToggleCellWidget>& cell : fCells)
            cell->setChecked(cell->getId() == value, false);
    }

    void updateSize(const bool updateChildren) final
    {
        DISTRHO_SAFE_ASSERT(updateChildren);

        const uint border = d_roundToUnsignedInt(R::border * fScaleFactor);
        const uint margin = d_roundToUnsignedInt(R::margin * fScaleFactor);
        const uint padding = d_roundToUnsignedInt(R::padding * fScaleFactor);

        // update children size first
        LibreAudioWidget::updateSize(true);

        // make all cells have the same width
        uint cellWidth = 0;

        for (const std::unique_ptr<LibreAudioBackgroundPillToggleCellWidget>& cell : fCells)
            cellWidth = std::max(cellWidth, cell->getWidth());

        for (const std::unique_ptr<LibreAudioBackgroundPillToggleCellWidget>& cell : fCells)
            cell->setWidth(cellWidth + margin * 2);

        // set width and height
        uint width = (border + margin) * 2;
        uint height = width;

        if (const uint numWidgets = widgets.size())
        {
            width += padding * (numWidgets - 1);
            width += numWidgets * cellWidth;
        }

        if constexpr (R::height != 0)
            height += R::height * fScaleFactor;
        else if (! fCells.empty())
            height += d_roundToUnsignedInt(fCells.front()->getHeight());
        else
            height += d_roundToUnsignedInt(fScaleFactor);

        LibreAudioWidget::setSize(width, height);

        // update everything else
        BaseWidget::updateSize(false);
    }
};

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioPillAreaWidget : public LibreAudioReferenceContainerWidget<LibreAudioReference::Widgets::PillArea>
{
    using R = LibreAudioReference::Widgets::PillArea;
    using BaseWidget = LibreAudioReferenceContainerWidget<R>;

    static constexpr const uint kMaxNumToggles = 2;

    std::list<std::unique_ptr<LibreAudioPillToggleWidget>> fToggles;
    std::list<std::unique_ptr<LibreAudioWidget>> fSpacers;

public:
    explicit LibreAudioPillAreaWidget(LibreAudioWidget* const parent)
        : BaseWidget(parent)
    {
        const std::vector<FaustParameter>& parameters = getFaustParameters();

        uint8_t numPills = 0;
        for (const FaustParameter& parameter : parameters)
        {
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

        updateSize(true);
    }

private:
    void addSpacer()
    {
        std::unique_ptr<LibreAudioWidget> spacer { new LibreAudioEmptyWidget(this) };
        widgets.push_back({ spacer.get(), Expanding });
        fSpacers.emplace_back(std::move(spacer));
    }

    void addWidget() = delete;

    void updateSize(const bool updateChildren) final
    {
        const uint border = d_roundToUnsignedInt(R::border * fScaleFactor);
        const uint margin = d_roundToUnsignedInt(R::margin * fScaleFactor);
        uint pillHeight;

        if constexpr (R::height != 0)
            pillHeight = d_roundToUnsignedInt(R::height * fScaleFactor);
        else if (! fToggles.empty())
            pillHeight = fToggles.front()->getHeight();
        else
            pillHeight = d_roundToUnsignedInt(fScaleFactor);

        LibreAudioWidget::setHeight((border + margin) * 2 + pillHeight);

        BaseWidget::updateSize(updateChildren);
    }
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
