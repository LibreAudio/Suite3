// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../widgets/base.hpp"
#include "../widgets/meter.hpp"
#include "../widgets-todo/knob-group.hpp"
#include "../widgets-todo/pill-toggle.hpp"

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------

class ParameterDumpStageWidget final : public ReferenceContainerWidget<Reference::Stage, kVertical>
{
    using R = Reference::Stage;
    using BaseWidget = ReferenceContainerWidget<R, kVertical>;
    using KnobGroupWidget10 = KnobGroupWidget<SmallKnobWidget, 10>;

    std::shared_ptr<LabWidget> fTopArea = addWidget<PillAreaWidget<>>();
    std::list<std::shared_ptr<LabWidget>> fSpacers;
    std::list<std::shared_ptr<KnobGroupWidget10>> fKnobGroups;

    const std::vector<FaustParameter>& kParameters = getFaustParameters();

public:
    explicit ParameterDumpStageWidget(LabWidget* const parent)
        : BaseWidget(parent)
    {
        fTopArea->setHeight(30 * fScaleFactor);

        // addSpacer();

        for (uint offset = 0, groups = 0; offset < kParameters.size() && groups < 3; ++groups)
        {
            addKnobGroup(offset);
            // addSpacer();
            if (const uint lastId = fKnobGroups.back()->getLastKnobId())
                offset = lastId + 1 - kParametersMainStart;
            else
                offset = UINT32_MAX;
            d_stdout("offset = %u", offset);
        }

        updateSize(true);
    }

private:
    void addKnobGroup(const uint offset)
    {
        std::shared_ptr<KnobGroupWidget10> widget { new KnobGroupWidget10(this, kParameters, kParametersMainStart, offset) };
        widgets.push_back({ widget.get(), Fixed });
        fKnobGroups.emplace_back(std::move(widget));
    }

    void addSpacer()
    {
        std::shared_ptr<LabWidget> spacer { new LabEmptyWidget(this) };
        // spacer->setId(id);
        widgets.push_back({ spacer.get(), Expanding });
        fSpacers.emplace_back(std::move(spacer));
    }

    void onNanoDisplay() final
    {
        const float w = getWidth();
        const float h = getHeight();

        // ------------------------------------------------------------------------------------------------------------
        // draw background and border

        beginPath();

        if constexpr (R::borderRadius != 0)
            roundedRect(0, 0, w, h, R::borderRadius * fScaleFactor);
        else
            rect(0, 0, w, h);

        {
            fillColor(Reference::Colors::bg0);
            fill();
        }

        fillPaint(linearGradient(0, h - h * 0.4f, 0, h - h * 0.2f, Reference::Colors::transparent, Color(0.f, 0.f, 0.f, 0.2f)));
        fill();

        if constexpr (R::border != 0 && d_isNotZero(R::borderColor.alpha))
        {
            strokeColor(R::borderColor);
            strokeWidth(R::border * 2 * fScaleFactor);
            stroke();
        }
    }
};

// --------------------------------------------------------------------------------------------------------------------

class ParameterDumpArea : public ReferenceContainerWidget<Reference::MainArea>
{
    std::shared_ptr<Widget> fMetersIn = addWidget<MeterWidget<Input>>();
    std::shared_ptr<ParameterDumpStageWidget> fStage = addWidget<ParameterDumpStageWidget, Expanding>();
    std::shared_ptr<Widget> fMetersOut = addWidget<MeterWidget<Output>>();

public:
    ParameterDumpArea(LabTopLevelWidget* const parent)
        : ReferenceContainerWidget(parent)
    {
    }
};

// --------------------------------------------------------------------------------------------------------------------

} /* namespace LibreAudio */
