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
    struct ReferenceTopBar : LibreAudioReference::TopBar {
        static constexpr const Color backgroundColor = LibreAudioReference::Colors::ink3;
    };
    using TopBarWidget = LibreAudioReferenceWidget<ReferenceTopBar>;

    struct ReferenceMainArea : LibreAudioReference::MainArea {
        static constexpr const Color backgroundColor = LibreAudioReference::Colors::bg0;
        static constexpr const Color borderColor = LibreAudioReference::Colors::ink;
        static constexpr const uint border = 10;
        static constexpr const uint borderRadius = 20;
    };

    // static constexpr const float kColor[] = { 0.3f, 0.1f, 0.05f, 1.f };
    using MainAreaWidget = LibreAudioReferenceWidget<ReferenceMainArea>;

public:
    LibreAudioUI()
        : LibreAudioBaseUI()
    {
        createRootWidget<LibreAudioTopBar, MainAreaWidget>();
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
