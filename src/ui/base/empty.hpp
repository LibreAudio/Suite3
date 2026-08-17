// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "base.hpp"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------
// empty widget, useful for making space and alignment of other widgets

struct LibreAudioEmptyReference {
    static constexpr const Color backgroundColor { 0.f, 0.f, 0.f, 0.f };
    static constexpr const Color borderColor { 0.f, 0.f, 0.f, 0.f };
    static constexpr const uint border = 0;
    static constexpr const uint borderRadius = 0;
    static constexpr const uint height = 0;
    static constexpr const uint width = 0;
};

template<class R = LibreAudioEmptyReference>
class LibreAudioEmptyWidget final : public LibreAudioReferenceWidget<R>
{
public:
    explicit LibreAudioEmptyWidget(LibreAudioWidget* const parent)
        : LibreAudioReferenceWidget<R>(parent) {}

    explicit LibreAudioEmptyWidget(LibreAudioTopLevelWidget* const parent)
        : LibreAudioReferenceWidget<R>(parent) {}
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
