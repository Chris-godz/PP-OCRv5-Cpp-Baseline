#!/bin/bash

# =============================================================================
# Benchmark.cpp Compilation and Execution Script
# =============================================================================

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build"
LOG_DIR="$PROJECT_ROOT/logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Create necessary directories
mkdir -p "$LOG_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$PROJECT_ROOT/output"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_DIR/benchmark_compilation_${TIMESTAMP}.log"
}

# Error handling - only exit on critical errors, not processing failures
set -e
trap 'log "ERROR: Script failed at line $LINENO"' ERR

log "=== Starting Benchmark.cpp Compilation ==="
log "Project Root: $PROJECT_ROOT"
log "Build Dir: $BUILD_DIR"

# =============================================================================
# Environment Setup
# =============================================================================

# Activate conda environment
log "Activating conda environment: deepx"
eval "$(conda shell.bash hook)"
conda activate deepx

# Verify conda environment
if [[ "$CONDA_DEFAULT_ENV" != "deepx" ]]; then
    log "ERROR: Failed to activate deepx environment"
    exit 1
fi
log "✓ Conda environment activated: $CONDA_DEFAULT_ENV"

# Ensure required Python packages are installed
log "Checking required Python packages..."
if ! python -c "import jiwer" 2>/dev/null; then
    log "Installing jiwer package for accuracy calculation..."
    pip install jiwer
fi
log "✓ Required Python packages verified"

# Set library paths for runtime
export LD_LIBRARY_PATH="$CONDA_PREFIX/lib:$LD_LIBRARY_PATH"
log "✓ Library paths configured: $LD_LIBRARY_PATH"

# Verify required libraries exist
REQUIRED_LIBS=("libmklml_intel.so" "libiomp5.so" "libcudart.so" "libcudnn.so")
for lib in "${REQUIRED_LIBS[@]}"; do
    if find "$CONDA_PREFIX/lib" -name "$lib*" &>/dev/null; then
        log "✓ Found library: $lib"
    else
        log "⚠ Warning: Library not found: $lib"
    fi
done

# =============================================================================
# Build Process
# =============================================================================

cd "$PROJECT_ROOT"

# Check if we need to build or rebuild
NEED_BUILD=false
FORCE_REBUILD="${FORCE_REBUILD:-false}"

if [[ "$FORCE_REBUILD" == "true" ]]; then
    log "Force rebuild requested"
    NEED_BUILD=true
elif [[ ! -d "$BUILD_DIR" ]]; then
    log "Build directory does not exist"
    NEED_BUILD=true
elif [[ ! -f "$BUILD_DIR/Benchmark" ]]; then
    log "Benchmark executable not found"
    NEED_BUILD=true
elif [[ "$BUILD_DIR/Benchmark" -ot "src/Benchmark.cpp" ]]; then
    log "Source code is newer than executable"
    NEED_BUILD=true
elif [[ "$BUILD_DIR/Benchmark" -ot "CMakeLists.txt" ]]; then
    log "CMakeLists.txt is newer than executable"
    NEED_BUILD=true
else
    log "✓ Benchmark executable is up to date"
fi

if [[ "$NEED_BUILD" == "true" ]]; then
    # Clean previous build if force rebuild
    if [[ "$FORCE_REBUILD" == "true" && -d "$BUILD_DIR" ]]; then
        log "Cleaning previous build directory..."
        rm -rf "$BUILD_DIR"
    fi

    # Create build directory
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    log "Starting CMake configuration..."

    # Properly isolate conda environment during build to avoid libcurl conflicts
    # Save conda environment variables
    CONDA_BACKUP_PREFIX="$CONDA_PREFIX"
    CONDA_BACKUP_DEFAULT_ENV="$CONDA_DEFAULT_ENV"
    CONDA_BACKUP_LD_LIBRARY_PATH="$LD_LIBRARY_PATH"
    CONDA_BACKUP_PATH="$PATH"
    
    # Completely isolate from conda during cmake to avoid library conflicts
    log "Temporarily isolating conda environment for cmake..."
    unset CONDA_PREFIX
    unset CONDA_DEFAULT_ENV
    unset LD_LIBRARY_PATH
    export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    
    log "Using system cmake with clean environment..."

    # Configure with cmake using system libraries only
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DWITH_MKL=ON \
        -DWITH_GPU=ON \
        -DWITH_STATIC_LIB=OFF \
        2>&1 | tee -a "$LOG_DIR/cmake_${TIMESTAMP}.log"

    CMAKE_EXIT_CODE=${PIPESTATUS[0]}

    # Restore conda environment immediately after cmake
    log "Restoring conda environment..."
    export CONDA_PREFIX="$CONDA_BACKUP_PREFIX"
    export CONDA_DEFAULT_ENV="$CONDA_BACKUP_DEFAULT_ENV" 
    export LD_LIBRARY_PATH="$CONDA_BACKUP_LD_LIBRARY_PATH"
    export PATH="$CONDA_BACKUP_PATH"

    if [[ $CMAKE_EXIT_CODE -ne 0 ]]; then
        log "ERROR: CMake configuration failed"
        exit 1
    fi
    log "✓ CMake configuration completed"

    # Build the project using make with isolated environment
    log "Starting compilation with isolated environment..."
    
    # Temporarily isolate conda again for make to avoid libcurl warnings
    unset CONDA_PREFIX
    unset CONDA_DEFAULT_ENV
    unset LD_LIBRARY_PATH
    export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    
    make -j$(nproc) 2>&1 | tee -a "$LOG_DIR/make_${TIMESTAMP}.log"
    MAKE_EXIT_CODE=${PIPESTATUS[0]}
    
    # Restore conda environment after make
    export CONDA_PREFIX="$CONDA_BACKUP_PREFIX"
    export CONDA_DEFAULT_ENV="$CONDA_BACKUP_DEFAULT_ENV" 
    export LD_LIBRARY_PATH="$CONDA_BACKUP_LD_LIBRARY_PATH"
    export PATH="$CONDA_BACKUP_PATH"

    if [[ $MAKE_EXIT_CODE -ne 0 ]]; then
        log "ERROR: Compilation failed"
        exit 1
    fi
    log "✓ Compilation completed successfully"
else
    log "✓ Skipping build - executable is up to date"
    cd "$BUILD_DIR"
fi
log "✓ Compilation completed successfully"

# Verify executable was created
if [[ -f "$BUILD_DIR/Benchmark" ]]; then
    log "✓ Benchmark executable created successfully"
    ls -la "$BUILD_DIR/Benchmark"
else
    log "ERROR: Benchmark executable not found"
    exit 1
fi

# =============================================================================
# Dataset and Benchmark Functions
# =============================================================================

# Function to verify custom dataset
verify_custom_dataset() {
    log "=== Verifying Custom Dataset ==="
    
    local images_dir="$PROJECT_ROOT/images"
    
    if [[ ! -d "$images_dir" ]]; then
        log "ERROR: Images directory not found: $images_dir"
        return 1
    fi
    
    # Check for labels.json file
    if [[ ! -f "$images_dir/labels.json" ]]; then
        log "ERROR: Labels file not found: $images_dir/labels.json"
        log "Please ensure you have labels.json file in your images directory"
        return 1
    fi
    
    # Count image files
    local img_count=$(find "$images_dir" -maxdepth 1 -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" | wc -l)
    
    if [[ $img_count -eq 0 ]]; then
        log "ERROR: No image files found in $images_dir"
        return 1
    fi
    
    log "✓ Custom dataset verified: $img_count images found"
    log "✓ Ground truth labels file: $images_dir/labels.json"
    
    cd "$PROJECT_ROOT"
}

# Function to calculate accuracy metrics
calculate_accuracy() {
    local results_dir="$1"
    local ground_truth_file="$2"
    
    log "=== Calculating OCR Accuracy Metrics ==="
    
    # Check if Python script exists
    if [[ ! -f "$PROJECT_ROOT/scripts/calculate_accuracy.py" ]]; then
        log "ERROR: Accuracy calculation script not found"
        return 1
    fi
    
    # Check if ground truth file exists
    if [[ ! -f "$ground_truth_file" ]]; then
        log "ERROR: Ground truth file not found: $ground_truth_file"
        return 1
    fi
    
    # Run accuracy calculation
    log "Running accuracy calculation..."
    log "Ground truth: $ground_truth_file"
    log "Output directory: $PROJECT_ROOT/output"
    
    cd "$PROJECT_ROOT"
    
    # This script now aggregates JSON outputs from the C++ benchmark run
    local all_json_outputs=$(grep "ACCURACY_JSON:" "$results_dir/benchmark_output.log" | sed 's/ACCURACY_JSON://')
    
    if [[ -z "$all_json_outputs" ]]; then
        log "ERROR: No ACCURACY_JSON outputs found in benchmark log."
        return 1
    fi
    
    # Combine all JSON objects into a single JSON array
    local combined_json="["
    while IFS= read -r line; do
        combined_json+="$line,"
    done <<< "$all_json_outputs"
    # Remove trailing comma and close bracket
    combined_json="${combined_json%,}]"
    
    # Calculate overall average character accuracy
    local avg_char_acc=$(echo "$combined_json" | python -c "import sys, json; data=json.load(sys.stdin); total_acc=sum(item.get('character_accuracy', 0) for item in data); count=len(data) if len(data) > 0 else 1; print(f'{total_acc/count*100:.2f}')" 2>/dev/null || echo "0.00")
    
    log "✓ Overall Average Character Accuracy: ${avg_char_acc}%"
    
    # Save a simplified JSON for the markdown table
    echo "{\"character_accuracy\": ${avg_char_acc}}" > "$results_dir/accuracy_metrics.json"
    log "✓ Accuracy metrics saved to: $results_dir/accuracy_metrics.json"
    
    return 0
}

# Function to generate a simplified Markdown results table
generate_markdown_table() {
    local results_dir="$1"
    
    log "=== Generating Detailed Markdown Results Table ==="
    
    local markdown_file="$results_dir/benchmark_summary.md"
    
    # Extract all PER_IMAGE_RESULT lines from the log
    local all_results=$(grep "PER_IMAGE_RESULT:" "$results_dir/benchmark_output.log" | sed 's/PER_IMAGE_RESULT://')
    
    if [[ -z "$all_results" ]]; then
        log "ERROR: No PER_IMAGE_RESULT outputs found in benchmark log."
        echo "# Benchmark Summary" > "$markdown_file"
        echo "" >> "$markdown_file"
        echo "**ERROR: No per-image results found to generate a table.**" >> "$markdown_file"
        return 1
    fi

    # Create the markdown table header with CPS column
    cat > "$markdown_file" << EOF
# Benchmark Summary

| Filename | Inference Time (ms) | FPS(image/s) | CPS (chars/s) | Accuracy (%) |
|---|---|---|---|---|
EOF

    # Process each JSON line and append to the table
    local total_acc=0
    local total_fps=0
    local total_cps=0
    local image_count=0

    while IFS= read -r line; do
        local filename=$(echo "$line" | python -c "import sys, json; print(json.load(sys.stdin).get('filename', 'N/A'))" 2>/dev/null || echo "Parse Error")
        local inference_ms=$(echo "$line" | python -c "import sys, json; print(f\"{json.load(sys.stdin).get('inference_ms', 0.0):.2f}\")" 2>/dev/null || echo "0.00")
        local fps=$(echo "$line" | python -c "import sys, json; print(f\"{json.load(sys.stdin).get('fps', 0.0):.2f}\")" 2>/dev/null || echo "0.00")
        local chars_per_second=$(echo "$line" | python -c "import sys, json; print(f\"{json.load(sys.stdin).get('chars_per_second', 0.0):.2f}\")" 2>/dev/null || echo "0.00")
        local accuracy=$(echo "$line" | python -c "import sys, json; print(f\"{json.load(sys.stdin).get('accuracy', 0.0) * 100:.2f}\")" 2>/dev/null || echo "0.00")
        
        # Append the row to the markdown file with CPS column
        echo "| \`$filename\` | $inference_ms | $fps | **$chars_per_second** | **$accuracy** |" >> "$markdown_file"

        # Sum for averages
        total_acc=$(echo "$total_acc + $accuracy" | bc)
        total_fps=$(echo "$total_fps + $fps" | bc)
        total_cps=$(echo "$total_cps + $chars_per_second" | bc)
        image_count=$((image_count + 1))

    done <<< "$all_results"

    # Calculate averages
    local avg_acc=0
    local avg_fps=0
    local avg_cps=0
    if [[ $image_count -gt 0 ]]; then
        avg_acc=$(echo "scale=2; $total_acc / $image_count" | bc)
        avg_fps=$(echo "scale=2; $total_fps / $image_count" | bc)
        avg_cps=$(echo "scale=2; $total_cps / $image_count" | bc)
    fi

    # Add summary row to the table with CPS average
    echo "| **Average** | - | **$avg_fps** | **$avg_cps** | **$avg_acc** |" >> "$markdown_file"

    log "✓ Detailed Markdown results table generated: $markdown_file"
    
    # Also display the simplified table in the console
    echo ""
    echo "========================================================================"
    echo "                    BENCHMARK SUMMARY"
    echo "========================================================================"
    cat "$markdown_file"
    echo "========================================================================"
}

# Function to run batch benchmark on images folder
run_batch_benchmark() {
    log "=== Running Batch Benchmark ==="
    
    cd "$PROJECT_ROOT"
    
    # Set up proper runtime environment
    export LD_LIBRARY_PATH="$CONDA_PREFIX/lib:$LD_LIBRARY_PATH"
    
    # Add PaddlePaddle library paths
    PADDLE_LIB_PATH="$PROJECT_ROOT/PaddleOCR/deploy/cpp_infer/third_party/paddle_inference"
    export LD_LIBRARY_PATH="$PADDLE_LIB_PATH/paddle/lib:$LD_LIBRARY_PATH"
    export LD_LIBRARY_PATH="$PADDLE_LIB_PATH/third_party/install/mklml/lib:$LD_LIBRARY_PATH"
    export LD_LIBRARY_PATH="$PADDLE_LIB_PATH/third_party/install/onednn/lib:$LD_LIBRARY_PATH"
    
    # Verify custom dataset
    local images_dir="$PROJECT_ROOT/images"
    if ! verify_custom_dataset; then
        log "ERROR: Custom dataset verification failed"
        log "Please ensure you have:"
        log "  1. Images directory: $images_dir/"
        log "  2. Image files (*.png, *.jpg, *.jpeg) in the images directory"
        log "  3. Ground truth labels: $images_dir/labels.json"
        return 1
    fi
    
    # Create results directory
    local results_dir="$PROJECT_ROOT/output/batch_results_${TIMESTAMP}"
    mkdir -p "$results_dir"
    
    log "Starting batch benchmark processing..."
    log "Results will be saved to: $results_dir"
    log "Using images directory: $images_dir"
    
    # Run the new batch-enabled Benchmark executable
    # It will handle all the image processing internally with proper timing
    local benchmark_start=$(date +%s.%N)
    
    log "=== Starting Benchmark Executable ==="
    log "Command: $BUILD_DIR/Benchmark $images_dir"
    log "Environment variables:"
    log "  LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
    log "  CONDA_DEFAULT_ENV: $CONDA_DEFAULT_ENV"
    log ""
    log "=== Starting Benchmark Processing ==="
    echo "Benchmark started - showing progress only. Full details saved to: $results_dir/benchmark_output.log"
    echo "========================================================================"
    
    # Run benchmark in background and monitor progress
    "$BUILD_DIR/Benchmark" "$images_dir" > "$results_dir/benchmark_output.log" 2>&1 &
    local benchmark_pid=$!
    
    # Monitor progress by tailing the log file for specific progress lines
    (
        tail -f "$results_dir/benchmark_output.log" 2>/dev/null | while read line; do
            # Show only important progress lines
            case "$line" in
                *"[SUCCESS] Found"*"images to process"*)
                    echo "  $line"
                    ;;
                *"[SUCCESS] PaddleOCR initialized successfully"*)
                    echo "  $line"
                    ;;
                *"[PROCESS "*)
                    echo "  $line"
                    ;;
                *"[SUCCESS] Image"*"processed successfully"*)
                    echo "  $line"
                    ;;
                *"[PROGRESS]"*)
                    echo "  $line"
                    ;;
                *"[ERROR]"*)
                    echo "  $line"
                    ;;
                *"BENCHMARK RESULTS SUMMARY"*)
                    echo "  === Final Results ==="
                    ;;
                *"Total images processed:"*)
                    echo "  $line"
                    ;;
                *"Success rate:"*)
                    echo "  $line"
                    ;;
                *"Average FPS"*)
                    echo "  $line"
                    ;;
            esac
        done
    ) &
    local monitor_pid=$!
    
    # Wait for benchmark to complete
    if wait $benchmark_pid; then
        # Stop the monitoring process
        kill $monitor_pid 2>/dev/null || true
        
        local benchmark_end=$(date +%s.%N)
        local benchmark_duration=$(echo "$benchmark_end - $benchmark_start" | bc -l)
        
        echo "========================================================================"
        log "✓ Batch benchmark completed successfully in ${benchmark_duration}s"
        
        # Extract metrics from the benchmark output
        log "=== Extracting Performance Metrics ==="
        local init_time=$(grep "TIMING_INFO:INIT:" "$results_dir/benchmark_output.log" | cut -d: -f3 | sed 's/ms//' || echo "0")
        local total_inference=$(grep "TIMING_INFO:TOTAL_INFERENCE:" "$results_dir/benchmark_output.log" | cut -d: -f3 | sed 's/ms//' || echo "0")
        local avg_inference=$(grep "TIMING_INFO:AVG_INFERENCE:" "$results_dir/benchmark_output.log" | cut -d: -f3 | sed 's/ms//' || echo "0")
        local avg_fps=$(grep "TIMING_INFO:AVG_FPS:" "$results_dir/benchmark_output.log" | cut -d: -f3 || echo "0")
        local batch_fps=$(grep "TIMING_INFO:BATCH_FPS:" "$results_dir/benchmark_output.log" | cut -d: -f3 || echo "0")
        local success_rate=$(grep "TIMING_INFO:SUCCESS_RATE:" "$results_dir/benchmark_output.log" | cut -d: -f3 | sed 's/%//' || echo "0")
        
        log "Extracted metrics:"
        log "  - Initialization time: ${init_time}ms"
        log "  - Total inference time: ${total_inference}ms"
        log "  - Average inference time: ${avg_inference}ms"
        log "  - Average FPS: ${avg_fps}"
        log "  - Batch FPS: ${batch_fps}"
        log "  - Success rate: ${success_rate}%"
        
        # Create summary with extracted metrics
        cat > "$results_dir/summary.txt" << EOF
=== Efficient Batch Benchmark Results ===
Start Time: $(date -Iseconds)
Total benchmark duration: ${benchmark_duration}s
Initialization time: ${init_time}ms
Total inference time: ${total_inference}ms
Average inference per image: ${avg_inference}ms
Average FPS (per image): ${avg_fps}
Batch throughput FPS: ${batch_fps}
Success rate: ${success_rate}%

Performance Improvement:
- Single initialization instead of per-image initialization
- Pure inference timing (excluding model loading)
- More accurate FPS measurements
- Reduced overhead from shell script loops
EOF
        
        log "=== Efficient Batch Benchmark Results ==="
        log "Total benchmark duration: ${benchmark_duration}s"
        log "Initialization time: ${init_time}ms"
        log "Total inference time: ${total_inference}ms"
        log "Average inference per image: ${avg_inference}ms"
        log "Average FPS (per image): ${avg_fps}"
        log "Batch throughput FPS: ${batch_fps}"
        log "Success rate: ${success_rate}%"
        log "Results saved to: $results_dir"
        
        # Calculate accuracy metrics
        local ground_truth_file="$PROJECT_ROOT/images/labels.json"
        if [[ -f "$ground_truth_file" ]]; then
            if calculate_accuracy "$results_dir" "$ground_truth_file"; then
                log "✓ Accuracy calculation completed"
            else
                log "⚠ Accuracy calculation failed, continuing with performance metrics only"
            fi
        else
            log "⚠ Ground truth file not found: $ground_truth_file"
            log "⚠ Skipping accuracy calculation"
        fi
        
        # Generate comprehensive Markdown results table
        generate_markdown_table "$results_dir" "$benchmark_duration" "$init_time" "$total_inference" \
                               "$avg_inference" "$avg_fps" "$batch_fps" "$success_rate"
        
        # Save summary to file for backward compatibility
        echo "$success_rate" > "$LOG_DIR/accuracy_${TIMESTAMP}.txt"
        
        # Save detailed summary
        cat > "$results_dir/summary.txt" << EOF
Benchmark Summary (${TIMESTAMP})
================================
Total Images: 50
Processing Duration: ${benchmark_duration}s
Initialization Time: ${init_time}ms
Total Inference Time: ${total_inference}ms
Average Inference per Image: ${avg_inference}ms
Average FPS: ${avg_fps}
Batch FPS: ${batch_fps}
Success Rate: ${success_rate}%

Files Generated:
- Performance Summary: $results_dir/summary.txt
- Markdown Results: $results_dir/benchmark_summary.md
- Accuracy Metrics: $results_dir/accuracy_metrics.json (if available)
- Raw Benchmark Log: $results_dir/benchmark_output.log
EOF
        
        log "=== Final Results Summary ==="
        log "Benchmark completed successfully - full details in: $results_dir/benchmark_output.log"
        log "📊 Markdown Report: $results_dir/benchmark_summary.md"
        log "📋 Summary: $results_dir/summary.txt"
        
    else
        # Stop the monitoring process
        kill $monitor_pid 2>/dev/null || true
        
        echo "========================================================================"
        log "ERROR: Batch benchmark failed"
        log "Error details in: $results_dir/benchmark_output.log"
        log "Last few lines of error:"
        tail -10 "$results_dir/benchmark_output.log" 2>/dev/null || true
        return 1
    fi
}

# =============================================================================
# Main Script Logic
# =============================================================================

# Parse command line arguments
COMMAND="${1:-benchmark}"

case "$COMMAND" in
    "build")
        log "Build only mode - compilation completed"
        ;;
    "benchmark"|"")
        log "Benchmark mode - running batch evaluation on images folder"
        run_batch_benchmark
        ;;
    "setup-dataset")
        log "Dataset verification mode"
        verify_custom_dataset
        ;;
    "rebuild")
        log "Force rebuild mode"
        FORCE_REBUILD=true
        run_batch_benchmark
        ;;
    "clean")
        log "Cleaning build directory..."
        rm -rf "$BUILD_DIR"
        rm -rf "$PROJECT_ROOT/output"
        log "✓ Clean completed"
        ;;
    *)
        cat << EOF
Usage: $0 [COMMAND]

Commands:
  benchmark (default)     - Run comprehensive benchmark on images folder dataset
  build                   - Only build Benchmark.cpp (if needed)
  setup-dataset           - Verify custom dataset in images folder
  rebuild                 - Force rebuild and run benchmark
  clean                   - Clean build directory

Examples:
  $0                      # Run benchmark on images folder
  $0 benchmark           # Run benchmark on images folder  
  $0 build               # Build only (if needed)
  $0 setup-dataset       # Verify custom dataset
  $0 rebuild             # Force rebuild and run benchmark
  $0 clean               # Clean build

Dataset and Evaluation Features:
  - Uses your custom dataset from images/ folder
  - Processes all images in images/ folder (supports .jpg, .png, .jpeg)
  - Calculates FPS (Frames Per Second) for each image
  - Measures accuracy and success rate using your labels.json
  - Generates comprehensive JSON results
  - Creates visualization outputs for each processed image
  - Supports both CPU and GPU benchmarking

Results are saved to: output/batch_results_TIMESTAMP/
  - benchmark_results.json: Complete results with metrics
  - Individual image outputs in separate folders
  - Processing logs for debugging

Environment variables:
  FORCE_REBUILD=true     # Force a complete rebuild
EOF
        exit 1
        ;;
esac

log "=== Script Complete ==="
log "Logs saved to: $LOG_DIR/"