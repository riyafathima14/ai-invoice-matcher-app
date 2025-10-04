import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:invoice_matcher/api_services/api_service.dart'; // Import structures

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

  Future<void> _handleFilePick(BuildContext context) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );

    if (result != null && result.files.single.bytes != null) {
      onPickFile(docType, result.files.single);
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
