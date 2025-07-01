import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../services/llm_service.dart';
import '../models/app_models.dart';
import '../utils/app_colors.dart';
import '../widgets/chat/chat_bubble.dart';
import '../widgets/chat/chat_input.dart';
import '../widgets/chat/typing_indicator.dart';

class ChatScreen extends StatefulWidget {
  final LLMService llmService;

  const ChatScreen({Key? key, required this.llmService}) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  bool _isGenerating = false;
  late AnimationController _animationController;
  StreamSubscription<String>? _generationSubscription;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _addWelcomeMessage();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _animationController.dispose();
    _generationSubscription?.cancel();
    super.dispose();
  }

  void _addWelcomeMessage() {
    final welcomeMessage = ChatMessage(
      text: "Hello! I'm ready to help you. What would you like to talk about?",
      isUser: false,
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
          _buildModelInfo(),
          Expanded(child: _buildMessagesList()),
          if (_isGenerating) const TypingIndicator(),
          ChatInput(
            onSendMessage: _sendMessage,
            onStopGeneration: _stopGeneration,
            isGenerating: _isGenerating,
          ),
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
            colors: [const Color(0xFF1E3A8A), const Color(0xFF3B82F6)],
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
              Icons.chat_bubble_rounded,
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
                  'Chat Assistant',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  '${widget.llmService.activeEngine?.name ?? 'Unknown'} Engine',
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

  Widget _buildModelInfo() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade100, width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color:
                  _isGenerating
                      ? Colors.orange.shade100
                      : Colors.green.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isGenerating
                  ? Icons.hourglass_empty_rounded
                  : Icons.check_rounded,
              color:
                  _isGenerating
                      ? Colors.orange.shade600
                      : Colors.green.shade600,
              size: 12,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Model: ${widget.llmService.selectedModelName ?? 'Unknown'}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${_messages.length} msgs',
              style: TextStyle(
                fontSize: 9,
                color: Colors.blue.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 40,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Start a conversation',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask me anything!',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return ChatBubble(
          message: message,
          onCopy: () => _copyMessage(message.text),
          onShare: () => _shareMessage(message.text),
        );
      },
    );
  }

  void _sendMessage(String text) {
    if (text.trim().isEmpty || _isGenerating) return;

    final userMessage = ChatMessage(text: text, isUser: true);
    setState(() {
      _messages.add(userMessage);
      _isGenerating = true;
    });

    _scrollToBottom();

    // Create AI message with empty text initially
    final aiMessage = ChatMessage(text: '', isUser: false);
    setState(() => _messages.add(aiMessage));

    _animationController.forward();

    // Cancel any existing subscription
    _generationSubscription?.cancel();

    // Start new generation
    _generationSubscription = widget.llmService
        .generateText(text)
        .listen(
          (token) {
            if (mounted) {
              setState(() {
                // Find the AI message index and update it
                final aiMessageIndex = _messages.length - 1;
                if (aiMessageIndex >= 0 && !_messages[aiMessageIndex].isUser) {
                  // Create a new ChatMessage object instead of modifying the existing one
                  _messages[aiMessageIndex] = ChatMessage(
                    text: _messages[aiMessageIndex].text + token,
                    isUser: false,
                    timestamp: _messages[aiMessageIndex].timestamp,
                  );
                }
              });

              // Scroll to bottom after each token
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scrollController.hasClients) {
                  _scrollController.animateTo(
                    _scrollController.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 50),
                    curve: Curves.easeOut,
                  );
                }
              });
            }
          },
          onDone: () {
            print('Generation completed normally');
            if (mounted) {
              setState(() {
                _isGenerating = false;
              });
              _animationController.reverse();
              _scrollToBottom();
            }
          },
          onError: (error) {
            print('Generation error: $error');
            if (mounted) {
              setState(() {
                final aiMessageIndex = _messages.length - 1;
                if (aiMessageIndex >= 0 && !_messages[aiMessageIndex].isUser) {
                  final currentText = _messages[aiMessageIndex].text;
                  _messages[aiMessageIndex] = ChatMessage(
                    text:
                        currentText.isEmpty
                            ? 'Sorry, I encountered an error: $error'
                            : currentText,
                    isUser: false,
                    timestamp: _messages[aiMessageIndex].timestamp,
                    error: error.toString(),
                  );
                }
                _isGenerating = false;
              });
              _animationController.reverse();
              _scrollToBottom();
            }
          },
          cancelOnError: true,
        );
  }

  void _stopGeneration() {
    print('Stopping generation...');
    _generationSubscription?.cancel();
    _generationSubscription = null;

    if (mounted) {
      setState(() {
        _isGenerating = false;
      });
      _animationController.reverse();
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _copyMessage(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.copy_rounded, color: Colors.white, size: 14),
            SizedBox(width: 8),
            Text('Copied to clipboard', style: TextStyle(fontSize: 12)),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _shareMessage(String text) {
    // Implement share functionality
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
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 32,
                  height: 3,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Chat Options',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                _buildOptionTile(
                  icon: Icons.clear_all_rounded,
                  title: 'Clear Chat',
                  onTap: () {
                    Navigator.pop(context);
                    _clearChat();
                  },
                ),
                _buildOptionTile(
                  icon: Icons.download_rounded,
                  title: 'Export Chat',
                  onTap: () {
                    Navigator.pop(context);
                    _exportChat();
                  },
                ),
                _buildOptionTile(
                  icon: Icons.settings_rounded,
                  title: 'Settings',
                  onTap: () {
                    Navigator.pop(context);
                    _showGenerationSettings();
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: Colors.grey.shade600),
      ),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  void _clearChat() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: const Text('Clear Chat', style: TextStyle(fontSize: 16)),
            content: const Text(
              'Are you sure you want to clear all messages?',
              style: TextStyle(fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(fontSize: 12)),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _stopGeneration(); // Stop any ongoing generation
                  setState(() {
                    _messages.clear();
                    _addWelcomeMessage();
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Clear', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
    );
  }

  void _exportChat() {
    final chatText = _messages
        .map((msg) => '${msg.isUser ? 'User' : 'Assistant'}: ${msg.text}')
        .join('\n\n');

    Clipboard.setData(ClipboardData(text: chatText));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Chat exported to clipboard',
          style: TextStyle(fontSize: 12),
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showGenerationSettings() {
    // Implement generation settings dialog
  }
}
