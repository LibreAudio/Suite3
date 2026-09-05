// lab: Libre Audio Base-Widgets
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: ISC

#pragma once

#include "DistrhoUtils.hpp"

START_NAMESPACE_DGL

// --------------------------------------------------------------------------------------------------------------------

class LabUIWidgetInterface
{
public:
    virtual ~LabUIWidgetInterface() = default;

    [[nodiscard]] virtual uint32_t getParameterCount() const noexcept = 0;
    [[nodiscard]] virtual const char* getParameterSymbol(uint32_t index) const noexcept = 0;
    [[nodiscard]] virtual float getParameterValue(uint32_t index) const noexcept = 0;

    virtual void parameterControlPressed(uint32_t index) = 0;
    virtual void parameterControlReleased(uint32_t index) = 0;
    virtual void parameterControlModified(uint32_t index, float value) = 0;

    virtual void buttonClicked(uint32_t id) = 0;
    [[nodiscard]] virtual bool isButtonEnabled(uint32_t id) const noexcept = 0;
    [[nodiscard]] virtual bool isButtonChecked(uint32_t id) const noexcept = 0;

    [[nodiscard]] virtual float getScaleFactor() const noexcept = 0;
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DGL
