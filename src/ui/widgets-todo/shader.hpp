// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../base/interface.hpp"

#include "Application.hpp"
#include "SubWidget.hpp"
#include "TopLevelWidget.hpp"

#include "extra/String.hpp"
#include "extra/ValueSmoother.hpp"

#include "las-resources.h"

#include <cstring>
#include <vector>

#include "OpenGL-include.hpp"

#ifdef DISTRHO_OS_WINDOWS
#include "extra/Windows-include.h"
extern "C" {
__declspec(dllimport) PROC WINAPI wglGetProcAddress(LPCSTR);
}
#endif

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioShaderBaseWidget : public SubWidget
{
public:
    explicit LibreAudioShaderBaseWidget(TopLevelWidget* const parent, LibreAudioUIWidgetInterface* const iface)
        : SubWidget(parent),
          fInterface(iface) {}

    void setBorderRadius(const float borderRadius) noexcept
    {
        if (d_isEqual(fBorderRadius, borderRadius))
            return;
        fBorderRadius = borderRadius;
        repaint();
    }

protected:
    LibreAudioUIWidgetInterface* const fInterface;
    float fBorderRadius = 0.f;
};

// --------------------------------------------------------------------------------------------------------------------

template<const char src[], uint size>
class LibreAudioBackgroundShaderWidget final : public LibreAudioShaderBaseWidget,
                                               public IdleCallback
{
public:
    explicit LibreAudioBackgroundShaderWidget(TopLevelWidget* const parent, LibreAudioUIWidgetInterface* const iface)
        : LibreAudioShaderBaseWidget(parent, iface),
          fParent(parent),
          fScaleFactor(parent->getScaleFactor()),
          fStartTime(parent->getApp().getTime())
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
        gl3.iScaleFactor = glGetUniformLocation(program, "iScaleFactor");
        gl3.iTime = glGetUniformLocation(program, "iTime");
        gl3.iLevelSlow = glGetUniformLocation(program, "iLevelSlow");
        gl3.iLevelFast = glGetUniformLocation(program, "iLevelFast");

        gl3.dpfBounds = glGetAttribLocation(program, "_dpf_bounds");
        gl3.dpfBorderRadius = glGetUniformLocation(program, "_dpf_border_radius");
        gl3.dpfPosition = glGetUniformLocation(program, "_dpf_position");

        if (const uint32_t count = fInterface->getParameterCount())
        {
            gl3.parameterValues = new GLint[count];
            String symbol;

            for (uint32_t i = 0; i < count; ++i)
            {
                // null for the common parameters, which have no Faust symbol
                const char* const parameterSymbol = fInterface->getParameterSymbol(i);

                symbol = "u_";
                symbol += parameterSymbol;
                gl3.parameterValues[i] = glGetUniformLocation(program, symbol);

                if (parameterSymbol == nullptr)
                    continue;

                // remember the input meters so the level smoothers can follow them
                if (std::strcmp(parameterSymbol, "input_peak_L") == 0)
                    fPeakParameterL = static_cast<int>(i);
                else if (std::strcmp(parameterSymbol, "input_peak_R") == 0)
                    fPeakParameterR = static_cast<int>(i);
            }
        }

        // Shaders cannot smooth anything themselves -- a fragment program keeps no
        // state between frames -- so the two brightness envelopes are integrated
        // here and handed over as plain uniforms. They advance once per repaint,
        // which the idle callback above fixes at 16 ms.
        fLevelSlow.setSampleRate(1.f / 0.016f);
        fLevelSlow.setTimeConstant(kLevelSlowSeconds);
        fLevelSlow.setTargetValue(kLevelSilenceDb);
        fLevelSlow.clearToTargetValue();

        fLevelFast.setSampleRate(1.f / 0.016f);
        fLevelFast.setTimeConstant(kLevelFastSeconds);
        fLevelFast.setTargetValue(kLevelSilenceDb);
        fLevelFast.clearToTargetValue();

        fMouseX.setSampleRate(1.0 / 0.008);
        fMouseX.setTimeConstant(0.5);

        fMouseY.setSampleRate(1.0 / 0.008);
        fMouseY.setTimeConstant(0.5);
    }

    ~LibreAudioBackgroundShaderWidget() final
    {
        fParent->removeIdleCallback(this);

        if (gl3.program == 0)
            return;

        delete[] gl3.parameterValues;
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

        glUseProgram(gl3.program);

        glUniform2f(gl3.dpfPosition, getAbsoluteX(), tlw->getHeight() - height - getAbsoluteY());
        glUniform3f(gl3.iMouse, fMouseX.next(), fMouseY.next(), fMouseZ);
        glUniform3f(gl3.iResolution, width, height, 0.f);
        glUniform1f(gl3.iScaleFactor, fScaleFactor);
        glUniform1f(gl3.iTime, static_cast<float>(getApp().getTime() - fStartTime));
        glUniform1f(gl3.dpfBorderRadius, fBorderRadius);

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

            glUniform1f(gl3.iLevelSlow, fLevelSlow.next());
            glUniform1f(gl3.iLevelFast, fLevelFast.next());
        }

        if (const uint32_t count = fInterface->getParameterCount())
        {
            for (uint32_t i = 0; i < count; ++i)
            {
                // glGetUniformLocation returns -1 when the shader does not use the
                // uniform; 0 is a valid location, so this must not test against 0.
                if (gl3.parameterValues[i] >= 0)
                    glUniform1f(gl3.parameterValues[i], fInterface->getParameterValue(i));
            }
        }

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

        glUseProgram(0);
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
        GLint iMouse;
        GLint iResolution;
        GLint iScaleFactor;
        GLint iTime;
        GLint iLevelSlow;
        GLint iLevelFast;
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

    TopLevelWidget* const fParent;
    const float fScaleFactor;
    const double fStartTime;
    bool fFirstResize = true;
    ExponentialValueSmoother fLevelSlow;
    ExponentialValueSmoother fLevelFast;
    int fPeakParameterL = -1;
    int fPeakParameterR = -1;
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

END_NAMESPACE_DISTRHO
