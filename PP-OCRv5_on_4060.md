**Test Configuration**:
- Model: PP-OCRv5 Server series full pipeline (high-precision configuration)
  - Document orientation classification: PP-LCNet_x1_0_doc_ori
  - Document rectification: UVDoc
  - Text line orientation classification: PP-LCNet_x1_0_textline_ori
  - Text detection: PP-OCRv5_server_det
  - Text recognition: PP-OCRv5_server_rec
- Hardware: Server-grade configuration with GPU acceleration support
  - GPU: NVIDIA GeForce RTX 4060 (8GB VRAM)
  - CPU: Intel Core i5-10210U (4 cores, 8 threads @ 1.60GHz)
  - Memory: 32GB DDR4
  - Operating System: Ubuntu 24.04.3 LTS
  - CUDA Driver: 550.163.01

**Test Results**:
| Filename | Inference Time (ms) | FPS(image/s) | CPS (chars/s) | Accuracy (%) |
|---|---|---|---|---|
| `image_11.png` | 5260.83 | 0.19 | **87.25** | **100.00** |
| `image_7.png` | 1245.79 | 0.80 | **838.83** | **97.22** |
| `image_9.png` | 3266.48 | 0.31 | **713.00** | **99.19** |
| `image_20.png` | 2402.53 | 0.42 | **681.78** | **95.49** |
| `image_4.png` | 672.82 | 1.49 | **167.95** | **92.86** |
| `image_16.png` | 2353.57 | 0.42 | **65.01** | **95.83** |
| `image_3.png` | 901.28 | 1.11 | **24.41** | **71.43** |
| `image_15.png` | 4848.87 | 0.21 | **945.17** | **99.52** |
| `image_8.png` | 2313.28 | 0.43 | **521.77** | **99.75** |
| `image_19.png` | 2577.48 | 0.39 | **820.57** | **95.39** |
| `image_14.png` | 3291.08 | 0.30 | **643.86** | **99.13** |
| `image_2.png` | 863.76 | 1.16 | **181.76** | **64.00** |
| `image_10.png` | 1992.46 | 0.50 | **633.89** | **100.00** |
| `image_6.png` | 4216.76 | 0.24 | **921.80** | **98.07** |
| `image_17.png` | 792.46 | 1.26 | **287.71** | **86.75** |
| `image_5.png` | 664.58 | 1.50 | **49.66** | **100.00** |
| `image_1.png` | 597.53 | 1.67 | **41.84** | **57.14** |
| `image_13.png` | 1031.23 | 0.97 | **192.00** | **100.00** |
| `image_12.png` | 3119.56 | 0.32 | **694.33** | **95.32** |
| `image_18.png` | 2269.78 | 0.44 | **804.92** | **99.83** |
| **Average** | - | **0.70** | **465.87** | **92.34** |

