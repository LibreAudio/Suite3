// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../_lab/base.hpp"

#include "../reference.hpp"

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------

class ComboBoxWidget final : public LabReferenceWidget<Reference::Zero>
{
    using R = Reference::Zero;
    using BaseWidget = LabReferenceWidget<R>;

public:
    ComboBoxWidget(LabWidget* const parent)
        : BaseWidget(parent) {}
};

// --------------------------------------------------------------------------------------------------------------------

} /* namespace LibreAudio */
