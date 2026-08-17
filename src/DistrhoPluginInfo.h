// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "config.h"

inline constexpr const char* const _constexpr_DISTRHO_PLUGIN_NAME = DISTRHO_PLUGIN_NAME;
static_assert(_constexpr_DISTRHO_PLUGIN_NAME[0] == 'L', "Name does not start with 'LA '");
static_assert(_constexpr_DISTRHO_PLUGIN_NAME[1] == 'A', "Name does not start with 'LA '");
static_assert(_constexpr_DISTRHO_PLUGIN_NAME[2] == ' ', "Name does not start with 'LA '");

inline constexpr const char* const _constexpr_DISTRHO_PLUGIN_LABEL = DISTRHO_PLUGIN_LABEL;
static_assert(_constexpr_DISTRHO_PLUGIN_LABEL[0] != '\0', "Label must not be empty");

#if defined(__has_include) && __has_include("config-custom.h")
#include "config-custom.h"
#endif

#define DISTRHO_PLUGIN_BRAND "Libre Audio"
#define DISTRHO_PLUGIN_BRAND_ID LiAu
#define DISTRHO_PLUGIN_HOMEPAGE "https://libreaudio.org/"
#define DISTRHO_PLUGIN_LICENSE "GPL-3.0-or-later"
#define DISTRHO_PLUGIN_MAKER "Libre Audio"

#ifndef _DARKGLASS_DEVICE_PABLITO
#define DISTRHO_PLUGIN_HAS_UI 1
#define DISTRHO_PLUGIN_WANT_STATE  1
#define DISTRHO_UI_DEFAULT_WIDTH 910
#define DISTRHO_UI_DEFAULT_HEIGHT 475
#define DISTRHO_UI_FILE_BROWSER   0
#define DISTRHO_UI_USER_RESIZABLE 1
#define DISTRHO_UI_USE_CUSTOM 1
#define DISTRHO_UI_CUSTOM_INCLUDE_PATH "ui/ui.hpp"
#define DISTRHO_UI_CUSTOM_WIDGET_TYPE DISTRHO_NAMESPACE::LibreAudioUIWidget
#endif

#define DISTRHO_PLUGIN_IS_RT_SAFE  1

#if DISTRHO_PLUGIN_NUM_INPUTS != 2
#error DISTRHO_PLUGIN_NUM_INPUTS != 2
#endif

#if DISTRHO_PLUGIN_NUM_OUTPUTS != 2
#error DISTRHO_PLUGIN_NUM_OUTPUTS != 2
#endif
