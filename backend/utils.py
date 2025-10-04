import json
import io
import re
import time
from tenacity import retry, wait_exponential, stop_after_attempt, retry_if_exception_type
from google.api_core.exceptions import ResourceExhausted, ServiceUnavailable
from google import genai
from PIL import Image

import fitz  # PyMuPDF
import pytesseract
from constants import DOCUMENT_SCHEMA 

# --- Tesseract Configuration (Uncomment and set path if needed on Windows) ---
# pytesseract.pytesseract.tesseract_cmd = r'C:\Program Files\Tesseract-OCR\tesseract.exe'

# --- Item Comparison Helper ---

def find_best_item_match(invoice_item, po_items):
    """
    Tries to find the best matching PO item for a given Invoice item by normalizing descriptions.
    A simple approach is used here: normalize and check for key phrase inclusion.
    """
    # Normalize the description from the Invoice item we are checking
    inv_desc_normalized = normalize_text(invoice_item.get('description', ''))
    
    for po_item in po_items:
        # Normalize the description from the current PO item
        po_desc_normalized = normalize_text(po_item.get('description', ''))
        
        # Simple containment check: if one description is contained within the other
        if inv_desc_normalized in po_desc_normalized or po_desc_normalized in inv_desc_normalized:
            return po_item
            
    return None

# --- Document Processing and Extraction (Remains the same) ---
def normalize_text(text):
    """Normalize text for comparison (lowercase, remove punctuation/extra whitespace)."""
    text = text.lower()
    text = re.sub(r'[^a-z0-9\s]', '', text)
    return ' '.join(text.split())

def extract_text_from_file(file_data, filename):
    """
    Extracts raw text from PDF or image file data, with OCR fallback for PDFs.
    """
    
    # 1. Image Files (Always use OCR)
    if filename.lower().endswith(('.png', '.jpg', '.jpeg')):
        try:
            img = Image.open(io.BytesIO(file_data))
            text = pytesseract.image_to_string(img)
            return text
        except Exception as e:
            return f"Error extracting image text (OCR): {e}"
            
    # 2. PDF Files (Try direct text, then fall back to OCR)
    elif filename.lower().endswith('.pdf'):
        doc = None
        try:
            doc = fitz.open(stream=file_data, filetype="pdf")
            raw_text = "".join(page.get_text() for page in doc)
            
            if len(raw_text.strip()) < 100 and len(doc) > 0:
                print("PDF text is sparse. Initiating OCR fallback.")
                
                page = doc[0] 
                pix = page.get_pixmap(matrix=fitz.Matrix(3, 3)) 
                img_data = pix.tobytes("ppm")
                
                img = Image.open(io.BytesIO(img_data))
                ocr_text = pytesseract.image_to_string(img)
                
                if len(ocr_text.strip()) > 100:
                    return ocr_text
                else:
                    return raw_text # Fall back to original if OCR also fails
            
            return raw_text 
            
        except Exception as e:
            return f"Error during PDF processing or OCR: {e}"
        finally:
            if doc:
                doc.close()
                
    return "Unsupported file format."

@retry(
    wait=wait_exponential(min=1, max=10), 
    stop=stop_after_attempt(5), 
    retry=retry_if_exception_type((ResourceExhausted, ServiceUnavailable)), 
    reraise=True 
)
def _call_gemini_with_retry(client, prompt, doc_type):
    """Internal function to call Gemini API with structured output and retry logic."""
    if not client:
        raise Exception("AI Client not initialized.")

    response = client.models.generate_content(
        model="gemini-2.5-flash",
        contents=prompt,
        config=genai.types.GenerateContentConfig(
            response_mime_type="application/json",
            response_schema=DOCUMENT_SCHEMA,
        ),
    )
    return response

def gemini_extract_data(client, raw_text, doc_type):
    """Wraps the retry call for structured data extraction."""
    
    prompt = f"""
    You are an expert document data extraction agent for a finance team.
    Analyze the following {doc_type} text and extract the required fields into the JSON format provided.
    Ensure 'document_type' is set to '{doc_type}'.

    DOCUMENT TEXT:
    ---
    {raw_text}
    ---
    """
    try:
        response = _call_gemini_with_retry(client, prompt, doc_type)
        return json.loads(response.text)
    except Exception as e:
        return {"error": f"Gemini API call failed after multiple retries: {e}"}

# --- Core Matching Logic (Updated) ---

def perform_matching(invoice_data, po_data):
    """Compares extracted data between the Invoice and Purchase Order (Agent-style with Line-Item Check)."""
    results = {
        "isMatch": True,
        "status": "APPROVED",
        "summary": "Perfect 2-Way Match! Vendor and Total Amount verified.",
        "details": [],
        "mismatch_categories": [],
        "invoice_data": invoice_data, 
        "po_data": po_data,           
    }
    
    # --- 1. Vendor Name Check ---
    inv_vendor = normalize_text(invoice_data.get('vendor_name', ''))
    po_vendor = normalize_text(po_data.get('vendor_name', ''))
    if inv_vendor != po_vendor:
        results["isMatch"] = False
        results["mismatch_categories"].append("Vendor Mismatch")
        results["details"].append(f"Vendor Mismatch: Invoice: '{invoice_data.get('vendor_name')}' vs. PO: '{po_data.get('vendor_name')}'")
    else:
        results["details"].append(f"Vendor Match: {invoice_data.get('vendor_name')}")

    # --- 2. Total Amount Check ---
    inv_total = float(invoice_data.get('total_amount', 0.0))
    po_total = float(po_data.get('total_amount', 0.0))
    if abs(inv_total - po_total) > 0.01:
        results["isMatch"] = False
        results["mismatch_categories"].append("Total Price Variance")
        difference = round(abs(inv_total - po_total), 2)
        results["details"].append(f"Total Amount Mismatch: Invoice: ${inv_total:.2f} vs. PO: ${po_total:.2f}. Difference: ${difference:.2f}")
    else:
        results["details"].append(f"Total Amount Match: ${inv_total:.2f}")

    # --- 3. Line-Item Verification (NEW COMPLEX CHECK) ---
    inv_items = invoice_data.get('items', [])
    # Create a mutable copy of PO items to track which ones have been matched
    po_items_remaining = list(po_data.get('items', []))
    
    line_item_mismatch = False
    
    for inv_item in inv_items:
        # Find the best match for the current invoice item in the remaining PO items
        matched_po_item = find_best_item_match(inv_item, po_items_remaining)
        
        if matched_po_item:
            # Check Quantity
            inv_qty = inv_item.get('quantity', 0)
            po_qty = matched_po_item.get('quantity', 0)
            
            if abs(inv_qty - po_qty) > 0:
                results["isMatch"] = False
                line_item_mismatch = True
                results["details"].append(f"⚠️ QTY MISMATCH for Item '{inv_item['description']}': Invoice Qty ({inv_qty}) != PO Qty ({po_qty})")
            
            # Check Unit Price (allowing small tolerance for floating point errors)
            inv_price = inv_item.get('unit_price', 0.0)
            po_price = matched_po_item.get('unit_price', 0.0)
            
            if abs(inv_price - po_price) > 0.01:
                results["isMatch"] = False
                line_item_mismatch = True
                results["details"].append(f"⚠️ PRICE MISMATCH for Item '{inv_item['description']}': Invoice Price (${inv_price:.2f}) != PO Price (${po_price:.2f})")
            
            # Remove matched item from remaining PO list to ensure each PO item is only used once
            po_items_remaining.remove(matched_po_item)
        else:
            results["isMatch"] = False
            line_item_mismatch = True
            results["details"].append(f"❌ UNMATCHED ITEM: Invoice item '{inv_item['description']}' not found on PO.")

    # Check for items ordered on PO but not billed on Invoice
    if po_items_remaining:
        results["isMatch"] = False
        line_item_mismatch = True
        results["details"].append(f"❌ MISSING ITEMS: {len(po_items_remaining)} item(s) ordered on PO but not found on Invoice.")
    
    if line_item_mismatch:
        # Only add the Line Item Discrepancy category if actual item mismatches occurred
        results["mismatch_categories"].append("Line Item Discrepancy")
    else:
        results["details"].append("✓ All Line Items Verified.")


    # --- 4. Agent-Style Summary Generation ---
    if not results["isMatch"]:
        results["status"] = "NEEDS REVIEW"
        
        # Use set/sorted to clean up and prioritize categories for the summary
        category_list = ", ".join(sorted(list(set(results["mismatch_categories"])))) 
        
        results["summary"] = f"⚠️ CRITICAL DISCREPANCY: Review required due to {category_list}. Please check the Verification Details below."
    
    elif results["isMatch"]:
        results["summary"] = "Perfect 2-Way Match! All key fields and line items verified and approved for payment processing."

    return results
