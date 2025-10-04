import 'package:flutter/material.dart';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:invoice_matcher/api_services/api_service.dart';
import 'package:invoice_matcher/widgets/file_uploader_card.dart';
import 'package:invoice_matcher/widgets/result_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ApiService _apiService = ApiService();
  Document? _invoice;
  Document? _po;
  MatchResult? _result;
  double _progress = 0.0;
  bool _isProcessing = false;
  String _jobId = '';
  Timer? _pollingTimer;
  bool _isPickingFile = false;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _resultsKey = GlobalKey();

  void _handleFilePick(String docType, PlatformFile file) {
    if (_isProcessing || _isPickingFile) return;

    setState(() {
      _isPickingFile = true;
      _result = null;
    });

    Document newDoc = Document(
      type: docType,
      name: file.name,
      id: 'Extracting...',
      vendor: 'Extracting...',
      file: file,
    );

    setState(() {
      if (docType == 'Invoice') {
        _invoice = newDoc;
      } else {
        _po = newDoc;
      }
    });

    _apiService
        .getPreviewData(file)
        .then((previewData) {
          setState(() {
            final updatedDoc = newDoc.copyWith(
              id: previewData['id'],
              vendor: previewData['vendor'],
            );
            if (docType == 'Invoice') {
              _invoice = updatedDoc;
            } else {
              _po = updatedDoc;
            }
          });
        })
        .catchError((e) {
          setState(() {
            final errorDoc = newDoc.copyWith(id: 'Error', vendor: e.toString());
            if (docType == 'Invoice') {
              _invoice = errorDoc;
            } else {
              _po = errorDoc;
            }
          });
        })
        .whenComplete(() {
          setState(() {
            _isPickingFile = false;
          });
        });
  }

  Future<void> _submitJob() async {
    if (_invoice == null || _po == null || _isProcessing) return;

    setState(() {
      _isProcessing = true;
      _progress = 0.01;
      _result = null;
      _jobId = '';
    });

    try {
      _jobId = await _apiService.submitJob(_invoice!, _po!);
      _startPolling();
    } catch (e) {
      _handleJobFailure('Job Submission Failed: $e');
    }
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) async {
      await _checkJobStatus();
    });
  }

  Future<void> _checkJobStatus() async {
    if (_jobId.isEmpty) return;

    try {
      final jsonResponse = await _apiService.checkStatus(_jobId);

      if (jsonResponse['status'] == 'completed') {
        _stopPolling();
        _handleJobSuccess(jsonResponse['results']);
      } else if (jsonResponse['status'] == 'processing') {
        setState(() {
          _progress = (jsonResponse['progress'] as int).toDouble() / 100.0;
        });
      }
    } catch (e) {
      _stopPolling();

      String errorMessage = e.toString();

      if (errorMessage.contains('503 UNAVAILABLE') ||
          errorMessage.contains('timed out')) {
        _handleJobFailure(errorMessage, isApiOverload: true);
      } else {
        _handleJobFailure('Polling Failed: $errorMessage');
      }
    }
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    setState(() {
      _isProcessing = false;
      _progress = 1.0;
    });
  }

  void _handleJobSuccess(Map<String, dynamic> results) {
    setState(() {
      _result = MatchResult.fromJson(results);
    });

    // --- AUTO-SCROLL TO RESULT ---
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_resultsKey.currentContext != null) {
        Scrollable.ensureVisible(
          _resultsKey.currentContext!,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
          alignment: 0.1,
        );
      }
    });
  }

  /// Handles and displays any job failure.
  void _handleJobFailure(String errorMsg, {bool isApiOverload = false}) {
    setState(() {
      _result = MatchResult(
        isMatch: false,
        status: isApiOverload ? 'TRY AGAIN' : 'ERROR',
        summary:
            isApiOverload
                ? 'The AI model is temporarily busy (503). Please wait 30 seconds and try again.'
                : 'A critical error occurred: $errorMsg',
        details:
            isApiOverload
                ? [
                  'This is a temporary issue with the AI service. Retrying in a few moments often resolves it.',
                ]
                : [errorMsg],
      );

      _isProcessing = false;
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Invoice & PO Matcher'),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Automated Document Verification',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Upload an Invoice and a Purchase Order to check for data consistency.',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 32),

                if (isMobile)
                  Column(
                    children: [
                      FileUploaderCard(
                        docType: 'Invoice',
                        doc: _invoice,
                        result: _result,
                        isProcessing: _isProcessing,
                        isPickingFile: _isPickingFile,
                        onPickFile: _handleFilePick,
                      ),
                      const SizedBox(height: 20),
                      FileUploaderCard(
                        docType: 'Purchase Order',
                        doc: _po,
                        result: _result,
                        isProcessing: _isProcessing,
                        isPickingFile: _isPickingFile,
                        onPickFile: _handleFilePick,
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: FileUploaderCard(
                          docType: 'Invoice',
                          doc: _invoice,
                          result: _result,
                          isProcessing: _isProcessing,
                          isPickingFile: _isPickingFile,
                          onPickFile: _handleFilePick,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: FileUploaderCard(
                          docType: 'Purchase Order',
                          doc: _po,
                          result: _result,
                          isProcessing: _isProcessing,
                          isPickingFile: _isPickingFile,
                          onPickFile: _handleFilePick,
                        ),
                      ),
                    ],
                  ),

                const SizedBox(height: 40),

                Opacity(
                  opacity:
                      (_invoice != null &&
                              _po != null &&
                              _invoice!.id != 'Extracting...' &&
                              _po!.id != 'Extracting...')
                          ? 1.0
                          : 0.5,
                  child: ElevatedButton.icon(
                    onPressed:
                        (_invoice != null &&
                                _po != null &&
                                !_isProcessing &&
                                !_isPickingFile &&
                                _invoice!.id != 'Extracting...' &&
                                _po!.id != 'Extracting...')
                            ? _submitJob
                            : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 6,
                    ),
                    icon:
                        (_isProcessing || _isPickingFile)
                            ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                            : const Icon(Icons.compare_arrows, size: 28),
                    label: Text(
                      _isProcessing
                          ? 'Processing... (${(_progress * 100).toInt()}%)'
                          : (_isPickingFile ||
                                  _invoice?.id == 'Extracting...' ||
                                  _po?.id == 'Extracting...'
                              ? 'Fetching Data...'
                              : 'Run Automated Matcher'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                if (_isProcessing) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: _progress,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.2),
                    color: Theme.of(context).colorScheme.primary,
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ],

                const SizedBox(height: 40),

                ResultsCard(result: _result, resultsKey: _resultsKey),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
