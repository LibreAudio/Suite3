// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "DistrhoUI.hpp"
#include "FaustParameters.hpp"
#include "LibreAudioSnapshots.hpp"

// --------------------------------------------------------------------------------------------------------------------

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioBaseUI : public UI,
                         private LibreAudioSnapshots::Callback
{
public:
    LibreAudioBaseUI();
    ~LibreAudioBaseUI() override;

    // ----------------------------------------------------------------------------------------------------------------
    // static metadata

    static const std::vector<FaustParameter>& kFaustParameters;
    static const std::vector<FaustParameter>& kFaustParametersIn;
    static const std::vector<FaustParameter>& kFaustParametersOut;
    static const std::vector<const char*>& kParameterSymbols;

    static bool isParameterOutputOrTrigger(uint32_t index);

protected:
    // ----------------------------------------------------------------------------------------------------------------
    // UI Widget Interface

    [[nodiscard]] PageButton getCurrentPage() const noexcept final { return fPage; }

    [[nodiscard]] uint32_t getParameterCount() const noexcept final { return kParameterCount; }
    [[nodiscard]] const char* getParameterSymbol(uint32_t index) const noexcept final;
    [[nodiscard]] float getParameterValue(uint32_t index) const noexcept final { return fParameterValues[index]; }

    [[nodiscard]] bool canUndo() const noexcept final { return fSnapshots.canUndo(); }
    [[nodiscard]] bool canRedo() const noexcept final { return fSnapshots.canRedo(); }
    [[nodiscard]] bool isCopyingSnapshot() const noexcept final { return fCopyingSnapshot; }
    [[nodiscard]] uint8_t getCurrentSnapshot() const noexcept final { return fSnapshots.getCurrent(); }

    void undo() final { fSnapshots.undo(); }
    void redo() final { fSnapshots.redo(); }

    void parameterControlPressed(uint32_t index) final;
    void parameterControlReleased(uint32_t index) final;
    void parameterControlModified(uint32_t index, float value) final;

    void pageButtonClicked(PageButton button) final;
    void snapshotButtonClicked(SnapshotButton button) final;

    // ----------------------------------------------------------------------------------------------------------------
    // Widget Callbacks

    void uiIdle() override;

private:
    // ----------------------------------------------------------------------------------------------------------------
    // private data

    const uint32_t kParameterCount;

    float* const fParameterValues;
    float* const fParameterValuesWhenActivated;

    PageButton fPage = kPageButtonEasy;
    PageButton fLastEasyExpertPage = kPageButtonEasy;

    LibreAudioSnapshots fSnapshots;
    bool fCopyingSnapshot = false;

    // ----------------------------------------------------------------------------------------------------------------
    // DSP/Plugin Callbacks

   /**
      A parameter has changed on the plugin side.@n
      This is called by the host to inform the UI about parameter changes.
    */
    void parameterChanged(uint32_t index, float value) final;

    void stateChanged(const char* key, const char* value) final;

    // ----------------------------------------------------------------------------------------------------------------
    // Other Callbacks

    void snapshotDataToSave(uint32_t snapshot,
                            const float* parameterValues,
                            const LibreAudioUndoRedo::Actions& undoRedoActions) final;
    void snapshotParameterChanged(uint32_t parameterIndex, float parameterValue) final;
    void snapshotParametersChanged(const float* parameterValues) final;

    DISTRHO_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(LibreAudioBaseUI)
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
