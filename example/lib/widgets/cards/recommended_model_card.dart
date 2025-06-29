import 'package:flutter/material.dart';
import 'package:llm_toolkit/llm_toolkit.dart';
import '../../models/app_models.dart';
import '../../services/llm_service.dart';

class RecommendedModelCard extends StatelessWidget {
  final RecommendedModel model;
  final LLMService llmService;

  const RecommendedModelCard({
    Key? key,
    required this.model,
    required this.llmService,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 10),
            _buildDescription(),
            const SizedBox(height: 10),
            _buildFeatures(),
            const SizedBox(height: 12),
            _buildActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors:
                  model.engine == InferenceEngineType.gemma
                      ? [Colors.blue.shade400, Colors.blue.shade600]
                      : [Colors.green.shade400, Colors.green.shade600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: (model.engine == InferenceEngineType.gemma
                        ? Colors.blue
                        : Colors.green)
                    .withOpacity(0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            model.engine == InferenceEngineType.gemma
                ? Icons.psychology_rounded
                : Icons.memory_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      model.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (model.isStable) _buildStableBadge(),
                ],
              ),
              const SizedBox(height: 6),
              _buildSpecBadges(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStableBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade100, Colors.green.shade200],
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, size: 8, color: Colors.green.shade700),
          const SizedBox(width: 2),
          Text(
            'STABLE',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecBadges() {
    return Wrap(
      spacing: 4,
      runSpacing: 3,
      children: [
        _buildBadge(
          model.quantization,
          Colors.orange.shade100,
          Colors.orange.shade700,
          Icons.compress_rounded,
        ),
        _buildBadge(
          model.size,
          Colors.blue.shade100,
          Colors.blue.shade700,
          Icons.storage_rounded,
        ),
        _buildBadge(
          model.difficulty,
          Colors.purple.shade100,
          Colors.purple.shade700,
          Icons.speed_rounded,
        ),
      ],
    );
  }

  Widget _buildBadge(
    String text,
    Color bgColor,
    Color textColor,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: textColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 8, color: textColor),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescription() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.grey.shade50, Colors.grey.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(
        model.description,
        style: TextStyle(
          color: Colors.grey.shade700,
          fontSize: 11,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildFeatures() {
    if (model.features.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.star_rounded, color: Colors.amber.shade600, size: 12),
            const SizedBox(width: 6),
            const Text(
              'Key Features',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          runSpacing: 3,
          children:
              model.features.map((feature) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Text(
                    feature,
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.amber.shade800,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _showModelDetails(context),
            icon: const Icon(Icons.info_outline_rounded, size: 12),
            label: const Text('Details', style: TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: () => _searchModel(context),
            icon: const Icon(Icons.search_rounded, size: 12),
            label: const Text('Find Models', style: TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showModelDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ModelDetailsSheet(model: model),
    );
  }

  Future<void> _searchModel(BuildContext context) async {
    try {
      await llmService.searchRecommendedModel(model);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Found models for ${model.name}',
              style: const TextStyle(fontSize: 12),
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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error searching ${model.name}: $e',
              style: const TextStyle(fontSize: 12),
            ),
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
}

class ModelDetailsSheet extends StatelessWidget {
  final RecommendedModel model;

  const ModelDetailsSheet({Key? key, required this.model}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 3,
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _buildDetailRow(
                  'Category',
                  model.category,
                  Icons.category_rounded,
                ),
                _buildDetailRow(
                  'Engine',
                  model.engine.name.toUpperCase(),
                  Icons.memory_rounded,
                ),
                _buildDetailRow('Size', model.size, Icons.storage_rounded),
                _buildDetailRow(
                  'Quantization',
                  model.quantization,
                  Icons.compress_rounded,
                ),
                _buildDetailRow(
                  'Difficulty',
                  model.difficulty,
                  Icons.speed_rounded,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Description',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  model.description,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    height: 1.4,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.blue.shade600),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
          ),
          Text(value, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
