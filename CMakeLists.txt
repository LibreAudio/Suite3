# Libre Audio Suite
# Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
# SPDX-License-Identifier: GPL-3.0-or-later

cmake_minimum_required(VERSION 3.8...3.31)

project(LibreAudioSuite VERSION 0.0.1)

option(LIBREAUDIO_BLOCK_SIZE "Vectorizable block size")

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_INTERPROCEDURAL_OPTIMIZATION OFF)

#######################################################################################################################
# check for dependencies

find_program(FAUST faust REQUIRED)
find_program(FAUSTDR faustdr REQUIRED)

#######################################################################################################################
# common flags

# enable fast-math for all builds
set(COMMON_FLAGS "-ffast-math")

# invalidate possible -fno-finite-math-only from user environment
set(COMMON_FLAGS "${COMMON_FLAGS} -ffinite-math-only")

# use a custom namespace for all DPF things
set(COMMON_FLAGS "${COMMON_FLAGS} -DDISTRHO_NAMESPACE=LibreAudioSuiteDISTRHO")
set(COMMON_FLAGS "${COMMON_FLAGS} -DDGL_NAMESPACE=LibreAudioSuiteDGL")

# configure nanovg
set(COMMON_FLAGS "${COMMON_FLAGS} -DDGL_USE_NANOVG_FBO")
set(COMMON_FLAGS "${COMMON_FLAGS} -DNVG_FONT_TEXTURE_FLAGS=NVG_IMAGE_NEAREST")

# base tuning, SSE2 or NEON required
if("${CMAKE_SYSTEM_PROCESSOR}" MATCHES "^(x86_64|amd64|AMD64|x64|X64|i.86|x86|X86)$")
  set(COMMON_FLAGS "${COMMON_FLAGS} -mtune=generic -msse -msse2 -mfpmath=sse")
elseif("${CMAKE_SYSTEM_PROCESSOR}" MATCHES "^(ARM|armv[3-9][a-z]*)$")
  set(COMMON_FLAGS "${COMMON_FLAGS} -mfpu=neon-vfpv4 -mfloat-abi=hard")
endif()

# Clang specific flags
if (CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang" OR CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
  # silence warnings caused by -ffinite-math-only
  set(COMMON_FLAGS "${COMMON_FLAGS} -Wno-nan-infinity-disabled")

# GCC specific flags
elseif (CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
  # do not keep GNU-specific symbols around, preventing dlclose() from working properly
  set(COMMON_FLAGS "${COMMON_FLAGS} -fno-gnu-unique")

  # keep math in single-precision where relevant/possible
  set(COMMON_FLAGS "${COMMON_FLAGS} -fsingle-precision-constant")

  # always report undefined symbols
  set(COMMON_FLAGS "${COMMON_FLAGS} -Wl,--no-undefined")
endif()

#######################################################################################################################
# strip flags

# split sections to help reduce binary size
set(STRIP_BUILD_FLAGS "-fdata-sections -ffunction-sections")

# strip symbols
if(CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang")
  set(STRIP_LINK_FLAGS "${RELEASE_FLAGS} -Wl,-dead_strip,-dead_strip_dylibs,-x")
elseif (CMAKE_CXX_COMPILER_ID STREQUAL "Clang" OR CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
  set(STRIP_LINK_FLAGS "${RELEASE_FLAGS} -Wl,--as-needed,--gc-sections,--strip-all")
endif()

#######################################################################################################################
# setup flags according to build type

if("${CMAKE_BUILD_TYPE}" STREQUAL "Release" OR "${CMAKE_BUILD_TYPE}" STREQUAL "MinSizeRel")
  set(CMAKE_C_VISIBILITY_PRESET hidden)
  set(CMAKE_CXX_VISIBILITY_PRESET hidden)
  set(CMAKE_VISIBILITY_INLINES_HIDDEN TRUE)
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${COMMON_FLAGS} ${STRIP_BUILD_FLAGS}")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${COMMON_FLAGS} ${STRIP_BUILD_FLAGS}")
  set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${STRIP_LINK_FLAGS}")
  set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${STRIP_LINK_FLAGS}")
else()
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${COMMON_FLAGS}")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${COMMON_FLAGS}")
endif()

#######################################################################################################################
# setup dependencies

add_subdirectory(deps)
add_subdirectory(deps/DPF)
# add_subdirectory(deps/DPF-Widgets)
add_subdirectory(deps/json)

# main source folder
add_subdirectory(src)
