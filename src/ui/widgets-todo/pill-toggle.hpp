// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "button.hpp"
#include "../lab/container.hpp"
#include "../lab/interface.hpp"

#include "LibreAudioParameters.hpp"
#include "FaustParameters.hpp"

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------

class BackgroundPillToggleCellWidget : public TextButtonWidget<kCornerBoth,
                                                                         Reference::Widgets::PillToggle::Cell>
{
    using R = Reference::Widgets::PillToggle::Cell;
    using BaseWidget = TextButtonWidget<kCornerBoth, Reference::Widgets::PillToggle::Cell>;

public:
    explicit BackgroundPillToggleCellWidget(LabWidget* const parent, const uint id, const char* const label)
        : BaseWidget(parent, label)
    {
        BaseWidget::setCheckable(true);
        BaseWidget::setId(id);
        BaseWidget::setName(label);
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

class PillToggleWidget : public ReferenceContainerWidget<Reference::Widgets::PillToggle>,
                         private ButtonEventHandler::Callback,
                         private IdleCallback
{
    using R = Reference::Widgets::PillToggle;
    using BaseWidget = ReferenceContainerWidget<R>;

    std::list<std::unique_ptr<BackgroundPillToggleCellWidget>> fCells;

public:
    explicit PillToggleWidget(LabWidget* const parent,
                              const FaustParameter& parameter,
                              const uint32_t id)
        : BaseWidget(parent)
    {
        addIdleCallback(this);
        setId(id);
        setName(parameter.label);

        for (uint i = 0; i < parameter.scalePointCount; ++i)
        {
            std::unique_ptr<BackgroundPillToggleCellWidget> widget {
                new BackgroundPillToggleCellWidget(
                    this, parameter.scalePoints[i].value, parameter.scalePoints[i].label)
            };
            widget->setCallback(this);
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
        BackgroundPillToggleCellWidget* const button = static_cast<BackgroundPillToggleCellWidget*>(widget);

        if (! button->isChecked())
        {
            button->setChecked(true, false);
            return;
        }

        for (const std::unique_ptr<BackgroundPillToggleCellWidget>& cell : fCells)
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

        for (const std::unique_ptr<BackgroundPillToggleCellWidget>& cell : fCells)
            cell->setChecked(cell->getId() == value, false);
    }

    void updateSize(const bool updateChildren) final
    {
        DISTRHO_SAFE_ASSERT(updateChildren);

        // update children size first
        BaseWidget::updateSize(true);

        const uint border = d_roundToUnsignedInt(R::border * fScaleFactor);
        const uint margin = d_roundToUnsignedInt(R::margin * fScaleFactor);
        const uint padding = d_roundToUnsignedInt(R::padding * fScaleFactor);

        // make all cells have the same width
        uint cellWidth = 0;

        for (const std::unique_ptr<BackgroundPillToggleCellWidget>& cell : fCells)
            cellWidth = std::max(cellWidth, cell->getWidth());

        for (const std::unique_ptr<BackgroundPillToggleCellWidget>& cell : fCells)
            cell->setWidth(cellWidth);

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

        LabWidget::setSize(width, height);

        // update everything else
        BaseWidget::updateSize(false);
    }
};

// --------------------------------------------------------------------------------------------------------------------

class PillAreaWidget : public ReferenceContainerWidget<Reference::Widgets::PillArea>
{
    using R = Reference::Widgets::PillArea;
    using BaseWidget = ReferenceContainerWidget<R>;

    static constexpr const uint kMaxNumToggles = 2;

    std::list<std::unique_ptr<PillToggleWidget>> fToggles;
    std::list<std::unique_ptr<Widget>> fSpacers;

public:
    explicit PillAreaWidget(LabWidget* const parent)
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
            std::unique_ptr<PillToggleWidget> widget { new PillToggleWidget(this, parameter, kParametersMainStart + i) };
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
        std::unique_ptr<LabWidget> spacer { new LabEmptyWidget(this) };
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

        LabWidget::setHeight((border + margin) * 2 + pillHeight);

        BaseWidget::updateSize(updateChildren);
    }
};

// --------------------------------------------------------------------------------------------------------------------

} /* namespace LibreAudio */
