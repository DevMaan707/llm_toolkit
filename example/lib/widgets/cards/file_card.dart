import 'package:flutter/material.dart';
import 'package:llm_toolkit/llm_toolkit.dart';
import '../../models/app_models.dart';
import '../../services/llm_service.dart';
import 'package:path_provider/path_provider.dart';

class FileCard extends StatelessWidget {
  final ModelInfo model;
  final ModelFile file;
  final LLMService llmService;

  const FileCard({
    Key? key,
    required this.model,
    required this.file,
    required this.llmService,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final downloadKey = '${model.id}_${file.filename}';
    final isDownloaded = llmService.isModelDownloaded(model.id, file.filename);
    final isCurrentlyDownloading =
        llmService.isDownloading[downloadKey] ?? false;
    final downloadProgress = llmService.downloadProgress[downloadKey] ?? 0.0;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors:
              isDownloaded
                  ? [Colors.green.shade50, Colors.green.shade100]
                  : [Colors.grey.shade50, Colors.grey.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDownloaded ? Colors.green.shade300 : Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.insert_drive_file_rounded,
                            size: 14,
                            color:
                                isDownloaded
                                    ? Colors.green.shade600
                                    : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              file.filename,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                color:
                                    isDownloaded
                                        ? Colors.green.shade800
                                        : Colors.grey.shade800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _buildFormatBadge(),
                          if (isDownloaded) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: Colors.green.shade600,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 10,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.storage_rounded,
                            size: 10,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            file.size > 0 ? file.sizeFormatted : 'Size unknown',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _buildActionButton(
                  context,
                  downloadKey,
                  isDownloaded,
                  isCurrentlyDownloading,
                  downloadProgress,
                ),
              ],
            ),
            if (isCurrentlyDownloading) ...[
              const SizedBox(height: 8),
              _buildProgressIndicator(downloadProgress),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFormatBadge() {
    MaterialColor color = file.fileType == 'GGUF' ? Colors.green : Colors.blue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.shade100,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.shade300),
      ),
      child: Text(
        file.fileType,
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.bold,
          color: color.shade700,
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    String downloadKey,
    bool isDownloaded,
    bool isCurrentlyDownloading,
    double downloadProgress,
  ) {
    if (isCurrentlyDownloading) {
      return Container(
        width: 70,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.blue.shade100,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(
            '${(downloadProgress * 100).toInt()}%',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade700,
            ),
          ),
        ),
      );
    }

    if (isDownloaded) {
      return ElevatedButton.icon(
        onPressed: () => _loadExistingModel(context),
        icon: const Icon(Icons.play_arrow_rounded, size: 12),
        label: const Text('Load'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green.shade600,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(fontSize: 10),
        ),
      );
    }

    return ElevatedButton.icon(
      onPressed: () => _downloadModel(context),
      icon: const Icon(Icons.download_rounded, size: 12),
      label: const Text('Download'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(fontSize: 10),
      ),
    );
  }

  Widget _buildProgressIndicator(double progress) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Downloading...',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
            ),
            Text(
              '${(progress * 100).toInt()}%',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.grey.shade300,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
          borderRadius: BorderRadius.circular(2),
          minHeight: 3,
        ),
      ],
    );
  }

  Future<void> _downloadModel(BuildContext context) async {
    try {
      await llmService.downloadAndLoadModel(model, file.filename);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '✅ ${model.name} downloaded and loaded successfully!',
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
                    '❌ Error: $e',
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

  Future<void> _loadExistingModel(BuildContext context) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final sanitizedModelId = model.id.replaceAll('/', '_');
      final actualPath =
          '${appDir.path}/models/${sanitizedModelId}_${file.filename}';

      final localModel = LocalModel(
        name: model.name,
        path: actualPath,
        size: file.sizeFormatted,
        lastModified: DateTime.now(),
        engine: ModelDetector.instance.detectEngine(file.filename),
      );

      await llmService.loadLocalModel(localModel);

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
}
