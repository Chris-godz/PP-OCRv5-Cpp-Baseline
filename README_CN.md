# PP-OCRv5 C++ 基准测试

[English README](README.md)

🚀 PP-OCRv5 C++ 基准测试工具链，使用 GPU 加速和完整性能评估


## 📈 性能表现

### 自定义数据集介绍

本项目使用多样化的自定义中文数据集进行基准测试。该数据集涵盖各种真实场景，包括街景标识、手写文本、试卷内容、课本页面和报纸文章，为不同文本识别挑战提供全面覆盖，并配有详细标注信息，包括文本内容和边界框坐标。

**测试配置**：
- 数据集：自定义中文文档数据集（20张图像）
- 数据格式：PNG图像 + JSON标注文件（包含文本内容和边界框坐标）
- 模型：PP-OCRv5 Server 系列完整Pipeline（高精度配置）
  - 文档方向分类：PP-LCNet_x1_0_doc_ori
  - 文档矫正：UVDoc
  - 文本行方向分类：PP-LCNet_x1_0_textline_ori
  - 文本检测：PP-OCRv5_server_det
  - 文本识别：PP-OCRv5_server_rec
- 硬件配置 1：
  - GPU: NVIDIA GeForce RTX 4060 (8GB VRAM)
  - CPU: Intel Core i5-10210U (4 cores, 8 threads @ 1.60GHz)
  - 内存: 32GB DDR4
  - 操作系统: Ubuntu 24.04.3 LTS
  - CUDA 驱动: 550.163.01
- 硬件配置 2：
  - GPU: NVIDIA Tesla V100 (32GB VRAM)
  - CPU: Intel Xeon Gold 6271C
  - 内存: 512GB DDR4
  - 操作系统: Ubuntu 24.04.3 LTS
  - CUDA 驱动: 550.163.01

**基准测试结果**：
| GPU 型号 | 平均推理时间 (ms) | 平均 FPS | 平均 CPS (chars/s) | 平均准确率 (%) | 
|---|---|---|---|---|
| `RTX 4060` | 2234.11 | 0.70 | 465.87 | 92.34 |
| `V100` | - | - | - | - |

- [RTX 4060上PP-OCRv5详细性能结果](./PP-OCRv5_on_4060.md)
- [V100上PP-OCRv5详细性能结果](./PP-OCRv5_on_V100.md)

## 🛠️ 快速开始

### ⚡ 简单三步开始你的 OCR 基准测试

**第一步：环境配置**
```bash
git clone https://github.com/Chris-godz/PP-OCRv5-Cpp-Baseline.git
cd PP-OCRv5-Cpp-Baseline
./scripts/setup_environment.sh
```

**第二步：依赖安装**
```bash
./scripts/compile_dependencies.sh
```

**第三步：运行基准测试**
```bash
./scripts/startup.sh
```

## 📁 项目结构

```
├── CMakeLists.txt          # C++编译配置
├── src/Benchmark.cpp       # 主程序（OCR推理+性能测试）
├── scripts/
│   ├── startup.sh          # 一键运行脚本
│   ├── setup_environment.sh # 环境配置
│   ├── compile_dependencies.sh # 依赖安装
│   └── calculate_acc.py    # 准确率计算
├── images/                 # 自定义数据集（20张PNG图像 + 标注文件）
│   ├── image_1.png ~ image_20.png  # 测试图像
│   └── labels.json         # 真实标签标注
├── models/                 # 预训练模型存储（自动下载）
├── PaddleOCR/              # PaddleOCR源码（自动克隆）
└── output/                 # 测试结果输出
```

## 📄 开源协议

本项目采用 Apache License 2.0 协议 - 详见 [LICENSE](LICENSE) 文件

## 🙏 致谢

感谢 [PaddleOCR 团队](https://github.com/PaddlePaddle/PaddleOCR) 提供优秀的 OCR 框架

---
