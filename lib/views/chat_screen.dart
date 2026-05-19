import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';

import '../controllers/app_state.dart';
import '../utils/media_utils.dart';
import 'message_details_screen.dart';
import 'components/message_context_menu.dart';
import '../widgets/common/multi_image_gallery.dart';

class ChatScreen extends StatefulWidget {
  final String friendName;
  final String friendEmail;
  final String friendAvatar;

  const ChatScreen({
    super.key,
    required this.friendName,
    required this.friendEmail,
    required this.friendAvatar,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _isSending = false;
  bool _isUploading = false;
  bool _isListening = false;
  bool _isMuted = false;
  bool _isPinned = false;
  String _liveSpeechText = '';
  String _lastInsertedSpeech = '';
  List<String> _attachments = [];
  Map<String, dynamic>? _replyingTo;
  String? _editingMessageId;
  final ScrollController _scrollController = ScrollController();
  final ExpansibleController _pinnedController = ExpansibleController();

  @override
  void initState() {
    super.initState();
    FirebaseService.markChatAsRead(widget.friendEmail);
    _loadChatMeta();
  }

  @override
  void dispose() {
    _pinnedController.dispose();
    _speech.stop();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadChatMeta() async {
    final results = await Future.wait<bool>([
      FirebaseService.isTargetMuted(type: 'user', targetId: widget.friendEmail),
      FirebaseService.isChatPinned(widget.friendEmail),
    ]);
    if (!mounted) return;
    setState(() {
      _isMuted = results[0];
      _isPinned = results[1];
    });
  }


  void _showSnack(String message, {bool success = true}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? null : Theme.of(context).colorScheme.error,
      ),
    );
  }

  String _formatMessageTime(dynamic rawValue) {
    if (rawValue is! Timestamp) return '';
    final date = rawValue.toDate();
    final now = DateTime.now();
    final isToday =
        date.day == now.day && date.month == now.month && date.year == now.year;

    final timeStr =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    if (isToday) return timeStr;

    final diffDays = now.difference(date).inDays;
    if (diffDays < 7) {
      final weekdays = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
      return '${weekdays[date.weekday - 1]} $timeStr';
    }

    return '${date.day}/${date.month} $timeStr';
  }

  String _formatSeparatorDate(Timestamp ts) {
    final date = ts.toDate();
    final now = DateTime.now();
    final timeStr =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    if (date.day == now.day &&
        date.month == now.month &&
        date.year == now.year) {
      return '$timeStr Hôm nay';
    }

    final yesterday = now.subtract(const Duration(days: 1));
    if (date.day == yesterday.day &&
        date.month == yesterday.month &&
        date.year == yesterday.year) {
      return '$timeStr Hôm qua';
    }

    return '$timeStr ${date.day}/${date.month}/${date.year}';
  }

  String _getReplyDisplayText(Map<String, dynamic> data, List<QueryDocumentSnapshot> docs) {
    final replyToId = data['replyToId']?.toString();
    final storedText = (data['replyToText'] ?? '').toString();
    if (replyToId == null || replyToId.isEmpty) return storedText;

    try {
      final parentDoc = docs.firstWhere((d) => d.id == replyToId);
      final parentData = parentDoc.data() as Map<String, dynamic>;
      if (parentData['isRecalled'] == true) {
        return 'Tin nhắn đã bị thu hồi';
      }
    } catch (_) {
      // Not in current list or error, use stored text
    }
    return storedText;
  }

  Future<void> _copyMessageText(String text) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: cleanText));
    if (!mounted) return;
    _showSnack('Đã sao chép tin nhắn');
  }

  Future<void> _pinMessage(
    String messageId,
    String text,
    String senderName, {
    bool isCurrentlyPinned = false,
  }) async {
    final result = await FirebaseService.togglePinChatMessage(
      widget.friendEmail,
      messageId,
      !isCurrentlyPinned,
    );
    if (!mounted) return;
    _showSnack(
      result == 'SUCCESS'
          ? (isCurrentlyPinned ? 'Đã gỡ ghim tin nhắn' : 'Đã ghim tin nhắn')
          : result,
      success: result == 'SUCCESS',
    );
  }

  void _scrollToMessage(String messageId, List<QueryDocumentSnapshot> docs) {
    final index = docs.indexWhere((doc) => doc.id == messageId);
    if (index != -1 && _scrollController.hasClients) {
      double offset = 0.0;
      for (int i = 0; i < index; i++) {
        final doc = docs[i];
        final data = doc.data() as Map<String, dynamic>;
        
        final text = (data['text'] ?? '').toString();
        final attachments = (data['attachments'] as List? ?? []).map((e) => e.toString()).toList();
        final isRecalled = data['isRecalled'] == true;
        final replyToId = data['replyToId']?.toString();
        final reactions = Map<String, String>.from(data['reactions'] ?? {});

        double itemHeight = 70.0; // base height for message
        
        if (isRecalled) {
          itemHeight = 60.0;
        } else {
          if (text.isNotEmpty) {
            final lines = (text.length / 30).ceil();
            itemHeight += (lines - 1) * 20.0;
          }
          if (replyToId != null && replyToId.isNotEmpty) {
            itemHeight += 50.0;
          }
          if (attachments.isNotEmpty) {
            for (var att in attachments) {
              if (isImageValue(att)) {
                itemHeight += 160.0;
              } else {
                itemHeight += 50.0;
              }
            }
          }
          if (reactions.isNotEmpty) {
            itemHeight += 24.0;
          }
        }

        // Date separator
        final currentTimestamp = data['createdAt'] as Timestamp?;
        if (currentTimestamp != null) {
          if (i == docs.length - 1) {
            itemHeight += 60.0;
          } else {
            final olderDoc = docs[i + 1];
            final olderData = olderDoc.data() as Map<String, dynamic>;
            final olderTimestamp = olderData['createdAt'] as Timestamp?;
            if (olderTimestamp != null) {
              final diff = currentTimestamp.toDate().difference(olderTimestamp.toDate());
              if (diff.inMinutes >= 30) {
                itemHeight += 60.0;
              }
            }
          }
        }

        offset += itemHeight;
      }

      _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  void _showMessageDetails(Map<String, dynamic> data) {
    final seenBy = List<String>.from(data['seenBy'] ?? []);
    final reactions = Map<String, String>.from(data['reactions'] ?? {});
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessageDetailsScreen(
          messageText: (data['text'] ?? '').toString(),
          createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
          seenBy: seenBy,
          receivedBy: [widget.friendEmail],
          memberInfoMap: {
            widget.friendEmail: {'name': widget.friendName, 'avatar': widget.friendAvatar},
            AppState.currentUserEmail: {'name': AppState.currentUserName, 'avatar': AppState.currentUserAvatar},
          },
          reactions: reactions,
        ),
      ),
    );
  }


  void _showMessageActions({
    required String messageId,
    required Map<String, dynamic> data,
    required bool isMe,
  }) {
    MessageContextMenu.show(
      context,
      isMe: isMe,
      isRecalled: data['isRecalled'] == true,
      isPinned: data['isPinned'] == true,
      messageText: (data['text'] ?? '').toString(),
      onReact: (emoji) {
        ChatService.toggleMessageReaction(widget.friendEmail, messageId, emoji);
      },
      onReply: () {
        setState(() {
          _replyingTo = {
            'id': messageId,
            'text': (data['text'] ?? '').toString().isEmpty ? 'Hình ảnh/Tệp' : data['text'],
            'senderName': (data['senderName'] ?? 'Người dùng').toString(),
          };
          _editingMessageId = null;
        });
      },
      onCopy: () => _copyMessageText((data['text'] ?? '').toString()),
      onPin: () => _pinMessage(
        messageId,
        (data['text'] ?? '').toString(),
        (data['senderName'] ?? 'Người dùng').toString(),
        isCurrentlyPinned: data['isPinned'] == true,
      ),
      onShowDetails: () => _showMessageDetails(data),
      onDeleteForMe: () async {
        await FirebaseService.deleteMessage(
          widget.friendEmail,
          messageId,
          deleteForEveryone: false,
        );
        if (mounted) _showSnack('Đã ẩn tin nhắn ở phía bạn');
      },
      onRecall: isMe ? () async {
        final shouldRecall = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Thu hồi tin nhắn?'),
            content: const Text('Tin nhắn này sẽ bị xóa đối với tất cả mọi người.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Thu hồi'),
              ),
            ],
          ),
        );
        if (shouldRecall == true) {
          final res = await FirebaseService.deleteMessage(
            widget.friendEmail,
            messageId,
            deleteForEveryone: true,
          );
          if (mounted) {
            _showSnack(
              res == 'SUCCESS' ? 'Đã thu hồi tin nhắn' : res,
              success: res == 'SUCCESS',
            );
          }
        }
      } : null,
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if ((text.isEmpty && _attachments.isEmpty) || _isSending || _isUploading) {
      return;
    }

    // Capture state in case we need to handle errors
    final currentAttachments = List<String>.from(_attachments);
    final currentReply = _replyingTo;
    final currentEditId = _editingMessageId;

    // OPTIMISTIC UPDATE: Clear UI immediately
    _messageController.clear();
    setState(() {
      _attachments = [];
      _replyingTo = null;
      _editingMessageId = null;
      _isSending = false;
      _liveSpeechText = '';
      _lastInsertedSpeech = '';
    });

    try {
      String result;
      if (currentEditId != null) {
        result = await FirebaseService.editMessage(
          widget.friendEmail,
          currentEditId,
          text,
        );
      } else {
        result = await FirebaseService.sendMessage(
          widget.friendEmail,
          text,
          attachments: currentAttachments,
          replyToData: currentReply,
        );
      }

      if (result != 'SUCCESS' && mounted) {
        _showSnack(result, success: false);
      }
    } catch (e) {
      if (mounted) _showSnack('Lỗi gửi tin nhắn: $e', success: false);
    }
  }

  Future<void> _muteFriend(Duration? duration) async {
    await FirebaseService.muteTarget(
      type: 'user',
      targetId: widget.friendEmail,
      label: widget.friendName,
      duration: duration,
    );
    if (!mounted) return;
    setState(() => _isMuted = true);
    _showSnack('Đã tắt thông báo cuộc trò chuyện');
  }

  Future<void> _togglePinnedChat() async {
    final result = await FirebaseService.toggleChatPin(
      widget.friendEmail,
      !_isPinned,
    );
    if (!mounted) return;
    if (result == 'SUCCESS') {
      setState(() => _isPinned = !_isPinned);
      _showSnack(
        _isPinned ? 'Đã ghim cuộc trò chuyện' : 'Đã bỏ ghim cuộc trò chuyện',
      );
      return;
    }
    _showSnack(result, success: false);
  }

  Future<void> _deleteConversation() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa đoạn chat?'),
        content: const Text(
          'Toàn bộ tin nhắn trong cuộc trò chuyện này sẽ bị xóa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;

    final result = await FirebaseService.deleteChatConversation(
      widget.friendEmail,
    );
    if (!mounted) return;
    if (result == 'SUCCESS') {
      setState(() => _isPinned = false);
      _showSnack('Đã xóa toàn bộ đoạn chat');
      return;
    }
    _showSnack(result, success: false);
  }

  Future<void> _blockFriend() async {
    final result = await FirebaseService.blockUser(widget.friendEmail);
    if (!mounted) return;
    Navigator.pop(context);
    _showSnack(
      result == 'SUCCESS' ? 'Đã chặn người dùng này' : result,
      success: result == 'SUCCESS',
    );
  }

  Future<void> _showEditNicknameDialog() async {
    final contactDocId = await FirebaseService.getContactDocIdByEmail(
      widget.friendEmail,
    );
    if (contactDocId.isEmpty) {
      _showSnack('Không tìm thấy thông tin liên hệ để đổi tên', success: false);
      return;
    }

    if (!mounted) return;

    final nameCtrl = TextEditingController(text: widget.friendName);
    final formKey = GlobalKey<FormState>();
    var isSaving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              if (isSaving || formKey.currentState?.validate() != true) return;
              setSheetState(() => isSaving = true);

              final newName = nameCtrl.text.trim();
              final result = await FirebaseService.updateContactName(
                contactDocId,
                newName,
              );

              if (!sheetContext.mounted) return;
              setSheetState(() => isSaving = false);

              if (result == "SUCCESS") {
                if (Navigator.of(sheetContext).canPop()) {
                  Navigator.of(sheetContext).pop();
                }
                _showSnack("Đã cập nhật biệt danh cho ${widget.friendEmail}");
              } else {
                _showSnack(result, success: false);
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 8,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Đổi tên gợi nhớ',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tên này sẽ chỉ hiển thị với bạn trong các cuộc hội thoại.',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: nameCtrl,
                        autofocus: true,
                        enabled: !isSaving,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'Biệt danh',
                          prefixIcon: Icon(Icons.edit_note_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Tên không được để trống';
                          }
                          return null;
                        },
                        onFieldSubmitted: (_) => submit(),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: isSaving ? null : submit,
                          child: Text(
                            isSaving ? 'Đang lưu...' : 'Lưu thay đổi',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    Future.delayed(const Duration(milliseconds: 500), () {
      nameCtrl.dispose();
    });
  }

  void _showChatOptions() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_note_outlined),
              title: const Text('Đổi tên gợi nhớ (biệt danh)'),
              onTap: () {
                Navigator.pop(context);
                _showEditNicknameDialog();
              },
            ),
            ListTile(
              leading: Icon(
                _isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              ),
              title: Text(
                _isPinned ? 'Bỏ ghim cuộc trò chuyện' : 'Ghim cuộc trò chuyện',
              ),
              onTap: () async {
                Navigator.pop(context);
                await _togglePinnedChat();
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_paused_outlined),
              title: const Text('Tắt thông báo 1 giờ'),
              onTap: () async {
                Navigator.pop(context);
                await _muteFriend(const Duration(hours: 1));
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_off_outlined),
              title: const Text('Tắt thông báo cho đến khi mở lại'),
              onTap: () async {
                Navigator.pop(context);
                await _muteFriend(null);
              },
            ),
            if (_isMuted)
              ListTile(
                leading: const Icon(Icons.volume_up_outlined),
                title: const Text('Mở lại thông báo'),
                onTap: () async {
                  await FirebaseService.unmuteTarget(
                    type: 'user',
                    targetId: widget.friendEmail,
                  );
                  if (!context.mounted) return;
                  setState(() => _isMuted = false);
                  Navigator.pop(context);
                  _showSnack('Đã mở lại thông báo');
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Xóa toàn bộ đoạn chat'),
              textColor: Colors.red,
              onTap: () async {
                Navigator.pop(context);
                await _deleteConversation();
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.block, color: Colors.red),
              title: const Text('Chặn người này'),
              textColor: Colors.red,
              onTap: _blockFriend,
            ),
          ],
        ),
      ),
    );
  }

  void _showFullAvatar(String? url, String name) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                width: double.infinity,
                height: double.infinity,
                color: Colors.black.withValues(alpha: 0.8),
              ),
            ),
            Hero(
              tag: 'avatar_preview',
              child: CircleAvatar(
                radius: MediaQuery.of(context).size.width * 0.4,
                backgroundImage: avatarImageProvider(url, name: name),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showChatInfo() {
    final colorScheme = Theme.of(context).colorScheme;

    Widget actionTile({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
      Color? iconColor,
    }) {
      return Expanded(
        child: Material(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (iconColor ?? colorScheme.primary).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: iconColor ?? colorScheme.primary, size: 22),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // User Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.surfaceContainerHigh,
                      colorScheme.surfaceContainerLow,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: () => _showFullAvatar(widget.friendAvatar, widget.friendName),
                      child: Stack(
                        children: [
                          Hero(
                            tag: 'avatar_preview',
                            child: CircleAvatar(
                              radius: 45,
                              backgroundImage: avatarImageProvider(
                                widget.friendAvatar,
                                name: widget.friendName,
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                shape: BoxShape.circle,
                                border: Border.all(color: colorScheme.surface, width: 2),
                              ),
                              child: const Icon(Icons.search, size: 14, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.friendName,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.friendEmail,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _isMuted ? colorScheme.errorContainer : colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isMuted
                                ? Icons.notifications_off_outlined
                                : Icons.notifications_active_outlined,
                            size: 16,
                            color: _isMuted ? colorScheme.onErrorContainer : colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isMuted ? 'Đang tắt thông báo' : 'Đang bật thông báo',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _isMuted ? colorScheme.onErrorContainer : colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Main Actions
              Row(
                children: [
                  actionTile(
                    icon: _isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    title: _isPinned ? 'Bỏ ghim' : 'Ghim chat',
                    subtitle: _isPinned
                        ? 'Đưa về mặc định'
                        : 'Giữ cuộc trò chuyện ở trên cùng',
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await _togglePinnedChat();
                    },
                  ),
                  const SizedBox(width: 12),
                  actionTile(
                    icon: _isMuted
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_off_outlined,
                    title: _isMuted ? 'Mở lại' : 'Tắt báo',
                    subtitle: _isMuted
                        ? 'Nhận lại thông báo'
                        : 'Ẩn thông báo tạm thời',
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      if (_isMuted) {
                        await FirebaseService.unmuteTarget(
                          type: 'user',
                          targetId: widget.friendEmail,
                        );
                        if (!mounted) return;
                        setState(() => _isMuted = false);
                        _showSnack('Đã mở lại thông báo');
                        return;
                      }
                      await _muteFriend(null);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Secondary Options
              Material(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  leading: CircleAvatar(
                    backgroundColor: colorScheme.secondaryContainer,
                    child: Icon(Icons.settings_outlined, color: colorScheme.secondary),
                  ),
                  title: const Text(
                    'Tùy chọn nâng cao',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('Xóa lịch sử, chặn người dùng...'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showChatOptions();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleVoiceInput() async {
    if (_isListening) {
      final capturedText = _liveSpeechText;
      await _speech.stop();
      _insertVoiceText(capturedText);
      if (mounted) setState(() => _isListening = false);
      return;
    }

    final microphoneStatus = await Permission.microphone.request();
    if (!microphoneStatus.isGranted) {
      _showSnack(
        'Bạn cần cấp quyền micro để nhập bằng giọng nói.',
        success: false,
      );
      return;
    }

    final available = await _speech.initialize(
      onStatus: (status) {
        if (!mounted) return;
        if (status == 'done' || status == 'notListening') {
          _insertVoiceText(_liveSpeechText);
          setState(() => _isListening = false);
        }
      },
      onError: (error) {
        if (!mounted) return;
        setState(() => _isListening = false);
        _showSnack(
          'Không nhận được giọng nói: ${error.errorMsg}',
          success: false,
        );
      },
    );

    if (!available) {
      _showSnack('Thiết bị chưa hỗ trợ nhận giọng nói.', success: false);
      return;
    }

    setState(() {
      _isListening = true;
      _liveSpeechText = '';
      _lastInsertedSpeech = '';
    });

    await _speech.listen(
      localeId: 'vi_VN',
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
      ),
      onResult: (result) {
        if (!mounted) return;
        setState(() => _liveSpeechText = result.recognizedWords);
        if (result.finalResult) _insertVoiceText(result.recognizedWords);
      },
    );
  }

  void _insertVoiceText(String text) {
    final cleanText = text.trim();
    if (cleanText.isEmpty || cleanText == _lastInsertedSpeech) return;
    _lastInsertedSpeech = cleanText;
    final current = _messageController.text.trim();
    _messageController.text = current.isEmpty
        ? cleanText
        : '$current $cleanText';
    _messageController.selection = TextSelection.fromPosition(
      TextPosition(offset: _messageController.text.length),
    );
    setState(() => _liveSpeechText = '');
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Chụp ảnh'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickImageAttachment(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Chọn ảnh từ thư viện'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickImageAttachment(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _requestGalleryPermission() async {
    if (Platform.isIOS) {
      final status = await Permission.photos.request();
      return status.isGranted || status.isLimited;
    }
    if (await Permission.photos.status.isGranted) return true;
    final result = await Permission.photos.request();
    if (result.isGranted) return true;
    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  Future<void> _pickImageAttachment(ImageSource source) async {
    if (_isUploading) return;

    if (source == ImageSource.camera) {
      final cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        _showSnack('Bạn cần cấp quyền camera để chụp ảnh.', success: false);
        return;
      }
    } else {
      if (!await _requestGalleryPermission()) {
        _showSnack('Bạn cần cấp quyền truy cập ảnh.', success: false);
        return;
      }
    }

    if (source == ImageSource.gallery) {
      final images = await _imagePicker.pickMultiImage(
        imageQuality: 40,
        maxWidth: 500,
      );
      if (images.isNotEmpty) {
        for (final img in images) {
          final file = File(img.path);
          final fileSize = await file.length();
          if (fileSize <= FirebaseService.maxAttachmentBytes) {
            final fileName = img.name.isNotEmpty ? img.name : 'image.jpg';
            _uploadAttachmentFile(file, fileName, fileSize);
          }
        }
      }
    } else {
      final image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 40,
        maxWidth: 500,
      );
      if (image == null) return;

      final file = File(image.path);
      final fileSize = await file.length();
      if (fileSize > FirebaseService.maxAttachmentBytes) {
        _showSnack('Ảnh quá lớn (>30MB).', success: false);
        return;
      }

      final fileName = image.name.isNotEmpty ? image.name : 'image.jpg';
      await _uploadAttachmentFile(file, fileName, fileSize);
    }
  }

  Future<void> _pickFileAttachment() async {
    if (_isUploading) return;
    if (Platform.isAndroid) {
      await Permission.storage.request();
    }
    final result = await FilePicker.pickFiles(withData: false, allowMultiple: true);
    if (result != null && result.files.isNotEmpty) {
      for (final pickedFile in result.files) {
        if (pickedFile.path != null) {
          final file = File(pickedFile.path!);
          final fileSize = pickedFile.size > 0 ? pickedFile.size : await file.length();
          if (fileSize <= FirebaseService.maxAttachmentBytes) {
            _uploadAttachmentFile(file, pickedFile.name, fileSize);
          }
        }
      }
    }
  }

  Future<void> _uploadAttachmentFile(
    File file,
    String fileName,
    int fileSize,
  ) async {
    setState(() => _isUploading = true);
    try {
      final url = await FirebaseService.uploadAttachmentFile(
        file,
        fileName,
        fileSize: fileSize,
      );
      if (url.isEmpty) throw Exception('Không tải được tệp lên.');
      if (!mounted) return;
      setState(() => _attachments.add(url));
    } catch (e) {
      _showSnack('Lỗi đính kèm: $e', success: false);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _openAttachment(String value, int index) async {
    try {
      final bytes = bytesFromDataUri(value);
      if (bytes != null) {
        final fileName = sanitizeFileName(
          fileNameFromDataUri(value, fallback: 'tep-${index + 1}'),
          fallback: 'tep-${index + 1}',
        );
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(bytes, flush: true);
        await OpenFilex.open(file.path);
        return;
      }
      final uri = Uri.tryParse(value);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showSnack('Không mở được tệp', success: false);
      }
    } catch (e) {
      _showSnack('Lỗi mở tệp: $e', success: false);
    }
  }

  void _showImagePreview(String value, int index) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: _AttachmentImage(
                  value: value,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDraftAttachments() {
    if (_attachments.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < _attachments.length; i++)
            InputChip(
              avatar: Icon(
                isImageValue(_attachments[i]) ? Icons.image_outlined : Icons.attach_file,
                size: 18,
              ),
              label: Text(attachmentLabel(_attachments[i], i)),
              onDeleted: () => setState(() => _attachments.removeAt(i)),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageAttachments(
    List<String> attachments,
    bool isMe,
    ColorScheme colorScheme,
  ) {
    final images = attachments.where((a) => isImageValue(a)).toList();
    final files = attachments.where((a) => !isImageValue(a)).toList();

    return Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (images.isNotEmpty) ...[
          MultiImageGallery(
            images: images,
            onTapImage: (index) {
              final originalIndex = attachments.indexOf(images[index]);
              _showImagePreview(images[index], originalIndex);
            },
            maxWidth: MediaQuery.of(context).size.width * 0.7,
          ),
          if (files.isNotEmpty) const SizedBox(height: 8),
        ],
        for (var i = 0; i < files.length; i++) ...[
          InkWell(
            onTap: () => _openAttachment(files[i], attachments.indexOf(files[i])),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isMe
                    ? colorScheme.onPrimary.withValues(alpha: 0.12)
                    : colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isMe
                      ? colorScheme.onPrimary.withValues(alpha: 0.18)
                      : colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.attach_file,
                    size: 18,
                    color: isMe ? colorScheme.onPrimary : colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      attachmentLabel(files[i], attachments.indexOf(files[i])),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: isMe ? colorScheme.onPrimary : null),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildReplyPreview() {
    if (_replyingTo == null) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: colorScheme.primary, width: 4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Đang trả lời ${_replyingTo!['senderName']}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                Text(
                  _replyingTo!['text'],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => setState(() => _replyingTo = null),
          ),
        ],
      ),
    );
  }

  Widget _buildEditHeader() {
    if (_editingMessageId == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: const Border(left: BorderSide(color: Colors.amber, width: 4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_outlined, size: 16, color: Colors.amber),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Đang sửa tin nhắn...',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.amber),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () {
              setState(() {
                _editingMessageId = null;
                _messageController.clear();
              });
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showUnpinDialog(String messageId) async {
    final chatId = FirebaseService.chatIdForEmails(
      AppState.currentUserEmail,
      widget.friendEmail,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gỡ ghim tin nhắn?'),
        content: const Text('Bạn có chắc chắn muốn gỡ ghim tin nhắn này không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseFirestore.instance
                  .collection('chats')
                  .doc(chatId)
                  .collection('messages')
                  .doc(messageId)
                  .update({'isPinned': false});
              _showSnack('Đã gỡ ghim tin nhắn', success: true);
            },
            child: const Text('Gỡ ghim', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildPinnedMessagesBar(List<QueryDocumentSnapshot> allMessages) {
    final chatId = FirebaseService.chatIdForEmails(
      AppState.currentUserEmail,
      widget.friendEmail,
    );
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .where('isPinned', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();
        final colorScheme = Theme.of(context).colorScheme;
        return Container(
          width: double.infinity,
          color: colorScheme.surfaceContainerLow,
          child: ExpansionTile(
            controller: _pinnedController,
            shape: const Border(),
            leading: Icon(Icons.push_pin, size: 20, color: colorScheme.primary),
            title: Text(
              '${docs.length} tin nhắn đã ghim',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            children: docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final text = (data['text'] ?? '').toString();
              final attachments = List<String>.from(data['attachments'] ?? []);
              
              String displayText = text;
              if (text.isEmpty && attachments.isNotEmpty) {
                final firstUrl = attachments.first.toLowerCase();
                if (firstUrl.contains('.jpg') || 
                    firstUrl.contains('.jpeg') || 
                    firstUrl.contains('.png') || 
                    firstUrl.contains('.gif') || 
                    firstUrl.contains('.webp')) {
                  displayText = 'Đã ghim 1 ảnh';
                } else {
                  displayText = 'Đã ghim 1 file';
                }
              }

              return ListTile(
                dense: true,
                title: Text(
                  displayText.isEmpty ? 'Hình ảnh/Tệp' : displayText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  'Bởi ${data['senderName'] ?? 'Ẩn danh'}',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: const Icon(Icons.chevron_right, size: 16),
                onTap: () {
                  _pinnedController.collapse();
                  _scrollToMessage(doc.id, allMessages);
                },
                onLongPress: () => _showUnpinDialog(doc.id),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(
          onTap: _showChatInfo,
          onLongPress: _togglePinnedChat,
          child: Row(
            children: [
              CircleAvatar(
                backgroundImage: avatarImageProvider(
                  widget.friendAvatar,
                  name: widget.friendName,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.friendName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (_isPinned) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.push_pin, size: 16, color: colorScheme.primary),
                        ],
                      ],
                    ),
                    Text(
                      _isMuted ? 'Đang tắt thông báo' : 'Chạm để xem thông tin',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showChatOptions,
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseService.getMessagesStream(widget.friendEmail),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final allDocs = snapshot.data?.docs ?? [];
          final docs = allDocs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final hiddenBy = List<String>.from(data['hiddenBy'] ?? const []);
            return !hiddenBy.contains(myEmail);
          }).toList();

          return Column(
            children: [
              _buildPinnedMessagesBar(docs),
              Expanded(
                child: docs.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                radius: 34,
                                backgroundImage: avatarImageProvider(
                                  widget.friendAvatar,
                                  name: widget.friendName,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                widget.friendName,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Bắt đầu cuộc trò chuyện, gửi ảnh hoặc giao tiếp bằng giọng nói ngay tại đây.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final isMe = (data['senderEmail'] ?? '').toString() == myEmail;
                          final attachments = (data['attachments'] as List? ?? [])
                              .map((e) => e.toString())
                              .toList();
                          final isRecalled = data['isRecalled'] == true;
                          final text = isRecalled
                              ? 'Tin nhắn đã bị thu hồi'
                              : (data['text'] ?? '').toString();
                          final timeLabel = _formatMessageTime(data['createdAt']);
                          final seenBy = List<String>.from(data['seenBy'] ?? const []);
                          final chatId = FirebaseService.chatIdForEmails(myEmail, widget.friendEmail);
                          if (!isMe && !seenBy.contains(myEmail)) {
                            FirebaseService.markMessageAsSeen(chatId, doc.id);
                          }

                          final reactions = Map<String, String>.from(data['reactions'] ?? {});

                          final currentTimestamp = data['createdAt'] as Timestamp?;
                          bool showDateSeparator = false;
                          if (currentTimestamp != null) {
                            if (index == docs.length - 1) {
                              showDateSeparator = true;
                            } else {
                              final olderDoc = docs[index + 1];
                              final olderData =
                                  olderDoc.data() as Map<String, dynamic>;
                              final olderTimestamp =
                                  olderData['createdAt'] as Timestamp?;
                              if (olderTimestamp != null) {
                                final diff = currentTimestamp
                                    .toDate()
                                    .difference(olderTimestamp.toDate());
                                if (diff.inMinutes >= 30) {
                                  showDateSeparator = true;
                                }
                              }
                            }
                          }

                          return Column(
                            children: [
                              if (showDateSeparator && currentTimestamp != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 24,
                                  ),
                                  child: Text(
                                    _formatSeparatorDate(currentTimestamp),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.7),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              Align(
                                alignment: isMe
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (!isMe)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 8, bottom: 12),
                                        child: CircleAvatar(
                                          radius: 14,
                                          backgroundImage: avatarImageProvider(
                                            widget.friendAvatar,
                                            name: widget.friendName,
                                          ),
                                        ),
                                      ),
                                    Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onLongPress: () {
                                            HapticFeedback.heavyImpact();
                                            _showMessageActions(
                                              messageId: doc.id,
                                              data: data,
                                              isMe: isMe,
                                            );
                                          },
                                          child: Container(
                                            constraints: BoxConstraints(
                                              maxWidth: MediaQuery.of(context).size.width * 
                                                  (isMe ? 0.78 : 0.72),
                                            ),
                                            margin: const EdgeInsets.only(bottom: 12),
                                            padding: (text.trim().isEmpty && attachments.isNotEmpty && attachments.every((a) => isImageValue(a)))
                                                ? EdgeInsets.zero
                                                : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                            decoration: BoxDecoration(
                                              color: (text.trim().isEmpty && attachments.isNotEmpty && attachments.every((a) => isImageValue(a)))
                                                  ? Colors.transparent
                                                  : (isRecalled
                                                      ? (isMe
                                                          ? colorScheme.primary.withValues(alpha: 0.1)
                                                          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5))
                                                      : (isMe
                                                          ? colorScheme.primary
                                                          : colorScheme.surfaceContainerHighest)),
                                              borderRadius: BorderRadius.circular(24),
                                              boxShadow: [
                                                if (!isRecalled && !(text.trim().isEmpty && attachments.isNotEmpty && attachments.every((a) => isImageValue(a))))
                                                  BoxShadow(
                                                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 2),
                                                  ),
                                              ],
                                            ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (data['isPinned'] == true)
                                              Padding(
                                                padding: const EdgeInsets.only(bottom: 6),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.push_pin, size: 12, color: Colors.amber),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'Đã ghim',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: isMe ? Colors.amber.shade100 : Colors.amber.shade800,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            if (!isRecalled &&
                                                data['replyToId'] != null &&
                                                (data['replyToId'] as String).isNotEmpty)
                                              InkWell(
                                                onTap: () => _scrollToMessage(data['replyToId'], docs),
                                                borderRadius: BorderRadius.circular(8),
                                                child: Container(
                                                  margin: const EdgeInsets.only(bottom: 6),
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: isMe
                                                        ? colorScheme.onPrimary.withValues(alpha: 0.16)
                                                        : colorScheme.primary.withValues(alpha: 0.1),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        (data['replyToSender'] ?? 'Người dùng').toString(),
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.bold,
                                                          color: isMe ? colorScheme.onPrimary : colorScheme.primary,
                                                        ),
                                                      ),
                                                      Text(
                                                        _getReplyDisplayText(data, docs),
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: isMe
                                                              ? colorScheme.onPrimary.withValues(alpha: 0.8)
                                                              : colorScheme.onSurfaceVariant,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            if (!isRecalled && attachments.isNotEmpty)
                                              _buildMessageAttachments(attachments, isMe, colorScheme),
                                            Text(
                                              text,
                                              style: TextStyle(
                                                color: isRecalled
                                                    ? (isMe ? colorScheme.primary : colorScheme.onSurfaceVariant)
                                                    : (isMe ? colorScheme.onPrimary : null),
                                                fontStyle: isRecalled ? FontStyle.italic : null,
                                                fontSize: isRecalled ? 13 : null,
                                              ),
                                            ),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              children: [
                                                if (data['isEdited'] == true)
                                                  Padding(
                                                    padding: const EdgeInsets.only(right: 4, top: 4),
                                                    child: Text(
                                                      '(Đã chỉnh sửa)',
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        fontStyle: FontStyle.italic,
                                                        color: isMe
                                                            ? Colors.white70
                                                            : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                                      ),
                                                    ),
                                                  ),
                                                if (timeLabel.isNotEmpty)
                                                  Padding(
                                                    padding: const EdgeInsets.only(top: 4),
                                                    child: Text(
                                                      timeLabel,
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.w400,
                                                        color: isMe
                                                            ? Colors.white60
                                                            : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                           ],
                                         ),
                                       ),
                                     ),
                                    if (reactions.isNotEmpty)
                                      Positioned(
                                        bottom: 0,
                                        right: isMe ? 8 : null,
                                        left: isMe ? null : 8,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: colorScheme.surface,
                                            borderRadius: BorderRadius.circular(12),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.1),
                                                blurRadius: 4,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                            border: Border.all(color: colorScheme.outlineVariant, width: 0.5),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                reactions.values.toSet().join(''),
                                                style: const TextStyle(fontSize: 12),
                                              ),
                                              if (reactions.length > 1) ...[
                                                const SizedBox(width: 4),
                                                Text(
                                                  '${reactions.length}',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: colorScheme.primary,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                    ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (isMe &&
                                    index == 0 &&
                                    seenBy.contains(widget.friendEmail))
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                          top: 4, right: 4),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'Đã xem',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: colorScheme
                                                  .onSurfaceVariant,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          CircleAvatar(
                                            radius: 7,
                                            backgroundImage:
                                                avatarImageProvider(
                                              widget.friendAvatar,
                                              name: widget.friendName,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            );
                        },
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildReplyPreview(),
                        _buildEditHeader(),
                        _buildDraftAttachments(),
                        if (_liveSpeechText.isNotEmpty)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(_liveSpeechText),
                          ),
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Ảnh',
                              onPressed: _isUploading ? null : _showImageSourceSheet,
                              icon: const Icon(Icons.image_outlined),
                            ),
                            IconButton(
                              tooltip: 'Tệp',
                              onPressed: _isUploading ? null : _pickFileAttachment,
                              icon: const Icon(Icons.attach_file),
                            ),
                            IconButton(
                              tooltip: 'Giọng nói',
                              onPressed: _toggleVoiceInput,
                              icon: Icon(_isListening ? Icons.stop_circle : Icons.mic_none),
                            ),
                            if (_isUploading)
                              const Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: TextField(
                                controller: _messageController,
                                minLines: 1,
                                maxLines: 4,
                                maxLength: 2000,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => _sendMessage(),
                                decoration: InputDecoration(
                                  hintText: 'Nhập tin nhắn...',
                                  counterText: '',
                                  filled: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              onPressed: _isSending || _isUploading
                                  ? null
                                  : () {
                                      HapticFeedback.lightImpact();
                                      _sendMessage();
                                    },
                              icon: _isSending
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.send),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AttachmentImage extends StatelessWidget {
  final String value;
  final BoxFit fit;

  const _AttachmentImage({required this.value, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    final bytes = bytesFromDataUri(value);
    if (bytes != null) return Image.memory(bytes, fit: fit);
    return Image.network(
      value,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined),
      ),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
    );
  }
}
