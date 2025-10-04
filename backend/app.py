import os
import json
import threading
import uuid
import time
from flask import Flask, request, jsonify
from flask_cors import CORS
from dotenv import load_dotenv
from google import genai

# FIX: Import modular functionality using the direct module name (non-relative import)
# This works because __init__.py is present in the backend directory.
from utils import extract_text_from_file, gemini_extract_data, perform_matching

# --- Configuration and Initialization ---

app = Flask(__name__)
CORS(app)

# Load environment variables (GEMINI_API_KEY)
load_dotenv()
api_key = os.environ.get("GEMINI_API_KEY")

# Global job manager and AI client instances
job_manager = {}
client = None

if not api_key:
    print("Warning: GEMINI_API_KEY not set. Using mock client.")
else:
    try:
        # Initialize Gemini client
        client = genai.Client(api_key=api_key)
        print("Gemini client initialized successfully.")
    except Exception as e:
        print(f"Error initializing Gemini client: {e}")
        client = None

# --- Main Job Runner (Async Thread) ---

def run_matching_job(job_id, invoice_file_data, po_file_data, invoice_filename, po_filename):
    """The actual long-running task to be executed in a separate thread."""
    print(f"Job {job_id}: Starting document matching...")
    job_manager[job_id]["progress"] = 5
    
    try:
        # 1. Extract Raw Text (Progress: 5% -> 25%) - Uses Advanced OCR Fallback
        time.sleep(0.5)
        raw_invoice_text = extract_text_from_file(invoice_file_data, invoice_filename)
        job_manager[job_id]["progress"] = 15
        raw_po_text = extract_text_from_file(po_file_data, po_filename)
        job_manager[job_id]["progress"] = 25

        if raw_invoice_text.startswith("Error") or raw_po_text.startswith("Error"):
            raise Exception(f"File Extraction Error: {raw_invoice_text} | {raw_po_text}")

        # 2. AI Structured Extraction - Invoice (Progress: 25% -> 50%)
        if not client:
            # Fallback to Mock Data if client is not initialized
            time.sleep(2)
            invoice_data = {
                "document_type": "Invoice",
                "document_id": "INV-2024-001",
                "vendor_name": "TechSupply Co.",
                "total_amount": 1295.00,
                "items": [{"description": "Laptop", "quantity": 1, "unit_price": 1200.00}],
            }
            job_manager[job_id]["progress"] = 50
        else:
            # Note: client is passed to the utility function
            invoice_data = gemini_extract_data(client, raw_invoice_text, "Invoice")
            job_manager[job_id]["progress"] = 50
            if "error" in invoice_data: raise Exception(f"AI Extraction Error (Invoice): {invoice_data['error']}")
        
        # 3. AI Structured Extraction - PO (Progress: 50% -> 75%)
        if not client:
            # Fallback to Mock Data if client is not initialized
            po_data = {
                "document_type": "Purchase Order",
                "document_id": "PO-2024-001",
                "vendor_name": "TechSupply Co.",
                "total_amount": 1295.00,
                "items": [{"description": "Laptop", "quantity": 1, "unit_price": 1200.00}],
            }
            job_manager[job_id]["progress"] = 75
        else:
            # Note: client is passed to the utility function
            po_data = gemini_extract_data(client, raw_po_text, "Purchase Order")
            job_manager[job_id]["progress"] = 75
            if "error" in po_data: raise Exception(f"AI Extraction Error (PO): {po_data['error']}")

        # 4. Perform Matching and Finalize Results (Progress: 75% -> 100%) - Uses Line-Item Check
        final_results = perform_matching(invoice_data, po_data)
        
        # Final status update
        job_manager[job_id]["results"] = final_results
        job_manager[job_id]["progress"] = 100
        job_manager[job_id]["status"] = "completed"
        print(f"Job {job_id}: Completed successfully. Match: {final_results['isMatch']}")

    except Exception as e:
        # Graceful failure update
        if job_id in job_manager:
            job_manager[job_id]["error"] = str(e)
            job_manager[job_id]["status"] = "failed"
            job_manager[job_id]["progress"] = 100
        print(f"Job {job_id}: Failed with error: {e}")

# --- API ENDPOINTS ---

@app.route("/submit_job", methods=["POST"])
def submit_job():
    """Receives two files (invoice and po) and starts the matching job asynchronously."""
    
    if 'invoice_file' not in request.files or 'po_file' not in request.files:
        return jsonify({"error": "Both 'invoice_file' and 'po_file' are required."}), 400

    invoice_file = request.files["invoice_file"]
    po_file = request.files["po_file"]
    
    if not invoice_file.filename or not po_file.filename:
         return jsonify({"error": "Filenames cannot be empty."}), 400
        
    try:
        invoice_file_data = invoice_file.read()
        po_file_data = po_file.read()

    except Exception as e:
        return jsonify({"error": f"Error reading files: {e}"}), 500

    # Start the asynchronous job
    job_id = str(uuid.uuid4())
    job_manager[job_id] = {"status": "processing", "progress": 0, "results": None, "error": None}
    
    thread = threading.Thread(
        target=run_matching_job, 
        args=(
            job_id, 
            invoice_file_data, 
            po_file_data, 
            invoice_file.filename, 
            po_file.filename
        )
    )
    thread.start()
    
    return jsonify({"job_id": job_id}), 202 

@app.route("/status/<job_id>", methods=["GET"])
def get_status(job_id):
    """Allows the frontend to poll for the current progress and final results."""
    if job_id not in job_manager:
        return jsonify({"error": "Job not found"}), 404
        
    job = job_manager[job_id]
    
    if job["status"] == "completed":
        results = job["results"]
        # Note: extracted data fields (invoice_data, po_data) are included in results
        return jsonify({
            "status": "completed",
            "progress": 100,
            "results": results
        }), 200
        
    elif job["status"] == "failed":
        error_msg = job["error"]
        
        return jsonify({
            "status": "failed",
            "progress": 100,
            "error": error_msg
        }), 500 
        
    else:
        
        return jsonify({
            "status": "processing",
            "progress": job["progress"]
        }), 200

@app.route("/extract_preview", methods=["POST"])
def extract_preview():
    """Receives a single file and performs fast extraction for immediate UI feedback."""
    if 'file' not in request.files:
        return jsonify({"error": "No file uploaded"}), 400

    file = request.files["file"]
    
    if not file.filename:
         return jsonify({"error": "Filename cannot be empty."}), 400
        
    try:
        file_data = file.read()
        filename = file.filename
        
        # 1. Raw text extraction
        raw_text = extract_text_from_file(file_data, filename)
        if raw_text.startswith("Error"):
             return jsonify({"error": f"Extraction failed: {raw_text}"}), 500

        # 2. AI Structured Extraction (Note: client is passed)
        extracted_data = gemini_extract_data(client, raw_text, "Document")
        
        if "error" in extracted_data: 
             return jsonify({"error": f"AI Parsing failed: {extracted_data['error']}"}), 500

        # Return only the essential fields for preview
        return jsonify({
            "document_id": extracted_data.get('document_id', 'N/A'),
            "vendor_name": extracted_data.get('vendor_name', 'N/A'),
        }), 200

    except Exception as e:
        return jsonify({"error": f"Server error during preview extraction: {e}"}), 500


if __name__ == "__main__":
    # In a production environment, set debug=False
    app.run(debug=True, host="0.0.0.0", port=5000)
