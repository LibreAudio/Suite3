// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../_lab/interface.hpp"

#include "Application.hpp"
#include "SubWidget.hpp"
#include "TopLevelWidget.hpp"

#include "extra/String.hpp"
#include "extra/ValueSmoother.hpp"

#include "las-resources.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <functional>
#include <vector>

#include "OpenGL-include.hpp"

#ifdef DISTRHO_OS_WINDOWS
#include "extra/Windows-include.h"
extern "C" {
__declspec(dllimport) PROC WINAPI wglGetProcAddress(LPCSTR);
}
#endif

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------

class ShaderBaseWidget : public SubWidget
{
public:
    explicit ShaderBaseWidget(TopLevelWidget* const parent, LabUIWidgetInterface* const iface)
        : SubWidget(parent),
          fInterface(iface) {}

    void setBorderRadius(const float borderRadius) noexcept
    {
        if (d_isEqual(fBorderRadius, borderRadius))
            return;
        fBorderRadius = borderRadius;
        repaint();
    }

    // A float uniform that is not a parameter -- something only the UI knows, like an animation's progress.
    // getter is asked once per repaint; a shader that does not declare the uniform simply never sees it.
    void setCustomUniform(const char* const name, std::function<float()> getter)
    {
        fCustomUniforms.push_back(CustomUniform { String(name), -2, std::move(getter) });
    }

protected:
    struct CustomUniform {
        String name;
        GLint location; // -2 until looked up
        std::function<float()> getter;
    };

    LabUIWidgetInterface* const fInterface;
    float fBorderRadius = 0.f;
    std::vector<CustomUniform> fCustomUniforms;
};

// --------------------------------------------------------------------------------------------------------------------

template<const char src[], uint size>
class BackgroundShaderWidget final : public ShaderBaseWidget,
                                     public IdleCallback
{
public:
    explicit BackgroundShaderWidget(TopLevelWidget* const parent, LabUIWidgetInterface* const iface)
        : ShaderBaseWidget(parent, iface),
          fParent(parent)
    {
        // 8ms was 125 Hz: on a 60 Hz display more than half of those frames were rendered
        // and then thrown away. The shader widgets all cover the same area, so the window
        // redraws at whichever callback is fastest -- this has to stay in step with them.
        parent->addIdleCallback(this, 16);

       #ifdef DISTRHO_OS_WINDOWS
        if (! initGL())
            return;
       #endif

        const GLuint program = glCreateProgram();
        DISTRHO_SAFE_ASSERT_RETURN(program != 0,);

        const GLuint vertex = glCreateShader(GL_VERTEX_SHADER);
        DISTRHO_SAFE_ASSERT_RETURN(vertex != 0,);

        glGenBuffers(2, gl3.buffers);

        static constexpr const char kShaderHeader[] =
           #if defined(DGL_USE_GLES3)
            "#version 300 es\n"
            "#define LIBREAUDIO_GL3\n"
           #elif defined(DGL_USE_GLES2)
            "#version 100\n"
            "#define LIBREAUDIO_GL2\n"
           #elif defined(DGL_USE_OPENGL3)
            "#version 150 core\n"
            "#define LIBREAUDIO_GL3\n"
           #else
            "#define LIBREAUDIO_GL2\n"
           #endif
            "#define LIBREAUDIO_HOSTED\n"
        ;

        static constexpr const char* const vertexSource[] = {
            kShaderHeader,
            SHADERS_LIBREAUDIO_VERT_DATA,
        };
        static constexpr const GLint vertexSourceLen[] = {
            sizeof(kShaderHeader) - 1,
            SHADERS_LIBREAUDIO_VERT_LEN,
        };
        glShaderSource(vertex, ARRAY_SIZE(vertexSource), vertexSource, vertexSourceLen);
        glCompileShader(vertex);

        int status;
        glGetShaderiv(vertex, GL_COMPILE_STATUS, &status);
        if (status == 0)
        {
            GLint len = 0;
            glGetShaderiv(vertex, GL_INFO_LOG_LENGTH, &len);

            std::vector<GLchar> errorLog(len);
            glGetShaderInfoLog(vertex, len, &len, errorLog.data());

            d_stderr2("vertex error: %s", errorLog.data());
            std::abort();
            return;
        }

        const GLuint fragment = glCreateShader(GL_FRAGMENT_SHADER);
        DISTRHO_SAFE_ASSERT_RETURN(fragment != 0,);

        static constexpr const char* const fragmentSource[] = {
            kShaderHeader,
            SHADERS_LIBREAUDIO_FRAG_DATA,
            src,
        };
        static constexpr const GLint fragmentSourceLen[] = {
            sizeof(kShaderHeader) - 1,
            SHADERS_LIBREAUDIO_FRAG_LEN,
            size,
        };
        glShaderSource(fragment, ARRAY_SIZE(fragmentSource), fragmentSource, fragmentSourceLen);
        glCompileShader(fragment);

        glGetShaderiv(fragment, GL_COMPILE_STATUS, &status);
        if (status == 0)
        {
            GLint len = 0;
            glGetShaderiv(fragment, GL_INFO_LOG_LENGTH, &len);

            std::vector<GLchar> errorLog(len);
            glGetShaderInfoLog(fragment, len, &len, errorLog.data());

            d_stderr2("fragment error: %s", errorLog.data());
            std::abort();
            return;
        }

        glAttachShader(program, fragment);
        glAttachShader(program, vertex);
        glLinkProgram(program);

        glDeleteShader(fragment);
        glDeleteShader(vertex);

        glGetProgramiv(program, GL_LINK_STATUS, &status);
        if (status == 0)
        {
            GLint len = 0;
            glGetProgramiv(program, GL_INFO_LOG_LENGTH, &len);

            std::vector<GLchar> errorLog(len);
            glGetProgramInfoLog(program, len, &len, errorLog.data());

            d_stderr2("------------------------------ glGetProgramiv error: %s", errorLog.data());
            std::abort();
            return;
        }

        gl3.program = program;
        gl3.iMouse = glGetUniformLocation(program, "iMouse");
        gl3.iResolution = glGetUniformLocation(program, "iResolution");
        gl3.iTime = glGetUniformLocation(program, "iTime");

        // FIXME remove these, rely on iTime instead
        gl3.fixmeLevelSlow = glGetUniformLocation(program, "iLevelSlow");
        gl3.fixmeLevelFast = glGetUniformLocation(program, "iLevelFast");
        gl3.fixmeLevelSlowTime = glGetUniformLocation(program, "iLevelSlowTime");

        gl3.dpfBounds = glGetAttribLocation(program, "_dpf_bounds");
        gl3.dpfBorderRadius = glGetUniformLocation(program, "_dpf_border_radius");
        gl3.dpfPosition = glGetUniformLocation(program, "_dpf_position");
        gl3.dpfScaleFactor = glGetUniformLocation(program, "_dpf_scale_factor");

        if (const uint32_t count = fInterface->getParameterCount())
        {
            gl3.parameterValues = new GLint[count];
            String symbol;

            for (uint32_t i = 0; i < count; ++i)
            {
                gl3.parameterValues[i] = -1;

                const char* const parameterSymbol = fInterface->getParameterSymbol(i);
                DISTRHO_SAFE_ASSERT_UINT_CONTINUE(parameterSymbol != nullptr, i);

                symbol = "u_";
                symbol += parameterSymbol;
                gl3.parameterValues[i] = glGetUniformLocation(program, symbol);

                // remember the input meters so the level smoothers can follow them
                if (std::strcmp(parameterSymbol, "input_peak_L") == 0)
                    fPeakParameterL = static_cast<int>(i);
                else if (std::strcmp(parameterSymbol, "input_peak_R") == 0)
                    fPeakParameterR = static_cast<int>(i);
                // ... and the gain-reduction meter, for the scrolling history below
                else if (std::strcmp(parameterSymbol, "gr") == 0)
                    fGrParameter = static_cast<int>(i);
            }
        }

        // A curve that scrolls needs the past, and a fragment program keeps none of
        // it: every frame starts from nothing. So a shader that asks for the gain
        // reduction over time -- by declaring iGrHistory -- gets a one-row texture
        // instead of a uniform, kept and uploaded here. A texture rather than a
        // uniform array because each fragment looks up its own column, and an
        // array indexed by gl_FragCoord is exactly what GLSL does not promise to
        // support; sampling also gives the resampling to the widget's width for
        // free, whatever that width is.
        gl3.grHistory = glGetUniformLocation(program, "iGrHistory");

        if (gl3.grHistory >= 0 && fGrParameter >= 0)
        {
            fGrHistory.resize(kGrHistoryColumns, 0.f);
            fGrTexels.resize(kGrHistoryColumns * 4, 0);

            glGenTextures(1, &gl3.grTexture);
            glBindTexture(GL_TEXTURE_2D, gl3.grTexture);
            // GL_NEAREST, so each column stays a block with a hard edge. There is
            // exactly one reading per repaint behind this texture and a column is
            // one of them, so interpolating between two columns would draw a ramp
            // the limiter never did -- and it lands on the one place it is most
            // wrong, the attack edge of a hit, turning a reduction that arrived
            // in a single frame into a slope several pixels wide. The cost is that
            // a release tail is a staircase of columns rather than a smooth line,
            // which is the honest shape: each step is one frame of limiting.
            // CLAMP_TO_EDGE so nothing wraps between the oldest and newest column.
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, kGrHistoryColumns, 1, 0,
                         GL_RGBA, GL_UNSIGNED_BYTE, fGrTexels.data());
            glBindTexture(GL_TEXTURE_2D, 0);
        }

        // Shaders cannot smooth anything themselves -- a fragment program keeps no
        // state between frames -- so the two brightness envelopes are integrated
        // here and handed over as plain uniforms. They advance once per repaint,
        // which the idle callback above fixes at 16 ms.
        fLevelSlow.setSampleRate(1.f / kFrameSeconds);
        fLevelSlow.setTimeConstant(kLevelSlowSeconds);
        fLevelSlow.setTargetValue(kLevelSilenceDb);
        fLevelSlow.clearToTargetValue();

        fLevelFast.setSampleRate(1.f / kFrameSeconds);
        fLevelFast.setTimeConstant(kLevelFastSeconds);
        fLevelFast.setTargetValue(kLevelSilenceDb);
        fLevelFast.clearToTargetValue();

        fMouseX.setSampleRate(1.0 / 0.008);
        fMouseX.setTimeConstant(0.5);

        fMouseY.setSampleRate(1.0 / 0.008);
        fMouseY.setTimeConstant(0.5);
    }

    ~BackgroundShaderWidget() final
    {
        fParent->removeIdleCallback(this);

        if (gl3.program == 0)
            return;

        delete[] gl3.parameterValues;

        if (gl3.grTexture != 0)
            glDeleteTextures(1, &gl3.grTexture);

        glDeleteProgram(gl3.program);
    }

private:
    void idleCallback() final
    {
        repaint();
    }

    void onDisplay() final
    {
        const TopLevelWidget* const tlw = getTopLevelWidget();

        const uint width = getWidth();
        const uint height = getHeight();

        const double time = getApp().getTime() - fStartTime;
        const double frameSeconds = std::clamp<double>(time - fLastTime, 0.0, 0.1);
        fLastTime = time;

        glUseProgram(gl3.program);

        glUniform1f(gl3.dpfBorderRadius, fBorderRadius);
        glUniform2f(gl3.dpfPosition, getAbsoluteX(), tlw->getHeight() - height - getAbsoluteY());
        glUniform1f(gl3.dpfScaleFactor, fInterface->getScaleFactor());

        glUniform3f(gl3.iMouse, fMouseX.next(), fMouseY.next(), fMouseZ);
        glUniform3f(gl3.iResolution, width, height, 0.f);
        glUniform1f(gl3.iTime, time);

        // Peak of the two input meters, in dBFS, run through a slow and a fast
        // envelope. Shaders blend the two to decide how bright to draw.
        {
            float peakDb = kLevelSilenceDb;

            if (fPeakParameterL >= 0)
                peakDb = std::max(peakDb, fInterface->getParameterValue(fPeakParameterL));

            if (fPeakParameterR >= 0)
                peakDb = std::max(peakDb, fInterface->getParameterValue(fPeakParameterR));

            fLevelSlow.setTargetValue(peakDb);
            fLevelFast.setTargetValue(peakDb);

            const float levelSlowDb = fLevelSlow.next();

            // A shader that drives a *rate* from the level -- the starfield flies
            // faster when the input is hot -- cannot just multiply iTime by it:
            // that would move everything already on screen every time the level
            // changed. It needs the integral of the level over time, which, like
            // the envelopes themselves, only the host can keep. Weighted by the
            // normalised level so the shader can scale it into its own units.
            const float levelSlowNorm = std::min(std::max((levelSlowDb - kLevelFloorDb) / (kLevelCeilDb - kLevelFloorDb), 0.f), 1.f);

            // Rates want their own timing, and an asymmetric one: a fly-through
            // picks up speed as the music arrives and coasts back down when it
            // stops, so the fall is the longer of the two. Braking as briskly as
            // it accelerated would read as the picture being yanked back.
            const float levelTimeSeconds = levelSlowNorm >= fLevelSlowHeld ? kLevelTimeAttackSeconds
                                                                           : kLevelTimeReleaseSeconds;

            fLevelSlowHeld += (levelSlowNorm - fLevelSlowHeld)
                            * (1.f - std::exp(-frameSeconds / levelTimeSeconds));

            fLevelSlowTime += fLevelSlowHeld * frameSeconds;

            glUniform1f(gl3.fixmeLevelSlow, levelSlowDb);
            glUniform1f(gl3.fixmeLevelFast, fLevelFast.next());
            glUniform1f(gl3.fixmeLevelSlowTime, fLevelSlowTime);
        }

        if (const uint32_t count = fInterface->getParameterCount())
        {
            for (uint32_t i = 0; i < count; ++i)
            {
                if (gl3.parameterValues[i] >= 0)
                    glUniform1f(gl3.parameterValues[i], fInterface->getParameterValue(i));
            }
        }

        for (CustomUniform& uniform : fCustomUniforms)
        {
            if (uniform.location == -2)
                uniform.location = glGetUniformLocation(gl3.program, uniform.name);
            if (uniform.location >= 0)
                glUniform1f(uniform.location, uniform.getter());
        }

        if (gl3.grTexture != 0)
            updateGrHistory(frameSeconds);

        static const constexpr GLfloat vertices[] = { -1, 1, -1, -1, 1, -1, 1, 1 };
        glBindBuffer(GL_ARRAY_BUFFER, gl3.buffers[0]);
        glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
        glEnableVertexAttribArray(gl3.dpfBounds);
        glVertexAttribPointer(gl3.dpfBounds, 2, GL_FLOAT, GL_FALSE, 0, nullptr);

        static constexpr const GLubyte order[] = { 0, 1, 2, 0, 2, 3 };
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, gl3.buffers[1]);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(order), order, GL_STATIC_DRAW);
        glDrawElements(GL_TRIANGLES, ARRAY_SIZE(order), GL_UNSIGNED_BYTE, nullptr);

        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
        glDisableVertexAttribArray(gl3.dpfBounds);
        glBindBuffer(GL_ARRAY_BUFFER, 0);

        if (gl3.grTexture != 0)
            glBindTexture(GL_TEXTURE_2D, 0);

        glUseProgram(0);
    }

    // One column of gain-reduction history per kGrColumnSeconds, oldest first, the
    // last one still being written. Each column keeps the deepest reduction that
    // fell inside it rather than an average, so a transient narrower than a column
    // still reaches its true depth instead of being diluted by the quiet either
    // side of it -- the same reason the DSP peak-holds the meter in the first place.
    void updateGrHistory(const double frameSeconds)
    {
        // Gain reduction is negative dB, so the deepest is the smallest.
        const float grDb = fInterface->getParameterValue(fGrParameter);
        fGrHistory.back() = std::min(fGrHistory.back(), grDb);

        fGrColumnAccum += frameSeconds;

        if (const int advance = static_cast<int>(fGrColumnAccum / kGrColumnSeconds))
        {
            fGrColumnAccum -= advance * kGrColumnSeconds;

            // frameSeconds is clamped to 0.1 s upstream, so this is a handful of
            // columns at worst; the whole-buffer case is only here so a pathological
            // one cannot run off the end.
            if (advance >= static_cast<int>(kGrHistoryColumns))
            {
                std::fill(fGrHistory.begin(), fGrHistory.end(), grDb);
            }
            else
            {
                std::memmove(fGrHistory.data(), fGrHistory.data() + advance,
                             (kGrHistoryColumns - advance) * sizeof(float));
                std::fill(fGrHistory.end() - advance, fGrHistory.end(), grDb);
            }
        }

        // Normalised to the meter's range and packed 16-bit across red and green.
        // 8 bits would put the scale in 256 steps, and a release tail crossing the
        // full height would visibly stair on any scope taller than that; the second
        // byte costs nothing and removes the question.
        for (uint i = 0; i < kGrHistoryColumns; ++i)
        {
            const float norm = std::clamp(-fGrHistory[i] / kGrRangeDb, 0.f, 1.f);
            const uint packed = static_cast<uint>(norm * 65535.f + 0.5f);
            fGrTexels[i * 4 + 0] = static_cast<GLubyte>(packed >> 8);
            fGrTexels[i * 4 + 1] = static_cast<GLubyte>(packed & 0xff);
        }

        // Unit 0 is left active by everything else that draws here, and this widget
        // binds nothing else, so there is no glActiveTexture to get wrong.
        glBindTexture(GL_TEXTURE_2D, gl3.grTexture);
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, kGrHistoryColumns, 1,
                        GL_RGBA, GL_UNSIGNED_BYTE, fGrTexels.data());
        glUniform1i(gl3.grHistory, 0);
    }

    bool onMouse(const MouseEvent& ev) final
    {
        if (ev.button == kMouseButtonLeft)
            fMouseZ = ev.press ? 1.f : 0.f;
        return SubWidget::onMouse(ev);
    }

    bool onMotion(const MotionEvent& ev) final
    {
        const float w = getWidth();
        const float h = getHeight();
        fMouseX.setTargetValue(w / 2 - ev.pos.getX() / w * (w / 4));
        fMouseY.setTargetValue(h / 2 + ev.pos.getY() / h * (h / 4));
        return SubWidget::onMotion(ev);
    }

    void onPositionChanged(const PositionChangedEvent& ev) final
    {
        fMouseX.setTargetValue(getWidth() * 0.5f);
        fMouseY.setTargetValue(getHeight() * 0.5f);
        fMouseX.clearToTargetValue();
        fMouseY.clearToTargetValue();
        SubWidget::onPositionChanged(ev);
    }

    void onResize(const ResizeEvent& ev) final
    {
        fMouseX.setTargetValue(ev.size.getWidth() * 0.5f);
        fMouseY.setTargetValue(ev.size.getHeight() * 0.5f);
        if (fFirstResize)
        {
            fFirstResize = false;
            fMouseX.clearToTargetValue();
            fMouseY.clearToTargetValue();
        }
        SubWidget::onResize(ev);
    }

    struct {
        GLuint buffers[2];
        GLuint program;
        GLint dpfBounds;
        GLint dpfBorderRadius;
        GLint dpfPosition;
        GLint dpfScaleFactor;
        GLint iMouse;
        GLint iResolution;
        GLint iTime;
        GLint fixmeLevelSlow;
        GLint fixmeLevelFast;
        GLint fixmeLevelSlowTime;
        GLint grHistory;
        GLuint grTexture;
        GLint* parameterValues;
    } gl3 = {};

    // Brightness envelope timing, plus the level stood in for silence (the input
    // meters bottom out at -70 dBFS).
    //
    // These are T60 -- time to cover 99.9% of a step -- which is a lot brisker than
    // it reads: ExponentialValueSmoother divides by 6.91 internally, so the actual
    // one-pole tau is T60/6.91 and most of the movement lands in the first seventh
    // of the quoted time. 1.5 s here is a tau of ~0.22 s, which reads as "follows
    // the phrase" rather than the twitch that 0.5 s gave.
    static constexpr const float kLevelSlowSeconds = 5.0f;
    static constexpr const float kLevelFastSeconds = 1.5f;
    static constexpr const float kLevelSilenceDb = -70.0f;

    // Nominal repaint period, matching the idle callback.
    static constexpr const float kFrameSeconds = 0.016f;

    // The window iLevelSlowTime normalises the slow envelope over, in dBFS.
    // Shaders reading it must use the same one -- it is meterFloorDb/meterCeilDb
    // in shadertoy-cloudstarfield.frag and friends.
    static constexpr const float kLevelFloorDb = -40.0f;
    static constexpr const float kLevelCeilDb  =   0.0f;

    // How quickly iLevelSlowTime takes a level up, and how slowly it gives one
    // back. Unlike the envelopes above these are plain one-pole taus, not T60s:
    // each covers 63% of the distance in the time quoted and all but a twentieth
    // of it in three times that.
    //
    // They sit on top of iLevelSlow's own smoothing rather than replacing it, so
    // the rise is the two in series -- an attack of 0 here would still not be
    // instant. Keep the attack the shorter of the two: arriving with the music and
    // outlasting it is the asymmetry the flight wants.
    static constexpr const float kLevelTimeAttackSeconds  = 1.0f;
    static constexpr const float kLevelTimeReleaseSeconds = 2.0f;

    // The gain-reduction history handed to shaders that ask for it. The window and
    // the column count are the shader's WIN and HISTN -- change one, change both.
    // kGrRangeDb is the meter's own range, MAXGR in limiter.dsp.
    //
    // 480 columns over 8 s is 60 a second: one per repaint on a 60 Hz display, and
    // a shade longer than the 16 ms idle callback so a frame advances the history
    // by one column or by none, never by two. That matters now the columns are
    // drawn as blocks -- advancing by two would fill both with the same reading
    // and leave a double-width block sitting among the rest. A frame that advances
    // by none is invisible: the column in progress just keeps peak-holding.
    //
    // The count cannot usefully go above the repaint rate. One reading arrives per
    // frame however many columns there are, so more of them only duplicate, and
    // the width a block occupies on screen is set by kGrWindowSeconds against the
    // widget's width -- a longer window is what makes the blocks finer.
    static constexpr const uint kGrHistoryColumns = 480;
    static constexpr const float kGrWindowSeconds = 8.0f;
    static constexpr const float kGrRangeDb = 24.0f;
    static constexpr const double kGrColumnSeconds = kGrWindowSeconds / kGrHistoryColumns;

    TopLevelWidget* const fParent;

    const double fStartTime = getApp().getTime();
    double fLastTime = fStartTime;

    bool fFirstResize = true;
    ExponentialValueSmoother fLevelSlow;
    ExponentialValueSmoother fLevelFast;
    float fLevelSlowTime = 0.f;
    float fLevelSlowHeld = 0.f;
    int fPeakParameterL = -1;
    int fPeakParameterR = -1;
    int fGrParameter = -1;
    std::vector<float> fGrHistory;    // dB of reduction, oldest first, last in progress
    std::vector<GLubyte> fGrTexels;   // the same, packed for the texture
    double fGrColumnAccum = 0.0;
    LinearValueSmoother fMouseX;
    LinearValueSmoother fMouseY;
    float fMouseZ = 0.f;

   #ifdef DISTRHO_OS_WINDOWS
    #define DGL_EXT(PROC, func) PROC func;
    DGL_EXT(PFNGLATTACHSHADERPROC,             glAttachShader)
    DGL_EXT(PFNGLBINDBUFFERPROC,               glBindBuffer)
    DGL_EXT(PFNGLBUFFERDATAPROC,               glBufferData)
    DGL_EXT(PFNGLCOMPILESHADERPROC,            glCompileShader)
    DGL_EXT(PFNGLCREATEPROGRAMPROC,            glCreateProgram)
    DGL_EXT(PFNGLCREATESHADERPROC,             glCreateShader)
    DGL_EXT(PFNGLDELETEBUFFERSPROC,            glDeleteBuffers)
    DGL_EXT(PFNGLDELETEPROGRAMPROC,            glDeleteProgram)
    DGL_EXT(PFNGLDELETESHADERPROC,             glDeleteShader)
    DGL_EXT(PFNGLDISABLEVERTEXATTRIBARRAYPROC, glDisableVertexAttribArray)
    DGL_EXT(PFNGLENABLEVERTEXATTRIBARRAYPROC,  glEnableVertexAttribArray)
    DGL_EXT(PFNGLGENBUFFERSPROC,               glGenBuffers)
    DGL_EXT(PFNGLGETATTRIBLOCATIONPROC,        glGetAttribLocation)
    DGL_EXT(PFNGLGETPROGRAMINFOLOGPROC,         glGetProgramInfoLog)
    DGL_EXT(PFNGLGETPROGRAMIVPROC,             glGetProgramiv)
    DGL_EXT(PFNGLGETSHADERINFOLOGPROC,         glGetShaderInfoLog)
    DGL_EXT(PFNGLGETSHADERIVPROC,              glGetShaderiv)
    DGL_EXT(PFNGLGETUNIFORMLOCATIONPROC,       glGetUniformLocation)
    DGL_EXT(PFNGLLINKPROGRAMPROC,              glLinkProgram)
    DGL_EXT(PFNGLSHADERSOURCEPROC,             glShaderSource)
    DGL_EXT(PFNGLUNIFORM1FPROC,                glUniform1f)
    DGL_EXT(PFNGLUNIFORM1IPROC,                glUniform1i)
    DGL_EXT(PFNGLUNIFORM2FPROC,                glUniform2f)
    DGL_EXT(PFNGLUNIFORM3FPROC,                glUniform3f)
    DGL_EXT(PFNGLUSEPROGRAMPROC,               glUseProgram)
    DGL_EXT(PFNGLVERTEXATTRIBPOINTERPROC,      glVertexAttribPointer)
    #undef DGL_EXT

    bool initGL()
    {
        #define DGL_EXT(PROC, func) \
            func = (PROC) wglGetProcAddress ( #func ); \
            DISTRHO_SAFE_ASSERT_RETURN(func != nullptr, false);
        DGL_EXT(PFNGLATTACHSHADERPROC,             glAttachShader)
        DGL_EXT(PFNGLBINDBUFFERPROC,               glBindBuffer)
        DGL_EXT(PFNGLBUFFERDATAPROC,               glBufferData)
        DGL_EXT(PFNGLCOMPILESHADERPROC,            glCompileShader)
        DGL_EXT(PFNGLCREATEPROGRAMPROC,            glCreateProgram)
        DGL_EXT(PFNGLCREATESHADERPROC,             glCreateShader)
        DGL_EXT(PFNGLDELETEBUFFERSPROC,            glDeleteBuffers)
        DGL_EXT(PFNGLDELETEPROGRAMPROC,            glDeleteProgram)
        DGL_EXT(PFNGLDELETESHADERPROC,             glDeleteShader)
        DGL_EXT(PFNGLDISABLEVERTEXATTRIBARRAYPROC, glDisableVertexAttribArray)
        DGL_EXT(PFNGLENABLEVERTEXATTRIBARRAYPROC,  glEnableVertexAttribArray)
        DGL_EXT(PFNGLGENBUFFERSPROC,               glGenBuffers)
        DGL_EXT(PFNGLGETATTRIBLOCATIONPROC,        glGetAttribLocation)
        DGL_EXT(PFNGLGETPROGRAMINFOLOGPROC,        glGetProgramInfoLog)
        DGL_EXT(PFNGLGETPROGRAMIVPROC,             glGetProgramiv)
        DGL_EXT(PFNGLGETSHADERINFOLOGPROC,         glGetShaderInfoLog)
        DGL_EXT(PFNGLGETSHADERIVPROC,              glGetShaderiv)
        DGL_EXT(PFNGLGETUNIFORMLOCATIONPROC,       glGetUniformLocation)
        DGL_EXT(PFNGLLINKPROGRAMPROC,              glLinkProgram)
        DGL_EXT(PFNGLSHADERSOURCEPROC,             glShaderSource)
        DGL_EXT(PFNGLUNIFORM1FPROC,                glUniform1f)
        DGL_EXT(PFNGLUNIFORM1IPROC,                glUniform1i)
        DGL_EXT(PFNGLUNIFORM2FPROC,                glUniform2f)
        DGL_EXT(PFNGLUNIFORM3FPROC,                glUniform3f)
        DGL_EXT(PFNGLUSEPROGRAMPROC,               glUseProgram)
        DGL_EXT(PFNGLVERTEXATTRIBPOINTERPROC,      glVertexAttribPointer)
        #undef DGL_EXT
        return true;
    }
   #endif
};

// --------------------------------------------------------------------------------------------------------------------

} /* namespace LibreAudio */
