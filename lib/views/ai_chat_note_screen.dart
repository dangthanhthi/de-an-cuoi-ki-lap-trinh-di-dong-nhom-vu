// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/ai_service.dart';
import '../controllers/app_state.dart';

/// Màn hình chat với AI.
/// Có thể mở độc lập (chat tự do) hoặc gắn với 1 ghi chú cụ thể.
class AIChatNoteScreen extends StatefulWidget {
  /// Nếu truyền vào thì AI biết ngữ cảnh ghi chú
  final String? noteTitle;
  final String? noteContent;

  /// Nếu muốn AI gợi ý todo và callback về CreateEditNoteScreen
  final int Function(List<AiTodoSuggestion> todos)? onTodosAccepted;

  const AIChatNoteScreen({
    super.key,
    this.noteTitle,
    this.noteContent,
    this.onTodosAccepted,
  });

  @override
  State<AIChatNoteScreen> createState() => _AIChatNoteScreenState();
}

class _AIChatNoteScreenState extends State<AIChatNoteScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  // Session Firestore
  String? _sessionId;
  bool _sessionReady = false;

  // Tin nhắn hiển thị trên UI (gộp Firestore + pending)
  List<AiMessage> _messages = [];
  StreamSubscription<List<AiMessage>>? _messagesSub;

  // State
  bool _isSending = false;
  bool _isTyping = false; // typing indicator của AI
  bool _isAcceptingTodos = false;
  String? _errorMessage;

  // Giới hạn gửi liên tiếp (debounce bằng flag)
  bool _canSend = true;

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  @override
  void dispose() {
    _messagesSub?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Init
  // -------------------------------------------------------------------------

  Future<void> _initSession() async {
    try {
      final sessionId = await AIService.createSession(
        noteId: widget.noteTitle != null ? 'note_context' : null,
        noteTitle: widget.noteTitle,
      );
      if (!mounted) return;

      setState(() {
        _sessionId = sessionId;
        _sessionReady = true;
      });

      // Lắng nghe messages stream từ Firestore
      _messagesSub = AIService.getMessagesStream(sessionId).listen((msgs) {
        if (!mounted) return;
        setState(() => _messages = msgs);
        _scrollToBottom();
      }, onError: (e) => _setError('Lỗi tải lịch sử chat: $e'));

      // Gửi tin nhắn chào mừng của AI (không lưu vào Firestore, chỉ UI)
      _addWelcomeMessage();
    } catch (e) {
      if (!mounted) return;
      _setError('Không thể khởi tạo phiên chat: $e');
    }
  }

  void _addWelcomeMessage() {
    // Tin nhắn chào chỉ hiện trên UI, không lưu Firestore
    final welcome = widget.noteTitle != null
        ? 'Xin chào ${AppState.currentUserName}! Tôi đã đọc ghi chú '
              '"${widget.noteTitle}". Bạn muốn tôi giúp gì nào?'
        : 'Xin chào ${AppState.currentUserName}! Tôi là trợ lý AI của SNote. '
              'Tôi có thể giúp bạn phân tích ghi chú, gợi ý công việc, và trả lời các câu hỏi. '
              'Bạn cần gì?';

    // Thêm vào đầu danh sách local (không qua Firestore stream)
    final welcomeMsg = AiMessage(
      id: '__welcome__',
      role: 'assistant',
      content: welcome,
      timestamp: DateTime.now(),
    );
    if (mounted) setState(() => _messages = [welcomeMsg, ..._messages]);
  }

  // -------------------------------------------------------------------------
  // Send message
  // -------------------------------------------------------------------------

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending || !_canSend || _sessionId == null) return;

    // Debounce: tránh double-tap
    _canSend = false;
    Future.delayed(const Duration(milliseconds: 800), () => _canSend = true);

    setState(() {
      _isSending = true;
      _isTyping = true;
      _errorMessage = null;
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      await AIService.sendMessage(
        sessionId: _sessionId!,
        userText: text,
        noteTitle: widget.noteTitle,
        noteContent: widget.noteContent,
      );
      // Messages sẽ tự cập nhật qua Firestore stream
    } catch (e) {
      if (!mounted) return;
      _setError(AIService.userMessageFor(e));
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
          _isTyping = false;
        });
        _scrollToBottom();
      }
    }
  }

  // -------------------------------------------------------------------------
  // Quick actions
  // -------------------------------------------------------------------------

  Future<void> _requestTodoSuggestions() async {
    if (_sessionId == null || _isSending) return;
    if (widget.noteContent == null || widget.noteContent!.trim().isEmpty) {
      _setError('Ghi chú chưa có nội dung để gợi ý công việc.');
      return;
    }

    setState(() {
      _isSending = true;
      _isTyping = true;
      _errorMessage = null;
    });

    try {
      // Gửi câu hỏi gợi ý todo tự nhiên vào chat
      await AIService.sendMessage(
        sessionId: _sessionId!,
        userText:
            'Hãy phân tích ghi chú này và gợi ý danh sách công việc cần làm (todo) cho tôi.',
        noteTitle: widget.noteTitle,
        noteContent: widget.noteContent,
      );
    } catch (e) {
      if (!mounted) return;
      _setError(AIService.userMessageFor(e));
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
          _isTyping = false;
        });
      }
    }
  }

  Future<void> _requestSummary() async {
    if (_sessionId == null || _isSending) return;

    await _sendUserTextDirectly('Hãy tóm tắt ghi chú này cho tôi.');
  }

  Future<void> _sendUserTextDirectly(String text) async {
    if (_sessionId == null || _isSending) return;
    setState(() {
      _isSending = true;
      _isTyping = true;
      _errorMessage = null;
    });

    try {
      await AIService.sendMessage(
        sessionId: _sessionId!,
        userText: text,
        noteTitle: widget.noteTitle,
        noteContent: widget.noteContent,
      );
    } catch (e) {
      if (!mounted) return;
      _setError(AIService.userMessageFor(e));
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
          _isTyping = false;
        });
      }
    }
  }

  // -------------------------------------------------------------------------
  // Accept todo suggestions
  // -------------------------------------------------------------------------

  void _acceptTodos(List<AiTodoSuggestion> todos) {
    if (_isAcceptingTodos) return;
    if (widget.onTodosAccepted == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mở ghi chú trước để thêm todo vào danh sách nhé!'),
        ),
      );
      return;
    }
    setState(() => _isAcceptingTodos = true);
    final addedCount = widget.onTodosAccepted!(todos);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          addedCount > 0
              ? 'Đã thêm $addedCount công việc vào ghi chú!'
              : 'Các gợi ý này đã có trong ghi chú rồi.',
        ),
        backgroundColor: addedCount > 0 ? Colors.green : Colors.orange,
      ),
    );
    Navigator.pop(context);
  }

  // -------------------------------------------------------------------------
  // UI helpers
  // -------------------------------------------------------------------------

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

  void _setError(String msg) {
    if (!mounted) return;
    setState(() => _errorMessage = msg);
  }

  // ignore: unused_element
  String _friendlyError(String raw) {
    if (raw.contains('API key'))
      return 'Chưa cấu hình AI. Vui lòng liên hệ admin.';
    if (raw.contains('timeout') || raw.contains('SocketException')) {
      return 'Mất kết nối mạng. Vui lòng thử lại.';
    }
    if (raw.contains('429') || raw.contains('Rate limit')) {
      return 'AI đang bận. Vui lòng chờ vài giây rồi thử lại.';
    }
    return 'Có lỗi xảy ra. Vui lòng thử lại.';
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasNoteContext = widget.noteTitle != null;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: _sessionReady ? Colors.green : Colors.orange,
                    shape: BoxShape.circle,
                  ),
                ),
                const Text(
                  'Chat với AI',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (hasNoteContext)
              Text(
                widget.noteTitle!,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          // Nút xóa session
          if (_sessionId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Xóa lịch sử chat này',
              onPressed: _confirmDeleteSession,
            ),
        ],
      ),
      body: !_sessionReady
          ? _buildLoadingState(colorScheme)
          : Column(
              children: [
                // Quick action chips (chỉ khi có ngữ cảnh ghi chú)
                if (hasNoteContext) _buildQuickActions(colorScheme),

                // Error banner
                if (_errorMessage != null) _buildErrorBanner(colorScheme),

                // Messages list
                Expanded(child: _buildMessagesList(colorScheme)),

                // Typing indicator
                if (_isTyping) _buildTypingIndicator(colorScheme),

                // Input bar
                _buildInputBar(colorScheme),
              ],
            ),
    );
  }

  Widget _buildLoadingState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Đang khởi tạo AI...',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _quickChip(
              icon: Icons.checklist_rtl_outlined,
              label: 'Gợi ý Todo',
              onTap: _isSending ? null : _requestTodoSuggestions,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            _quickChip(
              icon: Icons.summarize_outlined,
              label: 'Tóm tắt',
              onTap: _isSending ? null : _requestSummary,
              color: colorScheme.secondary,
            ),
            const SizedBox(width: 8),
            _quickChip(
              icon: Icons.lightbulb_outline,
              label: 'Lời khuyên',
              onTap: _isSending
                  ? null
                  : () => _sendUserTextDirectly(
                      'Đưa ra 3-5 lời khuyên chiến lược để thực hiện ý tưởng trong ghi chú này.',
                    ),
              color: Colors.orange,
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickChip({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required Color color,
  }) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: onTap == null ? Colors.grey : color),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: onTap == null ? Colors.grey : color,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: onTap == null
          ? Colors.grey.withValues(alpha: 0.1)
          : color.withValues(alpha: 0.1),
      side: BorderSide(
        color: onTap == null
            ? Colors.grey.withValues(alpha: 0.3)
            : color.withValues(alpha: 0.3),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: onTap,
    );
  }

  Widget _buildErrorBanner(ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(
                color: colorScheme.onErrorContainer,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => setState(() => _errorMessage = null),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList(ColorScheme colorScheme) {
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          'Hãy bắt đầu cuộc trò chuyện!',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        return _buildMessageBubble(msg, colorScheme);
      },
    );
  }

  Widget _buildMessageBubble(AiMessage msg, ColorScheme colorScheme) {
    final isUser = msg.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          // Avatar + bubble
          Row(
            mainAxisAlignment: isUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isUser) ...[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Icon(
                    Icons.auto_awesome,
                    size: 14,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: GestureDetector(
                  onLongPress: () => _copyMessage(msg.content),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.72,
                    ),
                    decoration: BoxDecoration(
                      color: isUser
                          ? colorScheme.primary
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isUser ? 18 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 18),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      msg.content,
                      style: TextStyle(
                        color: isUser
                            ? colorScheme.onPrimary
                            : colorScheme.onSurface,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
              if (isUser) const SizedBox(width: 4),
            ],
          ),

          // Todo suggestions card (chỉ ở assistant message)
          if (!isUser && msg.todoSuggestions.isNotEmpty)
            _buildTodoSuggestionsCard(msg.todoSuggestions, colorScheme),
        ],
      ),
    );
  }

  Widget _buildTodoSuggestionsCard(
    List<AiTodoSuggestion> todos,
    ColorScheme colorScheme,
  ) {
    return Container(
      margin: const EdgeInsets.only(top: 8, left: 36),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.checklist_rtl_outlined,
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Gợi ý ${todos.length} công việc',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...todos.take(5).map((todo) => _buildTodoItem(todo, colorScheme)),
          if (todos.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+ ${todos.length - 5} công việc khác...',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 10),
          // Nút thêm vào ghi chú
          if (widget.onTodosAccepted != null)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.add_task, size: 16),
                label: const Text('Thêm tất cả vào ghi chú'),
                onPressed: _isAcceptingTodos ? null : () => _acceptTodos(todos),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTodoItem(AiTodoSuggestion todo, ColorScheme colorScheme) {
    final priorityColor = _priorityColor(todo.priority);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6, right: 8),
            decoration: BoxDecoration(
              color: priorityColor,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  todo.task,
                  style: const TextStyle(fontSize: 13, height: 1.3),
                ),
                if (todo.deadline != null)
                  Text(
                    '📅 ${todo.deadline}',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: priorityColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _priorityLabel(todo.priority),
              style: TextStyle(
                fontSize: 10,
                color: priorityColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 12, 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: colorScheme.primaryContainer,
            child: Icon(
              Icons.auto_awesome,
              size: 12,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: _TypingDots(color: colorScheme.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(ColorScheme colorScheme) {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              focusNode: _inputFocus,
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              enabled: _sessionReady && !_isSending,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: 'Nhập câu hỏi...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerLow,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _isSending
                ? Container(
                    key: const ValueKey('loading'),
                    width: 48,
                    height: 48,
                    padding: const EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: colorScheme.primary,
                    ),
                  )
                : IconButton.filled(
                    key: const ValueKey('send'),
                    icon: const Icon(Icons.send_rounded),
                    onPressed: _sessionReady ? _sendMessage : null,
                    tooltip: 'Gửi',
                  ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  void _copyMessage(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã sao chép tin nhắn'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _confirmDeleteSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa lịch sử chat?'),
        content: const Text('Toàn bộ cuộc trò chuyện này sẽ bị xóa vĩnh viễn.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirmed == true && _sessionId != null) {
      await AIService.deleteSession(_sessionId!);
      if (mounted) Navigator.pop(context);
    }
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'urgent':
        return Colors.red;
      case 'high':
        return Colors.orange;
      case 'medium':
        return Colors.amber;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _priorityLabel(String priority) {
    switch (priority) {
      case 'urgent':
        return 'Khẩn';
      case 'high':
        return 'Cao';
      case 'medium':
        return 'Vừa';
      case 'low':
        return 'Thấp';
      default:
        return 'Thường';
    }
  }
}

// ---------------------------------------------------------------------------
// Typing dots animation widget
// ---------------------------------------------------------------------------

class _TypingDots extends StatefulWidget {
  final Color color;
  const _TypingDots({required this.color});

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            // Mỗi dot có phase lệch nhau 0.33
            final phase = ((_controller.value + index / 3) % 1.0);
            final opacity = phase < 0.5
                ? 0.3 + phase * 1.4
                : 1.0 - (phase - 0.5) * 1.4;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: opacity.clamp(0.3, 1.0)),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}




