# Libre Audio Suite
# Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
# SPDX-License-Identifier: GPL-3.0-or-later

cmake_minimum_required(VERSION 3.8...3.31)

project(LibreAudioSuite VERSION 0.0.1)

option(LIBREAUDIO_BLOCK_SIZE "Vectorizable block size")
option(LIBREAUDIO_CUSTOM_UI "Enable custom UIs" TRUE)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_INTERPROCEDURAL_OPTIMIZATION OFF)

if(CMAKE_BUILD_TYPE STREQUAL "Release" OR CMAKE_BUILD_TYPE STREQUAL "MinSizeRel")
  set(CMAKE_C_VISIBILITY_PRESET hidden)
  set(CMAKE_CXX_VISIBILITY_PRESET hidden)
  set(CMAKE_VISIBILITY_INLINES_HIDDEN TRUE)
else()
  set(CMAKE_C_VISIBILITY_PRESET default)
  set(CMAKE_CXX_VISIBILITY_PRESET default)
  set(CMAKE_VISIBILITY_INLINES_HIDDEN FALSE)
endif()

#######################################################################################################################
# check for dependencies

find_program(FAUST faust REQUIRED)
find_program(FAUSTDR faustdr REQUIRED)

#######################################################################################################################
# common flags

# enable fast-math for all builds
add_compile_options(-ffast-math)

# invalidate possible -fno-finite-math-only from user environment
add_compile_options(-ffinite-math-only)

# use a custom namespace for all DPF things
add_compile_definitions(DISTRHO_NAMESPACE=LibreAudioSuiteDISTRHO)
add_compile_definitions(DGL_NAMESPACE=LibreAudioSuiteDGL)

# configure nanovg
add_compile_definitions(DGL_USE_NANOVG_FBO)
add_compile_definitions(NVG_FONT_TEXTURE_FLAGS=NVG_IMAGE_NEAREST)

# base tuning, SSE2 or NEON required
if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64|AMD64|x64|X64|i.86|x86|X86)$")
  add_compile_options(-mtune=generic -msse -msse2 -mfpmath=sse)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(ARM|armv[3-9][a-z]*)$")
  add_compile_options(-mfpu=neon-vfpv4 -mfloat-abi=hard)
endif()

# always report undefined symbols
if (NOT APPLE)
  add_compile_options(-Wl,--no-undefined)
endif()

# Clang specific flags
if (CMAKE_CXX_COMPILER_ID MATCHES "^(AppleClang|Clang)$")
  # silence warnings caused by -ffinite-math-only
  if (CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL 17.0)
    add_compile_options(-Wno-nan-infinity-disabled)
  endif()
endif()

# GCC specific flags
if (CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
  # do not keep GNU-specific symbols around, preventing dlclose() from working properly
  # FIXME move this to DPF
  add_compile_options(-fno-gnu-unique)

  # keep math in single-precision where relevant/possible
  add_compile_options(-fsingle-precision-constant)
endif()

#######################################################################################################################
# setup flags according to build type

if(CMAKE_BUILD_TYPE STREQUAL "Release" OR CMAKE_BUILD_TYPE STREQUAL "MinSizeRel")
  # Release flags
  add_compile_options(-DNDEBUG)

  # split sections to help reduce binary size
  add_compile_options(-fdata-sections -ffunction-sections)

  # strip symbols
  if(CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang")
    add_link_options(-Wl,-dead_strip,-dead_strip_dylibs,-x)
  elseif (CMAKE_CXX_COMPILER_ID MATCHES "^(Clang|GNU)$")
    add_link_options(-Wl,--as-needed,--gc-sections,--strip-all)
  endif()

  # linker optimization
  if (CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    add_link_options(-Wl,-O1)
  endif()

else()
  # Debug flags
  add_compile_options(-DDEBUG)

endif()

#######################################################################################################################
# setup dependencies

add_subdirectory(deps)
add_subdirectory(deps/DPF)
# add_subdirectory(deps/DPF-Widgets)
add_subdirectory(deps/json)

# main source folder
add_subdirectory(src)
