cmake_minimum_required(VERSION 3.14)
project(infer_demo CXX)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED True)

# Set paths
set(PROJECT_ROOT "${CMAKE_SOURCE_DIR}")
set(PADDLE_OCR_DIR "${PROJECT_ROOT}/PaddleOCR/deploy/cpp_infer")
set(PADDLE_LIB "${PADDLE_OCR_DIR}/third_party/paddle_inference")
set(OPENCV_DIR "${PADDLE_OCR_DIR}/third_party/opencv-4.7.0/build/third_party/opencv-4.7.0/opencv4/")
set(PPOCR_SRC_DIR "${PADDLE_OCR_DIR}/src")

# Get conda environment path (from environment variables)
if(DEFINED ENV{CONDA_PREFIX})
    set(CONDA_LIB "$ENV{CONDA_PREFIX}/lib")
    set(CUDA_LIB "${CONDA_LIB}")
    set(CUDNN_LIB "${CONDA_LIB}")
else()
    message(WARNING "CONDA_PREFIX not set, using default paths")
    set(CUDA_LIB "/usr/local/cuda/lib64")
    set(CUDNN_LIB "/usr/local/cuda/lib64")
endif()

# Set compilation options
option(WITH_MKL        "Compile demo with MKL/OpenBlas support, default use MKL."       ON)
option(WITH_GPU        "Compile demo with GPU/CPU, default use CPU."                    ON)
option(WITH_STATIC_LIB "Compile demo with static/shared library, default use static."   OFF)

# Set OpenCV
set(OpenCV_DIR "${OPENCV_DIR}/lib64/cmake/opencv4")
find_package(OpenCV REQUIRED)
include_directories(${OpenCV_INCLUDE_DIRS})

# Set Paddle Inference
include_directories("${PADDLE_LIB}/paddle/include")
link_directories("${PADDLE_LIB}/paddle/lib")

# Set third-party libraries
include_directories("${PADDLE_LIB}/third_party/install/protobuf/include")
include_directories("${PADDLE_LIB}/third_party/install/glog/include")
include_directories("${PADDLE_LIB}/third_party/install/gflags/include")
include_directories("${PADDLE_LIB}/third_party/install/xxhash/include")
include_directories("${PADDLE_LIB}/third_party/install/zlib/include")
include_directories("${PADDLE_LIB}/third_party/install/yaml-cpp/include")
include_directories("${PADDLE_LIB}/third_party/install/openvino/include")
include_directories("${PADDLE_LIB}/third_party/install/tbb/include")
include_directories("${PADDLE_LIB}/third_party/boost")
include_directories("${PADDLE_LIB}/third_party/eigen3")

# Link directories
link_directories("${PADDLE_LIB}/third_party/install/zlib/lib")
link_directories("${PADDLE_LIB}/third_party/install/protobuf/lib")
link_directories("${PADDLE_LIB}/third_party/install/glog/lib")
link_directories("${PADDLE_LIB}/third_party/install/gflags/lib")
link_directories("${PADDLE_LIB}/third_party/install/xxhash/lib")
link_directories("${PADDLE_LIB}/third_party/install/yaml-cpp/lib")
link_directories("${PADDLE_LIB}/third_party/install/openvino/intel64")
link_directories("${PADDLE_LIB}/third_party/install/tbb/lib")

# Set math libraries
if(WITH_MKL)
    ADD_DEFINITIONS(-DUSE_MKL)
    include_directories("${PADDLE_LIB}/third_party/install/mklml/include")
    set(MATH_LIB ${PADDLE_LIB}/third_party/install/mklml/lib/libmklml_intel${CMAKE_SHARED_LIBRARY_SUFFIX}
            ${PADDLE_LIB}/third_party/install/mklml/lib/libiomp5${CMAKE_SHARED_LIBRARY_SUFFIX})
    
    set(MKLDNN_PATH "${PADDLE_LIB}/third_party/install/onednn")
    if(EXISTS ${MKLDNN_PATH})
        include_directories("${MKLDNN_PATH}/include")
        set(MKLDNN_LIB ${MKLDNN_PATH}/lib/libdnnl.so.3)
    endif()
else()
    set(MATH_LIB ${PADDLE_LIB}/third_party/install/openblas/lib/libopenblas${CMAKE_STATIC_LIBRARY_SUFFIX})
endif()

# Set dependency libraries
if(WITH_STATIC_LIB)
    set(DEPS ${PADDLE_LIB}/paddle/lib/libpaddle_inference${CMAKE_STATIC_LIBRARY_SUFFIX})
else()
    set(DEPS ${PADDLE_LIB}/paddle/lib/libpaddle_inference${CMAKE_SHARED_LIBRARY_SUFFIX})
endif()

set(DEPS ${DEPS}
    ${MATH_LIB} ${MKLDNN_LIB}
    glog gflags protobuf z xxhash yaml-cpp
    )

set(EXTERNAL_LIB "-ldl -lrt -lgomp -lz -lm -lpthread")
set(DEPS ${DEPS} ${EXTERNAL_LIB})
set(DEPS ${DEPS} ${OpenCV_LIBS})

# Link dependencies
set(DEPS ${DEPS} absl::statusor absl::status)
set(DEPS ${DEPS} polyclipping)

# Include PaddleOCR source code directories
include_directories("${PPOCR_SRC_DIR}")
include_directories("${PADDLE_OCR_DIR}")
include_directories("${PADDLE_OCR_DIR}/third_party/abseil-cpp")
include_directories("${PADDLE_OCR_DIR}/third_party/nlohmann/include")

# Create include path for polyclipping
set(CLIPPER_DIR "${PADDLE_OCR_DIR}/third_party/clipper_ver6.4.2/cpp")
include_directories("${CLIPPER_DIR}")

# Create symbolic link for polyclipping directory
execute_process(
    COMMAND ${CMAKE_COMMAND} -E create_symlink 
    "${CLIPPER_DIR}" 
    "${CMAKE_BINARY_DIR}/polyclipping"
)
include_directories("${CMAKE_BINARY_DIR}")

# Add third-party library subdirectories (if abseil-cpp compilation is needed)
set(THIRD_PARTY_PATH "${PADDLE_OCR_DIR}/third_party")
add_subdirectory("${THIRD_PARTY_PATH}/abseil-cpp" "${CMAKE_BINARY_DIR}/abseil-cpp")
add_subdirectory("${THIRD_PARTY_PATH}/clipper_ver6.4.2/cpp" "${CMAKE_BINARY_DIR}/clipper")

# Set compilation flags
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -g -O3 -fopenmp -std=c++11")

# Find source files
file(GLOB_RECURSE PPOCR_SRCS "${PPOCR_SRC_DIR}/*.cc")

# Create executable
add_executable(Benchmark src/Benchmark.cpp ${PPOCR_SRCS})
target_link_libraries(Benchmark ${DEPS})