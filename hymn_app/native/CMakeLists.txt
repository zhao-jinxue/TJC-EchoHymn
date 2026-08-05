cmake_minimum_required(VERSION 3.14)
project(hymn_engine_native LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 动态库：Windows -> hymn_engine.dll
#         Linux   -> libhymn_engine.so
#         macOS   -> libhymn_engine.dylib
add_library(hymn_engine SHARED
    hymn_engine/hymn_engine.cpp
    hymn_engine/hymn_engine_capi.cpp
)

target_include_directories(hymn_engine PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/hymn_engine
)

if (MSVC)
    target_compile_options(hymn_engine PRIVATE /W4)
else()
    target_compile_options(hymn_engine PRIVATE -Wall -Wextra)
endif()

# 可选：原生测试可执行文件（启用 BUILD_TESTING 时）
option(HYMN_ENGINE_BUILD_TESTS "Build native unit tests" OFF)
if (HYMN_ENGINE_BUILD_TESTS)
    add_executable(hymn_engine_test
        test/test_main.cpp
        hymn_engine/hymn_engine.cpp
    )
    target_include_directories(hymn_engine_test PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/hymn_engine
    )
endif()