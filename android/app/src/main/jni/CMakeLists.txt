cmake_minimum_required(VERSION 3.10)
project(my_ocr)

set(CMAKE_ANDROID_STL_TYPE c++_shared)

# Paths to ncnn and opencv-mobile — override via -D from gradle if needed
if(NOT DEFINED OPENCV_MOBILE_DIR)
    set(OPENCV_MOBILE_DIR ${CMAKE_SOURCE_DIR}/opencv-mobile-2.4.13.7-android)
endif()
if(NOT DEFINED NCNN_SDK_DIR)
    set(NCNN_SDK_DIR ${CMAKE_SOURCE_DIR}/ncnn-20260113-android-vulkan)
endif()

set(OpenCV_DIR ${OPENCV_MOBILE_DIR}/sdk/native/jni)
set(ncnn_DIR ${NCNN_SDK_DIR}/${ANDROID_ABI}/lib/cmake/ncnn)

find_package(OpenCV REQUIRED core imgproc highgui)
find_package(ncnn REQUIRED)

add_library(my_ocr SHARED
    ocr_jni.cpp
    ppocrv5.cpp
    omp_stub.cpp
)

target_link_libraries(my_ocr
    ncnn
    ${OpenCV_LIBS}
)
