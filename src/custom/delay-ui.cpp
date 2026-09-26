// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#include "LibreAudioBaseUI.hpp"

#include "ui/reference.hpp"
#include "ui/containers/stage.hpp"
#include "ui/containers/top-bar.hpp"
#include "ui/widgets/dual-slider.hpp"
#include "ui/widgets/gain-meter.hpp"
#include "ui/widgets/shader.hpp"

#include "delay-parameters.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <cstring>

// --------------------------------------------------------------------------------------------------------------------

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------
// The tap model behind the expert-page scope. curve-delay.frag draws the scope from the same formulas; this copy
// exists only to place the text a shader cannot draw. Change one, change both.

// prototype CSS px to plugin px at scale 1, REFPX in the shader
static constexpr const float kScopeRefPx = 1.5f;

// scope inset inside the well, prototype px, INSET_* in the shader
static constexpr const float kScopeInsetTop = 20.f;
static constexpr const float kScopeInsetX = 14.f;
static constexpr const float kScopeInsetBottom = 16.f;

struct DelayScopeModel {
    static constexpr const float kMaxDelayMs = 4000.f;
    static constexpr const float kAmpMin = 0.006f;
    static constexpr const float kMaxTaps = 32.f;

    float msL, msR;
    float g;
    int pingpong;
    int numTaps;    // repeats down to kAmpMin -- sets the zoom level only, every repeat on screen is drawn
    float level;    // the zoom level these settings call for, ms
    float span;     // the span actually shown, ms -- level, or a step of the flip toward it
    float gridStep;

    explicit DelayScopeModel(LabUIWidgetInterface* const iface)
    {
        const auto param = [iface](const FaustParameterIndex index) {
            return iface->getParameterValue(kParametersMainStart + index);
        };

        static constexpr const float kDivTable[] = {
            4.f, 2.f, 1.5f, 1.f, 2.f / 3.f, 0.75f, 0.5f, 1.f / 3.f, 0.375f, 0.25f, 1.f / 6.f
        };
        const auto divMult = [](const float index) {
            return kDivTable[std::clamp(d_roundToIntPositive(index), 0, static_cast<int>(ARRAY_SIZE(kDivTable)) - 1)];
        };

        // as delay.dsp resolves them
        const bool sync = param(kFaustParameterSync) > 0.5f;
        const bool linked = param(kFaustParameterLink) > 0.5f;
        const float beat = 60000.f / std::max(param(kFaustParameterBpm), 1.f);
        const float rawL = sync ? divMult(param(kFaustParameterDiv_l)) * beat : param(kFaustParameterTime_l);
        const float rawR = linked ? rawL : sync ? divMult(param(kFaustParameterDiv_r)) * beat
                                                : param(kFaustParameterTime_r);
        msL = std::clamp(rawL * (1.f + param(kFaustParameterOffset_l) / 100.f), 1.f, kMaxDelayMs);
        msR = std::clamp(rawR * (1.f + param(kFaustParameterOffset_r) / 100.f), 1.f, kMaxDelayMs);

        g = std::clamp(param(kFaustParameterFeedback) / 100.f, 0.f, 0.985f);
        pingpong = d_roundToIntPositive(param(kFaustParameterPingpong));

        numTaps = g > kAmpMin ? static_cast<int>(std::min(kMaxTaps, std::floor(std::log(kAmpMin) / std::log(g)))) : 0;

        float last = pingpong == 0 ? std::max(msL, msR) : 0.5f * (msL + msR);
        last = numTaps > 0 ? numTaps * last : std::max(msL, msR);
        // fixed zoom levels, doubling from 0.6 s to 153.6 s -- see setupModel in the shader
        level = 600.f;
        for (int i = 0; i < 8 && level < last * 1.06f; ++i)
            level *= 2.f;

        setSpan(level);
    }

    // Show `newSpan` ms top to bottom, and pick the grid for it.
    void setSpan(const float newSpan) noexcept
    {
        span = newSpan;
        gridStep = 32000.f;
        for (const float s : { 50.f, 100.f, 125.f, 250.f, 500.f, 1000.f, 2000.f, 4000.f, 8000.f, 16000.f })
        {
            if (span / s <= 7.f)
            {
                gridStep = s;
                break;
            }
        }
    }

    // "250 ms", "1 s", "1.5 s", "1.25 s" -- labelChars in the shader counts these.
    static void format(char* const buffer, const size_t size, const float ms)
    {
        if (ms < 1000.f)
        {
            std::snprintf(buffer, size, "%d ms", d_roundToInt(ms));
            return;
        }

        std::snprintf(buffer, size, "%.2f", ms / 1000.f);

        // trim trailing zeros, then a trailing point
        if (char* const dot = std::strchr(buffer, '.'))
        {
            char* end = dot + std::strlen(dot) - 1;
            while (end > dot && *end == '0')
                *end-- = '\0';
            if (end == dot)
                *end = '\0';
        }

        std::strncat(buffer, " s", size - std::strlen(buffer) - 1);
    }
};

// --------------------------------------------------------------------------------------------------------------------
// Animates the flips between zoom levels. The shader receives the current span as iSpan and DelayP2 draws its labels
// from the same value, so a flip is one tween both follow. It is a function of time rather than of repaints, so the
// two agree within a frame whichever of them asks first.

class DelayScopeZoom
{
public:
    // The span to show now, given the level the settings call for.
    float span(const float level, const double now) noexcept
    {
        if (fTo <= 0.f)
        {
            // first call: no flip on opening the UI
            fFrom = fTo = level;
            fStart = now;
        }
        else if (d_isNotEqual(level, fTo))
        {
            // retarget from wherever the flip has got to, so reversing mid-flip does not jump
            fFrom = spanAt(now);
            fTo = level;
            fStart = now;
        }

        return spanAt(now);
    }

private:
    static constexpr const double kFlipSeconds = 0.35;

    float fFrom = 0.f;
    float fTo = 0.f;
    double fStart = 0.0;

    // Eased in and out, and in log span: each doubling is the same zoom step, so the move reads as one zoom
    // rather than a scroll that speeds up toward the long end.
    [[nodiscard]] float spanAt(const double now) const noexcept
    {
        const double x = std::clamp((now - fStart) / kFlipSeconds, 0.0, 1.0);
        const double e = x < 0.5 ? 4.0 * x * x * x : 1.0 - std::pow(2.0 - 2.0 * x, 3.0) / 2.0;
        return static_cast<float>(std::exp(std::log(fFrom) + (std::log(fTo) - std::log(fFrom)) * e));
    }
};

// --------------------------------------------------------------------------------------------------------------------

class DelayExpertPageWidget final : public ReferenceContainerWidget<Reference::TransparentStage, kHorizontal>
{
    using R = Reference::TransparentStage;
    using BaseWidget = ReferenceContainerWidget<R, kHorizontal>;

    template<class R>
    class Controls : public ReferenceContainerWidget<R, kVertical>
    {
        using BaseWidget = ReferenceContainerWidget<R, kVertical>;
        using Layout = typename BaseWidget::Layout;

        std::list<std::shared_ptr<LabWidget>> fWidgets;

        struct TextReference : Reference::Zero {
            static constexpr const Color color = Reference::Colors::ink2;
            static constexpr const float fontSize = 12;
            static constexpr const float letterSpacing = fontSize * 0.01;
            static constexpr const uint margin = 0;
        };

    public:
        explicit Controls(LabWidget* const parent)
            : BaseWidget(parent) {}

        template <FaustParameterIndex parameterA, FaustParameterIndex parameterB>
        void addDualSlider()
        {
            std::shared_ptr<LabWidget> widget { new DualSliderWidget<parameterA, parameterB>(this) };
            Layout::widgets.push_back({ widget.get(), Fixed });
            fWidgets.emplace_back(std::move(widget));
        }

        void addPillToggle(const FaustParameterIndex parameter)
        {
            std::shared_ptr<LabWidget> widget { new PillAreaWidget<1>(this, parameter) };
            Layout::widgets.push_back({ widget.get(), Fixed });
            fWidgets.emplace_back(std::move(widget));
        }

        template<class W, uint maxNumParameters>
        std::shared_ptr<KnobGroupWidget<W, maxNumParameters>> addKnobGroup(const FaustParameterIndex parameterStart)
        {
            std::shared_ptr<KnobGroupWidget<W, maxNumParameters>> widget {
                new KnobGroupWidget<W, maxNumParameters>(this, kParametersMainStart, parameterStart, maxNumParameters <= 2)
            };
            Layout::widgets.push_back({ widget.get(), Fixed });
            fWidgets.push_back(widget);
            return widget;
        }

        void addSpacer()
        {
            std::shared_ptr<LabWidget> spacer { new LabEmptyWidget(this) };
            Layout::widgets.push_back({ spacer.get(), Expanding });
            fWidgets.emplace_back(std::move(spacer));
        }

        void addText(const char* const text)
        {
            std::shared_ptr<LabWidget> spacer { new TextButtonWidget<kCornerNone, TextReference, kVertical>(this, text) };
            Layout::widgets.push_back({ spacer.get(), Fixed });
            fWidgets.emplace_back(std::move(spacer));
        }

        std::shared_ptr<LabWidget> getWidgetById(const uint32_t parameter) const noexcept
        {
            for (const std::shared_ptr<LabWidget>& widget : fWidgets)
                if (widget->getId() == parameter)
                    return widget;

            return {};
        }
    };

    struct RowRef : Reference::OpaqueStage {
        static constexpr const uint padding = 0;
    };

    struct SmallRowRef : Reference::OpaqueSmallStage {
        static constexpr const uint padding = 0;
    };

    class ControlsColumn : public ReferenceContainerWidget<Reference::TransparentStage, kVertical>
    {
        using BaseWidget = ReferenceContainerWidget<Reference::TransparentStage, kVertical>;

    public:
        explicit ControlsColumn(LabWidget* const parent)
            : BaseWidget(parent)
        {
        }

    protected:
        std::shared_ptr<Controls<RowRef>> fTop = addWidget<Controls<RowRef>, Expanding>();
        std::shared_ptr<Controls<SmallRowRef>> fBottom = addWidget<Controls<SmallRowRef>>();

        void updateSize(const bool updateChildren) final
        {
            // FIXME
            static_cast<LabWidget*>(fBottom.get())->setHeight(100 * fScaleFactor);

            BaseWidget::updateSize(updateChildren);
        }
    };

    class ControlsColumnLeft : public ControlsColumn,
                               private IdleCallback
    {
    public:
        explicit ControlsColumnLeft(LabWidget* const parent)
            : ControlsColumn(parent)
        {
            fTop->addPillToggle(kFaustParameterMode);
            // fTop->addSpacer();
            fTop->addKnobGroup<SmallestKnobWidget, 2>(kFaustParameterSync);
            // fTop->addSpacer();
            fKnobsDiv = fTop->addKnobGroup<SmallestKnobWidget, 2>(kFaustParameterDiv_l);
            fKnobsTime = fTop->addKnobGroup<SmallestKnobWidget, 2>(kFaustParameterTime_l);
            // fTop->addSpacer();
            fTop->addKnobGroup<SmallestKnobWidget, 2>(kFaustParameterOffset_l);

            fBottom->addText("DYNAMICS");
            fBottom->addKnobGroup<SmallestKnobWidget, 2>(kFaustParameterDeess_amount);

            update(true);

            addIdleCallback(this);
        }

    private:
        std::shared_ptr<KnobGroupWidget<SmallestKnobWidget, 2>> fKnobsDiv;
        std::shared_ptr<KnobGroupWidget<SmallestKnobWidget, 2>> fKnobsTime;
        bool fSync;
        bool fLink;

        void idleCallback() final
        {
            update();
        }

        void update(const bool init = false)
        {
            bool changed = false;
            const bool sync = d_isNotZero(fInterface->getParameterValue(kParametersMainStart + kFaustParameterSync));
            const bool link = d_isNotZero(fInterface->getParameterValue(kParametersMainStart + kFaustParameterLink));

            if (init || fSync != sync)
            {
                changed = true;
                fSync = sync;
                fKnobsDiv->setVisible(sync);
                fKnobsTime->setVisible(!sync);
            }

            if (init || fLink != link)
            {
                changed = true;
                fLink = link;
                fKnobsDiv->updateEnabledById(kParametersMainStart + kFaustParameterDiv_r, !link);
                fKnobsTime->updateEnabledById(kParametersMainStart + kFaustParameterTime_r, !link);
            }

            if (changed && !init)
                updateSize(true);
        }
    };

    class DelayP2 : public ReferenceContainerWidget<Reference::Stage, kVertical>
    {
        using BaseWidget = ReferenceContainerWidget<Reference::Stage, kVertical>;

    public:
        explicit DelayP2(LabWidget* const parent)
            : BaseWidget(parent) {}

        void setScopeZoom(DelayScopeZoom* const zoom) noexcept
        {
            fZoom = zoom;
        }

    private:
        DelayScopeZoom* fZoom = nullptr;

        // The scope itself is curve-delay.frag, drawn underneath this widget. This adds the text it cannot draw:
        // the grid times down the left edge, and L / R.
        void onNanoDisplay() override
        {
            BaseWidget::onNanoDisplay();

            DelayScopeModel model(fInterface);

            if (fZoom != nullptr)
                model.setSpan(fZoom->span(model.level, getApp().getTime()));

            const float px = kScopeRefPx * fScaleFactor;
            const float x0 = kScopeInsetX * px;
            const float y0 = kScopeInsetTop * px;
            const float w = getWidth() - 2.f * kScopeInsetX * px;
            const float h = getHeight() - (kScopeInsetTop + kScopeInsetBottom) * px;
            const float fontPx = 8.f * px;

            if (w <= 0.f || h <= 0.f)
                return;

            // dimmed with the scope while bypassed
            const float alpha = fInterface->getParameterValue(kParametersCommonStart + kCommonParameterBypass) > 0.5f
                              ? 0.35f : 1.f;

            char buffer[24];

            fontFace("mono");
            fontSize(fontPx);

            // grid times, on their lines
            fillColor(Color(0x4a, 0x4b, 0x53, alpha));
            textLetterSpacing(0.1f * fontPx);
            textAlign(ALIGN_LEFT | ALIGN_MIDDLE);

            for (float s = model.gridStep; s < model.span; s += model.gridStep)
            {
                DelayScopeModel::format(buffer, sizeof(buffer), s);
                text(x0, y0 + s / model.span * h, buffer, nullptr);
            }

            // channel labels, above the scope
            fillColor(Color(0x6a, 0x6b, 0x74, alpha));
            textLetterSpacing(0.18f * fontPx);
            textAlign(ALIGN_LEFT | ALIGN_TOP);
            text(x0, y0 - 16.f * px, "L", nullptr);
            textAlign(ALIGN_RIGHT | ALIGN_TOP);
            text(x0 + w, y0 - 16.f * px, "R", nullptr);
        }
    };

    class ControlsColumnRight : public ControlsColumn,
                                private IdleCallback
    {
    public:
        explicit ControlsColumnRight(LabWidget* const parent)
            : ControlsColumn(parent)
        {
            fTop->addPillToggle(kFaustParameterPingpong);
            // fTop->addSpacer();
            fKnobsMode = fTop->addKnobGroup<SmallestKnobWidget, 3>(kFaustParameterFeedback);
            // fTop->addSpacer();
            fTop->addKnobGroup<SmallestKnobWidget, 3>(kFaustParameterMod_rate);
            // fTop->addSpacer();
            fTop->addDualSlider<kFaustParameterHp_freq, kFaustParameterLp_freq>();

            fBottom->addText("OUTPUT");
            fBottom->addKnobGroup<SmallestKnobWidget, 2>(kFaustParameterWidth);

            update(true);

            addIdleCallback(this);
        }

    private:
        std::shared_ptr<KnobGroupWidget<SmallestKnobWidget, 3>> fKnobsMode;
        int fMode;

        void idleCallback() final
        {
            update();
        }

        void update(const bool init = false)
        {
            bool changed = false;
            const int mode = d_roundToIntPositive(fInterface->getParameterValue(kParametersMainStart + kFaustParameterPingpong));

            if (init || fMode != mode)
            {
                fMode = mode;
                fKnobsMode->updateEnabledById(kParametersMainStart + kFaustParameterCross, mode == 0);
            }

            if (changed && !init)
                updateSize(true);
        }
    };

    std::array<std::shared_ptr<LabWidget>, 3> fWidgets {
        addWidget<ControlsColumnLeft, Expanding>(),
        addWidget<DelayP2, Expanding>(),
        addWidget<ControlsColumnRight, Expanding>(),
    };

public:
    explicit DelayExpertPageWidget(LabWidget* const parent)
        : BaseWidget(parent) {}

    void setScopeZoom(DelayScopeZoom* const zoom) noexcept
    {
        static_cast<DelayP2*>(fWidgets[1].get())->setScopeZoom(zoom);
    }

    [[nodiscard]] Point<int> getMiddleAreaAbsolutePos() const noexcept
    {
        return fWidgets[1]->getAbsolutePos();
    }

    [[nodiscard]] Size<uint> getMiddleAreaSize() const noexcept
    {
        return fWidgets[1]->getSize();
    }
};

// --------------------------------------------------------------------------------------------------------------------

class DelayMainArea : public ReferenceContainerWidget<Reference::MainArea>
{
    using BaseWidget = ReferenceContainerWidget<Reference::MainArea>;
    using DelayStageWidget = StageWidget<EasyStageWidget, DelayExpertPageWidget>;

    std::shared_ptr<LabWidget> fMetersIn = addWidget<GainMeterWidget<Input>>();
    std::shared_ptr<DelayStageWidget> fStage = addWidget<DelayStageWidget, Expanding>();
    std::shared_ptr<LabWidget> fMetersOut = addWidget<GainMeterWidget<Output>>();

public:
    DelayMainArea(LabTopLevelWidget* const parent)
        : BaseWidget(parent) {}

    void setScopeZoom(DelayScopeZoom* const zoom) noexcept
    {
        fStage->getExpertWidget()->setScopeZoom(zoom);
    }

    [[nodiscard]] Point<int> getMiddleAreaAbsolutePos(const Page page) const noexcept
    {
        return page == kPageExpert ? fStage->getExpertWidget()->getMiddleAreaAbsolutePos() : fStage->getAbsolutePos();
    }

    [[nodiscard]] Size<uint> getMiddleAreaSize(const Page page) const noexcept
    {
        return page == kPageExpert ? fStage->getExpertWidget()->getMiddleAreaSize() : fStage->getSize();
    }

    [[nodiscard]] float getMiddleAreaBorderRadius(Page) const noexcept
    {
        return fStage->getBorderRadius();
    }
};

// --------------------------------------------------------------------------------------------------------------------

class DelayRootWidget final : public RootWidget<TopBar, DelayMainArea>,
                              private IdleCallback
{
    using BaseWidget = RootWidget<TopBar, DelayMainArea>;

    Page fLastPage = kPageEasy;
    ShaderBaseWidget* fShaderBackground = nullptr;
    ShaderBaseWidget* fShaderScope = nullptr;
    DelayScopeZoom fScopeZoom;

public:
    DelayRootWidget(Window& window, LabUIWidgetInterface* const iface)
        : BaseWidget(window, iface)
    {
        addIdleCallback(this);
    }

    void setup(ShaderBaseWidget* const background, ShaderBaseWidget* const scope)
    {
        fShaderBackground = background;
        fShaderScope = scope;

        // one zoom, read by the shader and by the labels drawn over it
        fMainArea->setScopeZoom(&fScopeZoom);
        fShaderScope->setCustomUniform("iSpan", [this] {
            return fScopeZoom.span(DelayScopeModel(fInterface).level, getApp().getTime());
        });

        updateSize(false);
    }

private:
    void idleCallback() final
    {
        if (const Page page = getCurrentPage(fInterface); fLastPage != page)
        {
            fLastPage = page;
            updateSize(false);
        }
    }

    void updateSize(const bool updateChildren) final
    {
        BaseWidget::updateSize(updateChildren);

        const Point<int> pos = fMainArea->getMiddleAreaAbsolutePos(fLastPage);
        const Size<uint> size = fMainArea->getMiddleAreaSize(fLastPage);
        const float borderRadius = fMainArea->getMiddleAreaBorderRadius(fLastPage);

        if (fShaderBackground != nullptr)
        {
            fShaderBackground->setAbsolutePos(pos);
            fShaderBackground->setSize(size);
            fShaderBackground->setBorderRadius(borderRadius);
        }

        // the tap scope lives in the expert page's centre well only
        if (fShaderScope != nullptr)
        {
            fShaderScope->setVisible(fLastPage == kPageExpert);
            fShaderScope->setAbsolutePos(pos);
            fShaderScope->setSize(size);
            fShaderScope->setBorderRadius(borderRadius);
        }
    }
};

} /* namespace LibreAudio */

// --------------------------------------------------------------------------------------------------------------------

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioUI : public LibreAudioBaseUI
{
    std::unique_ptr<LibreAudio::ShaderBaseWidget> fShaderBackground;
    std::unique_ptr<LibreAudio::ShaderBaseWidget> fShaderScope;

public:
    LibreAudioUI()
        : LibreAudioBaseUI()
    {
        fShaderBackground.reset(new LibreAudio::BackgroundShaderWidget<SHADERS_SHADERTOY_CLOUDSTARFIELD_FRAG_DATA,
                                                                       SHADERS_SHADERTOY_CLOUDSTARFIELD_FRAG_LEN>(this, this));

        // above the starfield, below the root widget and the labels it draws over the scope
        fShaderScope.reset(new LibreAudio::BackgroundShaderWidget<SHADERS_CURVE_DELAY_FRAG_DATA,
                                                                  SHADERS_CURVE_DELAY_FRAG_LEN>(this, this));

        createRootWidget<LibreAudio::DelayRootWidget>();
        static_cast<LibreAudio::DelayRootWidget*>(fRootWidget.get())->setup(fShaderBackground.get(),
                                                                            fShaderScope.get());
    }

private:
    DISTRHO_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(LibreAudioUI)
};

// --------------------------------------------------------------------------------------------------------------------

UI* createUI()
{
    return new LibreAudioUI();
}

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
