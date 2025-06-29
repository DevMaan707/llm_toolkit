import 'package:flutter/material.dart';

class MessageActions extends StatelessWidget {
  final String messageText;
  final bool isUser;
  final VoidCallback? onCopy;
  final VoidCallback? onShare;
  final VoidCallback? onRegenerate;

  const MessageActions({
    Key? key,
    required this.messageText,
    required this.isUser,
    this.onCopy,
    this.onShare,
    this.onRegenerate,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) const SizedBox(width: 30), // Align with message
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildActionButton(
                  icon: Icons.copy_rounded,
                  onPressed: onCopy,
                  tooltip: 'Copy',
                ),
                if (onShare != null) ...[
                  const SizedBox(width: 4),
                  _buildActionButton(
                    icon: Icons.share_rounded,
                    onPressed: onShare,
                    tooltip: 'Share',
                  ),
                ],
                if (!isUser && onRegenerate != null) ...[
                  const SizedBox(width: 4),
                  _buildActionButton(
                    icon: Icons.refresh_rounded,
                    onPressed: onRegenerate,
                    tooltip: 'Regenerate',
                  ),
                ],
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 46), // Align with avatar
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 14, color: Colors.grey.shade600),
        ),
      ),
    );
  }
}
