import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb; 
import 'dart:io' show Platform; // Explicitly showing import for Platform
import 'package:file_picker/file_picker.dart';
import 'package:invoice_matcher/api_services/api_service.dart';
import 'package:permission_handler/permission_handler.dart';

typedef FilePickCallback = void Function(String docType, PlatformFile file);

class FileUploaderCard extends StatelessWidget {
  final String docType;
  final Document? doc;
  final MatchResult? result;
  final bool isProcessing;
  final bool isPickingFile;
  final FilePickCallback onPickFile;

  const FileUploaderCard({
    super.key,
    required this.docType,
    required this.doc,
    required this.result,
    required this.isProcessing,
    required this.isPickingFile,
    required this.onPickFile,
  });

  Future<bool> _checkAndRequestPermission(BuildContext context) async {
    // 1. Skip check if running on the web or desktop/fuchsia
    if (kIsWeb) {
      return true;
    }
    
    // Check for non-Android/iOS platforms (Windows, Linux, macOS)
    if (!kIsWeb) {
      try {
        if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
          return true;
        }
      } catch (e) {
        // Fallback if dart:io Platform is not available in some environments
        // This usually means we are on a mobile platform if it's not kIsWeb
        print('Platform check failed, assuming mobile environment.');
      }
    }


    // 2. Mobile Platform Logic (Android/iOS)
    try {
      // Use Permission.storage, which is the most common permission used by file_picker.
      // On Android 13 (SDK 33), this implicitly translates to Media/Files access
      // depending on the file type being accessed via the system picker.
      PermissionStatus status = await Permission.storage.request();
      
      if (status.isGranted) {
        return true;
      }
      
      if (status.isPermanentlyDenied) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Permission to access files is permanently denied. Please enable it in Settings.'),
            action: SnackBarAction(
              label: 'Open Settings',
              onPressed: () => openAppSettings(),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
        return false;
      }
      
      return status.isGranted;
      
    } catch (e) {
      print('Permission check error: $e. Proceeding without explicit permission check.');
      return true; 
    }
  }

  Future<void> _handleFilePick(BuildContext context) async {
    // 1. Check/Request Runtime Permission (Mobile only)
    if (!await _checkAndRequestPermission(context)) {
      return; // Stop if permission was denied
    }

    // 2. Proceed with file picking
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      // CRITICAL: Set withData to true to try and get bytes immediately (good for web/debug)
      withData: true, 
    );

    // 3. Robust validation check
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.single;

      // Check if file bytes (web/in-memory) OR file path (mobile temporary) is available.
      if (file.bytes != null || file.path != null) { 
        onPickFile(docType, file);
        return;
      }
    }
    
    // If we reach here, picking failed silently, show a message on mobile.
    if (!kIsWeb) {
       ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File selection failed. Please try a different file or location.'),
            duration: Duration(seconds: 3),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUploaded = doc != null;
    final primaryColor = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;
    final isEnabled = !isProcessing && !isPickingFile;

    String statusText = 'Ready for matching.';

    if (doc != null && doc!.id == 'Extracting...') {
      statusText = 'Extracting ID/Vendor...';
    } else if (doc != null && doc!.id == 'Error') {
      statusText = 'Extraction Failed: ${doc!.vendor}';
    } else if (isProcessing) {
      statusText = 'Processing AI extraction...';
    } else if (result != null) {
      statusText =
          result!.isMatch
              ? 'Status: ${result!.status} (Match)'
              : 'Status: ${result!.status} (Mismatch)';
    } else if (doc != null && doc!.id != 'N/A') {
      statusText = 'Extraction Complete. Ready for matching.';
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side:
            isUploaded
                ? BorderSide(color: primaryColor, width: 2)
                : BorderSide.none,
      ),
      child: InkWell(
        onTap: isEnabled ? () => _handleFilePick(context) : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    docType,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                  Icon(
                    isUploaded ? Icons.check_circle : Icons.upload_file,
                    color:
                        isUploaded
                            ? Colors.green
                            : primaryColor.withOpacity(0.7),
                    size: 32,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (isUploaded)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'File: ${doc!.name}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Display Extracted Data
                    Text(
                      'ID: ${doc!.id}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Vendor: ${doc!.vendor}',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    // Display Current Status
                    Text(
                      statusText,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color:
                            doc!.id == 'Error'
                                ? Colors.red.shade700
                                : onSurface.withOpacity(0.8),
                      ),
                    ),
                  ],
                )
              else
                Text(
                  'Click to upload a ${docType} (PDF or Image).',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: onSurface.withOpacity(0.6),
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
