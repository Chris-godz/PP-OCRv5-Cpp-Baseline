#include "src/api/pipelines/ocr.h"
#include <iostream>
#include <string>
#include <vector>
#include <chrono>
#include <iomanip>
#include <algorithm>
#include <dirent.h>
#include <sys/stat.h>
#include <cstdlib>
#include <fstream>
#include <sstream>

// Helper function to execute a command and capture its output
bool ExecuteCommand(const std::string& command, std::string* result) {
    char buffer[256];
    FILE* pipe = popen(command.c_str(), "r");
    if (!pipe) {
        std::cerr << "ERROR: popen() failed!" << std::endl;
        return false;
    }
    while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
        *result += buffer;
    }
    int exit_code = pclose(pipe);
    return exit_code == 0;
}

// Helper function to get the root path of the project
std::string get_root_path() {
    char* root_path_env = std::getenv("PWD");
    if (root_path_env != nullptr) {
        return std::string(root_path_env);
    }
    return ".";
}

// Helper function to check if file is an image
bool isImageFile(const std::string& filepath) {
    // Find the last dot to get extension
    size_t dot_pos = filepath.find_last_of('.');
    if (dot_pos == std::string::npos) return false;
    
    std::string ext = filepath.substr(dot_pos);
    std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);
    return ext == ".jpg" || ext == ".jpeg" || ext == ".png" || ext == ".bmp" || ext == ".tiff";
}

// Helper function to check if path is a directory
bool isDirectory(const std::string& path) {
    struct stat statbuf;
    if (stat(path.c_str(), &statbuf) != 0) return false;
    return S_ISDIR(statbuf.st_mode);
}

// Helper function to check if path is a regular file
bool isFile(const std::string& path) {
    struct stat statbuf;
    if (stat(path.c_str(), &statbuf) != 0) return false;
    return S_ISREG(statbuf.st_mode);
}

// Helper function to collect image files from directory recursively
void collectImagesFromDirectory(const std::string& dirPath, std::vector<std::string>& imagePaths) {
    DIR* dir = opendir(dirPath.c_str());
    if (!dir) return;
    
    struct dirent* entry;
    while ((entry = readdir(dir)) != nullptr) {
        std::string name = entry->d_name;
        if (name == "." || name == "..") continue;
        
        std::string fullPath = dirPath + "/" + name;
        
        if (isDirectory(fullPath)) {
            // Recursively process subdirectory
            collectImagesFromDirectory(fullPath, imagePaths);
        } else if (isFile(fullPath) && isImageFile(fullPath)) {
            imagePaths.push_back(fullPath);
        }
    }
    closedir(dir);
}

// Helper function to collect image files from directory or file list
std::vector<std::string> collectImagePaths(int argc, char* argv[]) {
    std::vector<std::string> imagePaths;
    
    for (int i = 1; i < argc; i++) {
        std::string path = argv[i];
        
        if (isDirectory(path)) {
            // If it's a directory, collect all image files
            collectImagesFromDirectory(path, imagePaths);
        } else if (isFile(path) && isImageFile(path)) {
            // If it's a single image file
            imagePaths.push_back(path);
        } else {
            std::cerr << "Warning: Skipping invalid path: " << path << std::endl;
        }
    }
    
    return imagePaths;
}

// Function to calculate accuracy for a single image
std::string calculateImageAccuracy(const std::string& image_name, const std::string& ground_truth_path) {
    // Extract base image name without extension and path
    std::string base_name = image_name;
    size_t dot_pos = base_name.find_last_of('.');
    if (dot_pos != std::string::npos) {
        base_name = base_name.substr(0, dot_pos);
    }
    
    size_t slash_pos = base_name.find_last_of('/');
    if (slash_pos != std::string::npos) {
        base_name = base_name.substr(slash_pos + 1);
    }
    
    // Construct command to call Python accuracy calculator for single image
    // Use the current activated conda environment python instead of conda run
    std::string python_cmd = "python scripts/calculate_acc.py "
                            "--ground_truth \"" + ground_truth_path + "\" "
                            "--output_dir \"./output\" "
                            "--image_name \"" + base_name + "\" 2>&1";
    
    // Execute command and capture output
    FILE* pipe = popen(python_cmd.c_str(), "r");
    if (!pipe) {
        return "ERROR: Failed to execute accuracy calculation";
    }
    
    std::string result;
    char buffer[256];
    while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
        result += buffer;
    }
    pclose(pipe);
    
    // Extract accuracy metrics from output
    std::istringstream iss(result);
    std::string line;
    
    while (std::getline(iss, line)) {
        if (line.find("SINGLE_ACC:") == 0) {
            // Extract and parse the JSON data
            size_t colon_pos = line.find(':');
            if (colon_pos != std::string::npos) {
                std::string json_data = line.substr(colon_pos + 1);
                // Remove leading whitespace
                size_t start = json_data.find_first_not_of(" \t\r\n");
                if (start != std::string::npos) {
                    json_data = json_data.substr(start);
                }
                return json_data;
            }
        }
    }
    
    return "{\"error\": \"No accuracy data found\"}";
}

int main(int argc, char* argv[]){
    // Check if image path is provided as command line argument
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <image_path_or_directory> [image_path2] [image_path3] ..." << std::endl;
        std::cerr << "Examples:" << std::endl;
        std::cerr << "  " << argv[0] << " ./general_ocr_002.png" << std::endl;
        std::cerr << "  " << argv[0] << " ./images/" << std::endl;
        std::cerr << "  " << argv[0] << " img1.png img2.jpg img3.png" << std::endl;
        return 1;
    }

    // Collect all image paths
    std::cout << "[INFO] Collecting image paths from " << (argc - 1) << " input arguments..." << std::endl;
    std::vector<std::string> imagePaths = collectImagePaths(argc, argv);
    
    if (imagePaths.empty()) {
        std::cerr << "[ERROR] No valid image files found!" << std::endl;
        std::cerr << "[ERROR] Please check that the specified paths contain image files (.jpg, .jpeg, .png, .bmp, .tiff)" << std::endl;
        return 1;
    }
    
    std::cout << "[SUCCESS] Found " << imagePaths.size() << " images to process" << std::endl;
    
    // Print first few image paths for verification
    std::cout << "[INFO] Sample images to be processed:" << std::endl;
    for (size_t i = 0; i < std::min((size_t)5, imagePaths.size()); i++) {
        std::cout << "  [" << (i+1) << "] " << imagePaths[i] << std::endl;
    }
    if (imagePaths.size() > 5) {
        std::cout << "  ... and " << (imagePaths.size() - 5) << " more images" << std::endl;
    }

    // Initialize PaddleOCR parameters
    PaddleOCRParams params;
    params.doc_orientation_classify_model_dir = "models/PP-LCNet_x1_0_doc_ori_infer"; // 文档方向分类模型路径。
    params.doc_unwarping_model_dir = "models/UVDoc_infer"; // 文本图像矫正模型路径。
    params.textline_orientation_model_dir = "models/PP-LCNet_x1_0_textline_ori_infer"; // 文本行方向分类模型路径。
    params.text_detection_model_dir = "models/PP-OCRv5_server_det_infer"; // 文本检测模型路径
    params.text_recognition_model_dir = "models/PP-OCRv5_server_rec_infer"; // 文本识别模型路径
    params.device = "gpu"; // 推理时使用GPU。请确保编译时添加 -DWITH_GPU=ON 选项，否则使用CPU。
    // params.use_doc_orientation_classify = false;  // 不使用文档方向分类模型。
    // params.use_doc_unwarping = false; // 不使用文本图像矫正模型。
    // params.use_textline_orientation = false; // 不使用文本行方向分类模型。
    // params.text_detection_model_name = "PP-OCRv5_server_det"; // 使用 PP-OCRv5_server_det 模型进行检测。
    // params.text_recognition_model_name = "PP-OCRv5_server_rec"; // 使用 PP-OCRv5_server_rec 模型进行识别。
    // params.vis_font_dir = "your_vis_font_dir"; // 当编译时添加 -DUSE_FREETYPE=ON 选项，必须提供相应 ttf 字体文件路径。

    // Initialize PaddleOCR once (this is the expensive operation)
    std::cout << "\n[INIT] Initializing PaddleOCR with the following configuration:" << std::endl;
    std::cout << "  - Device: " << (params.device.has_value() ? params.device.value() : "default") << std::endl;
    std::cout << "  - Detection model: " << (params.text_detection_model_dir.has_value() ? params.text_detection_model_dir.value() : "default") << std::endl;
    std::cout << "  - Recognition model: " << (params.text_recognition_model_dir.has_value() ? params.text_recognition_model_dir.value() : "default") << std::endl;
    std::cout << "  - Doc orientation model: " << (params.doc_orientation_classify_model_dir.has_value() ? params.doc_orientation_classify_model_dir.value() : "disabled") << std::endl;
    std::cout << "  - Doc unwarping model: " << (params.doc_unwarping_model_dir.has_value() ? params.doc_unwarping_model_dir.value() : "disabled") << std::endl;
    std::cout << "  - Textline orientation model: " << (params.textline_orientation_model_dir.has_value() ? params.textline_orientation_model_dir.value() : "disabled") << std::endl;
    std::cout << "[INIT] Starting PaddleOCR initialization..." << std::endl;
    
    auto init_start = std::chrono::high_resolution_clock::now();
    auto infer = PaddleOCR(params);
    auto init_end = std::chrono::high_resolution_clock::now();
    auto init_duration = std::chrono::duration_cast<std::chrono::milliseconds>(init_end - init_start);
    std::cout << "[SUCCESS] PaddleOCR initialized successfully in " << init_duration.count() << " ms" << std::endl;

    // Process all images in batch
    std::cout << "\n[BATCH] Starting batch processing of " << imagePaths.size() << " images..." << std::endl;
    std::vector<double> inference_times;
    int successful_count = 0;
    int failed_count = 0;
    auto total_start = std::chrono::high_resolution_clock::now();

    for (size_t i = 0; i < imagePaths.size(); i++) {
        const std::string& image_path = imagePaths[i];
        std::cout << "\n[PROCESS " << (i+1) << "/" << imagePaths.size() << "] Starting: " << image_path << std::endl;
        
        try {
            // Run inference 3 times to get average
            std::vector<double> run_times;
            std::vector<std::unique_ptr<BaseCVResult>> final_outputs;
            int total_chars = 0;
            
            std::cout << "  [INFERENCE] Running 3 iterations for average metrics..." << std::endl;
            
            for (int run = 0; run < 3; run++) {
                std::cout << "    [RUN " << (run+1) << "/3] Starting inference..." << std::endl;
                auto start_inference_time = std::chrono::high_resolution_clock::now();
                auto outputs = infer.Predict(image_path);
                auto end_inference_time = std::chrono::high_resolution_clock::now();
                auto inference_duration_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(end_inference_time - start_inference_time);
                double inference_ms = inference_duration_ns.count() / 1e6;
                run_times.push_back(inference_ms);
                
                // Save outputs from first run only
                if (run == 0) {
                    final_outputs = std::move(outputs);
                    // Count total characters from OCR results by parsing JSON output
                    for (const auto& output : final_outputs) {
                        if (output) {
                            // Get the OCR result and print to a string stream to capture JSON
                            std::ostringstream oss;
                            // Temporarily redirect cout to capture the JSON output
                            std::streambuf* orig = std::cout.rdbuf();
                            std::cout.rdbuf(oss.rdbuf());
                            output->Print();
                            std::cout.rdbuf(orig);
                            
                            std::string json_output = oss.str();
                            
                            // Count characters in rec_texts array
                            size_t rec_texts_pos = json_output.find("\"rec_texts\": [");
                            if (rec_texts_pos != std::string::npos) {
                                // Find the end of the rec_texts array
                                size_t array_start = json_output.find('[', rec_texts_pos);
                                size_t array_end = json_output.find(']', array_start);
                                
                                if (array_start != std::string::npos && array_end != std::string::npos) {
                                    std::string rec_texts_content = json_output.substr(array_start + 1, array_end - array_start - 1);
                                    
                                    // Count characters in all quoted strings
                                    size_t pos = 0;
                                    while ((pos = rec_texts_content.find('"', pos)) != std::string::npos) {
                                        size_t end_quote = rec_texts_content.find('"', pos + 1);
                                        if (end_quote != std::string::npos) {
                                            std::string text = rec_texts_content.substr(pos + 1, end_quote - pos - 1);
                                            // Count actual characters (excluding escape sequences)
                                            for (char c : text) {
                                                if (c != '\\') {  // Skip escape characters
                                                    total_chars++;
                                                }
                                            }
                                            pos = end_quote + 1;
                                        } else {
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                std::cout << "    [RUN " << (run+1) << "/3] Completed in " << std::fixed << std::setprecision(2) << inference_ms << " ms" << std::endl;
            }
            
            // Calculate average metrics
            double avg_inference_ms = 0.0;
            for (double time : run_times) {
                avg_inference_ms += time;
            }
            avg_inference_ms /= run_times.size();
            
            double avg_fps = (avg_inference_ms > 0) ? 1000.0 / avg_inference_ms : 0.0;
            double chars_per_second = (avg_inference_ms > 0) ? (total_chars * 1000.0) / avg_inference_ms : 0.0;
            
            inference_times.push_back(avg_inference_ms);
            
            std::cout << "  [METRICS] Average inference time: " << std::fixed << std::setprecision(2) << avg_inference_ms << " ms" << std::endl;
            std::cout << "  [METRICS] FPS: " << std::fixed << std::setprecision(2) << avg_fps << std::endl;
            std::cout << "  [METRICS] Characters/second: " << std::fixed << std::setprecision(2) << chars_per_second << " chars/s" << std::endl;
            std::cout << "  [METRICS] Total characters detected: " << total_chars << std::endl;
            std::cout << "  [OUTPUT] Processing " << final_outputs.size() << " output(s)..." << std::endl;
            
            // Save outputs (from first run)
            for (size_t j = 0; j < final_outputs.size(); j++) {
                std::cout << "    [OUTPUT " << (j+1) << "] Printing results..." << std::endl;
                final_outputs[j]->Print();
                std::cout << "    [OUTPUT " << (j+1) << "] Saving to image..." << std::endl;
                final_outputs[j]->SaveToImg("./output/");
                std::cout << "    [OUTPUT " << (j+1) << "] Saving to JSON..." << std::endl;
                final_outputs[j]->SaveToJson("./output/");
            }
            
            // Calculate accuracy immediately after saving outputs
            std::cout << "  [ACCURACY] Calculating accuracy metrics..." << std::endl;
            std::string rootPath = get_root_path();
            std::string ground_truth_path = rootPath + "/images/labels.json";
            
            // Extract just the filename for the python script
            std::string filename = image_path;
            size_t last_slash_pos = filename.find_last_of("/");
            if (std::string::npos != last_slash_pos) {
                filename.erase(0, last_slash_pos + 1);
            }

            // Use the current activated conda environment python instead of conda run
            std::string command = "python " + rootPath + "/scripts/calculate_acc.py";
            command += " --ground_truth \"" + ground_truth_path + "\"";
            command += " --output_dir \"" + rootPath + "/output\"";
            command += " --image_name \"" + filename + "\"";
            
            std::string result_str;
            if (!ExecuteCommand(command, &result_str)) {
                std::cerr << "[ERROR] Failed to execute accuracy calculation for " << filename << std::endl;
                std::cerr << "[ERROR] Python script output:\n" << result_str << std::endl;
                 // Still try to output performance data even if accuracy fails
                std::cout << "PER_IMAGE_RESULT:{\"filename\":\"" << filename 
                          << "\",\"inference_ms\":" << std::fixed << std::setprecision(2) << avg_inference_ms 
                          << ",\"fps\":" << std::fixed << std::setprecision(2) << avg_fps 
                          << ",\"chars_per_second\":" << std::fixed << std::setprecision(2) << chars_per_second 
                          << ",\"total_chars\":" << total_chars 
                          << ",\"accuracy\":0.0}" << std::endl;
                continue;
            }

            // Find the JSON part of the output
            std::string prefix = "SINGLE_ACC: ";
            size_t json_start = result_str.find(prefix);
            if (json_start != std::string::npos) {
                std::string json_output = result_str.substr(json_start + prefix.length());
                
                // Extract accuracy value from JSON string (simple parsing)
                double acc = 0.0;
                size_t acc_pos = json_output.find("\"character_accuracy\":");
                if (acc_pos != std::string::npos) {
                    size_t value_start = json_output.find(":", acc_pos) + 1;
                    size_t value_end = json_output.find_first_of(",}", value_start);
                    if (value_end != std::string::npos) {
                        std::string acc_str = json_output.substr(value_start, value_end - value_start);
                        // Remove whitespace
                        acc_str.erase(std::remove_if(acc_str.begin(), acc_str.end(), ::isspace), acc_str.end());
                        acc = std::stod(acc_str);
                    }
                }

                // Output the structured per-image result for final table generation
                std::cout << "PER_IMAGE_RESULT:{\"filename\":\"" << filename 
                          << "\",\"inference_ms\":" << std::fixed << std::setprecision(2) << avg_inference_ms 
                          << ",\"fps\":" << std::fixed << std::setprecision(2) << avg_fps 
                          << ",\"chars_per_second\":" << std::fixed << std::setprecision(2) << chars_per_second 
                          << ",\"total_chars\":" << total_chars 
                          << ",\"accuracy\":" << std::fixed << std::setprecision(4) << acc << "}" << std::endl;

            } else {
                std::cerr << "[ERROR] Could not find 'SINGLE_ACC:' prefix in Python script output for " << filename << std::endl;
                std::cerr << "[ERROR] Full script output: " << result_str << std::endl;
            }
            
            successful_count++;
            std::cout << "  [SUCCESS] Image " << (i+1) << " processed successfully." << std::endl;
                      
        } catch (const std::exception& e) {
            failed_count++;
            std::cerr << "  [ERROR] Failed to process " << image_path << ": " << e.what() << std::endl;
            std::cerr << "  [ERROR] Continuing with next image..." << std::endl;
        }
        
        // Progress update every 10 images or at milestones
        if ((i + 1) % 10 == 0 || (i + 1) == imagePaths.size()) {
            double progress = 100.0 * (i + 1) / imagePaths.size();
            std::cout << "\n[PROGRESS] " << (i + 1) << "/" << imagePaths.size() 
                      << " images processed (" << std::fixed << std::setprecision(1) << progress 
                      << "%) - Success: " << successful_count << ", Failed: " << failed_count << std::endl;
        }
    }

    auto total_end = std::chrono::high_resolution_clock::now();
    auto total_duration = std::chrono::duration_cast<std::chrono::milliseconds>(total_end - total_start);

    std::cout << "\n[BATCH] Batch processing completed!" << std::endl;
    std::cout << "[BATCH] Total time: " << total_duration.count() << " ms" << std::endl;

    // Calculate statistics
    if (!inference_times.empty()) {
        std::cout << "\n[STATS] Calculating performance statistics..." << std::endl;
        
        double total_inference_time = 0;
        double min_time = inference_times[0];
        double max_time = inference_times[0];
        
        for (double time : inference_times) {
            total_inference_time += time;
            min_time = std::min(min_time, time);
            max_time = std::max(max_time, time);
        }
        
        double avg_inference_time = total_inference_time / inference_times.size();
        double avg_fps = 1000.0 / avg_inference_time;
        double total_fps = successful_count * 1000.0 / total_inference_time;

        // Print comprehensive results
        std::cout << "\n" << std::string(60, '=') << std::endl;
        std::cout << "BENCHMARK RESULTS SUMMARY" << std::endl;
        std::cout << std::string(60, '=') << std::endl;
        std::cout << "Total images processed: " << imagePaths.size() << std::endl;
        std::cout << "Successful: " << successful_count << std::endl;
        std::cout << "Failed: " << failed_count << std::endl;
        std::cout << "Success rate: " << std::fixed << std::setprecision(1) 
                  << (100.0 * successful_count / imagePaths.size()) << "%" << std::endl;
        std::cout << std::string(60, '-') << std::endl;
        std::cout << "Initialization time: " << init_duration.count() << " ms" << std::endl;
        std::cout << "Total processing time: " << total_duration.count() << " ms" << std::endl;
        std::cout << "Pure inference time: " << std::fixed << std::setprecision(2) 
                  << total_inference_time << " ms" << std::endl;
        std::cout << std::string(60, '-') << std::endl;
        std::cout << "Average inference time: " << std::fixed << std::setprecision(2) 
                  << avg_inference_time << " ms" << std::endl;
        std::cout << "Min inference time: " << std::fixed << std::setprecision(2) 
                  << min_time << " ms" << std::endl;
        std::cout << "Max inference time: " << std::fixed << std::setprecision(2) 
                  << max_time << " ms" << std::endl;
        std::cout << std::string(60, '-') << std::endl;
        std::cout << "Average FPS (per image): " << std::fixed << std::setprecision(2) 
                  << avg_fps << std::endl;
        std::cout << "Batch throughput FPS: " << std::fixed << std::setprecision(2) 
                  << total_fps << std::endl;
        std::cout << std::string(60, '=') << std::endl;
        
        // Output timing info for shell script compatibility
        std::cout << "\n[SHELL_OUTPUT] Timing information for shell script:" << std::endl;
        std::cout << "TIMING_INFO:INIT:" << init_duration.count() << "ms" << std::endl;
        std::cout << "TIMING_INFO:TOTAL_INFERENCE:" << total_inference_time << "ms" << std::endl;
        std::cout << "TIMING_INFO:AVG_INFERENCE:" << avg_inference_time << "ms" << std::endl;
        std::cout << "TIMING_INFO:AVG_FPS:" << std::fixed << std::setprecision(2) << avg_fps << std::endl;
        std::cout << "TIMING_INFO:BATCH_FPS:" << std::fixed << std::setprecision(2) << total_fps << std::endl;
        std::cout << "TIMING_INFO:SUCCESS_RATE:" << (100.0 * successful_count / imagePaths.size()) << "%" << std::endl;
    } else {
        std::cerr << "\n[ERROR] No successful inferences completed - cannot calculate statistics!" << std::endl;
    }

    return (failed_count > 0) ? 1 : 0;
}