import 'package:flutter/material.dart';
import 'package:llm_toolkit/llm_toolkit.dart';
import '../../models/app_models.dart';
import '../../services/llm_service.dart';
import '../../utils/formatters.dart';

class LocalModelCard extends StatelessWidget {
  final LocalModel model;
  final LLMService llmService;

  const LocalModelCard({
    Key? key,
    required this.model,
    required this.llmService,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isCurrentlyLoaded = llmService.loadedModelPath == model.path;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white,
        border: Border.all(
          color:
              isCurrentlyLoaded ? Colors.green.shade300 : Colors.grey.shade200,
          width: isCurrentlyLoaded ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (isCurrentlyLoaded ? Colors.green : Colors.black)
                .withOpacity(0.08),
            blurRadius: isCurrentlyLoaded ? 15 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(isCurrentlyLoaded),
            const SizedBox(height: 16),
            _buildDetails(),
            const SizedBox(height: 20),
            _buildActions(context, isCurrentlyLoaded),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isCurrentlyLoaded) {
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors:
                  model.engine == InferenceEngineType.gemma
                      ? [Colors.blue.shade400, Colors.blue.shade600]
                      : [Colors.green.shade400, Colors.green.shade600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: (model.engine == InferenceEngineType.gemma
                        ? Colors.blue
                        : Colors.green)
                    .withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            model.engine == InferenceEngineType.gemma
                ? Icons.psychology_rounded
                : Icons.memory_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
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
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (isCurrentlyLoaded) _buildLoadedIndicator(),
                ],
              ),
              const SizedBox(height: 8),
              _buildEngineBadge(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoadedIndicator() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade500, Colors.green.shade600],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(Icons.check_rounded, color: Colors.white, size: 16),
    );
  }

  Widget _buildEngineBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors:
              model.engine == InferenceEngineType.gemma
                  ? [Colors.blue.shade50, Colors.blue.shade100]
                  : [Colors.green.shade50, Colors.green.shade100],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              model.engine == InferenceEngineType.gemma
                  ? Colors.blue.shade200
                  : Colors.green.shade200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            model.engine == InferenceEngineType.gemma
                ? Icons.psychology_rounded
                : Icons.memory_rounded,
            size: 12,
            color:
                model.engine == InferenceEngineType.gemma
                    ? Colors.blue.shade700
                    : Colors.green.shade700,
          ),
          const SizedBox(width: 4),
          Text(
            '${model.engine.name.toUpperCase()} Engine',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color:
                  model.engine == InferenceEngineType.gemma
                      ? Colors.blue.shade700
                      : Colors.green.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetails() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _buildDetailRow(
            Icons.storage_rounded,
            'Size',
            model.size,
            Colors.blue.shade600,
          ),
          const SizedBox(height: 8),
          _buildDetailRow(
            Icons.access_time_rounded,
            'Last Modified',
            Formatters.formatDate(model.lastModified),
            Colors.orange.shade600,
          ),
          const SizedBox(height: 8),
          _buildDetailRow(
            Icons.folder_rounded,
            'Location',
            model.path.split('/').last,
            Colors.purple.shade600,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade700,
            fontSize: 13,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context, bool isCurrentlyLoaded) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _showDeleteDialog(context),
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 16,
              color: Colors.red.shade600,
            ),
            label: Text('Delete', style: TextStyle(color: Colors.red.shade600)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.red.shade300),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: isCurrentlyLoaded ? null : () => _loadModel(context),
            icon: Icon(
              isCurrentlyLoaded
                  ? Icons.check_rounded
                  : Icons.play_arrow_rounded,
              size: 16,
            ),
            label: Text(isCurrentlyLoaded ? 'Loaded' : 'Load Model'),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isCurrentlyLoaded
                      ? Colors.grey.shade400
                      : Colors.green.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.delete_outline_rounded, color: Colors.red),
                SizedBox(width: 8),
                Text('Delete Model'),
              ],
            ),
            content: Text(
              'Are you sure you want to delete "${model.name}"?\n\nThis action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _deleteModel(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
  }

  Future<void> _loadModel(BuildContext context) async {
    try {
      await llmService.loadLocalModel(model);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('✅ ${model.name} loaded successfully!')),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('❌ Error loading model: $e')),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _deleteModel(BuildContext context) async {
    try {
      await llmService.deleteLocalModel(model);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Model deleted successfully'),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting model: $e'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }
}
