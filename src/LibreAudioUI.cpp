// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#include "LibreAudioBaseUI.hpp"

#include "ui/reference.hpp"
#include "ui/base/container.hpp"
#include "ui/widgets-todo/shader.hpp"
#include "ui/widgets.hpp"

// --------------------------------------------------------------------------------------------------------------------

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioUI : public LibreAudioBaseUI
{
    std::unique_ptr<LibreAudioShaderBaseWidget> fShaderBackground;
    std::unique_ptr<LibreAudioShaderBaseWidget> fShaderAnalyser;
    std::unique_ptr<LibreAudioShaderBaseWidget> fShaderLine;

public:
    LibreAudioUI()
        : LibreAudioBaseUI()
    {
        fShaderBackground.reset(new LibreAudioBackgroundShaderWidget<SHADERS_SHADERTOY_CLOUDSTARFIELD_FRAG_DATA, SHADERS_SHADERTOY_CLOUDSTARFIELD_FRAG_LEN>(this, this));

        // spectrum overlay: above the background, below the response curves
        fShaderAnalyser.reset(new LibreAudioBackgroundShaderWidget<SHADERS_ANALYSER_FFT_FRAG_DATA, SHADERS_ANALYSER_FFT_FRAG_LEN>(this, this));

        static constexpr const std::string_view label = DISTRHO_PLUGIN_LABEL;
        if constexpr (label == "chorus")
            fShaderLine.reset(new LibreAudioBackgroundShaderWidget<SHADERS_CURVE_CHORUS_FRAG_DATA, SHADERS_CURVE_CHORUS_FRAG_LEN>(this, this));
        else if constexpr (label == "vocalDoubler")
            fShaderLine.reset(new LibreAudioBackgroundShaderWidget<SHADERS_CURVE_VOCAL_DOUBLER_FRAG_DATA, SHADERS_CURVE_VOCAL_DOUBLER_FRAG_LEN>(this, this));
        else
            fShaderLine.reset(new LibreAudioBackgroundShaderWidget<SHADERS_LIBREAUDIO_LINE_FRAG_DATA, SHADERS_LIBREAUDIO_LINE_FRAG_LEN>(this, this));

        createRootWidget<LibreAudioTopBar, LibreAudioMainArea>();
    }

private:
    void updateSize() final
    {
        LibreAudioBaseUI::updateSize();

        const Point<int> pos = fRoot->getMainAreaAbsolutePos();
        const Size<uint> size = fRoot->getMainAreaSize();
        const float borderRadius = fRoot->getMainAreaBorderRadius();

        if (LibreAudioShaderBaseWidget* const sw = fShaderBackground.get())
        {
            sw->setAbsolutePos(pos);
            sw->setSize(size);
            sw->setBorderRadius(borderRadius);
        }
        if (LibreAudioShaderBaseWidget* const sw = fShaderAnalyser.get())
        {
            sw->setAbsolutePos(pos);
            sw->setSize(size);
            sw->setBorderRadius(borderRadius);
        }
        if (LibreAudioShaderBaseWidget* const sw = fShaderLine.get())
        {
            sw->setAbsolutePos(pos);
            sw->setSize(size);
            sw->setBorderRadius(borderRadius);
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
