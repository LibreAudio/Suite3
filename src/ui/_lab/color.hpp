// lab: Libre Audio Base-Widgets
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: ISC

#pragma once

#include "base.hpp"

START_NAMESPACE_DGL

// --------------------------------------------------------------------------------------------------------------------

template<const float rgba[4]>
class LabColorWidget final : public LabWidget
{
    static constexpr const Color kColor = { rgba[0], rgba[1], rgba[2], rgba[3] };

public:
    explicit LabColorWidget(LabWidget* const parent)
        : LabWidget(parent) {}

    explicit LabColorWidget(LabTopLevelWidget* const parent)
        : LabWidget(parent) {}

protected:
    void onNanoDisplay() final
    {
        beginPath();
        rect(0, 0, getWidth(), getHeight());
        fillColor(kColor);
        fill();
    }
};


// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DGL
