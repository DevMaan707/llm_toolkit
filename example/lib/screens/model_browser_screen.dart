import 'package:flutter/material.dart';
import '../services/llm_service.dart';
import '../widgets/common/custom_app_bar.dart';
import '../widgets/common/loading_overlay.dart';
import '../widgets/tabs/search_tab.dart';
import '../widgets/tabs/recommended_tab.dart';
import '../widgets/tabs/downloaded_tab.dart';
import '../widgets/tabs/rag_tab.dart';
import '../widgets/debug/debug_panel.dart';
import '../widgets/status/model_status_card.dart';
import '../services/asr_service_wrapper.dart';
import '../widgets/tabs/asr_tab.dart';

class ModelBrowserScreen extends StatefulWidget {
  @override
  _ModelBrowserScreenState createState() => _ModelBrowserScreenState();
}

class _ModelBrowserScreenState extends State<ModelBrowserScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final LLMService _llmService = LLMService();
  bool _showDebugPanel = false;
  final ASRServiceWrapper _asrService = ASRServiceWrapper();
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _llmService.initialize();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _llmService.dispose();
    _asrService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LoadingOverlay(
        child: Column(
          children: [
            CustomAppBar(
              title: 'LLM Toolkit',
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
                  AsrTab(llmService: _llmService, asrService: _asrService),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
