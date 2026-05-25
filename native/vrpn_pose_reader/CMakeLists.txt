cmake_minimum_required(VERSION 3.15)
project(vrpn_pose_reader LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../cmake")

find_package(VRPN REQUIRED)
find_package(Threads REQUIRED)

add_executable(vrpn_pose_reader src/main.cpp)
target_link_libraries(vrpn_pose_reader PRIVATE VRPN::vrpn Threads::Threads)

install(TARGETS vrpn_pose_reader RUNTIME DESTINATION bin)
