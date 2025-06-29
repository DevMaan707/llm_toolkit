import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildModelInfo(),
          Expanded(child: _buildMessagesList()),
          if (_isGenerating) const TypingIndicator(),
          ChatInput(onSendMessage: _sendMessage, isGenerating: _isGenerating),
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
            colors: [
              Theme.of(context).primaryColor,
              Theme.of(context).primaryColor.withOpacity(0.8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Chat Assistant',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          Text(
            'Powered by ${widget.llmService.activeEngine?.name ?? 'Unknown'} Engine',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: _showChatOptions,
          icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
        ),
      ],
    );
  }

  Widget _buildModelInfo() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade50, AppColors.blueLight],
        ),
        border: Border(bottom: BorderSide(color: Colors.blue.shade100)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.green.shade600,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 12,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Model: ${widget.llmService.selectedModelName ?? 'Unknown'}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            '${_messages.length} messages',
            style: TextStyle(fontSize: 11, color: Colors.blue.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    if (_messages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'Start a conversation',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
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

    final aiMessage = ChatMessage(text: '', isUser: false);
    setState(() => _messages.add(aiMessage));

    _animationController.forward();

    widget.llmService
        .generateText(text)
        .listen(
          (token) {
            setState(() {
              aiMessage.text += token;
            });
            _scrollToBottom();
          },
          onDone: () {
            setState(() => _isGenerating = false);
            _animationController.reverse();
            _scrollToBottom();
          },
          onError: (error) {
            setState(() {
              aiMessage.text = 'Sorry, I encountered an error: $error';
              aiMessage.error = error.toString();
              _isGenerating = false;
            });
            _animationController.reverse();
            _scrollToBottom();
          },
        );
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

  void _copyMessage(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.copy_rounded, color: Colors.white, size: 16),
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

  void _shareMessage(String text) {
    // Implement share functionality
    // You might want to use the share_plus package
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
                  leading: const Icon(Icons.settings_rounded),
                  title: const Text('Generation Settings'),
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

  void _clearChat() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Clear Chat'),
            content: const Text('Are you sure you want to clear all messages?'),
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
        .map((msg) => '${msg.isUser ? 'User' : 'Assistant'}: ${msg.text}')
        .join('\n\n');

    Clipboard.setData(ClipboardData(text: chatText));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Chat exported to clipboard'),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showGenerationSettings() {
    // Implement generation settings dialog
  }
}
