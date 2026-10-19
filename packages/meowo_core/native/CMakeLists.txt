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
