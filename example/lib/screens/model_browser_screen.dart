import 'package:flutter/material.dart';
import '../services/llm_service.dart';
import '../widgets/common/custom_app_bar.dart';
import '../widgets/common/loading_overlay.dart';
import '../widgets/tabs/search_tab.dart';
import '../widgets/tabs/recommended_tab.dart';
import '../widgets/tabs/downloaded_tab.dart';
import '../widgets/tabs/rag_tab.dart'; // Add this import
import '../widgets/debug/debug_panel.dart';
import '../widgets/status/model_status_card.dart';

class ModelBrowserScreen extends StatefulWidget {
  @override
  _ModelBrowserScreenState createState() => _ModelBrowserScreenState();
}

class _ModelBrowserScreenState extends State<ModelBrowserScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final LLMService _llmService = LLMService();
  bool _showDebugPanel = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
    ); // Change from 3 to 4
    _llmService.initialize();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _llmService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LoadingOverlay(
        child: Column(
          children: [
            CustomAppBar(
              title: 'LLM Toolkit Pro',
              onDebugToggle: () {
                setState(() {
                  _showDebugPanel = !_showDebugPanel;
                });
              },
              showDebugPanel: _showDebugPanel,
              tabController: _tabController,
            ),

            if (_showDebugPanel) DebugPanel(llmService: _llmService),

            ModelStatusCard(llmService: _llmService),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  SearchTab(llmService: _llmService),
                  RecommendedTab(llmService: _llmService),
                  DownloadedTab(llmService: _llmService),
                  RagTab(llmService: _llmService),
                ],
              ),
            ),
          ],
        ),
      ),

      //floatingActionButton: _buildRagFab(),
    );
  }

  // Widget _buildRagFab() {
  //   return StreamBuilder<bool>(
  //     // You might want to listen to RAG service state here
  //     builder: (context, snapshot) {
  //       // Only show if we're on RAG tab and have initialized RAG
  //       if (_tabController.index == 3) {
  //         return FloatingActionButton.extended(
  //           onPressed: () {
  //             // Navigate to RAG chat if initialized
  //             // You'll need to pass the RAG service instance here
  //           },
  //           backgroundColor: Colors.purple.shade600,
  //           foregroundColor: Colors.white,
  //           icon: const Icon(Icons.auto_awesome_rounded),
  //           label: const Text('RAG Chat'),
  //           elevation: 8,
  //         );
  //       }
  //       return const SizedBox.shrink();
  //     },
  //   );
  // }
}
