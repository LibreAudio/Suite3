// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#include "LibreAudioBaseUI.hpp"
#include "LibreAudioParameters.hpp"
#include "LibreAudioStates.hpp"

#include "common_input-parameters.hpp"
#include "common_output-parameters.hpp"

#include "nlohmann/json.hpp"

#if defined(__GNUC__) && !defined(__clang__)
#define constexprstr constexpr
#else
#define constexprstr
#endif

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

static float* createParameterValues(const uint32_t paramCount)
{
    const std::vector<FaustParameter>& kFaustParameters = getFaustParameters();
    const std::vector<FaustParameter>& kFaustParametersIn = common_input::getFaustParameters();
    const std::vector<FaustParameter>& kFaustParametersOut = common_output::getFaustParameters();

    float* const values = new float[paramCount];

    initCommonParameterValuesToDefault(values);

    for (uint32_t i = 0; i < common_input::kFaustParameterCount; ++i)
        values[kParametersInputStart + i] = kFaustParametersIn[i].init;

    for (uint32_t i = kCommonIOParameters; i < common_output::kFaustParameterCount; ++i)
        values[kParametersOutputStart + i - kCommonIOParameters] = kFaustParametersOut[i].init;

    for (uint32_t i = 0, size = kFaustParameters.size(); i < size; ++i)
        values[kParametersMainStart + i] = kFaustParameters[i].init;

    return values;
}

// --------------------------------------------------------------------------------------------------------------------

LibreAudioBaseUI::LibreAudioBaseUI()
    : UI(),
      kParameterCount(kParametersMainStart  + kFaustParameters.size()),
      fParameterValues(createParameterValues(kParameterCount)),
      fParameterValuesWhenActivated(new float[kParameterCount]),
      fSnapshots(kNumSnapshots, kParameterCount, fParameterValues, this)
{
    std::memcpy(fParameterValuesWhenActivated, fParameterValues, sizeof(float) * kParameterCount);

    // set minimum size
    const double scaleFactor = getScaleFactor();
    setGeometryConstraints(DISTRHO_UI_DEFAULT_WIDTH * scaleFactor, DISTRHO_UI_DEFAULT_HEIGHT * scaleFactor);
}

LibreAudioBaseUI::~LibreAudioBaseUI()
{
    delete[] fParameterValues;
    delete[] fParameterValuesWhenActivated;
}

// --------------------------------------------------------------------------------------------------------------------
// static metadata

static std::vector<const char*> createParameterSymbols()
{
    static std::vector<const char*> symbols;
    symbols.reserve(kParametersMainStart + getFaustParameters().size());

    const std::vector<FaustParameter>& kFaustParameters = getFaustParameters();
    const std::vector<FaustParameter>& kFaustParametersIn = common_input::getFaustParameters();
    const std::vector<FaustParameter>& kFaustParametersOut = common_output::getFaustParameters();

    for (uint32_t i = 0; i < kCommonParameterCount; ++i)
    {
        switch (static_cast<CommonParameters>(i))
        {
        case kCommonParameterBypass:
        case kCommonParameterReset:
            symbols.push_back(nullptr);
            break;
       #if LIBREAUDIO_WANT_DRYWET
        case kCommonParameterDryWet:
            symbols.push_back("dry_wet");
            break;
       #endif
        case kCommonParameterCount:
            break;
        }
    }

    for (uint32_t i = 0; i < common_input::kFaustParameterCount; ++i)
        symbols.push_back(kFaustParametersIn[i].symbol);

    for (uint32_t i = kCommonIOParameters; i < common_output::kFaustParameterCount; ++i)
        symbols.push_back(kFaustParametersOut[i].symbol);

    for (uint32_t i = 0, size = kFaustParameters.size(); i < size; ++i)
        symbols.push_back(kFaustParameters[i].symbol);

    return symbols;
}

// TODO convert common IO to C++
const std::vector<FaustParameter>& LibreAudioBaseUI::kFaustParameters = getFaustParameters();
const std::vector<FaustParameter>& LibreAudioBaseUI::kFaustParametersIn = common_input::getFaustParameters();
const std::vector<FaustParameter>& LibreAudioBaseUI::kFaustParametersOut = common_output::getFaustParameters();
const std::vector<const char*>& LibreAudioBaseUI::kParameterSymbols = createParameterSymbols();

bool LibreAudioBaseUI::isParameterOutputOrTrigger(const uint32_t i)
{
    return
        i >= kParametersMainStart ? isFaustParameterOutputOrTrigger(kFaustParameters[i - kParametersMainStart]) :
        i >= kParametersOutputStart ? isFaustParameterOutputOrTrigger(kFaustParametersOut[i - kParametersOutputStart + kCommonIOParameters]) :
        i >= kParametersInputStart ? isFaustParameterOutputOrTrigger(kFaustParametersIn[i - kParametersInputStart]) :
        false;
}

const char* LibreAudioBaseUI::getParameterSymbol(const uint32_t index) const noexcept
{
    return
        index >= kParametersMainStart ? kFaustParameters[index - kParametersMainStart].symbol :
        index >= kParametersOutputStart ? kFaustParametersOut[index - kParametersOutputStart + kCommonIOParameters].symbol :
        index >= kParametersInputStart ? kFaustParametersIn[index - kParametersInputStart].symbol :
        nullptr;

}

// --------------------------------------------------------------------------------------------------------------------
// DSP/Plugin Callbacks

void LibreAudioBaseUI::parameterChanged(const uint32_t index, const float value)
{
    fParameterValues[index] = value;

    switch (index)
    {
    case kCommonParameterBypass:
    case kCommonParameterReset:
        return;
    default:
        if (! isParameterOutputOrTrigger(index))
            fSnapshots.updateParameterValue(index, value, value);
        break;
    }
}

void LibreAudioBaseUI::stateChanged(const char* const key, const char* const value)
{
    if (std::strcmp(key, kStateKeys[kStateCurrentSnapshot]) == 0)
    {
        DISTRHO_SAFE_ASSERT_RETURN(value[0] != '\0',);
        DISTRHO_SAFE_ASSERT_RETURN(value[1] == '\0',);

        const uint8_t snapshot = value[0] - 'A';
        DISTRHO_SAFE_ASSERT_INT_RETURN(snapshot < kNumSnapshots, snapshot,);

        fSnapshots.restoreCurrentAndPrevious(snapshot);
        return;
    }

    constexprstr const size_t LIBREAUDIO_STATE_KEY_SNAPSHOT_VALUES_PREFIX_len =
        std::strlen(LIBREAUDIO_STATE_KEY_SNAPSHOT_VALUES_PREFIX);

    if (std::strncmp(key,
                     LIBREAUDIO_STATE_KEY_SNAPSHOT_VALUES_PREFIX,
                     LIBREAUDIO_STATE_KEY_SNAPSHOT_VALUES_PREFIX_len) == 0)
    {
        const char* const snapshotKey = key + LIBREAUDIO_STATE_KEY_SNAPSHOT_VALUES_PREFIX_len;
        DISTRHO_SAFE_ASSERT_RETURN(snapshotKey[0] != '\0',);
        DISTRHO_SAFE_ASSERT_RETURN(snapshotKey[1] == '\0',);

        const uint8_t snapshot = snapshotKey[0] -'a';
        DISTRHO_SAFE_ASSERT_INT_RETURN(snapshot < kNumSnapshots, snapshot,);

        // d_stdout("loading snapshot %u | %s", snapshot, value);

        float* const parameterValues = new float[kParameterCount];
        std::memcpy(parameterValues, fParameterValues, sizeof(float) * kParameterCount);

        nlohmann::json j;

        try {
            j = nlohmann::json::parse(value);
        } DISTRHO_SAFE_EXCEPTION("failed to unserialize snapshot");

        try {
            const nlohmann::json& jparameters = j.at("parameters");

           #if LIBREAUDIO_WANT_DRYWET
            try {
                parameterValues[kCommonParameterDryWet] = jparameters.at("dry_wet").get<float>();
            } catch(...) {
                parameterValues[kCommonParameterDryWet] = fParameterValues[kCommonParameterDryWet];
            }
           #endif

            for (uint32_t i = 0; i < common_input::kFaustParameterCount; ++i)
            {
                const FaustParameter& param = kFaustParametersIn[i];

                if (isFaustParameterOutputOrTrigger(param))
                    continue;

                try {
                    parameterValues[kParametersInputStart + i] = jparameters.at(param.symbol).get<float>();
                } catch(...) {
                    parameterValues[kParametersInputStart + i] = fParameterValues[kParametersInputStart + i];
                }
            }

            for (uint32_t i = kCommonIOParameters; i < common_output::kFaustParameterCount; ++i)
            {
                const FaustParameter& param = kFaustParametersOut[i];

                if (isFaustParameterOutputOrTrigger(param))
                    continue;

                try {
                    parameterValues[kParametersOutputStart + i - kCommonIOParameters] = jparameters.at(param.symbol).get<float>();
                } catch(...) {
                    parameterValues[kParametersOutputStart + i - kCommonIOParameters] = fParameterValues[kParametersOutputStart + i - kCommonIOParameters];
                }
            }

            for (uint32_t i = 0, size = kFaustParameters.size(); i < size; ++i)
            {
                const FaustParameter& param = kFaustParameters[i];

                if (isFaustParameterOutputOrTrigger(param))
                    continue;

                try {
                    parameterValues[kParametersMainStart + i] = jparameters.at(param.symbol).get<float>();
                } catch(...) {
                    parameterValues[kParametersMainStart + i] = fParameterValues[kParametersMainStart + i];
                }
            }
        } DISTRHO_SAFE_EXCEPTION("failed to unserialize snapshot parameters");

        LibreAudioUndoRedo::Actions actions;
        try {
            const nlohmann::json& jundoredo = j.at("undo/redo");

            const nlohmann::json& jactions = jundoredo.at("actions");

            const auto findSymbol = [](const std::string& symbol){
                for (uint32_t i = 0, size = kParameterSymbols.size(); i < size; ++i)
                    if (kParameterSymbols[i] != nullptr && symbol == kParameterSymbols[i])
                        return i;
                d_stderr2("invalid symbol %s", symbol.c_str());
                return UINT32_MAX;
            };

            for (const auto& jaction : jactions)
            {
                LibreAudioUndoRedo::Action action;
                for (const auto& jparameter : jaction)
                {
                    if (jparameter.contains("symbol") && jparameter.contains("value"))
                    {
                        const uint32_t index = findSymbol(jparameter.at("symbol").get<std::string>());

                        if (index != UINT32_MAX)
                            action.push_back({
                                index,
                                static_cast<float>(jparameter.at("value").get<double>()),
                            });
                    }
                }

                actions.data.push_back(action);
            }

            actions.position = jundoredo.at("position").get<int>();
        } catch(...) {
            d_stderr2("exception when restoring actions");
            actions = {};
        }

        fSnapshots.restoreSnapshotData(snapshot, parameterValues, std::move(actions));

        delete[] parameterValues;
        return;
    }
}

// --------------------------------------------------------------------------------------------------------------------
// Widget Callbacks

void LibreAudioBaseUI::parameterControlPressed(const uint32_t index)
{
    switch (index)
    {
    case kCommonParameterReset:
        return;
    case kCommonParameterBypass:
        break;
    default:
        fParameterValuesWhenActivated[index] = fParameterValues[index];
        break;
    }

    editParameter(index, true);
}

void LibreAudioBaseUI::parameterControlReleased(const uint32_t index)
{
    switch (index)
    {
    case kCommonParameterReset:
        return;
    case kCommonParameterBypass:
        break;
    default:
        fSnapshots.updateParameterValue(index, fParameterValues[index], fParameterValuesWhenActivated[index]);
        break;
    }

    editParameter(index, false);
}

void LibreAudioBaseUI::parameterControlModified(const uint32_t index, const float value)
{
    fParameterValues[index] = value;
    setParameterValue(index, value);
}

void LibreAudioBaseUI::pageButtonClicked(const PageButton button)
{
    if (fPage == button)
    {
        if (button == kPageButtonSettings)
            fPage = fLastEasyExpertPage;
        return;
    }

    fPage = button;

    switch (button)
    {
    case kPageButtonEasy:
    case kPageButtonExpert:
        fLastEasyExpertPage = button;
        break;
    default:
        break;
    }
}

void LibreAudioBaseUI::snapshotButtonClicked(const SnapshotButton button)
{
    if (button == kSnapshotButtonCopy)
    {
        fCopyingSnapshot = !fCopyingSnapshot;
        return;
    }

    const uint8_t snapshot = button - kSnapshotButtonA;

    // nothing to do if current snapshot clicked and there is no previous
    if (fSnapshots.getCurrent() == snapshot && fSnapshots.getPrevious() == snapshot)
        return;

    // special case for copy & pasting snapshot
    if (fCopyingSnapshot)
    {
        fCopyingSnapshot = false;
        fSnapshots.copyTo(snapshot);
        return;
    }

    // clicked new snapshot, load it
    if (fSnapshots.getCurrent() != snapshot)
        fSnapshots.load(snapshot);

    // clicked current snapshot, load previous one
    else
        fSnapshots.load(fSnapshots.getPrevious());

    // fUndoRedo.clear();

    // set state of active/current snapshot (index)
    const char snapshotStr[] = { static_cast<char>('A' + snapshot), '\0' };
    setState(kStateKeys[kStateCurrentSnapshot], snapshotStr);
}

void LibreAudioBaseUI::uiIdle()
{
    fSnapshots.idle();
}

// --------------------------------------------------------------------------------------------------------------------
// Other Callbacks

void LibreAudioBaseUI::snapshotDataToSave(const uint32_t snapshot,
                                          const float* const parameterValues,
                                          const LibreAudioUndoRedo::Actions& undoRedoActions)
{
    std::string value = "{}";

    try {
        nlohmann::json j;

        // parameter value
        {
            nlohmann::json& jparameters = j["parameters"] = nlohmann::json::object();

           #if LIBREAUDIO_WANT_DRYWET
            jparameters["dry_wet"] = parameterValues[kCommonParameterDryWet];
           #endif

            for (uint32_t i = 0; i < common_input::kFaustParameterCount; ++i)
            {
                const FaustParameter& param = kFaustParametersIn[i];

                if (isFaustParameterOutputOrTrigger(param))
                    continue;

                jparameters[param.symbol] = parameterValues[kParametersInputStart + i];
            }

            for (uint32_t i = kCommonIOParameters; i < common_output::kFaustParameterCount; ++i)
            {
                const FaustParameter& param = kFaustParametersOut[i];

                if (isFaustParameterOutputOrTrigger(param))
                    continue;

                jparameters[param.symbol] = parameterValues[kParametersOutputStart + i - kCommonIOParameters];
            }

            for (uint32_t i = 0, size = kFaustParameters.size(); i < size; ++i)
            {
                const FaustParameter& param = kFaustParameters[i];

                if (isFaustParameterOutputOrTrigger(param))
                    continue;

                jparameters[param.symbol] = parameterValues[kParametersMainStart + i];
            }
        }

        // undo/redo actions
        {
            nlohmann::json& jundoredo = j["undo/redo"] = nlohmann::json::object();

            jundoredo["position"] = static_cast<int>(undoRedoActions.position);

            nlohmann::json& jactions = jundoredo["actions"] = nlohmann::json::array();
            for (const LibreAudioUndoRedo::Action& action : undoRedoActions.data)
            {
                nlohmann::json jaction = nlohmann::json::array();

                for (const LibreAudioUndoRedo::Parameter& parameter : action)
                {
                    if (const char* const symbol = kParameterSymbols[parameter.index])
                    {
                        jaction.push_back(nlohmann::json::object({
                            { "symbol", symbol },
                            { "value", parameter.value },
                        }));
                    }
                }

                jactions.push_back(jaction);
            }
        }

        value = j.dump(1, '\t', true, nlohmann::json::error_handler_t::replace);
    } DISTRHO_SAFE_EXCEPTION("failed to serialize snapshot");

    d_stdout("saving snapshot %u | %s", snapshot, value.c_str());

    setState(kStateKeys[kStateSnapshotValuesA + snapshot], value.c_str());
}

void LibreAudioBaseUI::snapshotParametersChanged(const float* const parameterValues)
{
    for (uint32_t i = 0; i < kParameterCount; ++i)
    {
        if (isParameterOutputOrTrigger(i))
            continue;
        if (d_isEqual(fParameterValues[i], parameterValues[i]))
            continue;

        fParameterValues[i] = parameterValues[i];

        editParameter(i, true);
        setParameterValue(i, fParameterValues[i]);
        editParameter(i, false);
    }
}

void LibreAudioBaseUI::snapshotParameterChanged(const uint32_t parameterIndex, const float parameterValue)
{
    fParameterValues[parameterIndex] = parameterValue;

    editParameter(parameterIndex, true);
    setParameterValue(parameterIndex, parameterValue);
    editParameter(parameterIndex, false);
}

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
