// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "DistrhoPluginInfo.h"

#include "../_lab/color.hpp"
#include "../_lab/container.hpp"
#include "../_lab/image.hpp"

#include "../reference.hpp"
#include "../widgets/combo-box.hpp"
#include "../widgets/knob.hpp"
#include "../widgets/toggle-switch.hpp"

#include "LibreAudioParameters.hpp"

#include LIBREAUDIO_PLUGIN_PARAMETERS_INCLUDE

#include "Layout.hpp"

#include "las-resources.h"

#include <memory>

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------

template<class KnobWidget = SmallKnobWidget, uint kMaxNumParameters = 5>
class KnobGroupWidget : public ReferenceContainerWidget<Reference::Widgets::KnobGroup>,
                        private IdleCallback
{
    using R = Reference::Widgets::KnobGroup;
    using BaseWidget = ReferenceContainerWidget<R>;

    std::list<std::shared_ptr<KnobWidget>> fKnobs;
    std::list<std::shared_ptr<ButtonBaseWidget>> fButtons;
    std::list<std::shared_ptr<ToggleSwitchBaseWidget>> fToggles;
    std::list<std::shared_ptr<LabWidget>> fSpacers;

    struct Bracket {
        const char* const label;
        std::shared_ptr<KnobWidget> start;
        std::shared_ptr<KnobWidget> end;
    };
    std::list<Bracket> fBrackets;

    static constexpr const std::string_view kLabel = DISTRHO_PLUGIN_LABEL;

public:
    explicit KnobGroupWidget(LabWidget* const parent,
                             const uint32_t idOffset = 0,
                             const uint32_t parameterStart = 0,
                             const bool withSurroundingSpacers = false)
        : BaseWidget(parent),
          fParametersOffset(idOffset)
    {
        // FIXME alternative UI if no params exported
        // static_assert(!kFaustParameters.empty(), "must have at least 1 parameter");

        if (withSurroundingSpacers)
            addSpacer(0);

        for (uint32_t i = parameterStart, numVisibleWidgets = 0, count = std::size(kFaustParameters);
             i < count && numVisibleWidgets < kMaxNumParameters;
             ++i)
        {
            const FaustParameter& parameter = kFaustParameters[i];
            if ((parameter.isEnumerator && kMaxNumParameters == 5) || parameter.isOutput) {
                d_stdout("knob-group skipped parameter %s", parameter.name);
                continue;
            }

            if (! fKnobs.empty() || ! fButtons.empty() || ! fToggles.empty())
                addSpacer(idOffset + i);

            if (parameter.isEnumerator && parameter.scalePointCount == 2)
            {
                std::unique_ptr<ToggleSwitchBaseWidget> widget { new ToggleSwitchWidget<4, kMaxNumParameters == 2>(this, idOffset + i, parameter) };
                widgets.push_back({ widget.get(), Fixed });
                if (widget->getSize().isNull())
                    d_stderr2("Error: addToggle called but widget '%s' does not have a known size", widget->getName());
                fToggles.emplace_back(std::move(widget));
            }
            else if (parameter.isEnumerator)
            {
                std::unique_ptr<ButtonBaseWidget> widget { new ComboBoxWidget(this, idOffset + i, parameter) };
                widgets.push_back({ widget.get(), Fixed });
                if (widget->getSize().isNull())
                    d_stderr2("Error: addComboBox called but widget '%s' does not have a known size", widget->getName());
                fButtons.emplace_back(std::move(widget));
            }
            else
            {
                std::unique_ptr<KnobWidget> widget { new KnobWidget(this, parameter, idOffset + i) };
                widgets.push_back({ widget.get(), Fixed });
                if (widget->getSize().isNull())
                    d_stderr2("Error: addKnob called but widget '%s' does not have a known size", widget->getName());
                fKnobs.emplace_back(std::move(widget));
            }

            if constexpr (kLabel == "chorus")
            {
                if (std::strcmp(parameter.symbol, "dctr") != 0)
                    ++numVisibleWidgets;
            }
            else if constexpr (kLabel == "vocalDoubler")
            {
                if (std::strcmp(parameter.symbol, "adt_delay") == 0 ||
                    std::strcmp(parameter.symbol, "adt_2voice") == 0 ||
                    std::strcmp(parameter.symbol, "adt_wow_rate") == 0 ||
                    std::strcmp(parameter.symbol, "adt_wow_depth") == 0 ||
                    std::strcmp(parameter.symbol, "adt_pan") == 0 ||
                    std::strcmp(parameter.symbol, "adt_width") == 0 ||
                    std::strcmp(parameter.symbol, "doubler_base_delay") == 0 ||
                    std::strcmp(parameter.symbol, "doubler_detune") == 0 ||
                    std::strcmp(parameter.symbol, "doubler_wander_rate") == 0 ||
                    std::strcmp(parameter.symbol, "doubler_wander_depth") == 0 ||
                    std::strcmp(parameter.symbol, "doubler_width") == 0
                    // std::strcmp(parameter.symbol, "take_base_delay") == 0 ||
                    // std::strcmp(parameter.symbol, "take_timing") == 0 ||
                    // std::strcmp(parameter.symbol, "take_pitch") == 0 ||
                    // std::strcmp(parameter.symbol, "take_character") == 0 ||
                    // std::strcmp(parameter.symbol, "take_width") == 0
                )
                {
                }
                else
                {
                    ++numVisibleWidgets;
                }
            }
            else
            {
                ++numVisibleWidgets;
            }
        }

        if (withSurroundingSpacers)
            addSpacer(0);

        if (update())
            addIdleCallback(this);

        updateSize(true);
    }

    [[nodiscard]] uint32_t getLastKnobId() const
    {
        if (fKnobs.empty())
            return 0;

        return fKnobs.back()->getId();
    }

    void updateEnabledById(const uint32_t id, const bool enabled)
    {
        for (const std::shared_ptr<KnobWidget>& widget : fKnobs)
        {
            if (KnobWidget* const widgetPtr = widget.get(); widgetPtr->getId() == id)
            {
                widgetPtr->setEnabled(enabled, false);
                break;
            }
        }

        for (const std::shared_ptr<ButtonBaseWidget>& widget : fButtons)
        {
            if (ButtonBaseWidget* const widgetPtr = widget.get(); widgetPtr->getId() == id)
            {
                widgetPtr->setEnabled(enabled, false);
                break;
            }
        }

        for (const std::shared_ptr<ToggleSwitchBaseWidget>& widget : fToggles)
        {
            if (ToggleSwitchBaseWidget* const widgetPtr = widget.get(); widgetPtr->getId() == id)
            {
                widgetPtr->setEnabled(enabled, false);
                break;
            }
        }
    }

    void updateVisibilityById(const uint32_t id, const bool visible)
    {
        for (const std::shared_ptr<KnobWidget>& knob : fKnobs)
        {
            if (KnobWidget* const knobPtr = knob.get(); knobPtr->getId() == id)
            {
                knobPtr->setVisible(visible);
                break;
            }
        }

        for (const std::shared_ptr<ButtonBaseWidget>& widget : fButtons)
        {
            if (LabWidget* const widgetPtr = widget.get(); widgetPtr->getId() == id)
            {
                widgetPtr->setVisible(visible);
                break;
            }
        }

        for (const std::shared_ptr<ToggleSwitchBaseWidget>& widget : fToggles)
        {
            if (LabWidget* const widgetPtr = widget.get(); widgetPtr->getId() == id)
            {
                widgetPtr->setVisible(visible);
                break;
            }
        }

        for (const std::shared_ptr<LabWidget>& spacer : fSpacers)
        {
            if (LabWidget* const spacerPtr = spacer.get(); spacerPtr->getId() == id)
            {
                spacerPtr->setVisible(visible);
                break;
            }
        }
    }

private:
    const uint32_t fParametersOffset;
    bool fHasCachedValues = false;
    float cachedValue1;
    float cachedValue2;

    void addSpacer(const uint id)
    {
        std::shared_ptr<LabWidget> spacer { new LabEmptyWidget(this) };
        // static constexpr const float c[4] = { 0.0f, 0.71f, 0.11f, 1.f };
        // std::shared_ptr<LabWidget> spacer { new LabColorWidget<c>(this) };
        spacer->setId(id);
        widgets.push_back({ spacer.get(), Expanding });
        fSpacers.emplace_back(std::move(spacer));
    }

    void addWidget() = delete;

    void idleCallback() final
    {
        update();
    }

    bool update()
    {
#if 0
#elif defined(LIBREAUDIO_PLUGIN__chorus)
        static_assert(kLabel == "chorus", "wrong plugin");
        // if constexpr (kLabel == "chorus")
        {
            using namespace chorus;

            if (fKnobs.front()->getId() != kParametersMainStart + kFaustParameterDctr)
                return false;

            const float fmode = fInterface->getParameterValue(kParametersMainStart + kFaustParameterMode);
            const float fstereo = fInterface->getParameterValue(kParametersMainStart + kFaustParameterStereo);

            if (fHasCachedValues && d_isEqual(cachedValue1, fmode) && d_isEqual(cachedValue2, fstereo))
                return false;

            cachedValue1 = fmode;
            cachedValue2 = fstereo;

            const uint mode = d_roundToUnsignedInt(fmode);
            updateVisibilityById(kParametersMainStart + kFaustParameterDctr, mode == 0 || mode == 1 || mode == 2);
            updateVisibilityById(kParametersMainStart + kFaustParameterDdepth, mode == 0 || mode == 1 || mode == 2);
            updateVisibilityById(kParametersMainStart + kFaustParameterRate1, mode == 0 || mode == 1 || mode == 2);
            updateVisibilityById(kParametersMainStart + kFaustParameterRate2, mode == 0 || mode == 1 || mode == 2);
            updateEnabledById(kParametersMainStart + kFaustParameterRate2, mode == 1 || mode == 2);
            updateVisibilityById(kParametersMainStart + kFaustParameterDim, mode == 3);
            updateEnabledById(kParametersMainStart + kFaustParameterDetune, d_isNotZero(fstereo));
        }
#elif defined(LIBREAUDIO_PLUGIN__vocalDoubler)
        static_assert(kLabel == "vocalDoubler", "wrong plugin");
        // if constexpr (kLabel == "vocalDoubler")
        {
            using namespace vocalDoubler;

            if (fKnobs.front()->getId() != kParametersMainStart + kFaustParameterAdt_delay)
                return false;

            const float fmode = fInterface->getParameterValue(kParametersMainStart + kFaustParameterMode);
            const float f2voices = fInterface->getParameterValue(kParametersMainStart + kFaustParameterAdt_2voice);

            if (fHasCachedValues && d_isEqual(cachedValue1, fmode) && d_isEqual(cachedValue2, f2voices))
                return false;

            cachedValue1 = fmode;
            cachedValue2 = f2voices;

            const uint mode = d_roundToUnsignedInt(fmode);

            for (uint id : { kFaustParameterAdt_delay,
                             kFaustParameterAdt_2voice,
                             kFaustParameterAdt_wow_rate,
                             kFaustParameterAdt_wow_depth })
                updateVisibilityById(kParametersMainStart + id, mode == 0);

            for (uint id : { kFaustParameterDoubler_base_delay,
                             kFaustParameterDoubler_detune,
                             kFaustParameterDoubler_wander_rate,
                             kFaustParameterDoubler_wander_depth,
                             kFaustParameterDoubler_width })
                updateVisibilityById(kParametersMainStart + id, mode == 1);

            for (uint id : { kFaustParameterTake_base_delay,
                             kFaustParameterTake_timing,
                             kFaustParameterTake_pitch,
                             kFaustParameterTake_character,
                             kFaustParameterTake_width })
                updateVisibilityById(kParametersMainStart + id, mode == 2);

            updateVisibilityById(kParametersMainStart + kFaustParameterAdt_pan, mode == 0 && d_isNotEqual(f2voices, 2.f));
            updateVisibilityById(kParametersMainStart + kFaustParameterAdt_width, mode == 0 && d_isEqual(f2voices, 2.f));
        }

        // 1st widget must not be a spacer
        uint firstVisibleId = UINT_MAX;
        for (const std::shared_ptr<KnobWidget>& widget : fKnobs)
        {
            if (KnobWidget* const widgetPtr = widget.get(); widgetPtr->isVisible())
            {
                firstVisibleId = widgetPtr->getId();
                break;
            }
        }
        for (const std::shared_ptr<ButtonBaseWidget>& widget : fButtons)
        {
            if (LabWidget* const widgetPtr = widget.get(); widgetPtr->isVisible())
            {
                firstVisibleId = widgetPtr->getId();
                break;
            }
        }
        for (const std::shared_ptr<ToggleSwitchBaseWidget>& widget : fToggles)
        {
            if (LabWidget* const widgetPtr = widget.get(); widgetPtr->isVisible())
            {
                firstVisibleId = widgetPtr->getId();
                break;
            }
        }

        if (firstVisibleId != UINT_MAX)
        {
            for (const std::shared_ptr<LabWidget>& spacer : fSpacers)
            {
                if (Widget* const spacerPtr = spacer.get(); spacerPtr->isVisible())
                {
                    if (spacerPtr->getId() <= firstVisibleId)
                        spacerPtr->hide();
                    break;
                }
            }
        }
#else
        return false;
#endif

        fBrackets.clear();

        const char* lastBracket = "";
        for (const std::shared_ptr<KnobWidget>& knob : fKnobs)
        {
            const FaustParameter& parameter = knob->getParameter();

            if (std::strcmp(parameter.bracket, lastBracket) != 0)
            {
                if (*parameter.bracket != '\0' && knob->isVisible())
                    fBrackets.push_back({ parameter.bracket, knob, knob });

                lastBracket = parameter.bracket;
            }
            else if (! fBrackets.empty())
            {
                Bracket& bracket = fBrackets.back();

                if (std::strcmp(bracket.label, lastBracket) == 0)
                    bracket.end = knob;
            }
        }

        fHasCachedValues = true;
        updateSize(true);
        return true;
    }

    void onNanoDisplay() final
    {
        const float margin = R::Bracket::margin * fScaleFactor;
        const float padding = R::Bracket::padding * fScaleFactor;
        const float lw = R::Bracket::width * fScaleFactor;
        const float ly = R::Bracket::height * fScaleFactor;

        strokeWidth(lw);

        for (const Bracket& bracket : fBrackets)
        {
            const KnobWidget* const knobS = bracket.start.get();
            const KnobWidget* const knobE = bracket.end.get();

            const float sx = knobS->getAbsoluteX() - getAbsoluteX() + margin;
            const float ex = knobE->getAbsoluteX() + knobE->getWidth() - getAbsoluteX() - margin;
            const float mx = sx + (ex - sx) * 0.5f;

            beginPath();
            fontSize(R::Bracket::fontSize * fScaleFactor);
            textAlign(ALIGN_CENTER | ALIGN_MIDDLE);
            textLetterSpacing(R::Bracket::letterSpacing * fScaleFactor);

            // TODO text shadow
            // fillColor(Color(R::Bracket::color.minus(30), 0.5f));
            // text(mx, margin * 0.5f, bracket.label);

            fillColor(R::Bracket::color);
            text(mx, 0, bracket.label);

            Rectangle<float> bounds;
            textBounds(mx, 0, bracket.label, nullptr, bounds);

            strokeColor(R::Bracket::color);

            beginPath();
            moveTo(sx, ly);
            lineTo(sx, 0);
            lineTo(bounds.getX() - padding, 0);
            stroke();

            beginPath();
            moveTo(bounds.getX() + bounds.getWidth() + padding, 0);
            lineTo(ex, 0);
            lineTo(ex, ly);
            stroke();
        }
    }

    void updateSize(const bool updateChildren) final
    {
        const uint border = d_roundToUnsignedInt(R::border * fScaleFactor);
        const uint margin = d_roundToUnsignedInt(R::margin * fScaleFactor);
        uint knobHeight;

        if constexpr (R::height != 0)
            knobHeight = R::height * fScaleFactor;
        else if (! fKnobs.empty())
            knobHeight = fKnobs.front()->getHeight();
        else if (! fButtons.empty())
            knobHeight = fButtons.front()->getHeight();
        else if (! fToggles.empty())
            knobHeight = fToggles.front()->getHeight();
        else
            knobHeight = d_roundToUnsignedInt(fScaleFactor);

        Widget::setHeight((border + margin) * 2 + knobHeight);
        BaseWidget::updateSize(updateChildren);
    }
};

// --------------------------------------------------------------------------------------------------------------------

class EasyKnobsGroupWidget final : public ReferenceContainerWidget<Reference::Widgets::KnobGroup>
{
    using R = Reference::Widgets::KnobGroup;
    using BaseWidget = ReferenceContainerWidget<R>;

public:
    explicit EasyKnobsGroupWidget(LabWidget* const parent)
        : BaseWidget(parent)
    {
        addSpacer();

        for (uint32_t i = 0, count = std::size(kFaustParameters); i < count; ++i)
        {
            const FaustParameter& parameter = kFaustParameters[i];
            if (! parameter.isEasy) {
                continue;
            }
            std::shared_ptr<LabKnobWidget> widget { new EasyKnobWidget(this, parameter, kParametersMainStart + i) };
            widgets.push_back({ widget.get(), Fixed });
            fKnobs.emplace_back(std::move(widget));
        }

        addSpacer();

        updateSize(true);
    }

    void addWidget() = delete;

private:
    std::list<std::shared_ptr<LabKnobWidget>> fKnobs;
    std::list<std::shared_ptr<LabWidget>> fSpacers;

    void updateSize(const bool updateChildren) final
    {
        const uint border = d_roundToUnsignedInt(R::border * fScaleFactor);
        const uint margin = d_roundToUnsignedInt(R::margin * fScaleFactor);
        uint knobHeight;

        if constexpr (R::height != 0)
            knobHeight = R::height * fScaleFactor;
        else if (! fKnobs.empty())
            knobHeight = fKnobs.front()->getHeight();
        else
            knobHeight = d_roundToUnsignedInt(fScaleFactor);

        BaseWidget::setHeight((border + margin) * 2 + knobHeight);
        BaseWidget::updateSize(updateChildren);
    }

    void addSpacer()
    {
        std::shared_ptr<LabWidget> spacer { new LabEmptyWidget(this) };
        widgets.push_back({ spacer.get(), Expanding });
        fSpacers.emplace_back(std::move(spacer));
    }
};

// --------------------------------------------------------------------------------------------------------------------

class ExpertKnobsGroupWidget final : public ReferenceContainerWidget<Reference::Widgets::KnobGroup>
{
    using R = Reference::Widgets::KnobGroup;
    using BaseWidget = ReferenceContainerWidget<R>;

public:
    explicit ExpertKnobsGroupWidget(LabWidget* const parent)
        : BaseWidget(parent)
    {
        widgets.push_back({ fKnobsLeft.get(), Expanding });
        widgets.push_back({ fLogo.get(), Fixed });
        widgets.push_back({ fKnobsRight.get(), Expanding });

        updateSize(true);
    }

    void addWidget() = delete;

private:
    std::shared_ptr<KnobGroupWidget<>> fKnobsLeft { new KnobGroupWidget<>(this, kParametersMainStart, 0) };
    std::shared_ptr<LabWidget> fLogo { new LabImageWidget<IMAGES_LA_PNG_DATA, IMAGES_LA_PNG_LEN>(this) };
    std::shared_ptr<KnobGroupWidget<>> fKnobsRight { new KnobGroupWidget<>(this, kParametersMainStart, fKnobsLeft->getLastKnobId() + 1 - kParametersMainStart) };

    void updateSize(const bool updateChildren) final
    {
        const uint border = d_roundToUnsignedInt(R::border * fScaleFactor);
        const uint margin = d_roundToUnsignedInt(R::margin * fScaleFactor);
        uint knobHeight;

        if constexpr (R::height != 0)
            knobHeight = d_roundToUnsignedInt(R::height * fScaleFactor);
        else
            knobHeight = d_max(fKnobsLeft->getHeight(), fKnobsRight->getHeight());

        BaseWidget::setHeight((border + margin) * 2 + knobHeight);
        BaseWidget::updateSize(updateChildren);
    }
};

// --------------------------------------------------------------------------------------------------------------------

} /* namespace LibreAudio */
