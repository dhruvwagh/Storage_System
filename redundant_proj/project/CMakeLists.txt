# CMakeLists.txt

cmake_minimum_required(VERSION 3.10)
project(MultiDriveStorageSystem)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_FLAGS "-Wall -pthread")

find_package(PkgConfig REQUIRED)
pkg_check_modules(FUSE3 REQUIRED fuse3)

include_directories(${FUSE3_INCLUDE_DIRS})

add_executable(myfs main.cpp myfs.cpp murmurhash3.cpp ssd_model.cpp)
target_link_libraries(myfs ${FUSE3_LIBRARIES})
