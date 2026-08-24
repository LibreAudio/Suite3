// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../widgets-todo/base.hpp"
#include "../widgets-todo/knob-group.hpp"
#include "../widgets-todo/meter.hpp"
#include "../widgets-todo/pill-toggle.hpp"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioParameterDumpStageWidget final : public LibreAudioReferenceContainerWidget<LibreAudioReference::Stage, kVertical>
{
    using R = LibreAudioReference::Stage;
    using BaseWidget = LibreAudioReferenceContainerWidget<R, kVertical>;
    using KnobGroupWidget = LibreAudioKnobGroupWidget<LibreAudioSmallKnobWidget, 10>;

    std::unique_ptr<LibreAudioPillAreaWidget> fTopArea = addWidget<LibreAudioPillAreaWidget>();
    std::list<std::unique_ptr<LibreAudioWidget>> fSpacers;
    std::list<std::unique_ptr<KnobGroupWidget>> fKnobGroups;

    const std::vector<FaustParameter>& kParameters = getFaustParameters();

public:
    explicit LibreAudioParameterDumpStageWidget(LibreAudioWidget* const parent)
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
        std::unique_ptr<KnobGroupWidget> widget { new KnobGroupWidget(this, kParameters, kParametersMainStart, offset) };
        widgets.push_back({ widget.get(), Fixed });
        fKnobGroups.emplace_back(std::move(widget));
    }

    void addSpacer()
    {
        std::unique_ptr<LibreAudioEmptyWidget> spacer { new LibreAudioEmptyWidget(this) };
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
            fillColor(LibreAudioReference::Colors::bg0);
            fill();
        }

        fillPaint(linearGradient(0, h - h * 0.4f, 0, h - h * 0.2f, LibreAudioReference::Colors::transparent, Color(0.f, 0.f, 0.f, 0.2f)));
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

class LibreAudioParameterDumpArea : public LibreAudioReferenceContainerWidget<LibreAudioReference::MainArea>
{
    std::unique_ptr<LibreAudioWidget> fMetersIn = addWidget<LibreAudioMeterWidget<Input>>();
    std::unique_ptr<LibreAudioParameterDumpStageWidget> fStage = addWidget<LibreAudioParameterDumpStageWidget, Expanding>();
    std::unique_ptr<LibreAudioWidget> fMetersOut = addWidget<LibreAudioMeterWidget<Output>>();

public:
    LibreAudioParameterDumpArea(LibreAudioTopLevelWidget* const parent)
        : LibreAudioReferenceContainerWidget(parent)
    {
    }
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
