// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "DistrhoUtils.hpp"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioUIWidgetInterface
{
public:
    enum PageButton {
        kPageButtonAbout,
        kPageButtonEasy,
        kPageButtonExpert,
        kPageButtonSettings,
    };

    enum SnapshotButton {
        kSnapshotButtonCopy,
        kSnapshotButtonA,
        kSnapshotButtonB,
        kSnapshotButtonC,
        kSnapshotButtonD,
    };

    virtual ~LibreAudioUIWidgetInterface() = default;

    [[nodiscard]] virtual PageButton getCurrentPage() const noexcept = 0;

    [[nodiscard]] virtual uint32_t getParameterCount() const noexcept = 0;
    [[nodiscard]] virtual const char* getParameterSymbol(uint32_t index) const noexcept = 0;
    [[nodiscard]] virtual float getParameterValue(uint32_t index) const noexcept = 0;

    [[nodiscard]] virtual bool canUndo() const noexcept = 0;
    [[nodiscard]] virtual bool canRedo() const noexcept = 0;
    [[nodiscard]] virtual bool isCopyingSnapshot() const noexcept = 0;
    [[nodiscard]] virtual uint8_t getCurrentSnapshot() const noexcept = 0;

    virtual void undo() = 0;
    virtual void redo() = 0;

    virtual void parameterControlPressed(uint32_t index) = 0;
    virtual void parameterControlReleased(uint32_t index) = 0;
    virtual void parameterControlModified(uint32_t index, float value) = 0;

    virtual void pageButtonClicked(PageButton button) = 0;

    virtual void snapshotButtonClicked(SnapshotButton button) = 0;
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
