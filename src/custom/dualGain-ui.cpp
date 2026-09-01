// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#include "LibreAudioBaseUI.hpp"

#include "ui/reference.hpp"
#include "ui/reference/color.hpp"
#include "ui/widgets.hpp"

// --------------------------------------------------------------------------------------------------------------------

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioUI : public LibreAudioBaseUI
{
    struct ReferenceTopBar : LibreAudio::Reference::TopBar {
        static constexpr const Color backgroundColor = LibreAudio::Reference::Colors::ink3;
    };

    // class TopBarSubWidget : public LibreAudio::ReferenceContainerWidget<ReferenceTopBar>
    // {
    //     using BaseWidget = LibreAudio::ReferenceContainerWidget<ReferenceTopBar>;
    //
    // public:
    //     explicit TopBarSubWidget(LibreAudio::TopLevelWidget* const parent)
    //         : BaseWidget(parent) {}
    // };

    class TopBarWidget : public LibreAudio::ReferenceContainerWidget<ReferenceTopBar>
    {
        using BaseWidget = LibreAudio::ReferenceContainerWidget<ReferenceTopBar>;

        static constexpr const float kColor1[] = { 0.3f, 0.1f, 0.05f, 1.f };
        static constexpr const float kColor2[] = { 0.1f, 0.3f, 0.05f, 1.f };
        std::shared_ptr<LibreAudio::Widget> w1 = addWidget<LibreAudio::ColorWidget<kColor1>, Expanding>();
        std::shared_ptr<LibreAudio::Widget> w2 = addWidget<LibreAudio::ColorWidget<kColor2>, Expanding>();

    public:
        explicit TopBarWidget(LibreAudio::TopLevelWidget* const parent)
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
    using MainAreaWidget = LibreAudio::ReferenceWidget<ReferenceMainArea>;

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
