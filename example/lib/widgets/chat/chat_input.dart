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
  bool _isExpanded = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed: _showInputOptions,
              icon: Icon(
                Icons.add_circle_outline_rounded,
                color: Colors.grey.shade600,
              ),
            ),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Type your message...',
                    hintStyle: TextStyle(color: Colors.grey.shade500),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onChanged: (text) {
                    setState(() {
                      _isExpanded = text.isNotEmpty;
                    });
                  },
                  onSubmitted: widget.isGenerating ? null : _sendMessage,
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 48,
              height: 48,
              child:
                  widget.isGenerating
                      ? Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          ),
                        ),
                      )
                      : FloatingActionButton(
                        onPressed:
                            _controller.text.trim().isEmpty
                                ? null
                                : () => _sendMessage(_controller.text),
                        backgroundColor:
                            _controller.text.trim().isEmpty
                                ? Colors.grey.shade300
                                : Colors.blue.shade600,
                        elevation: 2,
                        child: Icon(
                          Icons.send_rounded,
                          color:
                              _controller.text.trim().isEmpty
                                  ? Colors.grey.shade600
                                  : Colors.white,
                          size: 20,
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }

  void _sendMessage(String text) {
    if (text.trim().isEmpty || widget.isGenerating) return;

    widget.onSendMessage(text.trim());
    _controller.clear();
    setState(() {
      _isExpanded = false;
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
                    'Quick Actions',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.lightbulb_outline_rounded),
                  title: const Text('Suggest Topics'),
                  onTap: () {
                    Navigator.pop(context);
                    _showTopicSuggestions();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.history_rounded),
                  title: const Text('Recent Prompts'),
                  onTap: () {
                    Navigator.pop(context);
                    // Implement recent prompts
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded),
                  title: const Text('Upload Image'),
                  subtitle: const Text('Coming soon'),
                  enabled: false,
                  onTap: () {
                    Navigator.pop(context);
                    // Implement image upload
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
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
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
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
                    'Topic Suggestions',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: suggestions.length,
                    itemBuilder: (context, index) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(suggestions[index]),
                          trailing: const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _controller.text = suggestions[index];
                            setState(() {
                              _isExpanded = true;
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
