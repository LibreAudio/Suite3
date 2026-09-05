// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../lab/interface.hpp"

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------

enum Page : uint8_t {
    kPageAbout,
    kPageEasy,
    kPageExpert,
    kPageSettings,
};

enum WidgetIds : uint16_t {
    kWidgetAbout = 1000,
    kWidgetEasy,
    kWidgetExpert,
    kWidgetMenu,
    kWidgetPower,
    kWidgetRedo,
    kWidgetSnapshotCopy,
    kWidgetSnapshotSlotA,
    kWidgetSnapshotSlotB,
    kWidgetSnapshotSlotC,
    kWidgetSnapshotSlotD,
    kWidgetUndo,
};

constexpr const char* WidgetIds2Str(const WidgetIds id) noexcept
{
    switch (id)
    {
    case kWidgetAbout:
        return "about";
    case kWidgetEasy:
        return "easy";
    case kWidgetExpert:
        return "expert";
    case kWidgetMenu:
        return "menu";
    case kWidgetPower:
        return "power";
    case kWidgetRedo:
        return "redo";
    case kWidgetSnapshotCopy:
        return "snapshot-copy";
    case kWidgetSnapshotSlotA:
        return "snapshot-slot-a";
    case kWidgetSnapshotSlotB:
        return "snapshot-slot-b";
    case kWidgetSnapshotSlotC:
        return "snapshot-slot-c";
    case kWidgetSnapshotSlotD:
        return "snapshot-slot-d";
    case kWidgetUndo:
        return "undo";
    }

    return "";
}

inline Page getCurrentPage(LabUIWidgetInterface* const iface) noexcept
{
    if (iface->isButtonEnabled(kWidgetEasy) && iface->isButtonChecked(kWidgetEasy))
        return kPageEasy;
    if (iface->isButtonEnabled(kWidgetExpert) && iface->isButtonChecked(kWidgetExpert))
        return kPageExpert;
    if (iface->isButtonEnabled(kWidgetMenu) && iface->isButtonChecked(kWidgetMenu))
        return kPageSettings;
    if (iface->isButtonEnabled(kWidgetAbout) && iface->isButtonChecked(kWidgetAbout))
        return kPageAbout;

    // fallback
    return kPageEasy;
}

// --------------------------------------------------------------------------------------------------------------------

} /* namespace LibreAudio */
