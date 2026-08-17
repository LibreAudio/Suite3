// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#include "LibreAudioSnapshots.hpp"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

LibreAudioSnapshots::LibreAudioSnapshots(const uint32_t snapshotCount,
                                         const uint32_t parameterCount,
                                         const float* const parameterValues,
                                         Callback* const callback)
    : fCallback(callback),
      fParameterCount(parameterCount),
      fSnapshotCount(snapshotCount),
      fCurrent(0),
      fParameterValues(new float*[snapshotCount]),
      fUndoRedos(new LibreAudioUndoRedo*[snapshotCount]),
      fUpdated(new bool[snapshotCount])
{
    for (uint32_t i = 0; i < snapshotCount; ++i)
    {
        fParameterValues[i] = new float[parameterCount];
        std::memcpy(fParameterValues[i], parameterValues, sizeof(float) * parameterCount);
        fUndoRedos[i] = new LibreAudioUndoRedo(this);
        fUpdated[i] = false;
    }
}

LibreAudioSnapshots::~LibreAudioSnapshots()
{
    for (uint32_t i = 0; i < fSnapshotCount; ++i)
    {
        delete[] fParameterValues[i];
        delete fUndoRedos[i];
    }
    delete[] fParameterValues;
    delete[] fUndoRedos;
    delete[] fUpdated;
}

bool LibreAudioSnapshots::canUndo() const noexcept
{
    return fUndoRedos[fCurrent]->canUndo();
}

bool LibreAudioSnapshots::canRedo() const noexcept
{
    return fUndoRedos[fCurrent]->canRedo();
}

void LibreAudioSnapshots::undo()
{
    fUndoRedos[fCurrent]->undo();
}

void LibreAudioSnapshots::redo()
{
    fUndoRedos[fCurrent]->redo();
}

void LibreAudioSnapshots::idle()
{
    for (uint32_t i = 0; i < fSnapshotCount; ++i)
    {
        if (fUpdated[i])
            triggerSave(i);
    }
}

void LibreAudioSnapshots::copyTo(const uint32_t snapshot)
{
    DISTRHO_SAFE_ASSERT_RETURN(fCurrent != snapshot,);

    std::memcpy(fParameterValues[snapshot], fParameterValues[fCurrent], sizeof(float) * fParameterCount);

    // set new snapshot (index)
    fPrevious = fCurrent;
    fCurrent = snapshot;

    // set state of previous and current snapshot (values)
    triggerSave(fPrevious);
    triggerSave(fCurrent);
}

void LibreAudioSnapshots::load(const uint32_t snapshot)
{
    DISTRHO_SAFE_ASSERT_RETURN(fCurrent != snapshot,);

    fPrevious = fCurrent;
    fCurrent = snapshot;
    fCallback->snapshotParametersChanged(fParameterValues[snapshot]);
}

void LibreAudioSnapshots::restoreCurrentAndPrevious(const uint32_t snapshot)
{
    fCurrent = fPrevious = snapshot;
}

void LibreAudioSnapshots::restoreSnapshotData(const uint32_t snapshot,
                                              const float* const parameterValues,
                                              LibreAudioUndoRedo::Actions&& undoRedoActions)
{
    std::memcpy(fParameterValues[snapshot], parameterValues, sizeof(float) * fParameterCount);

    fUndoRedos[snapshot]->swapActions(std::move(undoRedoActions));
}

void LibreAudioSnapshots::updateParameterValue(const uint32_t parameterIndex,
                                               const float parameterValue,
                                               const float parameterValueOnDragStart) noexcept
{
    DISTRHO_SAFE_ASSERT_RETURN(parameterIndex < fParameterCount,);

    if (d_isNotEqual(parameterValueOnDragStart, parameterValue))
        fUndoRedos[fCurrent]->push(parameterIndex, parameterValueOnDragStart, parameterValue);

    if (d_isNotEqual(fParameterValues[fCurrent][parameterIndex], parameterValue))
    {
        fParameterValues[fCurrent][parameterIndex] = parameterValue;
        fUpdated[fCurrent] = true;
    }
}

void LibreAudioSnapshots::triggerSave(const uint32_t snapshot)
{
    fUpdated[snapshot] = false;
    fCallback->snapshotDataToSave(snapshot, fParameterValues[snapshot], fUndoRedos[fCurrent]->getActions());
}

void LibreAudioSnapshots::undoRedoParameterChanged(const uint32_t index, const float value)
{
    if (d_isNotEqual(fParameterValues[fCurrent][index], value))
    {
        fParameterValues[fCurrent][index] = value;
        fUpdated[fCurrent] = true;
    }

    fCallback->snapshotParameterChanged(index, value);
}

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
