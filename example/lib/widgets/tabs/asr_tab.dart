import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/llm_service.dart';
import '../../services/asr_service_wrapper.dart';
import '../common/empty_state.dart';
import 'dart:async';

class AsrTab extends StatefulWidget {
  final LLMService llmService;
  final ASRServiceWrapper asrService;

  const AsrTab({Key? key, required this.llmService, required this.asrService})
    : super(key: key);

  @override
  _AsrTabState createState() => _AsrTabState();
}

class _AsrTabState extends State<AsrTab> {
  String? _selectedModelPath;
  StreamSubscription<String>? _streamingSubscription;

  @override
  void dispose() {
    _streamingSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.llmService,
      builder: (context, _) {
        final availableModels = widget.asrService.getAvailableASRModels(
          widget.llmService.downloadedModels,
        );

        if (availableModels.isEmpty) {
          return EmptyState(
            icon: Icons.mic_off_rounded,
            title: 'No TFLite Models Available',
            subtitle: 'Download TFLite models first to use ASR functionality',
            action: ElevatedButton.icon(
              onPressed: () {
                DefaultTabController.of(context)?.animateTo(0);
              },
              icon: const Icon(Icons.download_rounded, size: 16),
              label: const Text(
                'Download Models',
                style: TextStyle(fontSize: 12),
              ),
            ),
          );
        }

        return ListenableBuilder(
          listenable: widget.asrService,
          builder: (context, _) {
            return Column(
              children: [
                _buildModelSelectionSection(availableModels),
                if (widget.asrService.isInitialized) ...[
                  _buildControlsSection(),
                  Expanded(child: _buildResultsSection()),
                ] else
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Select and initialize a model to get started',
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildModelSelectionSection(List<dynamic> availableModels) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade50, Colors.orange.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.orange.shade600, Colors.orange.shade700],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.mic_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ASR Configuration',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade800,
                        ),
                      ),
                      Text(
                        'Automatic Speech Recognition with TFLite models',
                        style: TextStyle(
                          color: Colors.orange.shade600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!widget.asrService.isInitialized) ...[
              _buildModelDropdown(availableModels),
              const SizedBox(height: 16),
              _buildInitializeButton(),
            ] else
              _buildInitializedStatus(),
          ],
        ),
      ),
    );
  }

  Widget _buildModelDropdown(List<dynamic> availableModels) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.memory_rounded,
                size: 16,
                color: Colors.orange.shade600,
              ),
              const SizedBox(width: 8),
              Text(
                'ASR Model',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Colors.orange.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Select TFLite model for speech recognition',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedModelPath,
            onChanged: (value) => setState(() => _selectedModelPath = value),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            hint: const Text(
              'Select ASR model...',
              style: TextStyle(fontSize: 12),
            ),
            items:
                availableModels.map((model) {
                  return DropdownMenuItem<String>(
                    value: model.path,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          model.name,
                          style: const TextStyle(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          model.size,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildInitializeButton() {
    final canInitialize = _selectedModelPath != null;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed:
            canInitialize && !widget.asrService.isProcessing
                ? _initializeASR
                : null,
        icon:
            widget.asrService.isProcessing
                ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : const Icon(Icons.play_arrow_rounded, size: 16),
        label: Text(
          widget.asrService.isProcessing ? 'Initializing...' : 'Initialize ASR',
          style: const TextStyle(fontSize: 13),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange.shade600,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Widget _buildInitializedStatus() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            color: Colors.green.shade600,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ASR Engine Ready',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade800,
                    fontSize: 13,
                  ),
                ),
                Text(
                  'Model: ${widget.asrService.selectedModelName}',
                  style: TextStyle(color: Colors.green.shade700, fontSize: 10),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _resetASR,
            icon: const Icon(Icons.refresh_rounded, size: 14),
            label: const Text('Reset', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(foregroundColor: Colors.green.shade700),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Speech Recognition Options',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildRecordButton()),
                const SizedBox(width: 8),
                Expanded(child: _buildImportButton()),
                const SizedBox(width: 8),
                Expanded(child: _buildLiveButton()),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.asrService.isRecording ||
                widget.asrService.isProcessing ||
                widget.asrService.isStreaming)
              _buildStatusIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordButton() {
    return ElevatedButton.icon(
      onPressed:
          widget.asrService.isProcessing || widget.asrService.isStreaming
              ? null
              : _handleRecording,
      icon: Icon(
        widget.asrService.isRecording ? Icons.stop_rounded : Icons.mic_rounded,
        size: 16,
      ),
      label: Text(
        widget.asrService.isRecording ? 'Stop' : 'Record',
        style: const TextStyle(fontSize: 11),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor:
            widget.asrService.isRecording
                ? Colors.red.shade600
                : Colors.blue.shade600,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  Widget _buildImportButton() {
    return ElevatedButton.icon(
      onPressed:
          widget.asrService.isProcessing ||
                  widget.asrService.isRecording ||
                  widget.asrService.isStreaming
              ? null
              : _importAudioFile,
      icon: const Icon(Icons.file_upload_rounded, size: 16),
      label: const Text('Import', style: TextStyle(fontSize: 11)),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green.shade600,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  Widget _buildLiveButton() {
    return ElevatedButton.icon(
      onPressed:
          widget.asrService.isProcessing || widget.asrService.isRecording
              ? null
              : _handleLiveTranscription,
      icon: Icon(
        widget.asrService.isStreaming
            ? Icons.stop_rounded
            : Icons.radio_rounded,
        size: 16,
      ),
      label: Text(
        widget.asrService.isStreaming ? 'Stop Live' : 'Live',
        style: const TextStyle(fontSize: 11),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor:
            widget.asrService.isStreaming
                ? Colors.red.shade600
                : Colors.purple.shade600,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  Widget _buildStatusIndicator() {
    String statusText;
    Color statusColor;

    if (widget.asrService.isProcessing) {
      statusText = 'Processing audio...';
      statusColor = Colors.orange.shade600;
    } else if (widget.asrService.isStreaming) {
      statusText = 'Live transcription active';
      statusColor = Colors.purple.shade600;
    } else if (widget.asrService.isRecording) {
      statusText = 'Recording audio...';
      statusColor = Colors.red.shade600;
    } else {
      statusText = 'Ready';
      statusColor = Colors.green.shade600;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          if (widget.asrService.isProcessing ||
              widget.asrService.isRecording ||
              widget.asrService.isStreaming)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              ),
            )
          else
            Icon(Icons.check_circle_rounded, size: 12, color: statusColor),
          const SizedBox(width: 6),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsSection() {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.grey.shade50, Colors.grey.shade100],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.text_fields_rounded,
                  color: Colors.grey.shade600,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Transcription Results',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                if (widget.asrService.transcriptionResult.isNotEmpty)
                  IconButton(
                    onPressed: widget.asrService.clearResult,
                    icon: Icon(
                      Icons.clear_rounded,
                      size: 16,
                      color: Colors.grey.shade600,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child:
                widget.asrService.transcriptionResult.isEmpty
                    ? _buildEmptyResults()
                    : _buildTranscriptionResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyResults() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.text_fields_rounded, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No transcription yet',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Record audio, import a file, or try live transcription',
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTranscriptionResults() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: SelectableText(
          widget.asrService.transcriptionResult,
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
      ),
    );
  }

  // Event handlers
  Future<void> _initializeASR() async {
    if (_selectedModelPath == null) return;

    try {
      final selectedModel = widget.llmService.downloadedModels.firstWhere(
        (model) => model.path == _selectedModelPath,
      );

      await widget.asrService.initializeASR(
        _selectedModelPath!,
        selectedModel.name,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text('ASR engine initialized successfully!'),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initialize ASR: $e'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _handleRecording() async {
    try {
      if (widget.asrService.isRecording) {
        await widget.asrService.stopRecording();
      } else {
        final hasAccess = await widget.asrService.testMicrophoneAccess();
        if (!hasAccess) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Microphone access denied. Please grant permission.',
                ),
                backgroundColor: Colors.red.shade600,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            );
          }
          return;
        }

        await widget.asrService.startRecording();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Recording error: $e'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        );
      }
    }
  }

  Future<void> _importAudioFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['wav', 'mp3', 'flac', 'm4a'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        await widget.asrService.transcribeFile(filePath);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Text('Audio file transcribed successfully!'),
                ],
              ),
              backgroundColor: Colors.green.shade600,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import error: $e'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleLiveTranscription() async {
    try {
      if (widget.asrService.isStreaming) {
        // Stop streaming
        await _streamingSubscription?.cancel();
        _streamingSubscription = null;
        await widget.asrService.stopStreamingTranscription();
      } else {
        // Start streaming
        final hasAccess = await widget.asrService.testMicrophoneAccess();
        if (!hasAccess) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Microphone access denied. Please grant permission.',
                ),
                backgroundColor: Colors.red.shade600,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            );
          }
          return;
        }

        // Start the streaming subscription
        _streamingSubscription = widget.asrService
            .startStreamingTranscription()
            .listen(
              (chunk) {
                // The transcription result is already updated in the service
                // Just show a brief notification for each chunk if needed
                print('Received chunk: $chunk');
              },
              onError: (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Streaming error: $error'),
                      backgroundColor: Colors.red.shade600,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  );
                }
              },
              onDone: () {
                print('Streaming completed');
                _streamingSubscription = null;
              },
            );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Live transcription error: $e'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        );
      }
    }
  }

  void _resetASR() {
    // Cancel any ongoing operations
    _streamingSubscription?.cancel();
    _streamingSubscription = null;

    setState(() {
      _selectedModelPath = null;
    });
  }
}
