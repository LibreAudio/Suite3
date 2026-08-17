// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#include "LibreAudioBaseUI.hpp"

#include "ui/reference.hpp"
#include "ui/base/container.hpp"
#include "ui/widgets-todo/meter.hpp"
#include "ui/widgets-todo/shader.hpp"
#include "ui/widgets-todo/stage.hpp"
#include "ui/widgets-todo/top-bar-name.hpp"

// #include "LibreAudioParameters.hpp"
// #include "LibreAudioStates.hpp"

// #include "EventHandlers.hpp"
#include "Layout.hpp"
// #include "extra/Time.hpp"

// #include <string>
// #include <vector>

#include "ui/reference.hpp"
#include "ui/widgets.hpp"

// --------------------------------------------------------------------------------------------------------------------

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioTopBar : public LibreAudioReferenceContainerWidget<LibreAudioReference::TopBar>
{
    std::unique_ptr<LibreAudioTopBarLogoWidget> fLogo = addWidget<LibreAudioTopBarLogoWidget>();
    std::unique_ptr<LibreAudioTopBarNameWidget> fPluginName = addWidget<LibreAudioTopBarNameWidget>();
    std::unique_ptr<LibreAudioWidget> fSpacer = addSpacer();
    std::unique_ptr<LibreAudioButtonGroupWidget> fUndoRedoGroup = addWidget<LibreAudioTopBarUndoRedoGroupWidget>();
    std::unique_ptr<LibreAudioButtonGroupWidget> fSnapshotsGroup = addWidget<LibreAudioTopBarSnapshotsGroupWidget>();
    std::unique_ptr<LibreAudioButtonGroupWidget> fEasyExpertGroup = addWidget<LibreAudioTopBarEasyExpertGroupWidget>();
    std::unique_ptr<LibreAudioButtonGroupWidget> fMenuPowerGroup = addWidget<LibreAudioTopBarMenuPowerGroupWidget>();

public:
    LibreAudioTopBar(LibreAudioTopLevelWidget* const parent)
        : LibreAudioReferenceContainerWidget(parent)
    {
    }
};

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioMainArea : public LibreAudioReferenceContainerWidget<LibreAudioReference::MainArea>
{
    std::unique_ptr<LibreAudioWidget> fMetersIn = addWidget<LibreAudioMeterWidget<Input>>();
    std::unique_ptr<LibreAudioStageWidget> fStage = addWidget<LibreAudioStageWidget, Expanding>();
    std::unique_ptr<LibreAudioWidget> fMetersOut = addWidget<LibreAudioMeterWidget<Output>>();

public:
    LibreAudioMainArea(LibreAudioTopLevelWidget* const parent)
        : LibreAudioReferenceContainerWidget(parent)
    {
    }

    Point<int> getStageAreaAbsolutePos() const noexcept
    {
        return fStage->getAbsolutePos();
    }

    Size<uint> getStageAreaSize() const noexcept
    {
        return fStage->getSize();
    }
};

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioRootWidget : public LibreAudioReferenceContainerTopLevelWidget<LibreAudioReference::Window, kVertical>
{
    using R = LibreAudioReference::Window;

    std::unique_ptr<LibreAudioTopBar> fTopBar;
    std::unique_ptr<LibreAudioMainArea> fMainArea;

public:
    LibreAudioRootWidget(Window& window, LibreAudioUIWidgetInterface* const iface)
        : LibreAudioReferenceContainerTopLevelWidget(window, iface)
    {
        createFontFromMemory("regular",
                             FONTS_INTER_18PT_REGULAR_TTF_DATA,
                             FONTS_INTER_18PT_REGULAR_TTF_LEN,
                             false);
        createFontFromMemory("mono",
                             FONTS_SPLINESANSMONO_REGULAR_TTF_DATA,
                             FONTS_SPLINESANSMONO_REGULAR_TTF_LEN,
                             false);

        fTopBar = addWidget<LibreAudioTopBar>();
        fMainArea = addWidget<LibreAudioMainArea, Expanding>();

        // fake a resize after creating all widgets, to move everything into place
        ResizeEvent ev;
        ev.size = getSize();
        LibreAudioRootWidget::onResize(ev);
    }

    Point<int> getStageAreaAbsolutePos() const noexcept
    {
        return fMainArea->getStageAreaAbsolutePos();
    }

    Size<uint> getStageAreaSize() const noexcept
    {
        return fMainArea->getStageAreaSize();
    }
};

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioUI : public LibreAudioBaseUI
{
    using R = LibreAudioReference::Window;

    double fScaleFactor = getScaleFactor();
    std::unique_ptr<LibreAudioShaderBaseWidget> fShaderBackground;
    std::unique_ptr<LibreAudioShaderBaseWidget> fShaderLine;
    std::unique_ptr<LibreAudioRootWidget> fRoot { new LibreAudioRootWidget(getWindow(), this) };

public:
    LibreAudioUI()
        : LibreAudioBaseUI()
    {
        fShaderBackground.reset(new LibreAudioBackgroundShaderWidget<SHADERS_SHADERTOY_AURORA_FRAG_DATA, SHADERS_SHADERTOY_AURORA_FRAG_LEN>(this, this));

        static constexpr const std::string_view label = DISTRHO_PLUGIN_LABEL;
        if constexpr (label == "chorus")
            fShaderLine.reset(new LibreAudioBackgroundShaderWidget<SHADERS_CURVE_CHORUS_FRAG_DATA, SHADERS_CURVE_CHORUS_FRAG_LEN>(this, this));
        else if constexpr (label == "vocalDoubler")
            fShaderLine.reset(new LibreAudioBackgroundShaderWidget<SHADERS_CURVE_VOCAL_DOUBLER_FRAG_DATA, SHADERS_CURVE_VOCAL_DOUBLER_FRAG_LEN>(this, this));
        else
            fShaderLine.reset(new LibreAudioBackgroundShaderWidget<SHADERS_LIBREAUDIO_LINE_FRAG_DATA, SHADERS_LIBREAUDIO_LINE_FRAG_LEN>(this, this));

        updateShaderPosition();
    }

    ~LibreAudioUI() override
    {
    }

protected:
    // ----------------------------------------------------------------------------------------------------------------
    // Widget Callbacks

    void onNanoDisplay() override
    {
        const float w = getWidth();
        const float h = getHeight();

        beginPath();
        rect(0, 0, w, h);
        fillPaint(linearGradient(0, 0, 0, h, R::backgroundGradientStart, R::backgroundGradientStop));
        fill();

        if constexpr (R::border != 0 && d_isNotZero(R::borderColor.alpha))
        {
            strokeColor(R::borderColor);
            strokeWidth(R::border * 2 * fScaleFactor);
            stroke();
        }
    }

    void onResize(const ResizeEvent& ev) override
    {
        LibreAudioBaseUI::onResize(ev);
        updateShaderPosition();
    }

    void uiIdle() final
    {
        // FIXME
        updateShaderPosition();
    }

    void uiScaleFactorChanged(const double scaleFactor) final
    {
        fScaleFactor = scaleFactor;
        // fShaderTest->setBorderRadius(LibreAudioReference::Stage::borderRadius * fScaleFactor);
        // TODO
    }

private:
    void updateShaderPosition()
    {
        if (LibreAudioShaderBaseWidget* const sw = fShaderBackground.get())
        {
            sw->setAbsolutePos(fRoot->getStageAreaAbsolutePos());
            sw->setSize(fRoot->getStageAreaSize());
            sw->setBorderRadius(LibreAudioReference::Stage::borderRadius * fScaleFactor);
        }
        if (LibreAudioShaderBaseWidget* const sw = fShaderLine.get())
        {
            sw->setAbsolutePos(fRoot->getStageAreaAbsolutePos());
            sw->setSize(fRoot->getStageAreaSize());
            sw->setBorderRadius(LibreAudioReference::Stage::borderRadius * fScaleFactor);
        }
    }

    DISTRHO_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(LibreAudioUI)
};

// --------------------------------------------------------------------------------------------------------------------

UI* createUI()
{
    return new LibreAudioUI();
}

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
