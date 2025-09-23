# PP-OCRv5 C++ Benchmark

[中文 README](README_CN.md)

🚀 PP-OCRv5 C++ benchmarking toolchain with GPU acceleration and comprehensive performance evaluation.

## 📈 Performance Results

### Custom Dataset Overview

This project uses a diverse custom Chinese dataset for benchmarking. The dataset consists of various real-world scenarios including street signs, handwritten text, exam papers, textbooks, and newspapers, providing comprehensive coverage of different text recognition challenges with detailed annotations including text content and bounding box coordinates.

**Test Configuration**:
- Dataset: Custom Chinese document dataset (20 images)
- Data Format: PNG images with JSON annotations containing text and bbox coordinates
- Model: PP-OCRv5 Server series full pipeline (high-precision configuration)
  - Document orientation classification: PP-LCNet_x1_0_doc_ori
  - Document rectification: UVDoc
  - Text line orientation classification: PP-LCNet_x1_0_textline_ori
  - Text detection: PP-OCRv5_server_det
  - Text recognition: PP-OCRv5_server_rec
- Hardware configuration 1:
  - GPU: NVIDIA GeForce RTX 4060 (8GB VRAM)
  - CPU: Intel Core i5-10210U (4 cores, 8 threads @ 1.60GHz)
  - Memory: 32GB DDR4
  - Operating System: Ubuntu 24.04.3 LTS
  - CUDA Driver: 550.163.01
- Hardware configuration 2:
  - GPU: NVIDIA NVIDIA Tesla V100 (32GB VRAM)
  - CPU: Intel Xeon Gold 6271C
  - Memory: 512 GB DDR4
  - Operating System: Ubuntu 24.04.3 LTS
  - CUDA Driver: 550.163.01

**Benchmark Results**:
| GPU Model | Average Inference Time (ms) | Average FPS | Average CPS (chars/s) | Average Accuracy (%) | 
|---|---|---|---|---|
| `RTX 4060` | 2234.11 | 0.70 | 465.87 | 92.34 |
| `V100` | - | - | - | - |

- [Detailed Performance Results of PP-OCRv5 on RTX 4060](./PP-OCRv5_on_4060.md)
- [Detailed Performance Results of PP-OCRv5 on V100](./PP-OCRv5_on_V100.md)

## 🛠️ Quick Start

### ⚡ Three Simple Steps to Start Your OCR Benchmark

**Step 1: Environment Setup**
```bash
git clone https://github.com/Chris-godz/PP-OCRv5-Cpp-Baseline.git
cd PP-OCRv5-Cpp-Baseline
./scripts/setup_environment.sh
```

**Step 2: Install Dependencies**
```bash
./scripts/compile_dependencies.sh
```

**Step 3: Run Benchmark**
```bash
./scripts/startup.sh
```

## 📁 Project Structure

```
├── CMakeLists.txt          # C++ build configuration
├── src/Benchmark.cpp       # Main program (OCR inference + performance testing)
├── scripts/
│   ├── startup.sh          # One-click run script
│   ├── setup_environment.sh # Environment setup
│   ├── compile_dependencies.sh # Dependency installation
│   └── calculate_acc.py    # Accuracy calculation
├── images/                 # Custom dataset (20 PNG images + labels.json)
│   ├── image_1.png ~ image_20.png  # Test images
│   └── labels.json         # Ground truth annotations
├── models/                 # Pre-trained model storage (auto-downloaded)
├── PaddleOCR/              # PaddleOCR source code (auto-cloned)
└── output/                 # Test results output
```

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

Thanks to the [PaddleOCR team](https://github.com/PaddlePaddle/PaddleOCR) for providing an excellent OCR framework.
