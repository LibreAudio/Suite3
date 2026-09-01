// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#include "LibreAudioBaseUI.hpp"

#include "ui/reference.hpp"
#include "ui/base/container.hpp"
#include "ui/widgets/parameter-dump-area.hpp"
#include "ui/widgets/root.hpp"
#include "ui/widgets-todo/shader.hpp"
#include "ui/widgets.hpp"

#include <list>

// --------------------------------------------------------------------------------------------------------------------

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioRootWidgetWithShaders final : public LibreAudioRootWidget<LibreAudioTopBar, LibreAudioMainArea>
{
    using BaseWidget = LibreAudioRootWidget<LibreAudioTopBar, LibreAudioMainArea>;

    std::list<LibreAudioShaderBaseWidget*> fShaders;

public:
    LibreAudioRootWidgetWithShaders(Window& window, LibreAudioUIWidgetInterface* const iface)
        : BaseWidget(window, iface)
    {
    }

    void setup(const std::list<LibreAudioShaderBaseWidget*> &shaders)
    {
        fShaders = shaders;
        updateSize(false);
    }

private:
    void updateSize(const bool updateChildren) final
    {
        BaseWidget::updateSize(updateChildren);

        const Point<int> pos = fMainArea->getMainAreaAbsolutePos();
        const Size<uint> size = fMainArea->getMainAreaSize();
        const float borderRadius = fMainArea->getMainAreaBorderRadius();

        for (LibreAudioShaderBaseWidget* const sw : fShaders)
        {
            sw->setAbsolutePos(pos);
            sw->setSize(size);
            sw->setBorderRadius(borderRadius);
        }
    }
};

class LibreAudioUI : public LibreAudioBaseUI
{
    std::unique_ptr<LibreAudioShaderBaseWidget> fShaderBackground;
    std::unique_ptr<LibreAudioShaderBaseWidget> fShaderAnalyser;
    std::unique_ptr<LibreAudioShaderBaseWidget> fShaderLine;

public:
    LibreAudioUI()
        : LibreAudioBaseUI()
    {
        static constexpr const std::string_view label = DISTRHO_PLUGIN_LABEL;

        if constexpr (label == "chorus" || label == "djFilter" || label == "mbComp5" || label == "tiltEQ"
                   || label == "vocalDoubler")
        {
            fShaderBackground.reset(new LibreAudioBackgroundShaderWidget<SHADERS_SHADERTOY_CLOUDSTARFIELD_FRAG_DATA, SHADERS_SHADERTOY_CLOUDSTARFIELD_FRAG_LEN>(this, this));

            // spectrum overlay: above the background, below the response curves
            fShaderAnalyser.reset(new LibreAudioBackgroundShaderWidget<SHADERS_ANALYSER_FFT_FRAG_DATA, SHADERS_ANALYSER_FFT_FRAG_LEN>(this, this));

            if constexpr (label == "chorus")
                fShaderLine.reset(new LibreAudioBackgroundShaderWidget<SHADERS_CURVE_CHORUS_FRAG_DATA, SHADERS_CURVE_CHORUS_FRAG_LEN>(this, this));
            else if constexpr (label == "djFilter")
                fShaderLine.reset(new LibreAudioBackgroundShaderWidget<SHADERS_CURVE_DJ_FILTER_FRAG_DATA, SHADERS_CURVE_DJ_FILTER_FRAG_LEN>(this, this));
            else if constexpr (label == "mbComp5")
                fShaderLine.reset(new LibreAudioBackgroundShaderWidget<SHADERS_CURVE_MB_COMP5_FRAG_DATA, SHADERS_CURVE_MB_COMP5_FRAG_LEN>(this, this));
            else if constexpr (label == "tiltEQ")
                fShaderLine.reset(new LibreAudioBackgroundShaderWidget<SHADERS_CURVE_TILT_EQ_FRAG_DATA, SHADERS_CURVE_TILT_EQ_FRAG_LEN>(this, this));
            else if constexpr (label == "vocalDoubler")
                fShaderLine.reset(new LibreAudioBackgroundShaderWidget<SHADERS_CURVE_VOCAL_DOUBLER_FRAG_DATA, SHADERS_CURVE_VOCAL_DOUBLER_FRAG_LEN>(this, this));
            else
                __builtin_unreachable();

            const std::list<LibreAudioShaderBaseWidget*> shaders = {
                fShaderBackground.get(),
                fShaderAnalyser.get(),
                fShaderLine.get(),
            };
            createRootWidget<LibreAudioRootWidgetWithShaders>();
            static_cast<LibreAudioRootWidgetWithShaders*>(fRootWidget.get())->setup(shaders);
        }
        else
        {
            createRootWidget<LibreAudioTopBar, LibreAudioParameterDumpArea>();
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
