// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../lab/toggle-switch.hpp"
#include "../reference.hpp"

#include "FaustParameters.hpp"

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------

template <uint8_t accent>
class ToggleSwitchWidget : public ReferenceToggleSwitchWidget<Reference::Widgets::ToggleSwitch<accent>>
{
    using BaseWidget = ReferenceToggleSwitchWidget<Reference::Widgets::ToggleSwitch<accent>>;

public:
    explicit ToggleSwitchWidget(LabWidget* const parent, const uint id, const char* const name)
        : BaseWidget(parent, id, name) {}

    explicit ToggleSwitchWidget(LabWidget* const parent, const uint id, const FaustParameter& parameter)
        : BaseWidget(parent, id, parameter.name)
    {
        BaseWidget::setChecked(d_isNotZero(parameter.init), false);
    }
};

// --------------------------------------------------------------------------------------------------------------------

} /* namespace LibreAudio */
