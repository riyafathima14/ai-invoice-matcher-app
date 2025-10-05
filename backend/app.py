import os
import json
import threading
import uuid
import time
from flask import Flask, request, jsonify
from flask_cors import CORS
from dotenv import load_dotenv
from google import genai


from utils import extract_text_from_file, gemini_extract_data, perform_matching



app = Flask(__name__)
CORS(app)


load_dotenv()
api_key = os.environ.get("GEMINI_API_KEY")


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



def run_matching_job(job_id, invoice_file_data, po_file_data, invoice_filename, po_filename):
    """The actual long-running task to be executed in a separate thread."""
    print(f"Job {job_id}: Starting document matching...")
    job_manager[job_id]["progress"] = 5
    
    try:
        time.sleep(0.5)
        raw_invoice_text = extract_text_from_file(invoice_file_data, invoice_filename)
        job_manager[job_id]["progress"] = 15
        raw_po_text = extract_text_from_file(po_file_data, po_filename)
        job_manager[job_id]["progress"] = 25

        if raw_invoice_text.startswith("Error") or raw_po_text.startswith("Error"):
            raise Exception(f"File Extraction Error: {raw_invoice_text} | {raw_po_text}")

        if not client:
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
            invoice_data = gemini_extract_data(client, raw_invoice_text, "Invoice")
            job_manager[job_id]["progress"] = 50
            if "error" in invoice_data: raise Exception(f"AI Extraction Error (Invoice): {invoice_data['error']}")
        
        if not client:
            po_data = {
                "document_type": "Purchase Order",
                "document_id": "PO-2024-001",
                "vendor_name": "TechSupply Co.",
                "total_amount": 1295.00,
                "items": [{"description": "Laptop", "quantity": 1, "unit_price": 1200.00}],
            }
            job_manager[job_id]["progress"] = 75
        else:
            po_data = gemini_extract_data(client, raw_po_text, "Purchase Order")
            job_manager[job_id]["progress"] = 75
            if "error" in po_data: raise Exception(f"AI Extraction Error (PO): {po_data['error']}")

        final_results = perform_matching(invoice_data, po_data)
        
        job_manager[job_id]["results"] = final_results
        job_manager[job_id]["progress"] = 100
        job_manager[job_id]["status"] = "completed"
        print(f"Job {job_id}: Completed successfully. Match: {final_results['isMatch']}")

    except Exception as e:
        if job_id in job_manager:
            job_manager[job_id]["error"] = str(e)
            job_manager[job_id]["status"] = "failed"
            job_manager[job_id]["progress"] = 100
        print(f"Job {job_id}: Failed with error: {e}")


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
        
        raw_text = extract_text_from_file(file_data, filename)
        if raw_text.startswith("Error"):
             return jsonify({"error": f"Extraction failed: {raw_text}"}), 500

        extracted_data = gemini_extract_data(client, raw_text, "Document")
        
        if "error" in extracted_data: 
             return jsonify({"error": f"AI Parsing failed: {extracted_data['error']}"}), 500

        return jsonify({
            "document_id": extracted_data.get('document_id', 'N/A'),
            "vendor_name": extracted_data.get('vendor_name', 'N/A'),
        }), 200

    except Exception as e:
        return jsonify({"error": f"Server error during preview extraction: {e}"}), 500


if __name__ == "__main__":
    app.run(debug=False, host="0.0.0.0", port=5000)
