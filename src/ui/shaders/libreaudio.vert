// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

// DPF variables
attribute vec4 _dpf_bounds;

void main()
{
    gl_Position = vec4(_dpf_bounds.x, _dpf_bounds.y, 0.0, 1.0);
}
