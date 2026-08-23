// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "DistrhoUI.hpp"
#include "FaustParameters.hpp"
#include "LibreAudioSnapshots.hpp"

#include "ui/reference.hpp"
#include "ui/widgets/root.hpp"
#include "ui/widgets-todo/base.hpp"

// --------------------------------------------------------------------------------------------------------------------

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioBaseUI : public UI,
                         private LibreAudioSnapshots::Callback
{
    using R = LibreAudioReference::Window;

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

    // ----------------------------------------------------------------------------------------------------------------
    // protected data

protected:
    std::shared_ptr<LibreAudioRootBaseWidget> fRootWidget;

    template <class RootWidget>
    void createRootWidget()
    {
        fRootWidget.reset(new RootWidget(getWindow(), this));
        updateScaleFactorAndSize();
    }

    template <class TopBar, class MainArea>
    void createRootWidget()
    {
        fRootWidget.reset(new LibreAudioRootWidget<TopBar, MainArea>(getWindow(), this));
        updateScaleFactorAndSize();
    }

    void uiIdle() override;

private:
    // ----------------------------------------------------------------------------------------------------------------
    // private data

    const uint32_t kParameterCount;

    float* const fParameterValues;
    float* const fParameterValuesWhenActivated;

    Page fPage = kPageEasy;
    Page fLastEasyExpertPage = kPageEasy;

    LibreAudioSnapshots fSnapshots;
    bool fCopyingSnapshot = false;

    float fScaleFactor = 1.f;

    void pageButtonClicked(Page page);
    void snapshotButtonClicked(uint32_t button);
    void updateScaleFactorAndSize();

    // ----------------------------------------------------------------------------------------------------------------
    // DSP/Plugin Callbacks

   /**
      A parameter has changed on the plugin side.@n
      This is called by the host to inform the UI about parameter changes.
    */
    void parameterChanged(uint32_t index, float value) final;

    void stateChanged(const char* key, const char* value) final;

    // ----------------------------------------------------------------------------------------------------------------
    // Widget Callbacks

    void onNanoDisplay() final;

    // ----------------------------------------------------------------------------------------------------------------
    // UI Widget Interface

    [[nodiscard]] uint32_t getParameterCount() const noexcept final { return kParameterCount; }
    [[nodiscard]] const char* getParameterSymbol(uint32_t index) const noexcept final;
    [[nodiscard]] float getParameterValue(uint32_t index) const noexcept final { return fParameterValues[index]; }

    void parameterControlPressed(uint32_t index) final;
    void parameterControlReleased(uint32_t index) final;
    void parameterControlModified(uint32_t index, float value) final;

    void buttonClicked(uint32_t id) final;
    [[nodiscard]] bool isButtonEnabled(uint32_t id) const noexcept final;
    [[nodiscard]] bool isButtonChecked(uint32_t id) const noexcept final;

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
