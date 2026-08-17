// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "LibreAudioUndoRedo.hpp"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

struct LibreAudioSnapshots : private LibreAudioUndoRedo::Callback {
    struct Callback {
        virtual ~Callback() = default;
        virtual void snapshotDataToSave(uint32_t snapshot,
                                        const float* parameterValues,
                                        const LibreAudioUndoRedo::Actions& undoRedoActions) = 0;
        virtual void snapshotParameterChanged(uint32_t parameterIndex, float parameterValue) = 0;
        virtual void snapshotParametersChanged(const float* parameterValues) = 0;
    };

    LibreAudioSnapshots(uint32_t snapshotCount,
                        uint32_t parameterCount,
                        const float* parameterValues,
                        Callback* callback);
    ~LibreAudioSnapshots();

    bool canUndo() const noexcept;
    bool canRedo() const noexcept;

    void undo();
    void redo();

    inline uint32_t getCurrent() const noexcept
    {
        return fCurrent;
    }

    inline uint32_t getPrevious() const noexcept
    {
        return fPrevious;
    }

    void idle();

    void copyTo(uint32_t snapshot);
    void load(uint32_t snapshot);

    void restoreCurrentAndPrevious(uint32_t snapshot);
    void restoreSnapshotData(uint32_t snapshot,
                             const float* parameterValues,
                             LibreAudioUndoRedo::Actions&& undoRedoActions);

    void updateParameterValue(uint32_t parameterIndex, float parameterValue, float parameterValueOnDragStart) noexcept;

private:
    Callback* const fCallback;
    const uint32_t fParameterCount;
    const uint32_t fSnapshotCount;
    uint32_t fCurrent = 0;
    uint32_t fPrevious = fCurrent;
    float** const fParameterValues;
    LibreAudioUndoRedo** const fUndoRedos;
    bool* const fUpdated;

    void triggerSave(uint32_t snapshot);
    void undoRedoParameterChanged(uint32_t index, float value) final;
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
