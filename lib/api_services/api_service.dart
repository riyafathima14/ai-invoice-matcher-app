import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

const String backendUrl = 'http://127.0.0.1:5000'; 


class Document {
  final String type;
  final String name;
  final String id;
  final String vendor; 
  final PlatformFile file; 

  const Document({
    required this.type,
    required this.name,
    required this.id,
    required this.vendor, 
    required this.file,
  });

  Document copyWith({
    String? id,
    String? vendor,
    PlatformFile? file,
  }) {
    return Document(
      type: type,
      name: name,
      id: id ?? this.id,
      vendor: vendor ?? this.vendor,
      file: file ?? this.file,
    );
  }
}

class MatchResult {
  final bool isMatch;
  final String status;
  final String summary;
  final List<dynamic> details;

  const MatchResult({
    required this.isMatch,
    required this.status,
    required this.summary,
    required this.details,
  });

  factory MatchResult.fromJson(Map<String, dynamic> json) {
    return MatchResult(
      isMatch: json['isMatch'] ?? false,
      status: json['status'] ?? 'UNKNOWN',
      summary: json['summary'] ?? 'No summary available.',
      details: json['details'] ?? [],
    );
  }
}

// --- API Service Class ---

class ApiService {
  // --- 1. Job Submission ---
  Future<String> submitJob(Document invoice, Document po) async {
    var uri = Uri.parse('$backendUrl/submit_job');
    var request = http.MultipartRequest('POST', uri);

    request.files.add(http.MultipartFile.fromBytes(
      'invoice_file',
      invoice.file.bytes!.toList(),
      filename: invoice.file.name,
    ));

    request.files.add(http.MultipartFile.fromBytes(
      'po_file',
      po.file.bytes!.toList(),
      filename: po.file.name,
    ));

    var streamedResponse = await request.send();
    var response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 202) {
      final data = jsonDecode(response.body);
      return data['job_id'];
    } else {
      throw Exception('Job submission failed: ${response.body}');
    }
  }

  // --- 2. Status Polling ---
  Future<Map<String, dynamic>> checkStatus(String jobId) async {
    var uri = Uri.parse('$backendUrl/status/$jobId');
    var response = await http.get(uri);
    final jsonResponse = jsonDecode(response.body);

    if (response.statusCode == 500) {
      String errorMessage = jsonResponse['error'] ?? 'Unknown backend error.';
      throw Exception(errorMessage); 
    }
    if (response.statusCode != 200) {
      throw Exception('Server Status Check Failed: ${response.statusCode}'); 
    }

    return jsonResponse;
  }
  
  Future<Map<String, String>> getPreviewData(PlatformFile file) async {
    try {
      var uri = Uri.parse('$backendUrl/extract_preview');
      var request = http.MultipartRequest('POST', uri);
      
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        file.bytes!.toList(),
        filename: file.name,
      ));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      final jsonResponse = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'id': jsonResponse['document_id'] ?? 'N/A',
          'vendor': jsonResponse['vendor_name'] ?? 'N/A',
        };
      } else {
        return {'id': 'Error', 'vendor': jsonResponse['error'] ?? 'API Error'};
      }
    } catch (e) {
      return {'id': 'Error', 'vendor': 'Network error'};
    }
  }
}
