import 'package:flutter/material.dart';
import '../../services/llm_service.dart';
import '../cards/device_info_card.dart';
import '../cards/recommended_model_card.dart';

class RecommendedTab extends StatelessWidget {
  final LLMService llmService;

  const RecommendedTab({Key? key, required this.llmService}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: llmService,
      builder: (context, _) {
        final categories =
            llmService.recommendedModels
                .map((m) => m.category)
                .toSet()
                .toList();

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // Device Info Card
            if (llmService.deviceInfo != null)
              DeviceInfoCard(deviceInfo: llmService.deviceInfo!),

            const SizedBox(height: 16),

            // Header
            Text(
              'Recommended Models for Your Device',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'These models are tested and optimized for Android devices',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade600,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 16),

            // Categories
            ...categories.map((category) {
              final categoryModels =
                  llmService.recommendedModels
                      .where((m) => m.category == category)
                      .toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCategoryHeader(category),
                  const SizedBox(height: 8),
                  ...categoryModels.map(
                    (model) => RecommendedModelCard(
                      model: model,
                      llmService: llmService,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              );
            }).toList(),
          ],
        );
      },
    );
  }

  Widget _buildCategoryHeader(String category) {
    IconData icon;
    MaterialColor color;

    switch (category) {
      case 'Small & Fast':
        icon = Icons.speed_rounded;
        color = Colors.green;
        break;
      case 'Balanced':
        icon = Icons.balance_rounded;
        color = Colors.blue;
        break;
      case 'Code':
        icon = Icons.code_rounded;
        color = Colors.purple;
        break;
      case 'Multimodal':
        icon = Icons.photo_camera_rounded;
        color = Colors.orange;
        break;
      default:
        icon = Icons.category_rounded;
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.shade100, color.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.shade300),
      ),
      child: Row(
        children: [
          Icon(icon, color: color.shade700, size: 16),
          const SizedBox(width: 6),
          Text(
            category,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color.shade800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
