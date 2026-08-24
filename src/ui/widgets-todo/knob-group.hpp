// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "DistrhoPluginInfo.h"

#include "../reference.hpp"
#include "../reference/container.hpp"
#include "../reference/image.hpp"
#include "DistrhoUtils.hpp"
#include "knob.hpp"

#include "LibreAudioParameters.hpp"

#include "Layout.hpp"

#include "las-resources.h"

#include <memory>

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

template<class KnobWidget = LibreAudioSmallKnobWidget, uint kMaxNumParameters = 5>
class LibreAudioKnobGroupWidget : public LibreAudioReferenceContainerWidget<LibreAudioReference::Widgets::KnobGroup>,
                                  private IdleCallback
{
    using R = LibreAudioReference::Widgets::KnobGroup;
    using BaseWidget = LibreAudioReferenceContainerWidget<R>;

    std::vector<std::unique_ptr<KnobWidget>> fKnobs;
    std::vector<std::unique_ptr<LibreAudioEmptyWidget>> fSpacers;

    struct Bracket {
        uint start;
        uint end;
        const char* label;
    };
    std::vector<Bracket> fBrackets;

    static constexpr const std::string_view kLabel = DISTRHO_PLUGIN_LABEL;

public:
    explicit LibreAudioKnobGroupWidget(LibreAudioWidget* const parent,
                                       const std::vector<FaustParameter>& parameters,
                                       const uint32_t idOffset = 0,
                                       const uint32_t parameterStart = 0)
        : BaseWidget(parent),
          fParameters(parameters),
          fParametersOffset(idOffset)
    {
        DISTRHO_SAFE_ASSERT_RETURN(!parameters.empty(),);

        fKnobs.reserve(kMaxNumParameters);
        fSpacers.reserve(kMaxNumParameters + 1);

        for (uint32_t i = parameterStart, numVisibleWidgets = 0, count = parameters.size(); i < count && numVisibleWidgets < kMaxNumParameters; ++i)
        {
            const FaustParameter& parameter = parameters[i];
            if (parameter.isEnumerator || parameter.isOutput) {
                d_stdout("knob-group skipped parameter %s", parameter.name);
                continue;
            }

            if (! fKnobs.empty())
                addSpacer(idOffset + i);

            std::unique_ptr<KnobWidget> widget { new KnobWidget(this, parameter, idOffset + i) };
            widgets.push_back({ widget.get(), Fixed });
            if (widget->getSize().isNull())
                d_stderr2("Error: addKnob called but widget '%s' does not have a known size", widget->getName());

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
                    // widget->hide();
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

            fKnobs.emplace_back(std::move(widget));
        }

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

private:
    const std::vector<FaustParameter>& fParameters;
    const uint32_t fParametersOffset;
    bool fHasCachedValues = false;
    float cachedValue1;
    float cachedValue2;

    void addSpacer(const uint id)
    {
        std::unique_ptr<LibreAudioEmptyWidget> spacer { new LibreAudioEmptyWidget(this) };
        spacer->setId(id);
        widgets.push_back({ spacer.get(), Expanding });
        fSpacers.emplace_back(std::move(spacer));
    }

    void addWidget() = delete;

    void idleCallback() final
    {
        update();
    }

    void updateEnabledById(const uint32_t id, const bool enabled)
    {
        for (const std::unique_ptr<KnobWidget>& knob : fKnobs)
        {
            if (KnobWidget* const knobPtr = knob.get(); knobPtr->getId() == id)
            {
                knobPtr->setEnabled(enabled, false);
                break;
            }
        }
    }

    void updateVisibilityById(const uint32_t id, const bool visible)
    {
        for (const std::unique_ptr<KnobWidget>& knob : fKnobs)
        {
            if (KnobWidget* const knobPtr = knob.get(); knobPtr->getId() == id)
            {
                knobPtr->setVisible(visible);
                break;
            }
        }

        for (const std::unique_ptr<LibreAudioEmptyWidget>& spacer : fSpacers)
        {
            if (LibreAudioEmptyWidget* const spacerPtr = spacer.get(); spacerPtr->getId() == id)
            {
                spacerPtr->setVisible(visible);
                break;
            }
        }
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
#else
        return false;
#endif

        fBrackets.clear();

#if 0
        const char* lastBracket = "";
        for (uint i = 0, size = fKnobs.size(); i < size; ++i)
        {
            const std::unique_ptr<KnobWidget>& knob = fKnobs[i];

            const FaustParameter& parameter = fParameters.at(knob->getId() - fParametersOffset);

            if (std::strcmp(parameter.bracket, lastBracket) != 0)
            {
                if (fBrackets.empty())
                {
                    if (knob->isVisible())
                        fBrackets.push_back({ i, i, parameter.bracket });
                }
                else
                {
                    if (*lastBracket != '\0' && ! fBrackets.empty())
                        fBrackets.back().end = i - 1;

                    if (*parameter.bracket != '\0' && knob->isVisible())
                        fBrackets.push_back({ i, i, parameter.bracket });
                }
            }

            lastBracket = parameter.bracket;
        }

        if (*lastBracket != '\0' && ! fBrackets.empty())
            fBrackets.back().end = fKnobs.size() - 1;

        for (const Bracket& bracket : fBrackets)
            d_stdout("bracket %s: %u -> %u", bracket.label, bracket.start, bracket.end);
#endif

        if (fHasCachedValues)
        {
            // ResizeEvent ev;
            // ev.size = getSize();
            // onResize(ev);
        }
        else
        {
            fHasCachedValues = true;
        }

        updateSize(true);
        return true;
    }

    void onNanoDisplay() final
    {
        for (const Bracket& bracket : fBrackets)
        {
            const KnobWidget* const knobS = fKnobs[bracket.start].get();
            const KnobWidget* const knobE = fKnobs[bracket.end].get();

            const float lw = 2;
            const float sx = knobS->getAbsoluteX() /*- knobS->getWidth()*/;
            const float ex = knobE->getAbsoluteX() /*+ knobE->getWidth()*/;
            const float mx = sx + (ex - sx) * 0.5f;
            const float y = 20;

            beginPath();
            fontSize(LibreAudioReference::Common::fontSize * fScaleFactor);
            textAlign(ALIGN_CENTER | ALIGN_MIDDLE);

            fillColor(Color(LibreAudioReference::Colors::ink.invert(), 0.5f));
            text(mx, 1 * fScaleFactor, bracket.label);

            fillColor(LibreAudioReference::Colors::ink3);
            text(mx, 0, bracket.label);

            Rectangle<float> bounds;
            textBounds(mx, 0, bracket.label, nullptr, bounds);

            strokeColor(LibreAudioReference::Colors::ink3);
            strokeWidth(lw);

            beginPath();
            moveTo(sx, y);
            lineTo(sx, 0);
            lineTo(bounds.getX() - 2, 0);
            stroke();

            beginPath();
            moveTo(bounds.getX() + bounds.getWidth() + 2, 0);
            lineTo(ex, 0);
            lineTo(ex, y);
            stroke();
        }

        // const float w = getWidth();
        // const float h = getHeight();
        //
        // beginPath();
        // roundedRect(0, 0, w, h, 4 * this->fScaleFactor);
        // fillColor(Color(1.f, 0.f, 0.f));
        // fill();

        // const float border = 18 * this->fScaleFactor;
        // const float radius = 4 * this->fScaleFactor;
        // const float feather = 28 * this->fScaleFactor;

        // fillPaint(boxGradient(0, 0, w, h, radius, feather, Color(0.f, 0.f, 0.f, 0.f), Color(0.f, 0.f, 0.f, 1.0f)));
        // fill();
        //
        // beginPath();
        // roundedRect(border * 0.5f, border * 0.5f, w - border, h - border, radius);
        // strokeColor(Color(0.f, 1.f, 0.f, 0.5f));
        // strokeWidth(border);
        // stroke();
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
        else
            knobHeight = d_roundToUnsignedInt(fScaleFactor);

        LibreAudioWidget::setHeight((border + margin) * 2 + knobHeight);
        BaseWidget::updateSize(updateChildren);
    }
};

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioEasyKnobsGroupWidget final : public LibreAudioReferenceContainerWidget<LibreAudioReference::Widgets::KnobGroup>
{
    using R = LibreAudioReference::Widgets::KnobGroup;
    using BaseWidget = LibreAudioReferenceContainerWidget<R>;

public:
    explicit LibreAudioEasyKnobsGroupWidget(LibreAudioWidget* const parent)
        : BaseWidget(parent)
    {
        addSpacer();

        const std::vector<FaustParameter>& parameters = getFaustParameters();

        for (uint32_t i = 0, count = parameters.size(); i < count; ++i)
        {
            const FaustParameter& parameter = parameters[i];
            if (! parameter.isEasy) {
                continue;
            }
            std::unique_ptr<LibreAudioKnobWidget> widget { new LibreAudioEasyKnobWidget(this, parameter, kParametersMainStart + i) };
            widgets.push_back({ widget.get(), Fixed });
            fKnobs.emplace_back(std::move(widget));
        }

        addSpacer();

        updateSize(true);
    }

    void addWidget() = delete;

private:
    std::vector<std::unique_ptr<LibreAudioKnobWidget>> fKnobs;
    std::vector<std::unique_ptr<LibreAudioWidget>> fSpacers;

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
        std::unique_ptr<LibreAudioEmptyWidget> spacer { new LibreAudioEmptyWidget(this) };
        widgets.push_back({ spacer.get(), Expanding });
        fSpacers.emplace_back(std::move(spacer));
    }
};

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioExpertKnobsGroupWidget final : public LibreAudioReferenceContainerWidget<LibreAudioReference::Widgets::KnobGroup>
{
    using R = LibreAudioReference::Widgets::KnobGroup;
    using BaseWidget = LibreAudioReferenceContainerWidget<R>;

public:
    explicit LibreAudioExpertKnobsGroupWidget(LibreAudioWidget* const parent)
        : BaseWidget(parent)
    {
        const std::vector<FaustParameter>& parameters = getFaustParameters();

        fKnobsLeft.reset(new LibreAudioKnobGroupWidget<>(this, parameters, kParametersMainStart, 0));
        widgets.push_back({ fKnobsLeft.get(), Expanding });

        fLogo.reset(new LibreAudioImageWidget<IMAGES_LA_PNG_DATA, IMAGES_LA_PNG_LEN>(this));
        widgets.push_back({ fLogo.get(), Fixed });

        fKnobsRight.reset(new LibreAudioKnobGroupWidget<>(this, parameters, kParametersMainStart, fKnobsLeft->getLastKnobId() + 1 - kParametersMainStart));
        widgets.push_back({ fKnobsRight.get(), Expanding });

        updateSize(true);
    }

    void addWidget() = delete;

private:
    std::unique_ptr<LibreAudioKnobGroupWidget<>> fKnobsLeft;
    std::unique_ptr<LibreAudioWidget> fLogo;
    std::unique_ptr<LibreAudioKnobGroupWidget<>> fKnobsRight;

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

END_NAMESPACE_DISTRHO
