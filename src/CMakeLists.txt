# Libre Audio Suite
# Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# ---------------------------------------------------------------------------------------------------------------------
# function to generate $TARGET-dsp.{c,h}pp and $TARGET-parameters.{c,h}pp
# used for common code and DPF plugins

function(las_generate_faust_cpp TARGET)
  string(REPLACE "/" "_" OUTPUT ${TARGET})

  add_custom_command(
    OUTPUT
      ${CMAKE_CURRENT_BINARY_DIR}/${OUTPUT}-dsp.cpp
    COMMAND
      ${FAUSTDR}
      -a ${CMAKE_SOURCE_DIR}/src/templates/dsp.cpp.in
      -c ${TARGET}
      -o ${CMAKE_CURRENT_BINARY_DIR}/${OUTPUT}-dsp.cpp
      -Did=${OUTPUT}
      ${VEC_ARGS}
      -X--in-place
      -X--class-name -X${OUTPUT}
      -X--super-class-name -XFaustDSP
      ${CMAKE_SOURCE_DIR}/src/dsp-faust/${TARGET}.dsp
    DEPENDS
      dsp-faust/${TARGET}.dsp
      templates/dsp.cpp.in
    VERBATIM
  )

  add_custom_command(
    OUTPUT
      ${CMAKE_CURRENT_BINARY_DIR}/${OUTPUT}-dsp.hpp
    COMMAND
      ${FAUSTDR}
      -a ${CMAKE_SOURCE_DIR}/src/templates/dsp.hpp.in
      -c ${TARGET}
      -o ${CMAKE_CURRENT_BINARY_DIR}/${OUTPUT}-dsp.hpp
      -Did=${OUTPUT}
      ${CMAKE_SOURCE_DIR}/src/dsp-faust/${TARGET}.dsp
    DEPENDS
      dsp-faust/${TARGET}.dsp
      templates/dsp.hpp.in
    VERBATIM
  )

  add_custom_command(
    OUTPUT
      ${CMAKE_CURRENT_BINARY_DIR}/${OUTPUT}-parameters.cpp
    COMMAND
      ${FAUSTDR}
      -a ${CMAKE_SOURCE_DIR}/src/templates/parameters.cpp.in
      -c ${TARGET}
      -o ${CMAKE_CURRENT_BINARY_DIR}/${OUTPUT}-parameters.cpp
      -Did=${OUTPUT}
      ${CMAKE_SOURCE_DIR}/src/dsp-faust/${TARGET}.dsp
    DEPENDS
      dsp-faust/${TARGET}.dsp
      templates/parameters.cpp.in
    VERBATIM
  )

  add_custom_command(
    OUTPUT
      ${CMAKE_CURRENT_BINARY_DIR}/${OUTPUT}-parameters.hpp
    COMMAND
      ${FAUSTDR}
      -a ${CMAKE_SOURCE_DIR}/src/templates/parameters.hpp.in
      -c ${TARGET}
      -o ${CMAKE_CURRENT_BINARY_DIR}/${OUTPUT}-parameters.hpp
      -Did=${OUTPUT}
      ${CMAKE_SOURCE_DIR}/src/dsp-faust/${TARGET}.dsp
    DEPENDS
      dsp-faust/${TARGET}.dsp
      templates/parameters.hpp.in
    VERBATIM
  )
endfunction()

# ---------------------------------------------------------------------------------------------------------------------
# function to generate $TARGET/config.h
# used for DPF plugins

function(las_generate_faust_plugin TARGET)
  add_custom_command(
    OUTPUT
      ${CMAKE_CURRENT_BINARY_DIR}/${TARGET}
    COMMAND
      ${CMAKE_COMMAND}
      -E
      make_directory
      ${CMAKE_CURRENT_BINARY_DIR}/${TARGET}
    VERBATIM
  )
  add_custom_command(
    OUTPUT
      ${CMAKE_CURRENT_BINARY_DIR}/${TARGET}/config.h
    COMMAND
      ${FAUSTDR}
      -a ${CMAKE_SOURCE_DIR}/src/templates/config.h.in
      -c ${TARGET}
      -l c
      -o ${CMAKE_CURRENT_BINARY_DIR}/${TARGET}/config.h
      -Did=${TARGET}
      ${CMAKE_SOURCE_DIR}/src/dsp-faust/${TARGET}.dsp
    DEPENDS
      ${CMAKE_CURRENT_BINARY_DIR}/${TARGET}
      dsp-faust/${TARGET}.dsp
      templates/config.h.in
    VERBATIM
  )
endfunction()

# ---------------------------------------------------------------------------------------------------------------------
# function to generate resources
# used for DPF plugins

function(las_generate_resources)
  file(GLOB
    LIBREAUDIO_RESOURCES
      CONFIGURE_DEPENDS
        ui/shaders/*.frag
        ui/shaders/*.vert
        ../resources/fonts/*.ttf
        ../resources/images/*.png
  )

  string(REPLACE ";" "\\;" LIBREAUDIO_RESOURCES_ESC "${LIBREAUDIO_RESOURCES}")

  add_custom_command(
    OUTPUT
      ${CMAKE_CURRENT_BINARY_DIR}/las-resources.cpp
      ${CMAKE_CURRENT_BINARY_DIR}/las-resources.h
    COMMAND ${CMAKE_COMMAND}
      -D INPUT_FILES=${LIBREAUDIO_RESOURCES_ESC}
      -D OUTPUT_DIR=${CMAKE_CURRENT_BINARY_DIR}
      -D VERSION=${CMAKE_PROJECT_VERSION}
      -P ${CMAKE_SOURCE_DIR}/src/cmake/res2c.cmake
    DEPENDS
      ${LIBREAUDIO_RESOURCES}
      ${CMAKE_SOURCE_DIR}/src/cmake/res2c.cmake
    VERBATIM
  )

  add_library(las-resources STATIC ${CMAKE_CURRENT_BINARY_DIR}/las-resources.cpp)
endfunction()

# ---------------------------------------------------------------------------------------------------------------------
# common definitions between all plugins

las_generate_faust_cpp(common/input)
las_generate_faust_cpp(common/output)
las_generate_resources()

# ---------------------------------------------------------------------------------------------------------------------
# function to setup a DPF plugin

function(las_add_plugin LABEL)
  set(TARGET "la-${LABEL}")

  set(EXTRA_ARGS)
  if(CMAKE_BUILD_TYPE STREQUAL "Release" OR CMAKE_BUILD_TYPE STREQUAL "MinSizeRel")
  else()
    list(APPEND EXTRA_ARGS RUNTIME_TESTING)
  endif()

  set(EXTRA_DSP_LIBS)
  if("${LABEL}" STREQUAL "leveler")
    list(APPEND EXTRA_DSP_LIBS las-rnnoise)
  endif()

  set(EXTRA_UI_LIBS)

  set(DSP_FILE custom/${LABEL}-dsp.cpp)
  if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${DSP_FILE}")
    set(DSP_FILE LibreAudioPlugin.cpp)
  endif()

  set(UI_FILE custom/${LABEL}-ui.cpp)
  if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${UI_FILE}")
    set(UI_FILE LibreAudioUI.cpp)
  endif()

  if (${LIBREAUDIO_CUSTOM_UI})
    dpf_add_plugin(${TARGET}
      TARGETS
        au clap lv2 vst3 jack
      FILES_COMMON
        ${CMAKE_CURRENT_BINARY_DIR}/common_input-parameters.cpp
        ${CMAKE_CURRENT_BINARY_DIR}/common_input-parameters.hpp
        ${CMAKE_CURRENT_BINARY_DIR}/common_output-parameters.cpp
        ${CMAKE_CURRENT_BINARY_DIR}/common_output-parameters.hpp
        ${CMAKE_CURRENT_BINARY_DIR}/${LABEL}-parameters.cpp
        ${CMAKE_CURRENT_BINARY_DIR}/${LABEL}-parameters.hpp
        ${CMAKE_CURRENT_BINARY_DIR}/${LABEL}/config.h
      FILES_DSP
        ${DSP_FILE}
        ${CMAKE_CURRENT_BINARY_DIR}/common_input-dsp.cpp
        ${CMAKE_CURRENT_BINARY_DIR}/common_input-dsp.hpp
        ${CMAKE_CURRENT_BINARY_DIR}/common_output-dsp.cpp
        ${CMAKE_CURRENT_BINARY_DIR}/common_output-dsp.hpp
        ${CMAKE_CURRENT_BINARY_DIR}/${LABEL}-dsp.cpp
        ${CMAKE_CURRENT_BINARY_DIR}/${LABEL}-dsp.hpp
      FILES_UI
        ${UI_FILE}
        LibreAudioBaseUI.cpp
        LibreAudioSnapshots.cpp
        LibreAudioUndoRedo.cpp
        ${CMAKE_CURRENT_BINARY_DIR}/las-resources.h
      ${EXTRA_ARGS}
    )

    target_link_libraries(${TARGET}-ui
      PUBLIC
        # las-imgui
        las-resources
        nlohmann_json::nlohmann_json
        ${EXTRA_UI_LIBS}
    )

  else()
    dpf_add_plugin(${TARGET}
      TARGETS
        lv2
      FILES_COMMON
        ${CMAKE_CURRENT_BINARY_DIR}/${LABEL}-parameters.cpp
        ${CMAKE_CURRENT_BINARY_DIR}/${LABEL}-parameters.hpp
        ${CMAKE_CURRENT_BINARY_DIR}/${LABEL}/config.h
      FILES_DSP
        ${DSP_FILE}
        ${CMAKE_CURRENT_BINARY_DIR}/${LABEL}-dsp.cpp
        ${CMAKE_CURRENT_BINARY_DIR}/${LABEL}-dsp.hpp
      ${EXTRA_ARGS}
    )
  endif()

  las_generate_faust_cpp(${LABEL})
  las_generate_faust_plugin(${LABEL})

  set_target_properties(${TARGET}
    PROPERTIES
      INTERPROCEDURAL_OPTIMIZATION OFF
      POSITION_INDEPENDENT_CODE ON
  )

  target_compile_definitions(${TARGET}
    PUBLIC
      JSON_NO_IO
      VERSION_MAJOR=${CMAKE_PROJECT_VERSION_MAJOR}
      VERSION_MINOR=${CMAKE_PROJECT_VERSION_MINOR}
      VERSION_PATCH=${CMAKE_PROJECT_VERSION_PATCH}
      $<$<BOOL:${LIBREAUDIO_BLOCK_SIZE}>:LIBREAUDIO_BLOCK_SIZE=${LIBREAUDIO_BLOCK_SIZE}>
  )

  target_include_directories(${TARGET}
    PUBLIC
      ${CMAKE_CURRENT_BINARY_DIR}
      ${CMAKE_CURRENT_BINARY_DIR}/${LABEL}
      custom/${LABEL}
      .
  )

  target_link_libraries(${TARGET}-dsp
    PUBLIC
      ${EXTRA_DSP_LIBS}
  )
endfunction()

# ---------------------------------------------------------------------------------------------------------------------
# setup all plugins

file(GLOB
  LIBREAUDIO_PLUGINS
    CONFIGURE_DEPENDS
      dsp-faust/*.dsp
)

foreach(PLUGIN ${LIBREAUDIO_PLUGINS})
  string(REGEX REPLACE "^(.*)/(.*)\.dsp$" "\\2" PLUGIN "${PLUGIN}")
  las_add_plugin(${PLUGIN})
endforeach()

# ---------------------------------------------------------------------------------------------------------------------
