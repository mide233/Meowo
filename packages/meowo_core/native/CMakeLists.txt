cmake_minimum_required(VERSION 3.25)
project(meowo_core LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(ANDROID)
  add_library(meowo_sqlite3 STATIC ../../../third_party/sqlite3/sqlite3.c)
  target_include_directories(meowo_sqlite3 PUBLIC ../../../third_party/sqlite3)
  target_compile_definitions(meowo_sqlite3 PRIVATE SQLITE_THREADSAFE=1 SQLITE_OMIT_LOAD_EXTENSION)
  set_target_properties(meowo_sqlite3 PROPERTIES POSITION_INDEPENDENT_CODE ON)
  set(MEOWO_SQLITE_TARGET meowo_sqlite3)
else()
  find_package(SQLite3 REQUIRED)
  set(MEOWO_SQLITE_TARGET SQLite::SQLite3)
endif()

option(MEOWO_WITH_MUPDF "Render PDF/EPUB with MuPDF" ON)

add_library(meowo_core SHARED
  src/core.cpp
)
target_include_directories(meowo_core
  PUBLIC include
  PRIVATE ../../../third_party
)
target_link_libraries(meowo_core PRIVATE ${MEOWO_SQLITE_TARGET})
target_compile_options(meowo_core PRIVATE -Wall -Wextra -Wpedantic)
target_compile_definitions(meowo_core PRIVATE MEOWO_CORE_BUILD)

if(MEOWO_WITH_MUPDF)
  if(ANDROID)
    set(MEOWO_MUPDF_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../.tools/mupdf/mupdf-1.26.3-source"
        CACHE PATH "MuPDF source/build root")
    set(MEOWO_MUPDF_ANDROID_OBJ "${MEOWO_MUPDF_ROOT}/build/android/obj/local/arm64-v8a"
        CACHE PATH "MuPDF Android static library directory")
    set(MEOWO_MUPDF_LIBS
      "${MEOWO_MUPDF_ANDROID_OBJ}/libmupdf_core.a"
      "${MEOWO_MUPDF_ANDROID_OBJ}/libmupdf_thirdparty_freetype.a"
      "${MEOWO_MUPDF_ANDROID_OBJ}/libmupdf_thirdparty_gumbo.a"
      "${MEOWO_MUPDF_ANDROID_OBJ}/libmupdf_thirdparty_harfbuzz.a"
      "${MEOWO_MUPDF_ANDROID_OBJ}/libmupdf_thirdparty_jbig2dec.a"
      "${MEOWO_MUPDF_ANDROID_OBJ}/libmupdf_thirdparty_lcms2.a"
      "${MEOWO_MUPDF_ANDROID_OBJ}/libmupdf_thirdparty_libjpeg.a"
      "${MEOWO_MUPDF_ANDROID_OBJ}/libmupdf_thirdparty_mujs.a"
      "${MEOWO_MUPDF_ANDROID_OBJ}/libmupdf_thirdparty_openjpeg.a"
      "${MEOWO_MUPDF_ANDROID_OBJ}/libmupdf_thirdparty_extract.a"
      "${MEOWO_MUPDF_ANDROID_OBJ}/libmupdf_thirdparty_brotli.a"
    )
  else()
    set(MEOWO_MUPDF_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../.tools/mupdf/mupdf-1.26.3-source"
        CACHE PATH "MuPDF source/build root")
    set(MEOWO_MUPDF_LIBS
      "${MEOWO_MUPDF_ROOT}/build/release/libmupdf.a"
      "${MEOWO_MUPDF_ROOT}/build/release/libmupdf-third.a"
    )
  endif()

  foreach(mupdf_lib IN LISTS MEOWO_MUPDF_LIBS)
    if(NOT EXISTS "${mupdf_lib}")
      message(FATAL_ERROR "MuPDF library not found: ${mupdf_lib}. Build MuPDF first or set MEOWO_MUPDF_ROOT.")
    endif()
  endforeach()

  target_sources(meowo_core PRIVATE src/mupdf_import.cpp)
  target_include_directories(meowo_core PRIVATE "${MEOWO_MUPDF_ROOT}/include")
  target_compile_definitions(meowo_core PRIVATE MEOWO_HAS_MUPDF=1)
  if(ANDROID)
    target_link_libraries(meowo_core PRIVATE
      -Wl,--start-group ${MEOWO_MUPDF_LIBS} -Wl,--end-group z log)
  else()
    target_link_libraries(meowo_core PRIVATE ${MEOWO_MUPDF_LIBS} m pthread dl)
  endif()
endif()

set_target_properties(meowo_core PROPERTIES
  OUTPUT_NAME meowo_core
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
)

if(NOT ANDROID)
  enable_testing()
  find_package(GTest REQUIRED)
  add_executable(meowo_core_tests tests/core_tests.cpp)
  target_include_directories(meowo_core_tests PRIVATE ../../../third_party)
  target_link_libraries(meowo_core_tests PRIVATE meowo_core GTest::gtest_main SQLite::SQLite3)
  target_compile_options(meowo_core_tests PRIVATE -Wall -Wextra -Wpedantic)
  add_test(NAME meowo_core_tests COMMAND meowo_core_tests)
endif()
