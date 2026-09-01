// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

// #include <cmath>

#define in
#define out
#define uniform extern

struct sampler2D
{
};

struct _vec2 { float x, y; } vec22;

struct _vec2 vec2(float a, ...) { return struct _vec2{}; };

struct vec3
{
    float x, y, z;
    vec3(float, float, float) {}
};

struct vec4
{
    float x, y, z, a;
    vec4(float, float, float, float) {}
    vec4(vec3, float) {}
};

extern vec4 gl_FragCoord;
extern vec4 gl_FragColor;

double abs(double);
double length(double);
double log(double);
double step(double, double);
