import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:llm_toolkit/src/core/rag/rag_engine.dart';
import 'package:llm_toolkit/src/core/rag/engines/llama_rag_engine.dart';
import 'package:llm_toolkit/src/core/rag/models/rag_models.dart';
import '../models/app_models.dart';
import '../utils/logger.dart';

class RagService extends ChangeNotifier {
  final AppLogger _logger = AppLogger();

  RagEngine? _ragEngine;
  final List<RagDocument> _documents = [];
  bool _isInitialized = false;
  bool _isProcessing = false;
  String? _selectedEmbeddingModel;
  String? _selectedLLMModel;

  // Getters
  RagEngine? get ragEngine => _ragEngine;
  List<RagDocument> get documents => List.unmodifiable(_documents);
  bool get isInitialized => _isInitialized;
  bool get isProcessing => _isProcessing;
  String? get selectedEmbeddingModel => _selectedEmbeddingModel;
  String? get selectedLLMModel => _selectedLLMModel;
  AppLogger get logger => _logger;

  /// Initialize RAG engine with selected models
  Future<void> initializeRAG({
    required String embeddingModelPath,
    required String llmModelPath,
  }) async {
    _logger.info('🚀 Initializing RAG engine...');
    _setProcessing(true);

    try {
      // Dispose existing engine if any
      if (_ragEngine != null) {
        await _ragEngine!.dispose();
        _ragEngine = null;
      }

      // Create new RAG engine
      _ragEngine = LlamaRagEngine(
        embeddingModelPath: embeddingModelPath,
        llmModelPath: llmModelPath,
        libraryPath: 'libllama.so',
      );

      await _ragEngine!.initialize();

      _selectedEmbeddingModel = embeddingModelPath.split('/').last;
      _selectedLLMModel = llmModelPath.split('/').last;
      _isInitialized = true;

      _logger.success('✅ RAG engine initialized successfully');
    } catch (e) {
      _logger.error('❌ Failed to initialize RAG engine', e);
      _isInitialized = false;
      rethrow;
    } finally {
      _setProcessing(false);
    }
  }

  /// Add document from file picker - FIXED to allow all file types
  Future<void> addDocumentFromFile() async {
    if (!_isInitialized) {
      throw Exception('RAG engine not initialized');
    }

    _logger.info('📂 Opening file picker for document...');

    try {
      // TRY METHOD 1: Use FileType.any first
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
        withData: false,
        withReadStream: false,
      );

      // If no files selected, try the custom extension method
      if (result == null) {
        _logger.info(
          '📂 No files selected with FileType.any, trying custom...',
        );
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['txt', 'md', 'pdf', 'doc', 'docx', 'rtf'],
          allowMultiple: true,
        );
      }

      if (result != null && result.files.isNotEmpty) {
        _setProcessing(true);

        _logger.info('📂 Selected ${result.files.length} files');

        for (PlatformFile file in result.files) {
          if (file.path != null) {
            _logger.info(
              '📄 Processing file: ${file.name} (${file.extension})',
            );

            // Check if file type is supported
            if (_isFileTypeSupported(file.name)) {
              await _processAndAddDocument(file.path!, file.name);
            } else {
              _logger.warning('⚠️ Unsupported file type: ${file.name}');
              throw Exception(
                'Unsupported file type: ${file.extension}. Supported: TXT, MD, PDF',
              );
            }
          } else {
            _logger.warning('⚠️ File path is null for: ${file.name}');
          }
        }

        _logger.success('✅ Documents added successfully');
      } else {
        _logger.info('📂 File selection cancelled or no files selected');
      }
    } catch (e) {
      _logger.error('❌ Error adding document', e);
      rethrow;
    } finally {
      _setProcessing(false);
    }
  }

  /// Check if file type is supported
  bool _isFileTypeSupported(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    final supportedExtensions = ['txt', 'md', 'pdf', 'text', 'markdown'];
    return supportedExtensions.contains(extension);
  }

  /// Alternative method to add documents with different approach
  Future<void> addDocumentFromFileAlternative() async {
    if (!_isInitialized) {
      throw Exception('RAG engine not initialized');
    }

    _logger.info('📂 Opening alternative file picker...');

    try {
      // Try different file picker configurations
      FilePickerResult? result;

      // Method 1: Try with specific document types
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
        allowMultiple: true,
      );

      // If no text files, try PDFs
      if (result == null || result.files.isEmpty) {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf'],
          allowMultiple: true,
        );
      }

      // If still no files, try any file
      if (result == null || result.files.isEmpty) {
        result = await FilePicker.platform.pickFiles(
          type: FileType.any,
          allowMultiple: true,
        );
      }

      if (result != null && result.files.isNotEmpty) {
        _setProcessing(true);

        for (PlatformFile file in result.files) {
          if (file.path != null) {
            try {
              await _processAndAddDocument(file.path!, file.name);
            } catch (e) {
              _logger.error('❌ Failed to process ${file.name}', e);
              // Continue with other files
            }
          }
        }

        _logger.success('✅ Documents processing completed');
      } else {
        _logger.info('📂 No files selected');
      }
    } catch (e) {
      _logger.error('❌ Error in alternative file picker', e);
      rethrow;
    } finally {
      _setProcessing(false);
    }
  }

  /// Process and add document to RAG engine with better error handling
  Future<void> _processAndAddDocument(String filePath, String fileName) async {
    try {
      _logger.info('📄 Processing document: $fileName');

      // Check if file exists
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File does not exist: $filePath');
      }

      // Get file info
      final fileSize = await file.length();
      _logger.info('📄 File size: ${_formatBytes(fileSize)}');

      String content;
      final fileExtension = fileName.toLowerCase().split('.').last;

      _logger.info('📄 File extension detected: $fileExtension');

      switch (fileExtension) {
        case 'pdf':
          content = await _extractPdfText(filePath);
          break;
        case 'txt':
        case 'text':
          content = await _extractTextFile(filePath);
          break;
        case 'md':
        case 'markdown':
          content = await _extractTextFile(filePath);
          break;
        default:
          // Try to read as text file anyway
          _logger.info('📄 Unknown extension, trying to read as text...');
          content = await _extractTextFile(filePath);
          break;
      }

      if (content.trim().isEmpty) {
        _logger.warning(
          '⚠️ Document is empty or could not extract text: $fileName',
        );
        throw Exception(
          'Document appears to be empty or text could not be extracted',
        );
      }

      _logger.info('📄 Extracted ${content.length} characters from $fileName');

      // Create document ID
      final documentId = 'doc_${DateTime.now().millisecondsSinceEpoch}';

      // Add to RAG engine
      await _ragEngine!.addDocument(documentId, content, {
        'fileName': fileName,
        'filePath': filePath,
        'fileType': fileExtension,
        'addedAt': DateTime.now().toIso8601String(),
        'fileSize': content.length,
        'originalFileSize': fileSize,
      });

      // Add to local documents list
      final ragDoc = RagDocument(
        id: documentId,
        name: fileName,
        content: content,
        addedAt: DateTime.now(),
        chunkCount: _estimateChunkCount(content),
        fileSize: content.length,
        fileType: fileExtension,
      );

      _documents.add(ragDoc);
      _logger.success(
        '📄 Added document: $fileName (${ragDoc.chunkCount} chunks, ${ragDoc.formattedSize})',
      );
    } catch (e) {
      _logger.error('❌ Error processing document: $fileName', e);
      rethrow;
    }
  }

  /// Extract text from PDF files
  Future<String> _extractPdfText(String filePath) async {
    try {
      _logger.info('📖 Extracting text from PDF...');

      final file = File(filePath);
      final bytes = await file.readAsBytes();

      // Load PDF document
      final PdfDocument document = PdfDocument(inputBytes: bytes);

      // Create text extractor
      final PdfTextExtractor textExtractor = PdfTextExtractor(document);

      // Extract all text at once (simpler approach)
      final String extractedText = textExtractor.extractText();

      // Dispose the document
      document.dispose();

      _logger.success(
        '✅ PDF text extracted: ${extractedText.length} characters',
      );

      if (extractedText.trim().isEmpty) {
        throw Exception(
          'No text could be extracted from PDF. It might be an image-based PDF or corrupted.',
        );
      }

      return extractedText.trim();
    } catch (e) {
      _logger.error('❌ Failed to extract PDF text', e);
      throw Exception('Failed to extract text from PDF: $e');
    }
  }

  /// Extract text from plain text files with better encoding detection
  Future<String> _extractTextFile(String filePath) async {
    try {
      _logger.info('📝 Reading text file...');

      final file = File(filePath);

      // Try UTF-8 first
      try {
        final content = await file.readAsString(encoding: utf8);
        _logger.success('✅ Text file read with UTF-8 encoding');
        return content;
      } catch (e) {
        _logger.info('⚠️ UTF-8 failed, trying Latin-1 encoding');

        // Fallback to Latin-1
        try {
          final content = await file.readAsString(encoding: latin1);
          _logger.success('✅ Text file read with Latin-1 encoding');
          return content;
        } catch (e2) {
          _logger.info('⚠️ Latin-1 failed, trying ASCII encoding');

          // Try ASCII
          try {
            final content = await file.readAsString(encoding: ascii);
            _logger.success('✅ Text file read with ASCII encoding');
            return content;
          } catch (e3) {
            _logger.info('⚠️ ASCII failed, reading as bytes');

            // Last resort: read as bytes and convert
            final bytes = await file.readAsBytes();
            final content = _convertBytesToString(bytes);
            _logger.success(
              '✅ Text file read as bytes with fallback conversion',
            );
            return content;
          }
        }
      }
    } catch (e) {
      _logger.error('❌ Failed to read text file', e);
      throw Exception('Failed to read text file: $e');
    }
  }

  /// Convert bytes to string with fallback for invalid encoding
  String _convertBytesToString(List<int> bytes) {
    final StringBuffer buffer = StringBuffer();

    for (int i = 0; i < bytes.length; i++) {
      final byte = bytes[i];

      // Handle printable ASCII characters
      if (byte >= 32 && byte <= 126) {
        buffer.writeCharCode(byte);
      } else if (byte == 10 || byte == 13 || byte == 9) {
        // Preserve newlines, carriage returns, and tabs
        buffer.writeCharCode(byte);
      } else if (byte == 0) {
        // Skip null bytes
        continue;
      } else {
        // Replace problematic characters with space
        buffer.write(' ');
      }
    }

    return buffer.toString();
  }

  /// Format bytes for display
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Remove document from RAG engine
  Future<void> removeDocument(String documentId) async {
    if (!_isInitialized) return;

    try {
      await _ragEngine!.removeDocument(documentId);
      _documents.removeWhere((doc) => doc.id == documentId);
      _logger.success('🗑️ Document removed successfully');
    } catch (e) {
      _logger.error('❌ Error removing document', e);
      rethrow;
    }
    notifyListeners();
  }

  /// Query RAG engine
  Future<RagResponse> queryRAG(String query, {RagConfig? config}) async {
    if (!_isInitialized || _ragEngine == null) {
      throw Exception('RAG engine not initialized');
    }

    _logger.info(
      '🔍 Processing RAG query: "${query.substring(0, query.length > 50 ? 50 : query.length)}..."',
    );

    try {
      final response = await _ragEngine!.query(query, config: config);
      _logger.success(
        '✅ RAG query completed (confidence: ${response.confidence.toStringAsFixed(2)})',
      );
      return response;
    } catch (e) {
      _logger.error('❌ RAG query failed', e);
      rethrow;
    }
  }

  /// Get available models for RAG (GGUF files only)
  List<LocalModel> getAvailableModels(List<LocalModel> downloadedModels) {
    return downloadedModels
        .where((model) => model.path.toLowerCase().endsWith('.gguf'))
        .toList();
  }

  int _estimateChunkCount(String content) {
    final wordCount = content.split(RegExp(r'\s+')).length;
    return (wordCount / 150).ceil();
  }

  void _setProcessing(bool processing) {
    _isProcessing = processing;
    notifyListeners();
  }

  @override
  void dispose() {
    _ragEngine?.dispose();
    _logger.dispose();
    super.dispose();
  }
}

// RagDocument class remains the same
class RagDocument {
  final String id;
  final String name;
  final String content;
  final DateTime addedAt;
  final int chunkCount;
  final int fileSize;
  final String fileType;

  RagDocument({
    required this.id,
    required this.name,
    required this.content,
    required this.addedAt,
    required this.chunkCount,
    required this.fileSize,
    this.fileType = 'txt',
  });

  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024)
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get fileTypeDisplay {
    switch (fileType.toLowerCase()) {
      case 'pdf':
        return 'PDF';
      case 'txt':
      case 'text':
        return 'Text';
      case 'md':
      case 'markdown':
        return 'Markdown';
      default:
        return fileType.toUpperCase();
    }
  }

  IconData get fileIcon {
    switch (fileType.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'txt':
      case 'text':
        return Icons.description_rounded;
      case 'md':
      case 'markdown':
        return Icons.note_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }
}
