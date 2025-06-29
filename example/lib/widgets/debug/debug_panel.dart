import 'package:flutter/material.dart';
import '../../services/llm_service.dart';
import '../../utils/logger.dart';

class DebugPanel extends StatefulWidget {
  final LLMService llmService;

  const DebugPanel({Key? key, required this.llmService}) : super(key: key);

  @override
  _DebugPanelState createState() => _DebugPanelState();
}

class _DebugPanelState extends State<DebugPanel> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade300, width: 1),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade600,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.bug_report_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Debug Console',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    widget.llmService.logger.logs.clear();
                    setState(() {});
                  },
                  icon: const Icon(
                    Icons.clear_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: widget.llmService.logger,
              builder: (context, _) {
                final logs = widget.llmService.logger.logs;

                // Auto-scroll to bottom when new logs are added
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(
                      _scrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                });

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    return _buildLogEntry(log);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogEntry(LogEntry log) {
    Color textColor;
    IconData icon;

    switch (log.level) {
      case LogLevel.info:
        textColor = Colors.blue.shade300;
        icon = Icons.info_outline_rounded;
        break;
      case LogLevel.success:
        textColor = Colors.green.shade300;
        icon = Icons.check_circle_outline_rounded;
        break;
      case LogLevel.warning:
        textColor = Colors.orange.shade300;
        icon = Icons.warning_amber_rounded;
        break;
      case LogLevel.error:
        textColor = Colors.red.shade300;
        icon = Icons.error_outline_rounded;
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '[${log.timestamp.toIso8601String().substring(11, 19)}]',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          Icon(icon, color: textColor, size: 12),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              log.message,
              style: TextStyle(
                color: textColor,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
