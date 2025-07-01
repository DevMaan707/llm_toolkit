import 'package:flutter/material.dart';
import '../../services/llm_service.dart';
import '../../services/rag_service.dart';
import '../rag/rag_setup_section.dart';
import '../rag/rag_documents_section.dart';
import '../rag/rag_chat_section.dart';
import '../common/empty_state.dart';

class RagTab extends StatefulWidget {
  final LLMService llmService;

  const RagTab({Key? key, required this.llmService}) : super(key: key);

  @override
  _RagTabState createState() => _RagTabState();
}

class _RagTabState extends State<RagTab> {
  late RagService _ragService;

  @override
  void initState() {
    super.initState();
    _ragService = RagService();
  }

  @override
  void dispose() {
    _ragService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.llmService,
      builder: (context, _) {
        final availableModels = _ragService.getAvailableModels(
          widget.llmService.downloadedModels,
        );

        if (availableModels.isEmpty) {
          return EmptyState(
            icon: Icons.article_rounded,
            title: 'No GGUF Models Available',
            subtitle: 'Download GGUF models first to use RAG functionality',
            action: ElevatedButton.icon(
              onPressed: () {
                // Switch to search tab
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
          listenable: _ragService,
          builder: (context, _) {
            return Column(
              children: [
                // Setup Section
                RagSetupSection(
                  ragService: _ragService,
                  availableModels: availableModels,
                ),

                if (_ragService.isInitialized) ...[
                  // Documents Section
                  RagDocumentsSection(ragService: _ragService),

                  // Chat Launch Section (instead of embedded chat)
                  RagChatSection(ragService: _ragService),
                ] else
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Initialize RAG engine to get started',
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
}
