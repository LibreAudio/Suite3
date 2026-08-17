# Libre Audio Suite
# Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
# SPDX-License-Identifier: GPL-3.0-or-later

set(LAS_RESOURCES_CPP "// auto-generated file\n#include \"las-resources.h\"\n")
set(LAS_RESOURCES_H "// auto-generated file\n#pragma once\n")

foreach(INPUT_FILE ${INPUT_FILES})
  # get file length
  file(SIZE "${INPUT_FILE}" INPUT_FILE_LEN)

  # read file
  file(READ "${INPUT_FILE}" INPUT_FILE_HEX HEX)

  # convert file content into C hexadecimal array
  string(REGEX REPLACE "([0-9a-f][0-9a-f])" "0x\\1," INPUT_FILE_HEX "${INPUT_FILE_HEX}")

  # generate C-compatible symbol based on input name
  if("${INPUT_FILE}" MATCHES "^.*/resources/.*$")
    string(REGEX REPLACE "^(.*)/resources/(.*)$" "\\2" INPUT_SYMBOL "${INPUT_FILE}")
  elseif("${INPUT_FILE}" MATCHES "^.*/src/ui/.*$")
    string(REGEX REPLACE "^(.*)/src/ui/(.*)$" "\\2" INPUT_SYMBOL "${INPUT_FILE}")
  else()
    string(REGEX REPLACE "^(.*)/src/(.*)$" "\\2" INPUT_SYMBOL "${INPUT_FILE}")
  endif()
  string(MAKE_C_IDENTIFIER "${INPUT_SYMBOL}" INPUT_SYMBOL)
  string(TOUPPER "${INPUT_SYMBOL}" INPUT_SYMBOL)

  # set data type
  if("${INPUT_FILE}" MATCHES "^.*.(frag|vert)$")
    set(INPUT_TYPE "char")
  else()
    set(INPUT_TYPE "unsigned char")
  endif()

  # add to resource contents, later written to a file
  string(APPEND LAS_RESOURCES_CPP "const ${INPUT_TYPE} ${INPUT_SYMBOL}_DATA[] = { ${INPUT_FILE_HEX} }\;\n")
  string(APPEND LAS_RESOURCES_CPP "static_assert(sizeof(${INPUT_SYMBOL}_DATA) == ${INPUT_SYMBOL}_LEN, \"Incorrect auto-generated size\")\;\n")

  string(APPEND LAS_RESOURCES_H "#define ${INPUT_SYMBOL}_LEN ${INPUT_FILE_LEN}\n")
  string(APPEND LAS_RESOURCES_H "extern const ${INPUT_TYPE} ${INPUT_SYMBOL}_DATA[]\;\n")
endforeach()

# write files
file(WRITE "${OUTPUT_DIR}/las-resources.cpp" ${LAS_RESOURCES_CPP})
file(WRITE "${OUTPUT_DIR}/las-resources.h" ${LAS_RESOURCES_H})
