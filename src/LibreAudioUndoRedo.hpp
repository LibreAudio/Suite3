// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "DistrhoUtils.hpp"

#include <vector>

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

struct LibreAudioUndoRedo {
    struct Callback {
        virtual ~Callback() = default;
        virtual void undoRedoParameterChanged(uint32_t index, float value) = 0;
    };

    struct Parameter {
        uint32_t index; // used for live changes
        float value;
    };

    using Action = std::vector<Parameter>;

    struct Actions {
        std::vector<Action> data;
        uint32_t position = UINT32_MAX;
    };

    LibreAudioUndoRedo(Callback* const callback);

    bool canUndo() const noexcept;
    bool canRedo() const noexcept;
    bool isEmpty() const noexcept;

    void clear();

    inline const Actions& getActions() const noexcept
    {
        return fActions;
    }

    void push(uint32_t index, float initValue, float newValue);

    void undo();
    void redo();

    void swapActions(Actions&& actions);

private:
    Callback* const fCallback;
    Actions fActions;
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
