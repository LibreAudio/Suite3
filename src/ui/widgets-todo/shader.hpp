// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../base/interface.hpp"

#include "OpenGL-include.hpp"
#include "SubWidget.hpp"
#include "TopLevelWidget.hpp"

#include "extra/String.hpp"
#include "extra/ValueSmoother.hpp"

#include "las-resources.h"

#include <vector>

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

        gl3.dpfBounds = glGetAttribLocation(program, "_dpf_bounds");
        gl3.dpfBorderRadius = glGetUniformLocation(program, "_dpf_border_radius");
        gl3.dpfPosition = glGetUniformLocation(program, "_dpf_position");

        if (const uint32_t count = fInterface->getParameterCount())
        {
            gl3.parameterValues = new GLint[count];
            String symbol;

            for (uint32_t i = 0; i < count; ++i)
            {
                symbol = "u_";
                symbol += fInterface->getParameterSymbol(i);
                gl3.parameterValues[i] = glGetUniformLocation(program, symbol);
            }
        }

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

        if (const uint32_t count = fInterface->getParameterCount())
        {
            for (uint32_t i = 0; i < count; ++i)
            {
                if (gl3.parameterValues[i] != 0)
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
        GLint* parameterValues;
    } gl3 = {};

    TopLevelWidget* const fParent;
    const float fScaleFactor;
    const double fStartTime;
    bool fFirstResize = true;
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
