#!/bin/bash
# PP-OCRv5 Dependencies Installation Script
# This script installs PaddlePaddle, PaddleOCR, and builds required dependencies

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WORK_DIR="$PROJECT_DIR/PaddleOCR"
MODELS_DIR="$PROJECT_DIR/models"
CONDA_ENV="deepx"

# Check if conda environment exists and activate it
# Setup conda environment
setup_conda_env() {
    log_info "Setting up conda environment: $CONDA_ENV"
    
    # Check if environment exists
    if conda env list | grep -q "^$CONDA_ENV "; then
        log_warning "Environment $CONDA_ENV already exists"
    else
        log_info "Creating new environment: $CONDA_ENV"
        conda create -n "$CONDA_ENV" python=3.8 -y
    fi
    
    # Activate environment
    log_info "Activating environment: $CONDA_ENV"
    eval "$(conda shell.bash hook)"
    conda activate "$CONDA_ENV"
    
    # Install basic packages
    log_info "Installing basic packages..."
    conda install cmake wget -y
    
    # Install CUDA toolkit and cuDNN
    log_info "Installing CUDA toolkit 11.8.0 and cuDNN 8.9.2.26..."
    conda install cudatoolkit=11.8.0 cudnn=8.9.2.26=cuda11_0 -y
    
    # Install TensorRT 8.6.0
    log_info "Installing TensorRT 8.6.0..."
    local tensorrt_url="https://developer.nvidia.com/downloads/compute/machine-learning/tensorrt/secure/8.6.0/local_repos/nv-tensorrt-local-repo-ubuntu2204-8.6.0-cuda-11.8_1.0-1_amd64.deb"
    local tensorrt_deb="nv-tensorrt-local-repo-ubuntu2204-8.6.0-cuda-11.8_1.0-1_amd64.deb"
    
    # Check if TensorRT is already installed
    if dpkg -l | grep -q "tensorrt"; then
        log_warning "TensorRT appears to be already installed"
    else
        # Download TensorRT package
        if [ ! -f "/tmp/$tensorrt_deb" ]; then
            log_info "Downloading TensorRT package..."
            wget -O "/tmp/$tensorrt_deb" "$tensorrt_url"
        else
            log_warning "TensorRT package already downloaded"
        fi
        
        # Install TensorRT
        log_info "Installing TensorRT package (requires sudo)..."
        sudo dpkg -i "/tmp/$tensorrt_deb"
        
        # Add repository key and update
        sudo cp /var/nv-tensorrt-local-repo-ubuntu2204-8.6.0-cuda-11.8/nv-tensorrt-local-*-keyring.gpg /usr/share/keyrings/
        sudo apt-get update
        
        # Install TensorRT
        sudo apt-get install tensorrt -y
        
        # Install Python TensorRT bindings in conda environment
        pip install nvidia-tensorrt
        
        # Clean up
        rm -f "/tmp/$tensorrt_deb"
    fi
    
    log_success "Conda environment setup complete with CUDA 11.8, cuDNN 8.9.2, and TensorRT 8.6.0"
}

# Install PaddlePaddle
install_paddlepaddle() {
    log_info "Installing PaddlePaddle..."
    
    # Auto-detect GPU availability
    local use_gpu=false
    
    # Check if NVIDIA GPU is available
    if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
        log_info "NVIDIA GPU detected. Checking CUDA installation..."
        use_gpu=true
        
        # Check if CUDA is installed
        if ! command -v nvcc &> /dev/null; then
            log_warning "CUDA toolkit not found. Installing CUDA..."
            
            # Install CUDA toolkit
            log_info "Installing NVIDIA CUDA toolkit..."
            sudo apt update
            sudo apt install -y nvidia-cuda-toolkit
            
            # Verify installation
            if command -v nvcc &> /dev/null; then
                local cuda_version=$(nvcc --version | grep "release" | awk '{print $6}' | cut -d',' -f1 | cut -d'V' -f2)
                log_success "CUDA toolkit installed. Version: $cuda_version"
            else
                log_error "CUDA toolkit installation failed"
                log_warning "Falling back to CPU version"
                use_gpu=false
            fi
        else
            local cuda_version=$(nvcc --version | grep "release" | awk '{print $6}' | cut -d',' -f1 | cut -d'V' -f2)
            log_info "CUDA toolkit found. Version: $cuda_version"
        fi
    else
        log_info "No NVIDIA GPU detected. Installing CPU version."
    fi
    
    if [ "$use_gpu" = true ]; then
        log_info "Installing PaddlePaddle GPU version with CUDA 11.8..."
        python -m pip install paddlepaddle-gpu==3.0.0 -i https://www.paddlepaddle.org.cn/packages/stable/cu118/
        
        # Test GPU installation
        if python -c "import paddle; print('PaddlePaddle version:', paddle.__version__)" 2>/dev/null; then
            log_success "PaddlePaddle GPU version installed successfully"
        else
            log_error "PaddlePaddle GPU installation failed"
            log_warning "Falling back to CPU version"
            use_gpu=false
        fi
    fi
    
    if [ "$use_gpu" = false ]; then
        log_info "Installing PaddlePaddle CPU version..."
        python -m pip install paddlepaddle==3.0.0 -i https://www.paddlepaddle.org.cn/packages/stable/cpu/
    fi
    
    # Test installation
    log_info "Testing PaddlePaddle installation..."
    if python -c "import paddle; print('PaddlePaddle version:', paddle.__version__)"; then
        # Check if GPU is available
        if [ "$use_gpu" = true ]; then
            python -c "import paddle; print('GPU available:', paddle.device.cuda.device_count() > 0)"
        fi
        log_success "PaddlePaddle installed and tested successfully"
    else
        log_error "PaddlePaddle installation test failed"
        exit 1
    fi
}

# Install PaddleOCR
install_paddleocr() {
    log_info "Installing PaddleOCR..."
    
    # Install PaddleOCR package
    python -m pip install "paddleocr[all]"
    
    # Clone repository if not exists or if it's not a PaddleOCR repository
    if [ ! -d "$WORK_DIR" ] || [ ! -f "$WORK_DIR/requirements.txt" ]; then
        if [ -d "$WORK_DIR" ]; then
            log_warning "Directory $WORK_DIR exists but doesn't contain PaddleOCR repository. Removing..."
            rm -rf "$WORK_DIR"
        fi
        
        log_info "Cloning PaddleOCR repository to $WORK_DIR..."
        git clone https://github.com/PaddlePaddle/PaddleOCR.git "$WORK_DIR"
    else
        log_warning "PaddleOCR directory already exists at $WORK_DIR"
    fi
    
    cd "$WORK_DIR"
    
    # Install additional requirements
    if [ -f requirements.txt ]; then
        python -m pip install -r requirements.txt
    else
        log_error "requirements.txt not found in $WORK_DIR"
        exit 1
    fi
    
    log_success "PaddleOCR installed successfully"
}

# Build OpenCV
build_opencv() {
    log_info "Checking OpenCV installation..."
    
    cd "$WORK_DIR"
    mkdir -p deploy/cpp_infer/third_party
    cd deploy/cpp_infer/third_party
    
    # Check if OpenCV is already built
    if [ -d opencv-4.7.0/opencv4 ] && [ -f opencv-4.7.0/opencv4/lib64/libopencv_core.a ]; then
        log_success "OpenCV is already built, skipping build process"
        echo "  Build directory: $(pwd)/opencv-4.7.0/build"
        echo "  Install directory: $(pwd)/opencv-4.7.0/opencv4"
        
        # Count library files (static libraries .a)
        local lib_count=$(ls -1 opencv-4.7.0/opencv4/lib64/libopencv_*.a 2>/dev/null | wc -l)
        echo "  Libraries found: $lib_count static libraries in lib64"
        return
    fi
    
    log_info "Building OpenCV from source..."
    
    # Download OpenCV source if not exists
    if [ ! -f opencv-4.7.0.tar.gz ]; then
        log_info "Downloading OpenCV 4.7.0 source..."
        wget https://github.com/opencv/opencv/archive/4.7.0.tar.gz -O opencv-4.7.0.tar.gz
    fi
    
    # Extract if not already extracted
    if [ ! -d opencv-4.7.0 ]; then
        log_info "Extracting OpenCV source..."
        tar -xzf opencv-4.7.0.tar.gz
    fi
    
    # Build OpenCV with custom configuration
    cd opencv-4.7.0
    mkdir -p build
    cd build
    
    log_info "Configuring OpenCV build with CMake (using original PaddleOCR configuration)..."
    
    # Set install path to match original build_opencv.sh exactly
    local install_path="../opencv4"  # This resolves to opencv-4.7.0/opencv4 from build directory
    
    # Configure with CMake using exact same parameters as build_opencv.sh
    cmake .. \
        -DCMAKE_INSTALL_PREFIX=${install_path} \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DWITH_IPP=OFF \
        -DBUILD_IPP_IW=OFF \
        -DWITH_LAPACK=OFF \
        -DWITH_EIGEN=OFF \
        -DCMAKE_INSTALL_LIBDIR=lib64 \
        -DWITH_ZLIB=ON \
        -DBUILD_ZLIB=ON \
        -DWITH_JPEG=ON \
        -DBUILD_JPEG=ON \
        -DWITH_PNG=ON \
        -DBUILD_PNG=ON \
        -DWITH_TIFF=ON \
        -DBUILD_TIFF=ON
    
    log_info "Building OpenCV (this may take 30-60 minutes)..."
    make -j$(nproc)
    
    log_info "Installing OpenCV..."
    make install
    
    # Create symlinks for compatibility (point to the opencv4 directory)
    cd ../..
    if [ ! -L lib ]; then
        ln -sf opencv-4.7.0/opencv4/lib64 lib
    fi
    if [ ! -L include ]; then
        ln -sf opencv-4.7.0/opencv4/include include
    fi
    
    # Verify build completion
    if [ -d opencv-4.7.0/opencv4 ] && [ -f opencv-4.7.0/opencv4/lib64/libopencv_core.a ]; then
        log_success "OpenCV built successfully from source"
        echo "  Build directory: $(pwd)/opencv-4.7.0/build"
        echo "  Install directory: $(pwd)/opencv-4.7.0/opencv4"
        
        # Count library files (static libraries .a)
        local lib_count=$(ls -1 opencv-4.7.0/opencv4/lib64/libopencv_*.a 2>/dev/null | wc -l)
        echo "  Libraries built: $lib_count static libraries"
        
        # Show OpenCV version
        echo "  OpenCV version: 4.7.0"
        echo "  Build type: Static libraries (matching PaddleOCR requirements)"
    else
        log_error "OpenCV build verification failed"
        exit 1
    fi
}

# Build Paddle Inference
build_paddle_inference() {
    log_info "Checking Paddle Inference installation..."
    
    cd "$WORK_DIR/deploy/cpp_infer/third_party"
    
    # Check if Paddle Inference is already installed
    if [ -d paddle_inference ] && [ -d paddle_inference/paddle/include ] && [ -d paddle_inference/paddle/lib ]; then
        log_success "Paddle Inference is already installed, skipping download and extraction"
        echo "  Include directory: $(pwd)/paddle_inference/paddle/include"
        echo "  Library directory: $(pwd)/paddle_inference/paddle/lib"
        local lib_count=$(ls -1 paddle_inference/paddle/lib/*.so* paddle_inference/paddle/lib/*.a 2>/dev/null | wc -l)
        echo "  Found $lib_count library files"
        
        # Check GPU support by looking for CUDA libraries
        if ls paddle_inference/paddle/lib/*cuda* &>/dev/null || ls paddle_inference/paddle/lib/*cudnn* &>/dev/null; then
            echo "  GPU support: Enabled (pre-built with CUDA support)"
        else
            echo "  GPU support: CPU-only version"
        fi
        return
    fi
    
    log_info "Installing pre-built Paddle Inference..."
    
    # Check if GPU version was installed to determine which pre-built version to use
    local with_gpu="OFF"
    local paddle_inference_url=""
    
    if python -c "import paddle; exit(0 if paddle.device.cuda.device_count() > 0 else 1)" 2>/dev/null; then
        with_gpu="ON"
        log_info "GPU detected in PaddlePaddle, downloading GPU version of Paddle Inference"
        paddle_inference_url="https://paddle-inference-lib.bj.bcebos.com/3.0.0/cxx_c/Linux/GPU/x86-64_gcc11.2_avx_mkl_cuda12.6_cudnn9.5.1-trt10.5.0.18/paddle_inference.tgz"
    else
        log_info "No GPU detected, downloading CPU-only version of Paddle Inference"
        paddle_inference_url="https://paddle-inference-lib.bj.bcebos.com/3.0.0/cxx_c/Linux/CPU/gcc8.2_avx_mkl/paddle_inference.tgz"
    fi
    
    # Download pre-built Paddle Inference if not exists
    if [ ! -f paddle_inference.tgz ]; then
        log_info "Downloading pre-built Paddle Inference..."
        wget "$paddle_inference_url" -O paddle_inference.tgz
    else
        log_info "Pre-built Paddle Inference archive already exists, using it..."
    fi
    
    # Extract if not already extracted
    if [ ! -d paddle_inference ]; then
        log_info "Extracting Paddle Inference..."
        tar -xzf paddle_inference.tgz
    else
        log_info "Paddle Inference already extracted"
    fi
    
    # Create symbolic link for compatibility (some build scripts expect 'Paddle' directory)
    if [ ! -L Paddle ] && [ ! -d Paddle ]; then
        ln -s paddle_inference Paddle
        log_info "Created symbolic link Paddle -> paddle_inference for compatibility"
    fi
    
    # Verify extraction
    if [ -d paddle_inference/paddle/include ] && [ -d paddle_inference/paddle/lib ]; then
        log_success "Pre-built Paddle Inference installed successfully"
        echo "  Include directory: $(pwd)/paddle_inference/paddle/include"
        echo "  Library directory: $(pwd)/paddle_inference/paddle/lib"
        
        # List available libraries
        local lib_count=$(ls -1 paddle_inference/paddle/lib/*.so* paddle_inference/paddle/lib/*.a 2>/dev/null | wc -l)
        echo "  Found $lib_count library files"
        
        if [ "$with_gpu" = "ON" ]; then
            echo "  GPU support: Enabled (CUDA 12.6, cuDNN 9.5.1, TensorRT 10.5.0.18)"
        else
            echo "  GPU support: Disabled (CPU-only version)"
        fi
    else
        log_error "Paddle Inference extraction failed or incomplete"
        exit 1
    fi
}

# Download models
download_models() {
    log_info "Downloading pre-trained models..."
    
    # Use shared models directory at project level
    mkdir -p "$MODELS_DIR"
    cd "$MODELS_DIR"
    
    # Model URLs
    local models=(
        "https://paddle-model-ecology.bj.bcebos.com/paddlex/official_inference_model/paddle3.0.0/PP-LCNet_x1_0_doc_ori_infer.tar"
        "https://paddle-model-ecology.bj.bcebos.com/paddlex/official_inference_model/paddle3.0.0/UVDoc_infer.tar"
        "https://paddle-model-ecology.bj.bcebos.com/paddlex/official_inference_model/paddle3.0.0/PP-LCNet_x1_0_textline_ori_infer.tar"
        "https://paddle-model-ecology.bj.bcebos.com/paddlex/official_inference_model/paddle3.0.0/PP-OCRv5_server_det_infer.tar"
        "https://paddle-model-ecology.bj.bcebos.com/paddlex/official_inference_model/paddle3.0.0/PP-OCRv5_server_rec_infer.tar"
    )
    
    # Download each model
    for model_url in "${models[@]}"; do
        local model_name=$(basename "$model_url")
        local extract_dir=$(basename "$model_name" .tar)
        
        # Check if model is already extracted
        if [ -d "$extract_dir" ]; then
            log_warning "$extract_dir already extracted, skipping download"
            continue
        fi
        
        # Download if tar file doesn't exist
        if [ ! -f "$model_name" ]; then
            log_info "Downloading $model_name..."
            wget "$model_url"
        else
            log_warning "$model_name already exists, using existing file"
        fi
    done
    
    # Extract all models
    for model in *.tar; do
        if [ -f "$model" ]; then
            local extract_dir=$(basename "$model" .tar)
            if [ ! -d "$extract_dir" ]; then
                log_info "Extracting $model..."
                tar -xf "$model"
            fi
        fi
    done
    
    # Clean up tar files
    rm -f *.tar
    
    # Create symlink from cpp_infer/models to shared models directory
    local cpp_models_dir="$WORK_DIR/deploy/cpp_infer/models"
    if [ ! -L "$cpp_models_dir" ] && [ ! -d "$cpp_models_dir" ]; then
        log_info "Creating symlink from cpp_infer/models to shared models directory"
        ln -sf "$MODELS_DIR" "$cpp_models_dir"
    elif [ -d "$cpp_models_dir" ] && [ ! -L "$cpp_models_dir" ]; then
        log_warning "Found existing models directory in cpp_infer, backing up and creating symlink"
        mv "$cpp_models_dir" "${cpp_models_dir}.backup"
        ln -sf "$MODELS_DIR" "$cpp_models_dir"
    fi
    
    log_success "All models downloaded and extracted to shared directory"
    echo "  Models directory: $MODELS_DIR"
    echo "  Symlink created: $cpp_models_dir -> $MODELS_DIR"
}

# Build PP-OCRv5 demo
build_demo() {
    log_info "Building PP-OCRv5 demo..."
    
    cd "$WORK_DIR/deploy/cpp_infer"
    
    # Check if demo is already built
    if [ -f "build/ppocr" ]; then
        log_success "PP-OCRv5 demo is already built, skipping compilation"
        echo "  Executable: $(pwd)/build/ppocr"
        echo "  Build time: $(stat -c %y build/ppocr 2>/dev/null || echo 'Unknown')"
        return
    fi
    
    # Set the correct paths based on our installation (avoid hardcoded paths)
    local OPENCV_DIR="$(pwd)/third_party/opencv-4.7.0/opencv4"
    local LIB_DIR="$(pwd)/third_party/paddle_inference"
    local WITH_GPU="OFF"
    local CUDA_LIB_DIR=""
    local CUDNN_LIB_DIR=""
    
    # Check if we have GPU support
    if python -c "import paddle; exit(0 if paddle.device.cuda.device_count() > 0 else 1)" 2>/dev/null; then
        WITH_GPU="ON"
        log_info "Building with GPU support enabled"
        
        # Auto-detect CUDA and CUDNN library paths
        # First try conda environment paths
        if [ -n "$CONDA_PREFIX" ] && [ -d "$CONDA_PREFIX/lib" ]; then
            CUDA_LIB_DIR="$CONDA_PREFIX/lib"
            CUDNN_LIB_DIR="$CONDA_PREFIX/lib"
            log_info "Using conda environment libraries: $CONDA_PREFIX/lib"
        # Fallback to system CUDA installation
        elif [ -d "/usr/local/cuda/lib64" ]; then
            CUDA_LIB_DIR="/usr/local/cuda/lib64"
            CUDNN_LIB_DIR="/usr/local/cuda/lib64"
            log_info "Using system CUDA libraries: /usr/local/cuda/lib64"
        else
            log_warning "CUDA libraries not found, falling back to CPU-only build"
            WITH_GPU="OFF"
        fi
    else
        log_info "Building with CPU-only support"
    fi
    
    log_info "Using OpenCV directory: $OPENCV_DIR"
    log_info "Using Paddle Inference directory: $LIB_DIR"
    
    # Create build directory
    local BUILD_DIR="build"
    rm -rf ${BUILD_DIR}
    mkdir ${BUILD_DIR}
    cd ${BUILD_DIR}
    
    # Run CMake with correct paths (matching build.sh configuration)
    log_info "Running CMake configuration..."
    
    if [ "$WITH_GPU" = "ON" ]; then
        # GPU build with CUDA and CUDNN paths
        cmake .. \
            -DPADDLE_LIB=${LIB_DIR} \
            -DWITH_MKL=ON \
            -DWITH_GPU=${WITH_GPU} \
            -DWITH_STATIC_LIB=OFF \
            -DWITH_TENSORRT=OFF \
            -DOPENCV_DIR=${OPENCV_DIR} \
            -DCUDNN_LIB=${CUDNN_LIB_DIR} \
            -DCUDA_LIB=${CUDA_LIB_DIR} \
            -DUSE_FREETYPE=OFF
    else
        # CPU-only build
        cmake .. \
            -DPADDLE_LIB=${LIB_DIR} \
            -DWITH_MKL=ON \
            -DWITH_GPU=${WITH_GPU} \
            -DWITH_STATIC_LIB=OFF \
            -DWITH_TENSORRT=OFF \
            -DOPENCV_DIR=${OPENCV_DIR} \
            -DUSE_FREETYPE=OFF
    fi
    
    # Build the project
    log_info "Building project..."
    make -j$(nproc)
    
    # Go back to cpp_infer directory
    cd ../
    
    # Verify build
    if [ -f build/ppocr ]; then
        log_success "PP-OCRv5 demo built successfully"
        echo "  Executable: $(pwd)/build/ppocr"
        echo "  Size: $(du -h build/ppocr | cut -f1)"
    else
        log_error "Failed to build PP-OCRv5 demo"
        exit 1
    fi
}

# Run demo test
run_demo() {
    log_info "Running PP-OCRv5 demo test..."
    
    cd "$WORK_DIR/deploy/cpp_infer"
    
    # Activate conda environment first
    eval "$(conda shell.bash hook)"
    conda activate "$CONDA_ENV"
    
    # Set comprehensive library paths (following startup.sh pattern)
    export LD_LIBRARY_PATH="$CONDA_PREFIX/lib:$LD_LIBRARY_PATH"
    
    # Add PaddlePaddle library paths
    local PADDLE_LIB_PATH="$(pwd)/third_party/paddle_inference"
    export LD_LIBRARY_PATH="$PADDLE_LIB_PATH/paddle/lib:$LD_LIBRARY_PATH"
    export LD_LIBRARY_PATH="$PADDLE_LIB_PATH/third_party/install/mklml/lib:$LD_LIBRARY_PATH"
    export LD_LIBRARY_PATH="$PADDLE_LIB_PATH/third_party/install/onednn/lib:$LD_LIBRARY_PATH"
    
    log_info "Runtime environment configured:"
    log_info "  CONDA_DEFAULT_ENV: $CONDA_DEFAULT_ENV"
    log_info "  Library path: $LD_LIBRARY_PATH"
    
    # Download test image
    local test_image="general_ocr_002.png"
    local test_image_url="https://paddle-model-ecology.bj.bcebos.com/paddlex/imgs/demo_image/general_ocr_002.png"
    
    if [ ! -f "$test_image" ]; then
        log_info "Downloading test image..."
        wget "$test_image_url" -O "$test_image"
    else
        log_info "Test image already exists, using existing file"
    fi
    
    # Create output directory
    mkdir -p output
    
    # Run OCR demo
    log_info "Running OCR on test image: $test_image"
    ./build/ppocr ocr \
      --input "$test_image" \
      --save_path ./output/ \
      --doc_orientation_classify_model_dir models/PP-LCNet_x1_0_doc_ori_infer \
      --doc_unwarping_model_dir models/UVDoc_infer \
      --textline_orientation_model_dir models/PP-LCNet_x1_0_textline_ori_infer \
      --text_detection_model_dir models/PP-OCRv5_server_det_infer \
      --text_recognition_model_dir models/PP-OCRv5_server_rec_infer \
      --device cpu
    
    # Check if output was generated
    if [ -f "output/${test_image%.*}_ocr_res_img.png" ]; then
        log_success "OCR demo completed successfully!"
        echo "  Input image: $(pwd)/$test_image"
        echo "  Output image: $(pwd)/output/${test_image%.*}_ocr_res_img.png"
        echo "  Output JSON: $(pwd)/output/${test_image%.*}_res.json"
        echo "  Doc preprocessor: $(pwd)/output/${test_image%.*}_doc_preprocessor_res.png"
    else
        log_error "OCR demo failed - no output generated"
        exit 1
    fi
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..."
    
    echo "=== Installation Verification ==="
        
    # Check PaddleOCR
    if python -c "import paddleocr; print('PaddleOCR: OK')" 2>/dev/null; then
        echo "✓ PaddleOCR: OK"
    else
        echo "✗ PaddleOCR: Failed"
    fi
    
    # Check OpenCV build
    if [ -d "$WORK_DIR/deploy/cpp_infer/third_party/opencv-4.7.0/opencv4" ]; then
        echo "✓ OpenCV: Built"
    else
        echo "✗ OpenCV: Not built"
    fi
    
    # Check Paddle Inference
    if [ -d "$WORK_DIR/deploy/cpp_infer/third_party/paddle_inference" ]; then
        echo "✓ Paddle Inference: Installed (pre-built)"
    elif [ -d "$WORK_DIR/deploy/cpp_infer/third_party/Paddle/build/paddle_inference_install_dir" ]; then
        echo "✓ Paddle Inference: Built from source"
    else
        echo "✗ Paddle Inference: Not found"
    fi
    
    # Check demo executable
    if [ -f "$WORK_DIR/deploy/cpp_infer/build/ppocr" ]; then
        echo "✓ PP-OCRv5 Demo: Built"
    else
        echo "✗ PP-OCRv5 Demo: Not built"
    fi
    
    # Check models
    local model_count=$(ls -1 "$WORK_DIR/deploy/cpp_infer/models" 2>/dev/null | grep -v "\.tar$" | wc -l)
    echo "✓ Models: $model_count downloaded"
    
    echo
    echo "Working directory: $WORK_DIR"
    echo "Demo executable: $WORK_DIR/deploy/cpp_infer/build/ppocr"
    echo "Test results: $WORK_DIR/deploy/cpp_infer/output/"
    
    log_success "Installation verification completed"
}

# Main execution
main() {
    echo "====================================="
    echo "  PP-OCRv5 Dependencies Installation"
    echo "====================================="
    echo
    
    echo "This script will:"
    echo "1. Install PaddlePaddle and PaddleOCR"
    echo "2. Build OpenCV and Paddle Inference"
    echo "3. Download pre-trained models"
    echo "4. Build PP-OCRv5 demo"
    echo
    echo "Working directory: $WORK_DIR"
    echo "Estimated time: 2-3 hours"
    echo
    
    read -p "Continue with installation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled by user"
        exit 0
    fi
    
    setup_conda_env
    install_paddlepaddle
    install_paddleocr
    build_opencv
    build_paddle_inference
    download_models
    build_demo
    run_demo
    verify_installation
    
    echo
    log_success "Dependencies installation completed!"
    echo
}

# Run main function
main "$@"