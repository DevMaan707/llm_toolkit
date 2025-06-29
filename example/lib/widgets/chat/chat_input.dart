import 'package:flutter/material.dart';

class ChatInput extends StatefulWidget {
  final Function(String) onSendMessage;
  final bool isGenerating;

  const ChatInput({
    Key? key,
    required this.onSendMessage,
    this.isGenerating = false,
  }) : super(key: key);

  @override
  _ChatInputState createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _hasText = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildQuickActionsButton(),
            const SizedBox(width: 8),
            Expanded(child: _buildInputField()),
            const SizedBox(width: 8),
            _buildSendButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsButton() {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(18),
      ),
      child: IconButton(
        onPressed: _showInputOptions,
        icon: Icon(
          Icons.add_circle_outline_rounded,
          color: Colors.grey.shade600,
          size: 18,
        ),
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildInputField() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 100),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        maxLines: null,
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Type your message...',
          hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
        ),
        onChanged: (text) {
          setState(() {
            _hasText = text.trim().isNotEmpty;
          });
        },
        onSubmitted: widget.isGenerating ? null : _sendMessage,
      ),
    );
  }

  Widget _buildSendButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 36,
      height: 36,
      child:
          widget.isGenerating
              ? Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
              )
              : Container(
                decoration: BoxDecoration(
                  gradient:
                      _hasText
                          ? LinearGradient(
                            colors: [
                              const Color(0xFF3B82F6),
                              const Color(0xFF1E40AF),
                            ],
                          )
                          : null,
                  color: _hasText ? null : Colors.grey.shade300,
                  shape: BoxShape.circle,
                  boxShadow:
                      _hasText
                          ? [
                            BoxShadow(
                              color: const Color(0xFF3B82F6).withOpacity(0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ]
                          : null,
                ),
                child: IconButton(
                  onPressed:
                      _hasText ? () => _sendMessage(_controller.text) : null,
                  icon: Icon(
                    Icons.send_rounded,
                    color: _hasText ? Colors.white : Colors.grey.shade600,
                    size: 16,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ),
    );
  }

  void _sendMessage(String text) {
    if (text.trim().isEmpty || widget.isGenerating) return;

    widget.onSendMessage(text.trim());
    _controller.clear();
    setState(() {
      _hasText = false;
    });
  }

  void _showInputOptions() {
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
                    'Quick Actions',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                _buildQuickAction(
                  icon: Icons.lightbulb_outline_rounded,
                  title: 'Suggest Topics',
                  subtitle: 'Get conversation starters',
                  onTap: () {
                    Navigator.pop(context);
                    _showTopicSuggestions();
                  },
                ),
                _buildQuickAction(
                  icon: Icons.history_rounded,
                  title: 'Recent Prompts',
                  subtitle: 'Reuse previous messages',
                  onTap: () {
                    Navigator.pop(context);
                  },
                ),
                _buildQuickAction(
                  icon: Icons.photo_library_rounded,
                  title: 'Upload Image',
                  subtitle: 'Coming soon',
                  enabled: false,
                  onTap: () {
                    Navigator.pop(context);
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: enabled ? Colors.blue.shade50 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled ? Colors.blue.shade600 : Colors.grey.shade400,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: enabled ? Colors.black87 : Colors.grey.shade400,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 11,
          color: enabled ? Colors.grey.shade600 : Colors.grey.shade400,
        ),
      ),
      onTap: enabled ? onTap : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  void _showTopicSuggestions() {
    final suggestions = [
      'Explain quantum computing in simple terms',
      'Write a creative story about space exploration',
      'Help me debug this code',
      'Translate this text to Spanish',
      'Summarize the latest tech news',
      'Give me a recipe for chocolate cake',
      'What are the benefits of renewable energy?',
      'How does machine learning work?',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (context) => Container(
            height: MediaQuery.of(context).size.height * 0.6,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Column(
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
                    'Topic Suggestions',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: suggestions.length,
                    itemBuilder: (context, index) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          leading: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 14,
                              color: Colors.blue.shade600,
                            ),
                          ),
                          title: Text(
                            suggestions[index],
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 12,
                            color: Colors.grey.shade400,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _controller.text = suggestions[index];
                            setState(() {
                              _hasText = true;
                            });
                            _focusNode.requestFocus();
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
    );
  }
}
