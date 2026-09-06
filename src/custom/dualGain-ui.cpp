// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#include "LibreAudioBaseUI.hpp"

#include "ui/reference.hpp"
#include "ui/lab/color.hpp"
#include "ui/widgets.hpp"
#include "ui/widgets/toggle-switch.hpp"

// --------------------------------------------------------------------------------------------------------------------

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioUI : public LibreAudioBaseUI
{
    struct ReferenceTopBar : LibreAudio::Reference::TopBar {
        static constexpr const Color backgroundColor = LibreAudio::Reference::Colors::ink3;
        static constexpr const uint height = 88;
    };

    // class TopBarSubWidget : public LibreAudio::ReferenceContainerWidget<ReferenceTopBar>
    // {
    //     using BaseWidget = LibreAudio::ReferenceContainerWidget<ReferenceTopBar>;
    //
    // public:
    //     explicit TopBarSubWidget(LibreAudio::TopLevelWidget* const parent)
    //         : BaseWidget(parent) {}
    // };

    class TopBarWidget : public ReferenceContainerWidget<ReferenceTopBar>
    {
        using BaseWidget = ReferenceContainerWidget<ReferenceTopBar>;

        static constexpr const float kColor1[] = { 0.3f, 0.1f, 0.05f, 1.f };
        static constexpr const float kColor2[] = { 0.1f, 0.3f, 0.05f, 1.f };
        std::shared_ptr<LabWidget> w1 = addWidget<LabColorWidget<kColor1>, Expanding>();
        std::shared_ptr<LabWidget> w2 = addWidget<LabColorWidget<kColor2>, Expanding>();
        std::shared_ptr<LabWidget> w3 = addWidget<LibreAudio::ToggleSwitchWidget<1>, Expanding>(kCommonParameterBypass, "Bypass");

    public:
        explicit TopBarWidget(LabTopLevelWidget* const parent)
            : BaseWidget(parent) {}
    };
    // using TopBarWidget = LibreAudio::ReferenceWidget<ReferenceTopBar>;

    struct ReferenceMainArea : LibreAudio::Reference::MainArea {
        static constexpr const Color backgroundColor = LibreAudio::Reference::Colors::bg0;
        static constexpr const Color borderColor = LibreAudio::Reference::Colors::ink;
        static constexpr const uint border = 10;
        static constexpr const uint borderRadius = 20;
    };

    // static constexpr const float kColor[] = { 0.3f, 0.1f, 0.05f, 1.f };
    using MainAreaWidget = LabReferenceWidget<ReferenceMainArea>;

public:
    LibreAudioUI()
        : LibreAudioBaseUI()
    {
        createRootWidget<TopBarWidget, MainAreaWidget>();
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
