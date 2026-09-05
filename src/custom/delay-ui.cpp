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

    const std::vector<FaustParameter>& kParameters = getFaustParameters();

    class DelayP1 : public ReferenceContainerWidget<Reference::OpaqueStage, kVertical>
    {
        using BaseWidget = ReferenceContainerWidget<Reference::OpaqueStage, kVertical>;

    public:
        explicit DelayP1(LabWidget* const parent)
            : BaseWidget(parent) {}
    };

    class DelayP2 : public ReferenceContainerWidget<Reference::Stage, kVertical>
    {
        using BaseWidget = ReferenceContainerWidget<Reference::Stage, kVertical>;

    public:
        explicit DelayP2(LabWidget* const parent)
            : BaseWidget(parent) {}
    };

    class DelayP3 : public ReferenceContainerWidget<Reference::OpaqueStage, kVertical>
    {
        using BaseWidget = ReferenceContainerWidget<Reference::OpaqueStage, kVertical>;

        using KnobGroupWidget3 = KnobGroupWidget<SmallKnobWidget, 3>;

        const std::vector<FaustParameter>& kParameters = getFaustParameters();

        std::shared_ptr<PillToggleWidget> fPillToggle;
        std::list<std::shared_ptr<LabWidget>> fSpacers;
        std::list<std::shared_ptr<KnobGroupWidget3>> fKnobGroups;

    public:
        explicit DelayP3(LabWidget* const parent)
            : BaseWidget(parent)
        {
            {
                fPillToggle.reset(new PillToggleWidget(this, kParameters[delay::kFaustParameterPingpong], delay::kFaustParameterPingpong));
                widgets.push_back({ fPillToggle.get(), Fixed });
            }

            addSpacer();

            {
                std::shared_ptr<KnobGroupWidget3> widget { new KnobGroupWidget3(this, kParameters, kParametersMainStart, delay::kFaustParameterFeedback) };
                widgets.push_back({ widget.get(), Fixed });
                fKnobGroups.emplace_back(std::move(widget));
            }

            addSpacer();

            {
                std::shared_ptr<KnobGroupWidget3> widget { new KnobGroupWidget3(this, kParameters, kParametersMainStart, delay::kFaustParameterMod_rate) };
                widgets.push_back({ widget.get(), Fixed });
                fKnobGroups.emplace_back(std::move(widget));
            }

            addSpacer();
        }

        void addSpacer()
        {
            std::shared_ptr<LabWidget> spacer { new LabEmptyWidget(this) };
            widgets.push_back({ spacer.get(), Expanding });
            fSpacers.emplace_back(std::move(spacer));
        }
    };

    std::array<std::shared_ptr<LabWidget>, 3> fWidgets {
        addWidget<DelayP1, Expanding>(),
        addWidget<DelayP2, Expanding>(),
        addWidget<DelayP3, Expanding>(),
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
        fShaderBackground.reset(new LibreAudio::BackgroundShaderWidget<SHADERS_SHADERTOY_CLOUDSTARFIELD_FRAG_DATA, SHADERS_SHADERTOY_CLOUDSTARFIELD_FRAG_LEN>(this, this));
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
