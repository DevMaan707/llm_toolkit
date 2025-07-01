import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:llm_toolkit/src/core/rag/models/rag_models.dart';
import '../services/rag_service.dart';
import '../models/app_models.dart';
import '../widgets/chat/typing_indicator.dart';

class RagChatScreen extends StatefulWidget {
  final RagService ragService;

  const RagChatScreen({Key? key, required this.ragService}) : super(key: key);

  @override
  _RagChatScreenState createState() => _RagChatScreenState();
}

class _RagChatScreenState extends State<RagChatScreen>
    with TickerProviderStateMixin {
  final List<RagChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isGenerating = false;
  bool _hasText = false;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _controller.addListener(() {
      setState(() {
        _hasText = _controller.text.trim().isNotEmpty;
      });
    });
    _addWelcomeMessage();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _addWelcomeMessage() {
    final welcomeMessage = RagChatMessage(
      text:
          "Hello! I'm your RAG assistant with access to ${widget.ragService.documents.length} documents. I can answer questions based on your uploaded content. What would you like to know?",
      isUser: false,
      relevantChunks: [],
    );
    setState(() {
      _messages.add(welcomeMessage);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildDocumentInfo(),
          Expanded(child: _buildMessagesList()),
          if (_isGenerating) const TypingIndicator(),
          _buildChatInput(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.purple.shade600, Colors.purple.shade800],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: Colors.white,
            size: 20,
          ),
          padding: EdgeInsets.zero,
        ),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'RAG Assistant',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'Document-based Q&A',
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: IconButton(
            onPressed: _showChatOptions,
            icon: const Icon(
              Icons.more_vert_rounded,
              color: Colors.white,
              size: 18,
            ),
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Widget _buildDocumentInfo() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple.shade50, Colors.purple.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(
          bottom: BorderSide(color: Colors.purple.shade200, width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple.shade600, Colors.purple.shade700],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.folder_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Knowledge Base',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple.shade800,
                  ),
                ),
                Text(
                  '${widget.ragService.documents.length} documents • ${_getTotalChunks()} chunks available',
                  style: TextStyle(color: Colors.purple.shade600, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  color: Colors.green.shade600,
                  size: 12,
                ),
                const SizedBox(width: 4),
                Text(
                  'Ready',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _getTotalChunks() {
    return widget.ragService.documents.fold(
      0,
      (sum, doc) => sum + doc.chunkCount,
    );
  }

  Widget _buildMessagesList() {
    if (_messages.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return _buildMessageBubble(message);
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple.shade100, Colors.purple.shade200],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.chat_bubble_outline_rounded,
              size: 48,
              color: Colors.purple.shade600,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Start asking questions!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.purple.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'I can help you find information from your documents',
            style: TextStyle(fontSize: 14, color: Colors.purple.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _buildSuggestionChips(),
        ],
      ),
    );
  }

  Widget _buildSuggestionChips() {
    final suggestions = [
      "What are the main topics?",
      "Summarize the key points",
      "What does this document cover?",
      "Find specific information",
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children:
          suggestions.map((suggestion) {
            return ActionChip(
              label: Text(suggestion, style: const TextStyle(fontSize: 12)),
              onPressed: () {
                _controller.text = suggestion;
                setState(() => _hasText = true);
              },
              backgroundColor: Colors.purple.shade50,
              side: BorderSide(color: Colors.purple.shade200),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            );
          }).toList(),
    );
  }

  Widget _buildMessageBubble(RagChatMessage message) {
    return Container(
      margin: EdgeInsets.only(
        bottom: 16,
        left: message.isUser ? 60 : 0,
        right: message.isUser ? 0 : 60,
      ),
      child: Row(
        mainAxisAlignment:
            message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) _buildAvatar(false),
          if (!message.isUser) const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment:
                  message.isUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onLongPress: () => _showMessageOptions(message),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.8,
                    ),
                    decoration: BoxDecoration(
                      gradient:
                          message.isUser
                              ? LinearGradient(
                                colors: [
                                  Colors.purple.shade500,
                                  Colors.purple.shade600,
                                ],
                              )
                              : LinearGradient(
                                colors: [Colors.white, Colors.grey.shade50],
                              ),
                      borderRadius: BorderRadius.circular(16).copyWith(
                        bottomRight:
                            message.isUser ? const Radius.circular(4) : null,
                        bottomLeft:
                            message.isUser ? null : const Radius.circular(4),
                      ),
                      border:
                          message.isUser
                              ? null
                              : Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          message.text,
                          style: TextStyle(
                            color:
                                message.isUser ? Colors.white : Colors.black87,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                        if (!message.isUser && message.confidence != null) ...[
                          const SizedBox(height: 12),
                          _buildConfidenceIndicator(message.confidence!),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatTime(message.timestamp),
                              style: TextStyle(
                                color:
                                    message.isUser
                                        ? Colors.white.withOpacity(0.7)
                                        : Colors.grey.shade500,
                                fontSize: 11,
                              ),
                            ),
                            if (message.isUser) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.done_all_rounded,
                                size: 12,
                                color: Colors.white.withOpacity(0.7),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (!message.isUser && message.relevantChunks.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildSourcesSection(message.relevantChunks),
                ],
              ],
            ),
          ),
          if (message.isUser) const SizedBox(width: 12),
          if (message.isUser) _buildAvatar(true),
        ],
      ),
    );
  }

  Widget _buildAvatar(bool isUser) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors:
              isUser
                  ? [Colors.purple.shade500, Colors.purple.shade600]
                  : [Colors.grey.shade400, Colors.grey.shade600],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        isUser ? Icons.person_rounded : Icons.auto_awesome_rounded,
        color: Colors.white,
        size: 16,
      ),
    );
  }

  Widget _buildConfidenceIndicator(double confidence) {
    MaterialColor color;
    String label;
    IconData icon;

    if (confidence >= 0.8) {
      color = Colors.green;
      label = 'High';
      icon = Icons.check_circle_rounded;
    } else if (confidence >= 0.6) {
      color = Colors.orange;
      label = 'Medium';
      icon = Icons.warning_rounded;
    } else {
      color = Colors.red;
      label = 'Low';
      icon = Icons.error_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color.shade600),
          const SizedBox(width: 6),
          Text(
            'Confidence: $label (${(confidence * 100).toInt()}%)',
            style: TextStyle(
              fontSize: 11,
              color: color.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourcesSection(List<DocumentChunk> chunks) {
    return Container(
      margin: const EdgeInsets.only(left: 44),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade50, Colors.blue.shade100],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.source_rounded, size: 16, color: Colors.blue.shade600),
              const SizedBox(width: 6),
              Text(
                'Sources (${chunks.length})',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => _showAllSources(chunks),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                ),
                child: Text(
                  'View All',
                  style: TextStyle(fontSize: 10, color: Colors.blue.shade600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...chunks.take(2).map((chunk) => _buildSourceItem(chunk)),
          if (chunks.length > 2)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+ ${chunks.length - 2} more sources',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.blue.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSourceItem(DocumentChunk chunk) {
    final fileName = chunk.metadata?['fileName'] ?? 'Unknown Document';
    final relevanceScore = chunk.relevanceScore ?? 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        children: [
          Icon(
            Icons.description_rounded,
            size: 12,
            color: Colors.blue.shade600,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              fileName,
              style: TextStyle(
                fontSize: 11,
                color: Colors.blue.shade700,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${(relevanceScore * 100).toInt()}%',
              style: TextStyle(
                fontSize: 9,
                color: Colors.blue.shade600,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: TextField(
                controller: _controller,
                enabled: !_isGenerating,
                decoration: InputDecoration(
                  hintText:
                      _isGenerating
                          ? 'AI is analyzing documents...'
                          : 'Ask about your documents...',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: _isGenerating ? null : _sendMessage,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors:
                    _hasText && !_isGenerating
                        ? [Colors.purple.shade500, Colors.purple.shade600]
                        : [Colors.grey.shade400, Colors.grey.shade500],
              ),
              shape: BoxShape.circle,
              boxShadow:
                  _hasText && !_isGenerating
                      ? [
                        BoxShadow(
                          color: Colors.purple.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                      : [],
            ),
            child: IconButton(
              onPressed:
                  _hasText && !_isGenerating
                      ? () => _sendMessage(_controller.text)
                      : null,
              icon: const Icon(
                Icons.send_rounded,
                color: Colors.white,
                size: 20,
              ),
              padding: const EdgeInsets.all(12),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
          ),
        ],
      ),
    );
  }

  // Rest of the methods (sendMessage, showOptions, etc.) remain similar but with updated styling
  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _isGenerating) return;

    final userMessage = RagChatMessage(
      text: text,
      isUser: true,
      relevantChunks: [],
    );

    setState(() {
      _messages.add(userMessage);
      _isGenerating = true;
    });

    _controller.clear();
    setState(() => _hasText = false);
    _scrollToBottom();

    try {
      final config = RagConfig(
        maxRelevantChunks: 5,
        similarityThreshold: 0.5,
        maxTokens: 1000,
        temperature: 0.7,
      );

      final response = await widget.ragService.queryRAG(text, config: config);

      final aiMessage = RagChatMessage(
        text: response.answer,
        isUser: false,
        relevantChunks: response.relevantChunks,
        confidence: response.confidence,
      );

      setState(() {
        _messages.add(aiMessage);
        _isGenerating = false;
      });

      _scrollToBottom();
    } catch (e) {
      final errorMessage = RagChatMessage(
        text:
            'Sorry, I encountered an error while processing your question: $e',
        isUser: false,
        relevantChunks: [],
        confidence: 0.0,
      );

      setState(() {
        _messages.add(errorMessage);
        _isGenerating = false;
      });

      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showAllSources(List<DocumentChunk> chunks) {
    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              width: double.maxFinite,
              height: MediaQuery.of(context).size.height * 0.7,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.source_rounded, color: Colors.blue.shade600),
                      const SizedBox(width: 8),
                      Text(
                        'Source Documents (${chunks.length})',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: chunks.length,
                      itemBuilder: (context, index) {
                        final chunk = chunks[index];
                        final fileName =
                            chunk.metadata?['fileName'] ?? 'Unknown';
                        final relevanceScore = chunk.relevanceScore ?? 0.0;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.description_rounded,
                                      size: 16,
                                      color: Colors.blue.shade600,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        fileName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade100,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${(relevanceScore * 100).toInt()}% match',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.blue.shade700,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.grey.shade200,
                                    ),
                                  ),
                                  child: Text(
                                    chunk.content,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  void _showMessageOptions(RagChatMessage message) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('Copy Message'),
                  onTap: () {
                    Navigator.pop(context);
                    _copyMessage(message.text);
                  },
                ),
                if (!message.isUser && message.relevantChunks.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.source_rounded),
                    title: const Text('View Sources'),
                    onTap: () {
                      Navigator.pop(context);
                      _showAllSources(message.relevantChunks);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.share_rounded),
                  title: const Text('Share'),
                  onTap: () {
                    Navigator.pop(context);
                    _shareMessage(message);
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
    );
  }

  void _showChatOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Chat Options',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.clear_all_rounded),
                  title: const Text('Clear Chat'),
                  onTap: () {
                    Navigator.pop(context);
                    _clearChat();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.download_rounded),
                  title: const Text('Export Chat'),
                  onTap: () {
                    Navigator.pop(context);
                    _exportChat();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder_rounded),
                  title: const Text('Manage Documents'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pop(context); // Go back to RAG tab
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
    );
  }

  void _copyMessage(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('Message copied to clipboard'),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _shareMessage(RagChatMessage message) {
    final shareText = '''
  RAG Assistant Response:
  ${message.text}

  ${message.relevantChunks.isNotEmpty ? '\nSources:' : ''}
  ${message.relevantChunks.map((chunk) => '• ${chunk.metadata?['fileName'] ?? 'Unknown'}').join('\n')}

  Generated at: ${_formatTime(message.timestamp)}
  Confidence: ${message.confidence != null ? '${(message.confidence! * 100).toInt()}%' : 'N/A'}
  ''';

    Clipboard.setData(ClipboardData(text: shareText));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Response details copied to clipboard'),
        backgroundColor: Colors.blue.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _clearChat() {
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
                Text('Clear Chat History'),
              ],
            ),
            content: const Text(
              'Are you sure you want to clear all messages? This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    _messages.clear();
                    _addWelcomeMessage();
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Chat history cleared'),
                      backgroundColor: Colors.green.shade600,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Clear'),
              ),
            ],
          ),
    );
  }

  void _exportChat() {
    final chatText = _messages
        .map(
          (msg) => '''
  ${msg.isUser ? 'You' : 'RAG Assistant'}: ${msg.text}
  ${!msg.isUser && msg.confidence != null ? 'Confidence: ${(msg.confidence! * 100).toInt()}%' : ''}
  ${!msg.isUser && msg.relevantChunks.isNotEmpty ? 'Sources: ${msg.relevantChunks.map((c) => c.metadata?['fileName'] ?? 'Unknown').join(', ')}' : ''}
  Time: ${_formatTime(msg.timestamp)}
  ''',
        )
        .join('\n' + '=' * 50 + '\n');

    final fullExport = '''
  RAG Chat Export
  Generated: ${DateTime.now().toIso8601String()}
  Knowledge Base: ${widget.ragService.documents.length} documents
  Total Messages: ${_messages.length}

  ${'=' * 50}

  $chatText
  ''';

    Clipboard.setData(ClipboardData(text: fullExport));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Chat exported to clipboard'),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }
}

// RAG Chat Message model
class RagChatMessage extends ChatMessage {
  final List<DocumentChunk> relevantChunks;
  final double? confidence;

  RagChatMessage({
    required String text,
    required bool isUser,
    required this.relevantChunks,
    this.confidence,
    DateTime? timestamp,
    String? error,
  }) : super(text: text, isUser: isUser, timestamp: timestamp, error: error);
}
