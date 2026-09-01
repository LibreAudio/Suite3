// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#define attribute extern struct

struct vec4
{
    float x, y, z, a;
};

struct vec4 vec4(float x, float y, float z, float a)
{
    return (struct vec4){x, y, z, a};
}

extern struct vec4 gl_Position;

#define main main_vertex
