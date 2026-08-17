// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#include "LibreAudioUndoRedo.hpp"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

LibreAudioUndoRedo::LibreAudioUndoRedo(Callback* const callback)
    : fCallback(callback)
{
}

bool LibreAudioUndoRedo::canUndo() const noexcept
{
    return !isEmpty() && fActions.position != 0;
}

bool LibreAudioUndoRedo::canRedo() const noexcept
{
    return !isEmpty() && fActions.position < fActions.data.size() - 1;
}

bool LibreAudioUndoRedo::isEmpty() const noexcept
{
    return fActions.data.empty() || fActions.position == UINT32_MAX;
}

void LibreAudioUndoRedo::clear()
{
    fActions.data.clear();
    fActions.position = UINT32_MAX;
}

void LibreAudioUndoRedo::push(const uint32_t index, const float initValue, const float newValue)
{
    if (fActions.position != UINT32_MAX)
    {
        if (const uint32_t toErase = fActions.data.size() - fActions.position - 1)
            fActions.data.erase(fActions.data.cend() - toErase, fActions.data.cend());
    }

    if (fActions.data.empty())
    {
        const Parameter param = { index, initValue };
        const std::vector<Parameter> action = { param };
        fActions.data.emplace_back(std::move(action));
    }
    else
    {
        bool backHasIndex = false;
        for (const Parameter& param : fActions.data.back())
        {
            if (param.index == index)
            {
                backHasIndex = true;
                break;
            }
        }

        if (! backHasIndex)
        {
            const Parameter param = { index, initValue };
            fActions.data.back().emplace_back(std::move(param));
        }
    }

    const Parameter param = { index, newValue };
    const std::vector<Parameter> action = { param };
    fActions.data.emplace_back(std::move(action));
    fActions.position = fActions.data.size() - 1;
}

void LibreAudioUndoRedo::undo()
{
    DISTRHO_SAFE_ASSERT_RETURN(canUndo(),);

    --fActions.position;

    for (const Parameter& param : fActions.data[fActions.position])
        fCallback->undoRedoParameterChanged(param.index, param.value);
}

void LibreAudioUndoRedo::redo()
{
    DISTRHO_SAFE_ASSERT_RETURN(canRedo(),);

    ++fActions.position;

    for (const Parameter& param : fActions.data[fActions.position])
        fCallback->undoRedoParameterChanged(param.index, param.value);
}

void LibreAudioUndoRedo::swapActions(Actions&& actions)
{
    fActions = actions;
}

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
