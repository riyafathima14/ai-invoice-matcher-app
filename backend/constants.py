from google.genai import types

DOCUMENT_SCHEMA = types.Schema(
    type=types.Type.OBJECT,
    properties={
        "document_type": types.Schema(type=types.Type.STRING, description="The type of document: 'Invoice' or 'Purchase Order'"),
        "document_id": types.Schema(type=types.Type.STRING, description="The unique ID or number (e.g., INV-2024-001 or PO-2024-001)"),
        "vendor_name": types.Schema(type=types.Type.STRING, description="The name of the vendor/company"),
        "total_amount": types.Schema(type=types.Type.NUMBER, description="The final total monetary value"),
        "items": types.Schema(
            type=types.Type.ARRAY,
            items=types.Schema(
                type=types.Type.OBJECT,
                properties={
                    "description": types.Schema(type=types.Type.STRING),
                    "quantity": types.Schema(type=types.Type.NUMBER),
                    "unit_price": types.Schema(type=types.Type.NUMBER),
                },
                required=["description", "quantity", "unit_price"],
            ),
            description="A list of line items, including description, quantity, and unit price.",
        ),
    },
    required=["document_type", "document_id", "vendor_name", "total_amount", "items"],
)
