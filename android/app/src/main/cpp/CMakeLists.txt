cmake_minimum_required(VERSION 3.10.2)

project("groundpipe_native")

add_library(groundpipe_native SHARED
    signalsmith_stretch_wrapper.cpp
)

target_include_directories(groundpipe_native PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)

find_library(log-lib log)

target_link_libraries(groundpipe_native
    ${log-lib}
)
