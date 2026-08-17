// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "Color.hpp"
// #include "EventHandlers.hpp"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

struct LibreAudioReference {
    struct Common {
        static constexpr const float fontSize = 19;
        static constexpr const float letterSpacing = fontSize * 0.01;
        static constexpr const uint margin = 12;
    };

    struct Colors {
        static constexpr const Color ink { 0xf6, 0xf6, 0xf8 };
        static constexpr const Color ink2 { 0xc8, 0xca, 0xd0 };
        static constexpr const Color ink3 { 0x8c, 0x8e, 0x96 };
        static constexpr const Color acc { 0xc3, 0xd9, 0xff };
        static constexpr const Color accGlow { 0xc3, 0xd9, 0xff, 0.45f };
        static constexpr const Color orange { 0xff, 0x7e, 0x1c };
        static constexpr const Color bg0 { 0x16, 0x16, 0x18 };
        static constexpr const Color bg1 { 0x1c, 0x1c, 0x20 };
        static constexpr const Color bg2 { 0x26, 0x26, 0x2b };
        static constexpr const Color track { 0x13, 0x13, 0x16 };
        static constexpr const Color line { 0x2a, 0x2a, 0x30 };
        static constexpr const Color line2 { 0x3b, 0x3b, 0x44 };

        static constexpr const Color transparent { 0.f, 0.f, 0.f, 0.f };
    };

    struct Zero {
        static constexpr const Color backgroundColor = Colors::transparent;
        static constexpr const Color borderColor = Colors::transparent;
        static constexpr const uint border = 0;
        static constexpr const uint borderRadius = 0;
        static constexpr const uint height = 0;
        static constexpr const uint padding = 0;
        static constexpr const uint margin = 0;
        static constexpr const uint width = 0;
    };

    struct Window {
        static constexpr const Color backgroundGradientStart { 0x2c, 0x2c, 0x34 };
        static constexpr const Color backgroundGradientStop { 0x2a, 0x2a, 0x2f };
        static constexpr const Color borderColor { 0, 0, 0, 0.35f };
        static constexpr const uint border = 1;
        static constexpr const uint padding = Common::margin;
        static constexpr const uint margin = Common::margin;
    };

    struct TopBar : Zero {
        static constexpr const uint height = 28;
        static constexpr const uint padding = 20;
        struct PluginName {
            static constexpr const Color color = Colors::acc;
            static constexpr const float fontSize = 22;
            static constexpr const float letterSpacing = fontSize * 0.05;
        };
    };

    struct Line {
        static constexpr const Color colorGradientStart = Colors::acc;
        static constexpr const Color colorGradientStop = Colors::accGlow;
    };

    struct MainArea : Zero {
        static constexpr const Color backgroundColor = Colors::transparent;
        static constexpr const Color borderColor = Colors::transparent;
        static constexpr const uint padding = Common::margin;
    };

    struct Meter : Zero {
        static constexpr const Color backgroundColor = Colors::track;
        static constexpr const Color borderColor { 0, 0, 0, 0.22f };
        static constexpr const uint border = 1;
        static constexpr const uint borderRadius = 7;
        static constexpr const uint margin = 3;
        static constexpr const uint width = 26;

        struct Slider {
            static constexpr const Color color = Colors::acc;
            static constexpr const Color colorGradientStart = Colors::accGlow;
            static constexpr const Color colorGradientStop { Colors::accGlow, 0.f };
            static constexpr const uint height = 3;
        };

        struct Tick {
            static constexpr const Color color { Colors::ink3, 0.15f };
            static constexpr const Color colorMaj { Colors::ink2, 0.26f };
            static constexpr const uint height = 1;
            static constexpr const uint width = 18;
        };

        struct Track {
            static constexpr const Color colorGradientStart = Colors::acc;
            static constexpr const Color colorGradientStop = Colors::accGlow;
            static constexpr const uint width = 9;
        };
    };

    struct Stage : Zero {
        static constexpr const Color backgroundColor = Colors::transparent;
        // static constexpr const Color backgroundColor = { 0x1b, 0x1c, 0x20 };
        static constexpr const uint border = 1;
        static constexpr const Color borderColor { 0, 0, 0, 0.22f };
        static constexpr const uint borderRadius = 7;
        static constexpr const uint margin = Common::margin;
        static constexpr const uint padding = Common::margin;
    };

    struct Widgets {
        struct Button : Zero {
            static constexpr const Color backgroundColor = { 0x42, 0x42, 0x5a };
            static constexpr const Color color = Colors::acc;
            static constexpr const Color color〡deactivated = Colors::ink3;
            static constexpr const float fontSize = Common::fontSize;
            static constexpr const float letterSpacing = Common::letterSpacing;
            static constexpr const uint borderRadius = 6;
            static constexpr const uint margin = 6;
        };

        struct Button〡Bypass : Button {
            static constexpr const Color backgroundColorBypass = { 0x5a, 0x35, 0x3c };
            static constexpr const Color colorBypass = { 0xff, 0x5d, 0x5d };
        };

        struct ButtonGroup : Zero {
            static constexpr const Color backgroundColor = { 0xff, 0xff, 0xff, 0.08f };
            static constexpr const Color borderColor = Colors::transparent;
            static constexpr const uint borderRadius = 6;
            static constexpr const uint padding = 1;
        };

        struct Knob : Zero {
            static constexpr const Color backgroundColor = Colors::transparent;
            static constexpr const Color borderColor = Colors::transparent;
            // static constexpr const Color color = { 0xff, 0xff, 0xff };
            static constexpr const uint height = 58 + 20;
            static constexpr const uint width = 58;
            struct Name {
                static constexpr const Color color = Colors::acc;
                static constexpr const float fontSize = 17;
                static constexpr const float letterSpacing = Common::letterSpacing;
                // text-shadow
            };
            struct Value {
                static constexpr const Color color = Colors::ink2;
                static constexpr const float fontSize = 15;
                // font-mono
            };
            struct Unit {
                static constexpr const Color color = Colors::ink3;
                static constexpr const float fontSize = 14;
                static constexpr const float letterSpacing = fontSize * 0.02;
                // font-ui
            };
        };

        struct EasyKnob : Zero {
            static constexpr const Color backgroundColor = Colors::transparent;
            static constexpr const Color borderColor = Colors::transparent;
            // static constexpr const Color color = { 0xff, 0xff, 0xff };
            static constexpr const uint height = (68 + 20) * 2;
            static constexpr const uint width = 68 * 2;
            struct Name {
                static constexpr const Color color = Colors::acc;
                static constexpr const float fontSize = 23;
                static constexpr const float letterSpacing = Common::letterSpacing;
                // text-shadow
            };
            struct Value {
                static constexpr const Color color = Colors::ink2;
                static constexpr const float fontSize = 20;
                // font-mono
            };
            struct Unit {
                static constexpr const Color color = Colors::ink3;
                static constexpr const float fontSize = 19;
                static constexpr const float letterSpacing = fontSize * 0.02;
                // font-ui
            };
        };

        struct KnobGroup : Zero {
            static constexpr const Color backgroundColor = Colors::transparent;
            static constexpr const Color borderColor = Colors::transparent;
            static constexpr const uint margin = Common::margin;
        };

        struct PillArea : Zero {
            static constexpr const Color backgroundColor = Colors::transparent;
            static constexpr const Color borderColor = Colors::transparent;
        };

        struct PillToggle : Zero {
            static constexpr const Color backgroundColor = { 0xff, 0xff, 0xff, 0.07 };
            static constexpr const Color borderColor = { 0xff, 0xff, 0xff, 0.04 };
            // static constexpr const Color deactivatedColor = Colors::ink3;
            // static constexpr const Color color = Colors::acc;
            // static constexpr const float fontSize = Common::fontSize;
            // static constexpr const float letterSpacing = Common::letterSpacing;
            static constexpr const uint border = 1;
            static constexpr const uint borderRadius = 8;
            static constexpr const uint margin = 1;
            static constexpr const uint padding = 2;
            struct Cell : Zero {
                static constexpr const Color backgroundColor = Colors::transparent;
                static constexpr const Color backgroundColor〡selected = { 0xff, 0xff, 0xff, 0.12 };
                static constexpr const Color color = Colors::ink2;
                static constexpr const Color color〡deactivated = Colors::ink3;
                static constexpr const Color color〡selected = Colors::acc;
                static constexpr const float fontSize = 17;
                static constexpr const float letterSpacing = Common::letterSpacing;
                static constexpr const uint borderRadius = 6;
                static constexpr const uint height = 26;
                static constexpr const uint margin = 9;
            };
        };
    };
};

static_assert(LibreAudioReference::Meter::width == (
        LibreAudioReference::Meter::border * 2 +
        LibreAudioReference::Meter::margin * 2 +
        // LibreAudioReference::Meter::padding +
        LibreAudioReference::Meter::Track::width * 2
    ), "incorrect meter size");

static_assert(LibreAudioReference::Meter::Tick::width == (
        LibreAudioReference::Meter::width - (LibreAudioReference::Meter::border + LibreAudioReference::Meter::margin) * 2
    ), "incorrect meter tick size");

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
