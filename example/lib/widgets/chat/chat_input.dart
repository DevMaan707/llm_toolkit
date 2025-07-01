import 'package:flutter/material.dart';

class ChatInput extends StatefulWidget {
  final Function(String) onSendMessage;
  final VoidCallback onStopGeneration;
  final bool isGenerating;

  const ChatInput({
    Key? key,
    required this.onSendMessage,
    required this.onStopGeneration,
    required this.isGenerating,
  }) : super(key: key);

  @override
  _ChatInputState createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() {
        _hasText = _controller.text.trim().isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200, width: 1)),
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
                enabled: !widget.isGenerating,
                decoration: InputDecoration(
                  hintText:
                      widget.isGenerating
                          ? 'AI is thinking...'
                          : 'Type your message...',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: widget.isGenerating ? null : _sendMessage,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _buildActionButton(),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    if (widget.isGenerating) {
      // Show stop button when generating
      return Container(
        decoration: BoxDecoration(
          color: Colors.red.shade600,
          shape: BoxShape.circle,
        ),
        child: IconButton(
          onPressed: widget.onStopGeneration,
          icon: const Icon(Icons.stop_rounded, color: Colors.white, size: 20),
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        ),
      );
    } else {
      // Show send button when not generating
      return Container(
        decoration: BoxDecoration(
          color: _hasText ? Colors.blue.shade600 : Colors.grey.shade400,
          shape: BoxShape.circle,
        ),
        child: IconButton(
          onPressed: _hasText ? () => _sendMessage(_controller.text) : null,
          icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        ),
      );
    }
  }

  void _sendMessage(String text) {
    if (text.trim().isEmpty || widget.isGenerating) return;

    widget.onSendMessage(text.trim());
    _controller.clear();
    setState(() {
      _hasText = false;
    });
  }
}
