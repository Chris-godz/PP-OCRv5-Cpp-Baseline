#!/usr/bin/env python3
"""
Research-standard OCR accuracy calculator following academic papers
Implements standard CER and WER calculations used in OCR research
"""

import json
import argparse
import os
import sys
from typing import Dict, List, Tuple, Optional
import unicodedata
import jiwer

def normalize_text_research_standard(text: str) -> str:
    """
    This normalization is designed to be strict for research-level CER/Accuracy.
    It aims to mirror academic standards for OCR evaluation.
    - Converts full-width characters to half-width.
    - Lowercases all text.
    - Removes a comprehensive set of punctuation, symbols, and all whitespace.
    """
    if not isinstance(text, str):
        return ""

    # 1. Unicode normalization to handle combined characters
    text = unicodedata.normalize('NFKC', text)

    # 2. Lowercase the text
    text = text.lower()

    # 3. Build a comprehensive translation table for removal
    # This is far more efficient than repeated .replace() calls
    
    # Combining all forms of punctuation and symbols to be removed.
    # Includes CJK punctuation, general punctuation, and ASCII symbols.
    punctuation_to_remove = "＂＃＄％＆＇（）＊＋，－．／：；＜＝＞？＠［＼］＾＿｀｛｜｝～" \
                            "·｜「」『』《》〈〉（）" \
                            ".,;:!?\"'()[]{}<>@#$%^&*-_=+|\\`~" \
                            "●"
    
    # All whitespace characters (space, tab, newline, return, formfeed, vertical tab)
    whitespace_to_remove = " \t\n\r\f\v"

    # The translation table maps the ordinal value of each character to None (for deletion)
    translator = str.maketrans('', '', punctuation_to_remove + whitespace_to_remove)
    
    return text.translate(translator)

def calculate_character_error_rate(reference: str, hypothesis: str) -> Dict[str, float]:
    """
    Calculate Character Error Rate (CER) and other metrics using the jiwer library.
    jiwer is a standard, well-tested library for this purpose.
    """
    ref_norm = normalize_text_research_standard(reference)
    hyp_norm = normalize_text_research_standard(hypothesis)

    if len(ref_norm) == 0:
        return {
            'cer': 0.0 if len(hyp_norm) == 0 else 1.0,
            'accuracy': 1.0 if len(hyp_norm) == 0 else 0.0,
            'substitutions': 0,
            'insertions': len(hyp_norm),
            'deletions': 0,
            'ref_length': 0,
            'hyp_length': len(hyp_norm)
        }

    # Use jiwer to compute all metrics at once
    # For character-level, we pass the strings directly.
    # For word-level, we would pass lists of words.
    error = jiwer.cer(ref_norm, hyp_norm)
    
    # Manually calculate accuracy from the error rate
    accuracy = max(0.0, 1.0 - error)
    
    # To get detailed S/I/D counts, we can use process_words/process_characters
    # but for simplicity and to match the core metric, cer is sufficient.
    # Let's get the detailed output for the full report.
    output = jiwer.process_characters(ref_norm, hyp_norm)

    return {
        'cer': error,
        'accuracy': accuracy,
        'substitutions': output.substitutions,
        'insertions': output.insertions,
        'deletions': output.deletions,
        'ref_length': len(ref_norm),
        'hyp_length': len(hyp_norm)
    }

def calculate_word_error_rate(reference: str, hypothesis: str) -> Dict[str, float]:
    """
    Calculate Word Error Rate (WER) using the jiwer library.
    """
    ref_norm = normalize_text_research_standard(reference)
    hyp_norm = normalize_text_research_standard(hypothesis)
    
    # Use jiwer's default transformation, which handles splitting into words.
    error = jiwer.wer(ref_norm, hyp_norm)
    accuracy = max(0.0, 1.0 - error)
    output = jiwer.process_words(ref_norm, hyp_norm)
    
    return {
        'wer': error,
        'accuracy': accuracy,
        'ref_word_count': output.references,
        'hyp_word_count': output.hypotheses
    }

def calculate_research_standard_accuracy(ground_truth: Dict, ocr_result: Dict, debug: bool = False) -> Dict:
    """
    Calculate OCR accuracy using research-standard methods - UPDATED for custom dataset format
    """
    
    # Extract ground truth texts from custom dataset format
    gt_texts = []
    if 'document' in ground_truth:
        for item in ground_truth['document']:
            if 'text' in item:
                gt_texts.append(item['text'])
    
    # Extract OCR prediction texts from PaddleOCR format
    pred_texts = []
    if 'rec_texts' in ocr_result:
        pred_texts = ocr_result['rec_texts']
    
    # Combine all text
    gt_combined = ''.join(gt_texts)  # NO SPACES - direct concatenation
    pred_combined = ''.join(pred_texts)  # NO SPACES - direct concatenation
    
    if debug:
        print("\n--- DEBUG MODE ---")
        print(f"RAW Ground Truth:\n---\n{gt_combined}\n---")
        print(f"RAW Prediction:\n---\n{pred_combined}\n---")
        
        gt_norm_debug = normalize_text_research_standard(gt_combined)
        pred_norm_debug = normalize_text_research_standard(pred_combined)
        
        print(f"NORMALIZED Ground Truth:\n---\n{gt_norm_debug}\n---")
        print(f"NORMALIZED Prediction:\n---\n{pred_norm_debug}\n---")
        print("--- END DEBUG ---\n")
    
    # Calculate character-level metrics
    char_metrics = calculate_character_error_rate(gt_combined, pred_combined)
    
    # Calculate word-level metrics
    word_metrics = calculate_word_error_rate(gt_combined, pred_combined)
    
    # Calculate exact match
    gt_norm = normalize_text_research_standard(gt_combined)
    pred_norm = normalize_text_research_standard(pred_combined)
    exact_match = 1.0 if gt_norm == pred_norm else 0.0
    
    # Calculate detection metrics
    gt_regions = len(gt_texts)
    detected_regions = len(pred_texts)
    
    detection_recall = min(detected_regions / gt_regions, 1.0) if gt_regions > 0 else 1.0
    detection_precision = min(gt_regions / detected_regions, 1.0) if detected_regions > 0 else 0.0
    
    # Calculate F1 score for overall text similarity (research standard)
    if char_metrics['ref_length'] > 0 and char_metrics['hyp_length'] > 0:
        precision = max(0, (char_metrics['hyp_length'] - char_metrics['insertions']) / char_metrics['hyp_length'])
        recall = max(0, (char_metrics['ref_length'] - char_metrics['deletions']) / char_metrics['ref_length'])
        f1_score = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0.0
    else:
        f1_score = 0.0
    
    return {
        # ONLY Character Accuracy - simplified output
        'character_accuracy': char_metrics['accuracy'],
        'character_error_rate': char_metrics['cer'],
        
        # Debug info
        'reference_length': char_metrics['ref_length'],
        'hypothesis_length': char_metrics['hyp_length'],
        'substitutions': char_metrics['substitutions'],
        'insertions': char_metrics['insertions'],
        'deletions': char_metrics['deletions']
    }

def load_ground_truth_for_image(ground_truth_file: str, image_name: str) -> Optional[Dict]:
    """Load ground truth data for a specific image - UPDATED for custom dataset format"""
    try:
        with open(ground_truth_file, 'r', encoding='utf-8') as f:
            gt_data = json.load(f)
        
        # Custom dataset format: direct image name keys
        if image_name in gt_data:
            # Convert custom format to expected format
            texts = []
            for item in gt_data[image_name]:
                if 'text' in item:
                    texts.append({'text': item['text']})
            
            return {'document': texts}
        
        print(f"Warning: Ground truth not found for image: {image_name}")
        return None
        
    except Exception as e:
        print(f"Error loading ground truth: {e}")
        return None

def load_ocr_result_for_image(output_dir: str, image_name: str) -> Optional[Dict]:
    """Load OCR result for a specific image"""
    try:
        base_name = os.path.splitext(image_name)[0]
        json_filename = f"{base_name}_res.json"
        json_path = os.path.join(output_dir, json_filename)
        
        if not os.path.exists(json_path):
            print(f"Warning: OCR result not found: {json_path}")
            return None
        
        with open(json_path, 'r', encoding='utf-8') as f:
            ocr_data = json.load(f)
        
        return ocr_data
        
    except Exception as e:
        print(f"Error loading OCR result: {e}")
        return None

def calculate_accuracy():
    """
    This function is now a placeholder. The main logic is handled in startup.sh
    which processes all images and then calls this script for each one.
    This script is now focused on single-image calculation.
    """
    pass

def main():
    parser = argparse.ArgumentParser(description='Calculate OCR accuracy for a single image')
    parser.add_argument('--ground_truth', required=True, help='Path to the master ground truth JSON file (e.g., labels.json)')
    parser.add_argument('--output_dir', required=True, help='Directory containing OCR output JSON files')
    parser.add_argument('--image_name', required=True, help='The specific image file name to process (e.g., image_0.png)')
    parser.add_argument('--debug', action='store_true', help='Enable debug mode to print raw and normalized texts')
    parser.add_argument('--results_file', help=argparse.SUPPRESS) # Suppress help for this unused arg

    args = parser.parse_args()

    # Load the specific ground truth document for the given image
    gt_data = load_ground_truth_for_image(args.ground_truth, args.image_name)
    if gt_data is None:
        # This is a critical error for single-image calculation
        print(f"ERROR: Ground truth not found for {args.image_name} in {args.ground_truth}", file=sys.stderr)
        # Return a JSON error message for the C++ application to parse
        print(f"SINGLE_ACC: {{\"error\": \"Ground truth not found for {args.image_name}\"}}")
        sys.exit(1)

    # Load the corresponding OCR result
    ocr_data = load_ocr_result_for_image(args.output_dir, args.image_name)
    if ocr_data is None:
        print(f"ERROR: OCR result not found for {args.image_name} in {args.output_dir}", file=sys.stderr)
        print(f"SINGLE_ACC: {{\"error\": \"OCR result not found for {args.image_name}\"}}")
        sys.exit(1)

    # Calculate the accuracy metrics
    accuracy_metrics = calculate_research_standard_accuracy(gt_data, ocr_data, debug=args.debug)

    # Print a clean, human-readable summary to stderr for immediate feedback in the log
    summary = f"""
========================================
CHARACTER ACCURACY EVALUATION
========================================
Image: {args.image_name}
Character Accuracy: {accuracy_metrics['character_accuracy']*100:.2f}%
Character Error Rate: {accuracy_metrics['character_error_rate']*100:.2f}%
Ref Length: {accuracy_metrics['reference_length']}, Hyp Length: {accuracy_metrics['hypothesis_length']}
========================================
"""
    print(summary, file=sys.stderr)

    # Print the machine-readable JSON to stdout, prefixed for easy parsing by the C++ app
    print(f"SINGLE_ACC: {json.dumps(accuracy_metrics, ensure_ascii=False)}")

if __name__ == "__main__":
    main()