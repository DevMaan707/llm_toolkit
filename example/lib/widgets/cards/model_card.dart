import 'package:flutter/material.dart';
import 'package:llm_toolkit/llm_toolkit.dart';
import '../../services/llm_service.dart';
import '../../utils/formatters.dart';
import 'file_card.dart';

class ModelCard extends StatelessWidget {
  final ModelInfo model;
  final LLMService llmService;

  const ModelCard({Key? key, required this.model, required this.llmService})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    final predictedEngine = ModelDetector.instance.detectEngine(
      model.compatibleFiles.isNotEmpty
          ? model.compatibleFiles.first.filename
          : model.name,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.all(20),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          leading: _buildModelIcon(predictedEngine),
          title: Text(
            model.name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          subtitle: _buildSubtitle(),
          children: [
            _buildDescription(),
            const SizedBox(height: 16),
            _buildFilesSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildModelIcon(InferenceEngineType engine) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors:
              engine == InferenceEngineType.gemma
                  ? [const Color(0xFF3B82F6), const Color(0xFF1E40AF)]
                  : [const Color(0xFF10B981), const Color(0xFF047857)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (engine == InferenceEngineType.gemma
                    ? const Color(0xFF3B82F6)
                    : const Color(0xFF10B981))
                .withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(
        engine == InferenceEngineType.gemma
            ? Icons.psychology_rounded
            : Icons.memory_rounded,
        color: Colors.white,
        size: 28,
      ),
    );
  }

  Widget _buildSubtitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.download_rounded, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(
              '${Formatters.formatNumber(model.downloads)} downloads',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildBadges(),
      ],
    );
  }

  Widget _buildBadges() {
    return Wrap(
      spacing: 8,
      children: [
        _buildEngineBadge(),
        if (model.ggufFiles.isNotEmpty) _buildFormatBadge('GGUF', Colors.green),
        if (model.tfliteFiles.isNotEmpty)
          _buildFormatBadge('TFLite', Colors.blue),
      ],
    );
  }

  Widget _buildEngineBadge() {
    final predictedEngine = ModelDetector.instance.detectEngine(
      model.compatibleFiles.isNotEmpty
          ? model.compatibleFiles.first.filename
          : model.name,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors:
              predictedEngine == InferenceEngineType.gemma
                  ? [Colors.blue.shade50, Colors.blue.shade100]
                  : [Colors.green.shade50, Colors.green.shade100],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              predictedEngine == InferenceEngineType.gemma
                  ? Colors.blue.shade200
                  : Colors.green.shade200,
        ),
      ),
      child: Text(
        '${predictedEngine.name.toUpperCase()} Engine',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color:
              predictedEngine == InferenceEngineType.gemma
                  ? Colors.blue.shade700
                  : Colors.green.shade700,
        ),
      ),
    );
  }

  Widget _buildFormatBadge(String format, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        format,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color.shade700,
        ),
      ),
    );
  }

  Widget _buildDescription() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.grey.shade50,
            Colors.grey.shade100,
          ], // Fixed: removed shade25
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(
        model.description.isNotEmpty
            ? model.description
            : 'No description available',
        style: TextStyle(
          color: Colors.grey.shade700,
          fontSize: 14,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildFilesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.folder_rounded, color: Colors.blue.shade600, size: 20),
            const SizedBox(width: 8),
            Text(
              'Available Files (${model.compatibleFiles.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (model.compatibleFiles.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange.shade600,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No compatible files available',
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          ...model.compatibleFiles
              .take(5)
              .map(
                (file) =>
                    FileCard(model: model, file: file, llmService: llmService),
              )
              .toList(),
      ],
    );
  }
}
