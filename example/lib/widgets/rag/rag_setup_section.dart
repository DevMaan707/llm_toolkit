import 'package:flutter/material.dart';
import '../../services/rag_service.dart';
import '../../models/app_models.dart';

class RagSetupSection extends StatefulWidget {
  final RagService ragService;
  final List<LocalModel> availableModels;

  const RagSetupSection({
    Key? key,
    required this.ragService,
    required this.availableModels,
  }) : super(key: key);

  @override
  _RagSetupSectionState createState() => _RagSetupSectionState();
}

class _RagSetupSectionState extends State<RagSetupSection> {
  String? _selectedEmbeddingModel;
  String? _selectedLLMModel;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple.shade50, Colors.purple.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            if (!widget.ragService.isInitialized) ...[
              _buildModelSelectors(),
              const SizedBox(height: 16),
              _buildInitializeButton(),
            ] else
              _buildInitializedStatus(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.purple.shade600, Colors.purple.shade700],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.article_rounded,
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
                'RAG Configuration',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.purple.shade800,
                ),
              ),
              Text(
                'Retrieval-Augmented Generation with your documents',
                style: TextStyle(color: Colors.purple.shade600, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModelSelectors() {
    return Column(
      children: [
        _buildModelDropdown(
          'Embedding Model',
          'Select model for document embeddings',
          _selectedEmbeddingModel,
          (value) => setState(() => _selectedEmbeddingModel = value),
          Icons.psychology_rounded,
          Colors.blue,
        ),
        const SizedBox(height: 12),
        _buildModelDropdown(
          'LLM Model',
          'Select model for text generation',
          _selectedLLMModel,
          (value) => setState(() => _selectedLLMModel = value),
          Icons.chat_rounded,
          Colors.green,
        ),
      ],
    );
  }

  Widget _buildModelDropdown(
    String title,
    String subtitle,
    String? selectedValue,
    Function(String?) onChanged,
    IconData icon,
    MaterialColor color,
  ) {
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
              Icon(icon, size: 16, color: color.shade600),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: color.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: selectedValue,
            onChanged: onChanged,
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
            hint: const Text('Select model...', style: TextStyle(fontSize: 12)),
            items:
                widget.availableModels.map((model) {
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
    final canInitialize =
        _selectedEmbeddingModel != null && _selectedLLMModel != null;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed:
            canInitialize && !widget.ragService.isProcessing
                ? _initializeRAG
                : null,
        icon:
            widget.ragService.isProcessing
                ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : const Icon(Icons.rocket_launch_rounded, size: 16),
        label: Text(
          widget.ragService.isProcessing ? 'Initializing...' : 'Initialize RAG',
          style: const TextStyle(fontSize: 13),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.purple.shade600,
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
                  'RAG Engine Ready',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade800,
                    fontSize: 13,
                  ),
                ),
                Text(
                  'Embedding: ${widget.ragService.selectedEmbeddingModel}\n'
                  'LLM: ${widget.ragService.selectedLLMModel}',
                  style: TextStyle(color: Colors.green.shade700, fontSize: 10),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _resetRAG,
            icon: const Icon(Icons.refresh_rounded, size: 14),
            label: const Text('Reset', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(foregroundColor: Colors.green.shade700),
          ),
        ],
      ),
    );
  }

  Future<void> _initializeRAG() async {
    if (_selectedEmbeddingModel == null || _selectedLLMModel == null) return;

    try {
      await widget.ragService.initializeRAG(
        embeddingModelPath: _selectedEmbeddingModel!,
        llmModelPath: _selectedLLMModel!,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text('RAG engine initialized successfully!'),
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
            content: Text('Failed to initialize RAG: $e'),
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

  void _resetRAG() {
    setState(() {
      _selectedEmbeddingModel = null;
      _selectedLLMModel = null;
    });
    // Note: Add actual reset logic in RagService if needed
  }
}
