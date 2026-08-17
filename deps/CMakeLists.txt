# Libre Audio Suite
# Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# ---------------------------------------------------------------------------------------------------------------------
# DPF-Widgets related libraries

add_library(las-imgui INTERFACE)

set_target_properties(las-imgui
  PROPERTIES
    INTERPROCEDURAL_OPTIMIZATION OFF
    POSITION_INDEPENDENT_CODE ON
)

target_compile_definitions(las-imgui
  INTERFACE
    IMGUI_DISABLE_DEBUG_TOOLS
    IMGUI_DISABLE_DEFAULT_SHELL_FUNCTIONS
    # IMGUI_DISABLE_DEMO_WINDOWS
)

target_include_directories(las-imgui
  INTERFACE
    DPF-Widgets/generic
    DPF-Widgets/opengl
)

target_sources(las-imgui
  INTERFACE
    DPF-Widgets/opengl/DearImGui.cpp
)

# ---------------------------------------------------------------------------------------------------------------------
# rnnoise library

add_library(las-rnnoise STATIC)

set_target_properties(las-rnnoise
  PROPERTIES
    INTERPROCEDURAL_OPTIMIZATION OFF
    POSITION_INDEPENDENT_CODE ON
)

target_compile_definitions(las-rnnoise
  PRIVATE
    DISABLE_DEBUG_FLOAT
    FLOAT_APPROX
    RNNOISE_EXPORT=
)

target_include_directories(las-rnnoise
  PRIVATE
    rnnoise/src
    rnnoise-model-data
  PUBLIC
    rnnoise/include
)

target_sources(las-rnnoise
  PRIVATE
    rnnoise/src/celt_lpc.c
    rnnoise/src/denoise.c
    rnnoise/src/kiss_fft.c
    rnnoise/src/nnet.c
    rnnoise/src/nnet_default.c
    rnnoise/src/parse_lpcnet_weights.c
    rnnoise/src/pitch.c
    rnnoise/src/rnn.c
    rnnoise/src/rnnoise_tables.c
    rnnoise-model-data/rnnoise_data.c
)

if("${CMAKE_SYSTEM_PROCESSOR}" MATCHES "^(x86_64|amd64|AMD64|x64|X64|i.86|x86|X86)$")
  target_compile_definitions(las-rnnoise
    PRIVATE
      CPU_INFO_BY_ASM
      RNN_ENABLE_X86_RTCD
  )

  target_sources(las-rnnoise
    PRIVATE
      rnnoise/src/x86/nnet_avx2.c
      rnnoise/src/x86/nnet_sse4_1.c
      rnnoise/src/x86/x86cpu.c
      rnnoise/src/x86/x86_dnn_map.c
  )

  set_source_files_properties(rnnoise/src/x86/nnet_avx2.c
    PROPERTIES
      COMPILE_FLAGS
        "-mavx -mfma -mavx2"
  )

  set_source_files_properties(rnnoise/src/x86/nnet_sse4_1.c
    PROPERTIES
      COMPILE_FLAGS
        "-msse4.1"
  )
endif()

# ---------------------------------------------------------------------------------------------------------------------
