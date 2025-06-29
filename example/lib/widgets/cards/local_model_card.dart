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
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
        border: Border.all(
          color:
              isCurrentlyLoaded ? Colors.green.shade300 : Colors.grey.shade200,
          width: isCurrentlyLoaded ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (isCurrentlyLoaded ? Colors.green : Colors.black)
                .withOpacity(0.04),
            blurRadius: isCurrentlyLoaded ? 8 : 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(isCurrentlyLoaded),
            const SizedBox(height: 10),
            _buildDetails(),
            const SizedBox(height: 12),
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
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isCurrentlyLoaded) _buildLoadedIndicator(),
                ],
              ),
              const SizedBox(height: 6),
              _buildEngineBadge(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoadedIndicator() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade500, Colors.green.shade600],
        ),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.check_rounded, color: Colors.white, size: 12),
    );
  }

  Widget _buildEngineBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors:
              model.engine == InferenceEngineType.gemma
                  ? [Colors.blue.shade50, Colors.blue.shade100]
                  : [Colors.green.shade50, Colors.green.shade100],
        ),
        borderRadius: BorderRadius.circular(6),
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
            size: 10,
            color:
                model.engine == InferenceEngineType.gemma
                    ? Colors.blue.shade700
                    : Colors.green.shade700,
          ),
          const SizedBox(width: 3),
          Text(
            '${model.engine.name.toUpperCase()} Engine',
            style: TextStyle(
              fontSize: 8,
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
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
          const SizedBox(height: 6),
          _buildDetailRow(
            Icons.access_time_rounded,
            'Modified',
            Formatters.formatDate(model.lastModified),
            Colors.orange.shade600,
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
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade700,
            fontSize: 11,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
              size: 12,
              color: Colors.red.shade600,
            ),
            label: Text(
              'Delete',
              style: TextStyle(color: Colors.red.shade600, fontSize: 11),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.red.shade300),
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
            onPressed: isCurrentlyLoaded ? null : () => _loadModel(context),
            icon: Icon(
              isCurrentlyLoaded
                  ? Icons.check_rounded
                  : Icons.play_arrow_rounded,
              size: 12,
            ),
            label: Text(
              isCurrentlyLoaded ? 'Loaded' : 'Load Model',
              style: const TextStyle(fontSize: 11),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isCurrentlyLoaded
                      ? Colors.grey.shade400
                      : Colors.green.shade600,
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

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: const Row(
              children: [
                Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                SizedBox(width: 8),
                Text('Delete Model', style: TextStyle(fontSize: 16)),
              ],
            ),
            content: Text(
              'Are you sure you want to delete "${model.name}"?\n\nThis action cannot be undone.',
              style: const TextStyle(fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(fontSize: 12)),
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
                child: const Text('Delete', style: TextStyle(fontSize: 12)),
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
                const Icon(Icons.check_circle, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '✅ ${model.name} loaded successfully!',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '❌ Error loading model: $e',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
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

  Future<void> _deleteModel(BuildContext context) async {
    try {
      await llmService.deleteLocalModel(model);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text(
                  'Model deleted successfully',
                  style: TextStyle(fontSize: 12),
                ),
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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error deleting model: $e',
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
