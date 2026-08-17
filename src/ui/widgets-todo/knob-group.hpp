// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../reference.hpp"
#include "../base/container.hpp"
#include "../base/image.hpp"
#include "DistrhoUtils.hpp"
#include "knob.hpp"

#include "LibreAudioParameters.hpp"

#include "Layout.hpp"

#include "las-resources.h"

#include <memory>

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

template<class KnobWidget = LibreAudioSmallKnobWidget>
class LibreAudioKnobGroupWidget : public LibreAudioReferenceContainerWidget<LibreAudioReference::Widgets::KnobGroup>,
                                  private IdleCallback
{
    using R = LibreAudioReference::Widgets::KnobGroup;

    static constexpr const uint kMaxNumParameters = 5;

    std::vector<std::unique_ptr<KnobWidget>> fKnobs;
    std::vector<std::unique_ptr<LibreAudioWidget>> fSpacers;

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
                                       const uint32_t parameterOffset = 0)
        : LibreAudioReferenceContainerWidget(parent),
          fParameters(parameters),
          fParametersOffset(idOffset)
    {
        DISTRHO_SAFE_ASSERT_RETURN(!parameters.empty(),);

        fKnobs.reserve(kMaxNumParameters);
        fSpacers.reserve(kMaxNumParameters + 1);

        addSpacer();

        for (uint32_t i = parameterOffset, numVisibleWidgets = 0, count = parameters.size(); i < count && numVisibleWidgets < kMaxNumParameters; ++i)
        {
            const FaustParameter& parameter = parameters[i];
            if (parameter.isEnumerator || parameter.isOutput) {
                d_stdout("knob-group skipped parameter %s", parameter.name);
                continue;
            }
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
            addSpacer();
        }

        if (update())
            addIdleCallback(this);

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

    void addSpacer()
    {
        std::unique_ptr<LibreAudioEmptyWidget<>> spacer { new LibreAudioEmptyWidget(this) };
        widgets.push_back({ spacer.get(), Expanding });
        fSpacers.emplace_back(std::move(spacer));
    }

    void addWidget() = delete;

    void idleCallback() final
    {
        update();
    }

    [[nodiscard]] KnobWidget* getKnobById(const uint32_t id) const
    {
        for (const std::unique_ptr<KnobWidget>& knob : fKnobs)
            if (KnobWidget* const knobPtr = knob.get(); knobPtr->getId() == id)
                return knobPtr;

        d_stderr2("getKnobById with invalid id %u", id);
        return nullptr;
    }

    bool update()
    {
#if 0
#elif defined(LIBREAUDIO_PLUGIN__chorus)
        static_assert(kLabel == "chorus", "wrong plugin");
        // if constexpr (kLabel == "chorus")
        {
            if (fKnobs.front()->getId() != kParametersMainStart + chorus::kFaustParameterDctr)
                return false;

            const float fmode = fInterface->getParameterValue(kParametersMainStart + chorus::kFaustParameterMode);
            const float fstereo = fInterface->getParameterValue(kParametersMainStart + chorus::kFaustParameterStereo);

            if (fHasCachedValues && d_isEqual(cachedValue1, fmode) && d_isEqual(cachedValue2, fstereo))
                return false;

            cachedValue1 = fmode;
            cachedValue2 = fstereo;

            const uint mode = d_roundToUnsignedInt(fmode);
            getKnobById(kParametersMainStart + chorus::kFaustParameterDctr)->setVisible(mode == 0 || mode == 1 || mode == 2);
            getKnobById(kParametersMainStart + chorus::kFaustParameterDdepth)->setVisible(mode == 0 || mode == 1 || mode == 2);
            getKnobById(kParametersMainStart + chorus::kFaustParameterRate1)->setVisible(mode == 0 || mode == 1 || mode == 2);
            getKnobById(kParametersMainStart + chorus::kFaustParameterRate2)->setVisible(mode == 1 || mode == 2);
            getKnobById(kParametersMainStart + chorus::kFaustParameterDim)->setVisible(mode == 3);
            getKnobById(kParametersMainStart + chorus::kFaustParameterDetune)->setEnabled(d_isNotZero(fstereo), false);
        }
#elif defined(LIBREAUDIO_PLUGIN__vocalDoubler)
        static_assert(kLabel == "vocalDoubler", "wrong plugin");
        // if constexpr (kLabel == "vocalDoubler")
        {
            if (fKnobs.front()->getId() != kParametersMainStart + vocalDoubler::kFaustParameterAdt_delay)
                return false;

            const float fmode = fInterface->getParameterValue(kParametersMainStart + vocalDoubler::kFaustParameterMode);
            const float f2voices = fInterface->getParameterValue(kParametersMainStart + vocalDoubler::kFaustParameterAdt_2voice);

            if (fHasCachedValues && d_isEqual(cachedValue1, fmode) && d_isEqual(cachedValue2, f2voices))
                return false;

            cachedValue1 = fmode;
            cachedValue2 = f2voices;

            const uint mode = d_roundToUnsignedInt(fmode);
            getKnobById(kParametersMainStart + vocalDoubler::kFaustParameterAdt_delay)->setVisible(mode == 0);
            getKnobById(kParametersMainStart + vocalDoubler::kFaustParameterAdt_2voice)->setVisible(mode == 0);
            getKnobById(kParametersMainStart + vocalDoubler::kFaustParameterAdt_wow_rate)->setVisible(mode == 0);
            getKnobById(kParametersMainStart + vocalDoubler::kFaustParameterAdt_wow_depth)->setVisible(mode == 0);
            getKnobById(kParametersMainStart + vocalDoubler::kFaustParameterAdt_pan)->setVisible(mode == 0 && d_isEqual(f2voices, 2.f));
            getKnobById(kParametersMainStart + vocalDoubler::kFaustParameterAdt_width)->setVisible(mode == 0 && d_isNotEqual(f2voices, 2.f));
            getKnobById(kParametersMainStart + vocalDoubler::kFaustParameterDoubler_base_delay)->setVisible(mode == 1);
            getKnobById(kParametersMainStart + vocalDoubler::kFaustParameterDoubler_detune)->setVisible(mode == 1);
            getKnobById(kParametersMainStart + vocalDoubler::kFaustParameterDoubler_wander_rate)->setVisible(mode == 1);
            getKnobById(kParametersMainStart + vocalDoubler::kFaustParameterDoubler_wander_depth)->setVisible(mode == 1);
            getKnobById(kParametersMainStart + vocalDoubler::kFaustParameterDoubler_width)->setVisible(mode == 1);
            getKnobById(kParametersMainStart + vocalDoubler::kFaustParameterTake_base_delay)->setVisible(mode == 2);
            getKnobById(kParametersMainStart + vocalDoubler::kFaustParameterTake_timing)->setVisible(mode == 2);
            getKnobById(kParametersMainStart + vocalDoubler::kFaustParameterTake_pitch)->setVisible(mode == 2);
            getKnobById(kParametersMainStart + vocalDoubler::kFaustParameterTake_character)->setVisible(mode == 2);
            getKnobById(kParametersMainStart + vocalDoubler::kFaustParameterTake_width)->setVisible(mode == 2);
        }
#else
        return false;
#endif

        fBrackets.clear();

        const char* lastBracket = "";
        for (uint i = 0, size = fKnobs.size(); i < size; ++i)
        {
            const std::unique_ptr<KnobWidget>& knob = fKnobs[i];
            if (! knob->isVisible())
                continue;

            const FaustParameter& parameter = fParameters.at(knob->getId() - fParametersOffset);

            if (std::strcmp(parameter.bracket, lastBracket) != 0)
            {
                if (fBrackets.empty())
                {
                    fBrackets.push_back({ i, i, parameter.bracket });
                }
                else
                {
                    if (*lastBracket != '\0')
                        fBrackets.back().end = i - 1;

                    if (*parameter.bracket != '\0')
                        fBrackets.push_back({ i, i, parameter.bracket });
                }
            }

            lastBracket = parameter.bracket;
        }

        if (*lastBracket != '\0')
            fBrackets.back().end = fKnobs.size() - 1;

        if (fHasCachedValues)
        {
            ResizeEvent ev;
            ev.size = getSize();
            onResize(ev);
        }
        else
        {
            fHasCachedValues = true;
        }

        return true;
    }

    void onNanoDisplay() final
    {
        for (const Bracket& bracket : fBrackets)
        {
            const KnobWidget* const knobS = fKnobs[bracket.start].get();
            const KnobWidget* const knobE = fKnobs[bracket.end].get();

            const float lw = 2;
            const float sx = knobS->getAbsoluteX() - knobS->getWidth();
            const float ex = knobE->getAbsoluteX() + knobE->getWidth();
            const float y = 20;

            beginPath();
            fontSize(LibreAudioReference::Common::fontSize * fScaleFactor);
            textAlign(ALIGN_CENTER | ALIGN_MIDDLE);

            fillColor(Color(LibreAudioReference::Colors::ink.invert(), 0.5f));
            text(sx + (ex - sx) * 0.5f, 1 * fScaleFactor, bracket.label);

            fillColor(LibreAudioReference::Colors::ink3);
            text(sx + (ex - sx) * 0.5f, 0, bracket.label);

            Rectangle<float> bounds;
            textBounds(sx + (ex - sx) * 0.5f, 0, bracket.label, nullptr, bounds);

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
};

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioEasyKnobsGroupWidget final : public LibreAudioReferenceContainerWidget<LibreAudioReference::Widgets::KnobGroup>
{
    using R = LibreAudioReference::Widgets::KnobGroup;

public:
    explicit LibreAudioEasyKnobsGroupWidget(LibreAudioWidget* const parent)
        : LibreAudioReferenceContainerWidget<R>(parent)
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
    }

    void addWidget() = delete;

private:
    std::vector<std::unique_ptr<LibreAudioKnobWidget>> fKnobs;
    std::vector<std::unique_ptr<LibreAudioWidget>> fSpacers;

    void addSpacer()
    {
        std::unique_ptr<LibreAudioEmptyWidget<>> spacer { new LibreAudioEmptyWidget(this) };
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

        const uint border = d_roundToUnsignedInt(R::border * fScaleFactor);
        const uint margin = d_roundToUnsignedInt(R::margin * fScaleFactor);
        uint knobHeight;

        if constexpr (R::height != 0)
            knobHeight = R::height * fScaleFactor;
        else
            knobHeight = d_max(fKnobsLeft->getHeight(), fKnobsRight->getHeight());

        BaseWidget::setHeight((border + margin) * 2 + knobHeight);
    }

    void addWidget() = delete;

private:
    std::unique_ptr<LibreAudioKnobGroupWidget<>> fKnobsLeft;
    std::unique_ptr<LibreAudioWidget> fLogo;
    std::unique_ptr<LibreAudioKnobGroupWidget<>> fKnobsRight;
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
