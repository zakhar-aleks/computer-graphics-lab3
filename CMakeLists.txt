cmake_minimum_required(VERSION 3.20)
project(MetalColorLab CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(glfw3 REQUIRED)

include(FetchContent)

FetchContent_Declare(
    metal_cpp
    GIT_REPOSITORY https://github.com/apple/metal-cpp.git
    GIT_TAG main
)
FetchContent_MakeAvailable(metal_cpp)

FetchContent_Declare(
    imgui
    GIT_REPOSITORY https://github.com/ocornut/imgui.git
    GIT_TAG master
)
FetchContent_MakeAvailable(imgui)

file(GLOB IMGUI_SOURCES
    ${imgui_SOURCE_DIR}/*.cpp
    ${imgui_SOURCE_DIR}/backends/imgui_impl_glfw.cpp
    ${imgui_SOURCE_DIR}/backends/imgui_impl_metal.mm
)

set_source_files_properties(${imgui_SOURCE_DIR}/backends/imgui_impl_metal.mm main.mm PROPERTIES COMPILE_FLAGS "-fobjc-arc")

add_executable(${PROJECT_NAME} main.mm metal_impl.cpp ${IMGUI_SOURCES})

target_include_directories(${PROJECT_NAME} PRIVATE 
    ${metal_cpp_SOURCE_DIR}
    ${imgui_SOURCE_DIR}
    ${imgui_SOURCE_DIR}/backends
)

target_link_libraries(${PROJECT_NAME} PRIVATE 
    glfw
    "-framework Metal"
    "-framework Foundation"
    "-framework QuartzCore"
    "-framework Cocoa"
)