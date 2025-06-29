import 'package:example/utils/app_colors.dart';
import 'package:flutter/material.dart';
import '../../services/llm_service.dart';
import '../cards/local_model_card.dart';
import '../common/empty_state.dart';

class DownloadedTab extends StatelessWidget {
  final LLMService llmService;

  const DownloadedTab({Key? key, required this.llmService}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(context),
        Expanded(
          child: ListenableBuilder(
            listenable: llmService,
            builder: (context, _) {
              if (llmService.downloadedModels.isEmpty) {
                return EmptyState(
                  icon: Icons.folder_open_rounded,
                  title: 'No downloaded models',
                  subtitle:
                      'Download models from the Search or Recommended tabs',
                  action: ElevatedButton.icon(
                    onPressed: () => _refreshDownloads(context),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text(
                      'Refresh',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () => _refreshDownloads(context),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: llmService.downloadedModels.length,
                  itemBuilder: (context, index) {
                    return LocalModelCard(
                      model: llmService.downloadedModels[index],
                      llmService: llmService,
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade50, AppColors.blueLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(bottom: BorderSide(color: Colors.blue.shade100)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade600, Colors.blue.shade700],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.storage_rounded,
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
                  'Downloaded Models',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade800,
                  ),
                ),
                ListenableBuilder(
                  listenable: llmService,
                  builder: (context, _) {
                    return Text(
                      '${llmService.downloadedModels.length} models available',
                      style: TextStyle(
                        color: Colors.blue.shade600,
                        fontSize: 11,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => _refreshDownloads(context),
            icon: const Icon(Icons.refresh_rounded, size: 14),
            label: const Text('Refresh', style: TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshDownloads(BuildContext context) async {
    try {
      await llmService.loadDownloadedModels();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text(
                  'Downloaded models refreshed',
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
              'Error refreshing: $e',
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
