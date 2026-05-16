import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MessageContextMenu extends StatelessWidget {
  final bool isMe;
  final bool isRecalled;
  final bool isPinned;
  final String messageText;
  final Function(String emoji) onReact;
  final VoidCallback onReply;
  final VoidCallback onCopy;
  final VoidCallback onPin;
  final VoidCallback onShowDetails;
  final VoidCallback onDeleteForMe;
  final VoidCallback? onRecall;

  const MessageContextMenu({
    super.key,
    required this.isMe,
    required this.isRecalled,
    required this.isPinned,
    required this.messageText,
    required this.onReact,
    required this.onReply,
    required this.onCopy,
    required this.onPin,
    required this.onShowDetails,
    required this.onDeleteForMe,
    this.onRecall,
  });

  static const List<String> reactions = ['❤️', '👍', '😄', '😲', '😭', '😡'];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          
          // Message Preview
          if (!isRecalled && messageText.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Text(
                messageText,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),

          // Reaction Bar
          if (!isRecalled)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: reactions.map((emoji) {
                  return InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      onReact(emoji);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(emoji, style: const TextStyle(fontSize: 28)),
                    ),
                  );
                }).toList(),
              ),
            ),

          const SizedBox(height: 12),

          // Action Grid
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 4,
            mainAxisSpacing: 16,
            crossAxisSpacing: 8,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              if (!isRecalled) ...[
                _ActionItem(
                  icon: Icons.reply,
                  label: 'Trả lời',
                  onTap: () {
                    Navigator.pop(context);
                    onReply();
                  },
                ),
                _ActionItem(
                  icon: Icons.copy,
                  label: 'Sao chép',
                  onTap: () {
                    Navigator.pop(context);
                    onCopy();
                  },
                ),
                _ActionItem(
                  icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  label: isPinned ? 'Bỏ ghim' : 'Ghim',
                  iconColor: isPinned ? Colors.orange : null,
                  onTap: () {
                    Navigator.pop(context);
                    onPin();
                  },
                ),
              ],
              _ActionItem(
                icon: Icons.info_outline,
                label: 'Chi tiết',
                onTap: () {
                  Navigator.pop(context);
                  onShowDetails();
                },
              ),
              _ActionItem(
                icon: Icons.delete_outline,
                label: 'Xóa',
                onTap: () {
                  Navigator.pop(context);
                  onDeleteForMe();
                },
              ),
              if (isMe && !isRecalled && onRecall != null)
                _ActionItem(
                  icon: Icons.undo,
                  label: 'Thu hồi',
                  iconColor: Colors.red,
                  textColor: Colors.red,
                  onTap: () {
                    Navigator.pop(context);
                    onRecall!();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  static void show(
    BuildContext context, {
    required bool isMe,
    required bool isRecalled,
    required bool isPinned,
    required String messageText,
    required Function(String emoji) onReact,
    required VoidCallback onReply,
    required VoidCallback onCopy,
    required VoidCallback onPin,
    required VoidCallback onShowDetails,
    required VoidCallback onDeleteForMe,
    VoidCallback? onRecall,
  }) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => MessageContextMenu(
        isMe: isMe,
        isRecalled: isRecalled,
        isPinned: isPinned,
        messageText: messageText,
        onReact: onReact,
        onReply: onReply,
        onCopy: onCopy,
        onPin: onPin,
        onShowDetails: onShowDetails,
        onDeleteForMe: onDeleteForMe,
        onRecall: onRecall,
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? textColor;

  const _ActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (iconColor ?? colorScheme.primary).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor ?? colorScheme.primary, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: textColor ?? colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
