// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#include "LibreAudioBaseUI.hpp"

#include "ui/reference.hpp"
#include "ui/lab/color.hpp"
#include "ui/widgets-todo/shader.hpp"
#include "ui/widgets.hpp"

// #include "delay-parameters.hpp"

#include <array>

// --------------------------------------------------------------------------------------------------------------------

namespace LibreAudio {

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

        const std::vector<FaustParameter>& kParameters = getFaustParameters();

        std::list<std::shared_ptr<LabWidget>> fWidgets;

        struct TextReference : Reference::Zero {
            static constexpr const Color color = Reference::Colors::ink2;
            static constexpr const float fontSize = 12;
            static constexpr const float letterSpacing = fontSize * 0.01;
        };

    public:
        explicit Controls(LabWidget* const parent)
            : BaseWidget(parent) {}

        void addPillToggle(const uint32_t parameter)
        {
            std::shared_ptr<LabWidget> widget { new PillAreaWidget<1>(this, parameter) };
            Layout::widgets.push_back({ widget.get(), Fixed });
            fWidgets.emplace_back(std::move(widget));
        }

        template<uint maxNumParameters>
        void addKnobGroup(const uint32_t parameterStart)
        {
            std::shared_ptr<LabWidget> widget {
                new KnobGroupWidget<SmallKnobWidget, maxNumParameters>(this, kParameters, kParametersMainStart, parameterStart, maxNumParameters <= 2)
            };
            Layout::widgets.push_back({ widget.get(), Fixed });
            fWidgets.emplace_back(std::move(widget));
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
    };

    class ControlsColumn : public ReferenceContainerWidget<Reference::TransparentStage, kVertical>
    {
        using BaseWidget = ReferenceContainerWidget<Reference::TransparentStage, kVertical>;

    protected:
        std::shared_ptr<Controls<Reference::OpaqueStage>> fTop = addWidget<Controls<Reference::OpaqueStage>, Expanding>();
        std::shared_ptr<Controls<Reference::OpaqueSmallStage>> fBottom = addWidget<Controls<Reference::OpaqueSmallStage>>();

    public:
        explicit ControlsColumn(LabWidget* const parent)
            : BaseWidget(parent)
        {
        }

    private:
        void updateSize(const bool updateChildren) final
        {
            // FIXME
            static_cast<LabWidget*>(fBottom.get())->setHeight(120 * fScaleFactor);

            BaseWidget::updateSize(updateChildren);
        }
    };

    class ControlsColumnLeft : public ControlsColumn
    {
    public:
        explicit ControlsColumnLeft(LabWidget* const parent)
            : ControlsColumn(parent)
        {
            fTop->addPillToggle(delay::kFaustParameterMode);
            // fTop->addSpacer();
            fTop->addKnobGroup<2>(delay::kFaustParameterSync);
            // fTop->addSpacer();
            fTop->addKnobGroup<2>(delay::kFaustParameterTime_l);

            fBottom->addText("DYNAMICS");
            fBottom->addKnobGroup<2>(delay::kFaustParameterDeess_amount);
        }
    };

    class DelayP2 : public ReferenceContainerWidget<Reference::Stage, kVertical>
    {
        using BaseWidget = ReferenceContainerWidget<Reference::Stage, kVertical>;

    public:
        explicit DelayP2(LabWidget* const parent)
            : BaseWidget(parent) {}
    };

    class ControlsColumnRight : public ControlsColumn
    {
    public:
        explicit ControlsColumnRight(LabWidget* const parent)
            : ControlsColumn(parent)
        {
            fTop->addPillToggle(delay::kFaustParameterPingpong);
            // fTop->addSpacer();
            fTop->addKnobGroup<3>(delay::kFaustParameterFeedback);
            // fTop->addSpacer();
            fTop->addKnobGroup<3>(delay::kFaustParameterMod_rate);

            fBottom->addText("OUTPUT");
            fBottom->addKnobGroup<2>(delay::kFaustParameterWidth);
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

    std::shared_ptr<LabWidget> fMetersIn = addWidget<MeterWidget<Input>>();
    std::shared_ptr<DelayStageWidget> fStage = addWidget<DelayStageWidget, Expanding>();
    std::shared_ptr<LabWidget> fMetersOut = addWidget<MeterWidget<Output>>();

public:
    DelayMainArea(LabTopLevelWidget* const parent)
        : BaseWidget(parent) {}

    [[nodiscard]] Point<int> getMiddleAreaAbsolutePos(const Page page) const noexcept
    {
        return page == kPageExpert ? fStage->getExpertWidget()->getMiddleAreaAbsolutePos() : fStage->getAbsolutePos();
    }

    [[nodiscard]] Size<uint> getMiddleAreaSize(const Page page) const noexcept
    {
        return page == kPageExpert ? fStage->getExpertWidget()->getMiddleAreaSize() : fStage->getSize();
    }

    [[nodiscard]] float getMiddleAreaBorderRadius(const Page page) const noexcept
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

public:
    DelayRootWidget(Window& window, LabUIWidgetInterface* const iface)
        : BaseWidget(window, iface)
    {
        addIdleCallback(this);
    }

    void setup(ShaderBaseWidget* const shader)
    {
        fShaderBackground = shader;
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
    }
};

} /* namespace LibreAudio */

// --------------------------------------------------------------------------------------------------------------------

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioUI : public LibreAudioBaseUI
{
    std::unique_ptr<LibreAudio::ShaderBaseWidget> fShaderBackground;

public:
    LibreAudioUI()
        : LibreAudioBaseUI()
    {
        fShaderBackground.reset(new LibreAudio::BackgroundShaderWidget<SHADERS_SHADERTOY_CLOUDSTARFIELD_FRAG_DATA,
                                                                       SHADERS_SHADERTOY_CLOUDSTARFIELD_FRAG_LEN>(this, this));
        createRootWidget<LibreAudio::DelayRootWidget>();
        static_cast<LibreAudio::DelayRootWidget*>(fRootWidget.get())->setup(fShaderBackground.get());
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
