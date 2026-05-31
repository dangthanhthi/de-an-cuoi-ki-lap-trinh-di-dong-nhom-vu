import 'dart:io';
import 'dart:convert';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:easy_image_viewer/easy_image_viewer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import 'image_grid_preview_screen.dart';
import '../controllers/app_state.dart';
import '../controllers/notification_service.dart';
import '../controllers/ai_service.dart';
import '../models/app_models.dart';
import '../utils/media_utils.dart';
import '../utils/snack_utils.dart';
import 'ai_chat_note_screen.dart';

class CreateEditNoteScreen extends StatefulWidget {
  final Note? note;
  final String? docId;
  final String? initialGroupId;

  const CreateEditNoteScreen({
    super.key,
    this.note,
    this.docId,
    this.initialGroupId,
  });

  @override
  State<CreateEditNoteScreen> createState() => _CreateEditNoteScreenState();
}

class _CreateEditNoteScreenState extends State<CreateEditNoteScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final TextEditingController _customLabelController;
  late final TextEditingController _customPriorityController;
  late final stt.SpeechToText _speech;

  String _selectedLabel = AppState.labels.first;
  bool _isTodo = false;
  List<TodoItem> _todos = [];
  bool _hasReminder = false;
  DateTime? _selectedReminderTime;
  List<String> _attachments = [];
  final List<Map<String, dynamic>> _uploadingAttachments = [];
  bool _isUploading = false;
  bool _isListening = false;
  bool _isPinned = false;
  String _priority = NotePriority.none;
  String _priorityChoice = NotePriority.none;
  List<String> _groupMembers = [];
  bool _canManageGroupTasks = true;
  bool _hasUserChangedLabel = false;

  String _liveSpeechText = '';
  String _lastInsertedSpeech = '';
  String _titleTextColor = '';
  bool _titleIsBold = true;
  bool _titleIsItalic = false;
  bool _titleIsUnderlined = false;
  double _titleFontSize = 26.0;
  String _contentTextColor = '';
  bool _contentIsBold = false;
  bool _contentIsItalic = false;
  bool _contentIsUnderlined = false;
  double _contentFontSize = 17.0;

  late Color _selectedColor;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController = TextEditingController(
      text: widget.note?.content ?? '',
    );

    // Nếu là ghi chú cũ có rich text, cố gắng parse sang text thường
    if (widget.note?.isRichText == true && widget.note?.content != null) {
      try {
        final doc = quill.Document.fromJson(jsonDecode(widget.note!.content));
        _contentController.text = doc.toPlainText().trim();
      } catch (e) {
        debugPrint('Lỗi parse rich text: $e');
        // Giữ nguyên content thô nếu lỗi
      }
    }
    _customLabelController = TextEditingController();
    _customPriorityController = TextEditingController();
    _selectedColor = widget.note?.coverColor ?? AppState.noteColors.first;
    _titleController.addListener(() {
      if (mounted) setState(() {});
    });

    if (widget.note != null) {
      if (AppState.labels.contains(widget.note!.label)) {
        _selectedLabel = widget.note!.label;
      } else {
        _selectedLabel = AppState.otherLabel;
        _customLabelController.text = widget.note!.label;
      }
      _isTodo = widget.note!.isTodo;
      _todos = widget.note!.todos.map((todo) => todo.copyWith()).toList();
      _hasReminder = widget.note!.hasReminder;
      _selectedReminderTime = widget.note!.reminderTime;
      _attachments = List.from(widget.note!.attachments);
      _isPinned = widget.note!.isPinned;
      _priority = NotePriority.normalize(widget.note!.priority);
      _priorityChoice = NotePriority.choiceValue(_priority);
      _titleTextColor = widget.note!.titleTextColor;
      _titleIsBold = widget.note!.titleIsBold;
      _titleIsItalic = widget.note!.titleIsItalic;
      _titleIsUnderlined = widget.note!.titleIsUnderlined;
      _titleFontSize = widget.note!.titleFontSize;
      _contentTextColor = widget.note!.contentTextColor;
      _contentIsBold = widget.note!.contentIsBold;
      _contentIsItalic = widget.note!.contentIsItalic;
      _contentIsUnderlined = widget.note!.contentIsUnderlined;
      _contentFontSize = widget.note!.contentFontSize;
      if (_priorityChoice == NotePriority.custom) {
        _customPriorityController.text = _priority;
      }
    }
    if (_activeGroupId.isNotEmpty) {
      _canManageGroupTasks = false;
    }
    _loadGroupMembers();
  }

  @override
  void dispose() {
    _speech.stop();
    _titleController.dispose();
    _contentController.dispose();
    _customLabelController.dispose();
    _customPriorityController.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool success = true}) {
    SnackUtils.show(context, message, success: success);
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String content,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
  }

  Future<void> _applyAiMetadata() async {
    if (_titleController.text.isEmpty && _contentController.text.isEmpty) {
      return;
    }

    try {
      final metadata = await AIService.analyzeNoteMetadata(
        title: _titleController.text,
        content: _contentController.text,
      );

      setState(() {
        // Tự động gán nhãn nếu người dùng chưa đổi nhãn thủ công
        if (!_hasUserChangedLabel) {
          final label = metadata['label'];
          if (AppState.labels.contains(label)) {
            _selectedLabel = label;
            _customLabelController.clear();
          }
        }

        // Tự động gán độ ưu tiên nếu chưa có độ ưu tiên cao
        if (_priorityChoice == NotePriority.none ||
            _priorityChoice == NotePriority.custom) {
          final priority = metadata['priority'];
          if (priority != NotePriority.none) {
            _priority = priority;
            _priorityChoice = NotePriority.choiceValue(priority);
          }
        }

        // Tự động gán nhắc nhở nếu tìm thấy ngày tháng và chưa có nhắc nhở
        if (!_hasReminder && metadata['reminder'] != null) {
          _selectedReminderTime = metadata['reminder'];
          _hasReminder = true;
        }
      });
    } catch (e) {
      debugPrint('Lỗi phân tích AI metadata: $e');
    }
  }

  Color _resolvedTitleColor(ColorScheme colorScheme) {
    if (_titleTextColor.isEmpty) return colorScheme.onSurface;
    try {
      return Color(int.parse(_titleTextColor, radix: 16));
    } catch (_) {
      return colorScheme.onSurface;
    }
  }

  String _normalizeTodoTask(String task) {
    return task
        .toLowerCase()
        .replaceAll(RegExp("[.,:;!?\"'()\\[\\]-]+"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  int _appendSuggestedTodos(List<AiTodoSuggestion> suggestions) {
    if (_todos.length <= 1 && _todos.any((todo) => todo.task.trim().isEmpty)) {
      _todos.clear();
    }

    final existing = _todos
        .map((todo) => _normalizeTodoTask(todo.task))
        .where((task) => task.isNotEmpty)
        .toSet();

    var addedCount = 0;
    for (final suggestion in suggestions) {
      final task = suggestion.task.trim();
      final key = _normalizeTodoTask(task);
      if (task.isEmpty || key.isEmpty || existing.contains(key)) continue;

      existing.add(key);
      _todos.add(
        TodoItem(
          task: task,
          priority: suggestion.priority,
          deadline: suggestion.deadline != null
              ? DateTime.tryParse(suggestion.deadline!)
              : null,
        ),
      );
      addedCount++;
    }

    if (addedCount > 0) {
      _isTodo = true;
    }

    return addedCount;
  }

  String get _activeGroupId {
    final noteGroupId = widget.note?.groupId.trim() ?? '';
    if (noteGroupId.isNotEmpty) return noteGroupId;
    final initialGroupId = widget.initialGroupId?.trim() ?? '';
    if (initialGroupId.isNotEmpty) return initialGroupId;
    return FirebaseService.currentGroupId.trim();
  }

  bool get _usesGroupTaskMetadata => _activeGroupId.isNotEmpty;

  bool get isAdmin => AppState.currentUserRole.toLowerCase() == 'admin';

  bool get _isLimitedEditor {
    if (_activeGroupId.isEmpty) return false;

    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    final myUid = FirebaseService.currentUid;
    final creatorEmail = widget.note?.createdByEmail.toLowerCase().trim() ?? '';
    final isOwner = creatorEmail == myEmail ||
                    (widget.note?.userId.isNotEmpty == true && widget.note?.userId == myUid) ||
                    (widget.note == null);

    if (isOwner) return false;
    if (_canManageGroupTasks) return false;

    return true;
  }

  bool get _isGroupTaskLocked {
    return _isLimitedEditor;
  }

  bool _canEditTodoDefinition(int index) {
    if (widget.note == null) return true;
    if (isAdmin || _canManageGroupTasks) return true;
    if (_activeGroupId.isEmpty) return true;
    return false;
  }

  bool _canUpdateTodoStatusAndAttachments(int index) {
    if (widget.note == null) return true;
    if (isAdmin || _canManageGroupTasks) return true;
    if (_activeGroupId.isEmpty) return true;
    if (index < 0 || index >= _todos.length) return false;

    final todo = _todos[index];
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    final isAssignee = todo.assigneeEmail.toLowerCase().trim() == myEmail;

    return isAssignee;
  }


  Future<void> _loadGroupMembers() async {
    final groupId = _activeGroupId;
    if (groupId.isEmpty) return;
    final results = await Future.wait([
      FirebaseService.getGroupMemberEmails(groupId),
      FirebaseService.canCurrentUserManageGroupTasks(groupId),
    ]);
    if (!mounted) return;
    setState(() {
      _groupMembers = results[0] as List<String>;
      _canManageGroupTasks = results[1] as bool;
      if (!_canManageGroupTasks && widget.note == null) {
        _isTodo = false;
        _todos = [];
      }
    });
  }

  String _formatDate(DateTime date) {
    final dateStr =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    if (date.hour == 0 && date.minute == 0) return dateStr;
    return '$dateStr ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickTodoDeadline(int index) async {
    final current = _todos[index].deadline ?? DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );

    if (pickedTime == null) return;

    setState(() {
      _todos[index] = _todos[index].copyWith(
        deadline: DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        ),
      );
    });
  }

  Future<void> _pickReminderTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedReminderTime ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );

    if (pickedDate == null || !mounted) {
      setState(() => _hasReminder = false);
      return;
    }

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _selectedReminderTime ?? DateTime.now(),
      ),
    );

    if (pickedTime == null) {
      setState(() => _hasReminder = false);
      return;
    }

    setState(() {
      _selectedReminderTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
      _hasReminder = true;
    });
  }

  Future<void> _suggestContentOnly() async {
    if (_titleController.text.isEmpty) {
      _showSnack('Nhập tiêu đề trước để AI gợi ý nội dung.');
      return;
    }

    // Xác nhận nếu đã có nội dung
    if (_contentController.text.trim().isNotEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ghi đè nội dung?'),
          content: const Text(
            'Bạn đang có nội dung trong ghi chú. Bạn muốn ghi đè bằng gợi ý của AI hay nối thêm vào cuối?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, null), // Append
              child: const Text('Nối thêm'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true), // Overwrite
              child: const Text('Ghi đè'),
            ),
          ],
        ),
      );

      if (confirm == false) return; // User cancelled

      setState(() => _isUploading = true);
      try {
        final suggestedContent = await AIService.suggestNoteContent(
          noteTitle: _titleController.text,
        );
        if (suggestedContent.isNotEmpty) {
          setState(() {
            if (confirm == true) {
              _contentController.text = suggestedContent;
            } else {
              // Append logic
              final current = _contentController.text.trim();
              _contentController.text =
                  '$current\n\n--- Gợi ý từ AI ---\n$suggestedContent';
            }
          });
          _applyAiMetadata();
          _showSnack('AI đã cập nhật nội dung!');
        }
      } catch (e) {
        _showSnack('Lỗi AI: $e', success: false);
      } finally {
        if (mounted) setState(() => _isUploading = false);
      }
      return;
    }

    // Default logic for empty content
    setState(() => _isUploading = true);
    try {
      final suggestedContent = await AIService.suggestNoteContent(
        noteTitle: _titleController.text,
      );
      if (suggestedContent.isNotEmpty) {
        setState(() => _contentController.text = suggestedContent);
        _applyAiMetadata();
        _showSnack('AI đã đề xuất nội dung!');
      }
    } catch (e) {
      _showSnack('Lỗi AI: $e', success: false);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _suggestTodosOnly() async {
    if (_titleController.text.isEmpty && _contentController.text.isEmpty) {
      _showSnack('Nhập tiêu đề hoặc nội dung trước để AI gợi ý todo.');
      return;
    }
    setState(() => _isUploading = true);
    try {
      final suggestions = await AIService.suggestTodosFromNote(
        noteTitle: _titleController.text,
        noteContent: _contentController.text,
      );

      if (suggestions.isNotEmpty) {
        setState(() {
          _appendSuggestedTodos(suggestions);
          _isTodo = true;
        });
        _applyAiMetadata(); // Tự động điền nhãn, ưu tiên, nhắc nhở
        _showSnack('AI đã thêm ${suggestions.length} công việc!');
      } else {
        _showSnack('AI không tìm thấy công việc phù hợp.', success: false);
      }
    } catch (e) {
      _showSnack('Lỗi AI: $e', success: false);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _saveNote() async {
    if (_uploadingAttachments.isNotEmpty) {
      _showSnack('Vui lòng đợi các tệp tải lên hoàn tất trước khi lưu.', success: false);
      return;
    }
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    final inferredLabel = (!_hasUserChangedLabel && widget.note == null)
        ? AIService.suggestLabel(
            title,
            content,
            isTodo: _isTodo || _todos.isNotEmpty,
          )
        : _selectedLabel;
    final label = inferredLabel == AppState.otherLabel
        ? _customLabelController.text.trim()
        : inferredLabel;
    final priority = _priorityChoice == NotePriority.custom
        ? _customPriorityController.text.trim()
        : _priorityChoice;
    final rawTodos = _todos
        .where((todo) => todo.task.trim().isNotEmpty)
        .map(
          (todo) => todo.copyWith(
            task: todo.task.trim(),
            status: todo.isDone ? TodoStatus.done : todo.status,
          ),
        )
        .toList();
    final cleanTodos = rawTodos.map((todo) {
      if (_usesGroupTaskMetadata) return todo;
      return todo.copyWith(
        status: todo.isDone ? TodoStatus.done : TodoStatus.todo,
      );
    }).toList();

    if (title.isEmpty) {
      _showSnack('Vui lòng nhập tiêu đề');
      return;
    }

    if (label.isEmpty) {
      _showSnack('Vui lòng nhập nhãn ghi chú');
      return;
    }

    if (_priorityChoice == NotePriority.custom && priority.isEmpty) {
      _showSnack('Vui lòng nhập mức độ ưu tiên');
      return;
    }

    if (_isTodo && cleanTodos.isEmpty) {
      _showSnack('Vui lòng thêm ít nhất một công việc');
      return;
    }

    final noteData = widget.note != null
        ? widget.note!.copyWith(
            title: title,
            content: content,
            titleTextColor: _titleTextColor,
            titleIsBold: _titleIsBold,
            titleIsItalic: _titleIsItalic,
            titleIsUnderlined: _titleIsUnderlined,
            titleFontSize: _titleFontSize,
            label: label,
            isTodo: _isTodo,
            todos: cleanTodos,
            sharedWith: widget.note!.sharedWith,
            coverColor: _selectedColor,
            hasReminder: _hasReminder,
            reminderTime: _hasReminder ? _selectedReminderTime : null,
            attachments: _attachments,
            isPinned: _isPinned,
            priority: priority.isEmpty ? NotePriority.none : priority,
          )
        : Note(
            id: '',
            title: title,
            content: content,
            titleTextColor: _titleTextColor,
            titleIsBold: _titleIsBold,
            titleIsItalic: _titleIsItalic,
            titleIsUnderlined: _titleIsUnderlined,
            titleFontSize: _titleFontSize,
            label: label,
            date: DateTime.now().toString().substring(0, 10),
            isTodo: _isTodo,
            todos: cleanTodos,
            sharedWith: const [],
            coverColor: _selectedColor,
            hasReminder: _hasReminder,
            reminderTime: _hasReminder ? _selectedReminderTime : null,
            attachments: _attachments,
            isPinned: _isPinned,
            priority: priority.isEmpty ? NotePriority.none : priority,
            createdByEmail: AppState.currentUserEmail.toLowerCase().trim(),
            createdByName: AppState.currentUserName,
            groupId: _activeGroupId,
            isRichText: false,
            userId: FirebaseService.currentUid,
          );

    final navigator = Navigator.of(context);

    try {
      late final String savedNoteId;
      if (widget.note == null) {
        savedNoteId = await FirebaseService.addNote(noteData);
        if (savedNoteId.isEmpty) {
          throw Exception('Không thể tạo ghi chú mới.');
        }
        _showSnack('Đã tạo ghi chú mới!');
      } else {
        await FirebaseService.updateNote(widget.note!.id, noteData);
        savedNoteId = widget.note!.id;
        _showSnack('Đã cập nhật thay đổi!');
      }

      await NotificationService.syncNoteReminder(
        noteId: savedNoteId,
        title: 'SNote nhắc nhở: $title',
        body: content.isNotEmpty ? content : 'Đến giờ thực hiện công việc rồi!',
        scheduledTime: _hasReminder ? _selectedReminderTime : null,
        todos: _todos,
      );

      if (mounted) navigator.pop();
    } catch (e) {
      _showSnack('Lỗi khi lưu: $e', success: false);
    }
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
    setState(() {
      if (_isTodo) {
        _todos.add(TodoItem(task: cleanText));
      } else {
        if (_contentController.text.trim().isNotEmpty) {
          _contentController.text += '\n';
        }
        _contentController.text += cleanText;
      }
      _liveSpeechText = '';
    });
  }

  Future<bool> _requestGalleryPermission() async {
    if (Platform.isIOS) {
      final status = await Permission.photos.request();
      return status.isGranted || status.isLimited;
    }
    // Android 13+ (SDK 33+)
    if (await Permission.photos.status.isGranted) return true;
    final result = await Permission.photos.request();
    if (result.isGranted) return true;
    // Fallback Android < 13
    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  void _showImageSourceSheet({int? todoIndex}) {
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
                _pickImageAttachment(ImageSource.camera, todoIndex: todoIndex);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Chọn ảnh từ thư viện'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickImageAttachment(ImageSource.gallery, todoIndex: todoIndex);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImageAttachment(
    ImageSource source, {
    int? todoIndex,
  }) async {
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

    final picker = ImagePicker();
    if (source == ImageSource.gallery) {
      var images = await picker.pickMultiImage(
        imageQuality: 30,
        maxWidth: 512,
      );
      if (images.isNotEmpty) {
        if (images.length > 15) {
          _showSnack('Chỉ được chọn tối đa 15 ảnh mỗi lần. Đã lấy 15 ảnh đầu tiên.', success: false);
          images = images.sublist(0, 15);
        }
        for (final img in images) {
          final file = File(img.path);
          final fileSize = await file.length();
          if (fileSize <= FirebaseService.maxAttachmentBytes) {
            final name = img.name.isNotEmpty ? img.name : 'image.jpg';
            _uploadAttachmentFile(file, name, fileSize, todoIndex: todoIndex);
          } else {
            _showSnack('Ảnh ${img.name} quá lớn (>30MB).', success: false);
          }
        }
      }
    } else {
      final image = await picker.pickImage(
        source: source,
        imageQuality: 30,
        maxWidth: 512,
      );
      if (image == null) return;

      final file = File(image.path);
      final fileSize = await file.length();
      if (fileSize > FirebaseService.maxAttachmentBytes) {
        _showSnack('Ảnh quá lớn (>30MB).', success: false);
        return;
      }

      final name = image.name.isNotEmpty ? image.name : 'image.jpg';
      _uploadAttachmentFile(file, name, fileSize, todoIndex: todoIndex);
    }
  }

  Future<void> _pickFileAttachment() async {
    try {
      if (Platform.isAndroid) {
        final storageStatus = await Permission.storage.request();
        if (!storageStatus.isGranted) {
          // Xử lý quyền nếu cần, nhưng FilePicker thường vẫn mở được
        }
      }

      final result = await FilePicker.pickFiles(withData: false, allowMultiple: true);
      if (result == null || result.files.isEmpty) return;

      for (final file in result.files) {
        final path = file.path;
        if (path == null || path.isEmpty) {
          _showSnack('Không đọc được đường dẫn tệp.', success: false);
          continue;
        }

        final selectedFile = File(path);
        if (!await selectedFile.exists()) {
          _showSnack('Tệp không tồn tại.', success: false);
          continue;
        }

        final size = file.size > 0 ? file.size : await selectedFile.length();
        if (size > FirebaseService.maxAttachmentBytes) {
          _showSnack(
            'Tệp ${file.name} vượt quá 30MB. Vui lòng chọn tệp nhỏ hơn.',
            success: false,
          );
          continue;
        }

        _uploadAttachmentFile(selectedFile, file.name, size);
      }
    } catch (e) {
      _showSnack('Lỗi chọn tệp: $e', success: false);
    }
  }

  Future<void> _pickTodoFile(int index) async {
    try {
      final result = await FilePicker.pickFiles(withData: false, allowMultiple: true);
      if (result == null || result.files.isEmpty) return;

      for (final file in result.files) {
        final path = file.path;
        if (path == null || path.isEmpty) {
          _showSnack('Không đọc được đường dẫn tệp.', success: false);
          continue;
        }

        final selectedFile = File(path);
        if (!await selectedFile.exists()) {
          _showSnack(
            'Tệp không tồn tại hoặc không truy cập được.',
            success: false,
          );
          continue;
        }

        final size = file.size > 0 ? file.size : await selectedFile.length();
        if (size > FirebaseService.maxAttachmentBytes) {
          _showSnack(
            'Tệp ${file.name} vượt quá 30MB. Vui lòng chọn tệp nhỏ hơn.',
            success: false,
          );
          continue;
        }

        _uploadAttachmentFile(
          selectedFile,
          file.name,
          size,
          todoIndex: index,
        );
      }
    } catch (e) {
      _showSnack('Lỗi chọn tệp: $e', success: false);
    }
  }

  Future<void> _uploadAttachmentFile(
    File file,
    String fileName,
    int fileSize, {
    int? todoIndex,
  }) async {
    if (fileSize > FirebaseService.maxAttachmentBytes) {
      _showSnack(
        'Tệp vượt quá 30MB. Vui lòng chọn tệp nhỏ hơn.',
        success: false,
      );
      return;
    }

    final uploadId = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
    final uploadItem = {
      'id': uploadId,
      'name': fileName,
      'todoIndex': todoIndex,
    };

    setState(() {
      _uploadingAttachments.add(uploadItem);
    });

    try {
      final url = await FirebaseService.uploadAttachmentFile(
        file,
        fileName,
        fileSize: fileSize,
      );
      if (!mounted) return;

      bool wasCancelled = true;
      setState(() {
        wasCancelled = !_uploadingAttachments.any((item) => item['id'] == uploadId);
        _uploadingAttachments.removeWhere((item) => item['id'] == uploadId);
        if (!wasCancelled) {
          if (todoIndex != null) {
            if (todoIndex >= 0 && todoIndex < _todos.length) {
              _todos[todoIndex].attachments.add(url);
            }
          } else {
            _attachments.add(url);
          }
        }
      });
      if (!wasCancelled) {
        _showSnack('Đã đính kèm tệp.');
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() {
          _uploadingAttachments.removeWhere((item) => item['id'] == uploadId);
        });
        _showSnack('Lỗi Storage (${e.code}): ${e.message}', success: false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploadingAttachments.removeWhere((item) => item['id'] == uploadId);
        });
        _showSnack('Lỗi đính kèm: $e', success: false);
      }
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

  void _showImagePreview(List<String> imagesOnly, int initialIndex) {
    if (imagesOnly.length > 1) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ImageGridPreviewScreen(
            images: imagesOnly,
            initialIndex: initialIndex,
          ),
        ),
      );
      return;
    }
    final List<ImageProvider> providers = [];
    for (final value in imagesOnly) {
      final bytes = bytesFromDataUri(value);
      if (bytes != null) {
        providers.add(MemoryImage(bytes));
      } else {
        providers.add(CachedNetworkImageProvider(value));
      }
    }
    if (providers.isEmpty) return;

    showImageViewerPager(
      context,
      MultiImageProvider(providers, initialIndex: initialIndex),
      swipeDismissible: true,
      doubleTapZoomable: true,
    );
  }

  Widget _buildGroupContextCard(ColorScheme colorScheme) {
    if (!_usesGroupTaskMetadata) return const SizedBox.shrink();

    final accent = _isGroupTaskLocked ? Colors.orange : colorScheme.primary;
    final background = _isGroupTaskLocked
        ? Colors.orange.withValues(alpha: 0.10)
        : colorScheme.primaryContainer.withValues(alpha: 0.55);
    final message = _isGroupTaskLocked
        ? 'Bạn có thể chỉnh nội dung ghi chú, nhưng chỉ trưởng nhóm mới được tạo và giao task trong nhóm.'
        : 'Ghi chú này đang ở trong nhóm. Hãy giao người phụ trách và hạn chót thật rõ để mọi người theo dõi dễ hơn.';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.groups_2_outlined, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ghi chú trong nhóm',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodoToggle(ColorScheme colorScheme) {
    return InkWell(
      onTap: () => setState(() => _isTodo = !_isTodo),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _isTodo
              ? colorScheme.primaryContainer.withValues(alpha: 0.3)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isTodo ? colorScheme.primary : colorScheme.outlineVariant,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'Chế độ danh sách công việc',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: _isTodo
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Switch(
              value: _isTodo,
              onChanged: _isLimitedEditor
                  ? null
                  : (val) => setState(() => _isTodo = val),
              activeThumbColor: colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabelDropdown(ColorScheme colorScheme, Color subtleFill) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: subtleFill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedLabel,
          icon: const Icon(Icons.arrow_drop_down, size: 20),
          isDense: true,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          items: AppState.labels
              .map((l) => DropdownMenuItem(value: l, child: Text(l)))
              .toList(),
          onChanged: _isLimitedEditor
              ? null
              : (val) => setState(() {
                  _hasUserChangedLabel = true;
                  _selectedLabel = val!;
                  if (_selectedLabel != AppState.otherLabel) {
                    _customLabelController.clear();
                  }
                }),
        ),
      ),
    );
  }

  Widget _buildPriorityChip(ColorScheme colorScheme, Color subtleFill) {
    return ActionChip(
      avatar: Icon(Icons.flag_outlined, size: 16, color: colorScheme.primary),
      label: Text(NotePriority.label(_priorityChoice)),
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      backgroundColor: subtleFill,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onPressed: _isLimitedEditor
          ? null
          : () {
              showModalBottomSheet(
                context: context,
                showDragHandle: true,
                builder: (context) => ListView(
                  shrinkWrap: true,
                  children: NotePriority.values
                      .map(
                        (p) => ListTile(
                          leading: const Icon(Icons.flag_outlined),
                          title: Text(NotePriority.label(p)),
                          selected: _priorityChoice == p,
                          onTap: () {
                            setState(() {
                              _priorityChoice = p;
                              _priority = p;
                            });
                            Navigator.pop(context);
                          },
                        ),
                      )
                      .toList(),
                ),
              );
            },
    );
  }

  Widget _buildReminderChip(ColorScheme colorScheme, Color subtleFill) {
    final reminderText = _selectedReminderTime == null
        ? 'Nhắc nhở'
        : '${_selectedReminderTime!.hour.toString().padLeft(2, '0')}:${_selectedReminderTime!.minute.toString().padLeft(2, '0')}';

    return ActionChip(
      avatar: Icon(
        _hasReminder ? Icons.alarm_on : Icons.alarm_add_outlined,
        size: 16,
        color: _hasReminder ? Colors.green : colorScheme.primary,
      ),
      label: Text(reminderText),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: _hasReminder ? Colors.green : null,
      ),
      backgroundColor: subtleFill,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onPressed: _isLimitedEditor
          ? null
          : () {
              if (_hasReminder) {
                setState(() {
                  _hasReminder = false;
                  _selectedReminderTime = null;
                });
              } else {
                _pickReminderTime();
              }
            },
    );
  }

  Widget _buildAttachmentChips() {
    final noteUploading = _uploadingAttachments.where((item) => item['todoIndex'] == null).toList();
    if (_attachments.isEmpty && noteUploading.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 48,
      margin: const EdgeInsets.only(bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const SizedBox(width: 12),
            for (var i = 0; i < _attachments.length; i++) ...[
              InputChip(
                label: Text(attachmentLabel(_attachments[i], i), style: const TextStyle(fontSize: 12)),
                onDeleted: () => setState(() => _attachments.removeAt(i)),
                deleteIcon: const Icon(Icons.close, size: 14),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                onPressed: () {
                  if (isImageValue(_attachments[i])) {
                    _showImagePreview([_attachments[i]], 0);
                  } else {
                    _openAttachment(_attachments[i], i);
                  }
                },
              ),
              const SizedBox(width: 8),
            ],
            for (var item in noteUploading) ...[
              Chip(
                avatar: const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
                label: Text(
                  item['name'] as String,
                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
                onDeleted: () {
                  setState(() {
                    _uploadingAttachments.removeWhere((x) => x['id'] == item['id']);
                  });
                },
                deleteIcon: const Icon(Icons.close, size: 14),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  InputDecoration _taskFieldDecoration(String hint, ColorScheme colorScheme) {
    return InputDecoration(
      hintText: hint,
      filled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.2),
      ),
    );
  }

  void _showTemplateSheet() {
    final templates = [
      _NoteTemplate(
        title: 'Họp nhóm',
        label: 'Công việc',
        content:
            'Mục tiêu cuộc họp:\n\nNội dung chính:\n- \n\nQuyết định:\n- \n\nViệc cần làm:',
        todos: const [
          'Gửi biên bản họp',
          'Chốt người phụ trách',
          'Theo dõi deadline',
        ],
      ),
      _NoteTemplate(
        title: 'Kế hoạch học tập',
        label: 'Học tập',
        content:
            'Môn học:\nMục tiêu tuần này:\n\nTài liệu cần đọc:\n- \n\nGhi chú:',
        todos: const ['Ôn lý thuyết', 'Làm bài tập', 'Tổng hợp câu hỏi'],
      ),
      _NoteTemplate(
        title: 'Báo cáo đồ án',
        label: 'Học tập',
        content:
            'Tên đồ án:\nThành viên:\n\nTiến độ hiện tại:\n\nPhần đã hoàn thành:\n- \n\nVấn đề còn lại:',
      ),
      _NoteTemplate(
        title: 'Danh sách mua sắm',
        label: 'Cá nhân',
        isTodo: true,
        todos: const [
          'Mua vật dụng cần thiết',
          'Kiểm tra ngân sách',
          'Lưu hóa đơn',
        ],
      ),
      _NoteTemplate(
        title: 'Bug report',
        label: 'Công việc',
        content:
            'Mô tả lỗi:\n\nCác bước tái hiện:\n1. \n2. \n3. \n\nKết quả mong muốn:\n\nKết quả thực tế:\n\nThiết bị/Phiên bản:',
        todos: const ['Xác minh lỗi', 'Gán người xử lý', 'Kiểm thử lại'],
      ),
    ];

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemBuilder: (context, index) {
          final template = templates[index];
          return ListTile(
            leading: Icon(template.isTodo ? Icons.checklist : Icons.article),
            title: Text(template.title),
            subtitle: Text(template.isTodo ? 'Công việc' : template.label),
            onTap: () {
              Navigator.pop(context);
              setState(() {
                _hasUserChangedLabel = true;
                _titleController.text = template.title;
                _contentController.text = template.content;
                _selectedLabel = AppState.labels.contains(template.label)
                    ? template.label
                    : AppState.labels.first;
                _isTodo = template.isTodo || template.todos.isNotEmpty;
                _todos = template.todos
                    .map((task) => TodoItem(task: task))
                    .toList();
              });
            },
          );
        },
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemCount: templates.length,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subtleFill = colorScheme.surfaceContainerHighest.withValues(
      alpha: Theme.of(context).brightness == Brightness.dark ? 0.48 : 1,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.note == null ? 'Tạo ghi chú' : 'Sửa ghi chú',
          style: const TextStyle(fontSize: 18),
        ),
        actions: [
          if (!_isLimitedEditor) ...[
            IconButton(
              icon: const Icon(Icons.post_add_outlined),
              tooltip: 'Mẫu ghi chú',
              onPressed: _showTemplateSheet,
            ),
            PopupMenuButton<int>(
              icon: Icon(Icons.electric_bolt, color: colorScheme.tertiary),
              tooltip: 'Hỗ trợ AI',
              onSelected: (value) {
                if (value == 1) _suggestContentOnly();
                if (value == 2) _suggestTodosOnly();
                if (value == 3) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AIChatNoteScreen(
                        noteTitle: _titleController.text,
                        noteContent: _contentController.text,
                        onTodosAccepted: (suggestions) {
                          setState(() {
                            _appendSuggestedTodos(suggestions);
                          });
                          return suggestions.length;
                        },
                      ),
                    ),
                  );
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 1,
                  child: Row(
                    children: [
                      Icon(Icons.description_outlined, size: 20),
                      SizedBox(width: 10),
                      Text('Đề xuất nội dung'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 2,
                  child: Row(
                    children: [
                      Icon(Icons.checklist_rtl_rounded, size: 20),
                      SizedBox(width: 10),
                      Text('Đề xuất công việc'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 3,
                  child: Row(
                    children: [
                      Icon(Icons.chat_bubble_outline_rounded, size: 20),
                      SizedBox(width: 10),
                      Text('Trò chuyện với AI'),
                    ],
                  ),
                ),
              ],
            ),

          ],
          if (!_isLimitedEditor)
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Lưu',
              onPressed: _saveNote,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                children: [
                  _buildSectionHeader(
                    icon: Icons.tune_rounded,
                    title: 'Thông tin ghi chú',
                    subtitle: 'Màu, tiêu đề, nhãn, mức ưu tiên và nhắc hẹn',
                  ),
                  const SizedBox(height: 12),

                  // Color Picker
                  SizedBox(
                    height: 36,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: AppState.noteColors.length,
                      itemBuilder: (ctx, i) => GestureDetector(
                        onTap: _isLimitedEditor
                            ? null
                            : () => setState(
                                () => _selectedColor = AppState.noteColors[i],
                              ),
                        child: Container(
                          width: 32,
                          height: 32,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            color: AppState.noteColors[i],
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _selectedColor == AppState.noteColors[i]
                                  ? colorScheme.primary
                                  : colorScheme.outlineVariant,
                              width: _selectedColor == AppState.noteColors[i]
                                  ? 2
                                  : 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (_isLimitedEditor)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(
                          alpha: 0.15,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Bạn đang ở chế độ đóng góp: Có thể thêm file/ảnh nhưng không thể sửa nội dung chính.',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Title Field
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _titleController,
                          readOnly: _isLimitedEditor,
                          maxLength: 100,
                          minLines: 1,
                          maxLines: 3,
                          style: TextStyle(
                            fontSize: _titleFontSize,
                            fontWeight: _titleIsBold
                                ? FontWeight.bold
                                : FontWeight.w600,
                            fontStyle: _titleIsItalic
                                ? FontStyle.italic
                                : FontStyle.normal,
                            decoration: null,
                            color: _resolvedTitleColor(colorScheme),
                            height: 1.2,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Tiêu đề',
                            counterText: '',
                            hintStyle: TextStyle(color: colorScheme.outline),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          Icons.format_paint_outlined,
                          color: _isLimitedEditor
                              ? colorScheme.outline
                              : colorScheme.primary.withValues(alpha: 0.75),
                        ),
                        onPressed: _isLimitedEditor
                            ? null
                            : _showTitleFormattingSheet,
                        tooltip: 'Định dạng tiêu đề',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Meta Info Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildLabelDropdown(colorScheme, subtleFill),
                        const SizedBox(width: 8),
                        _buildPriorityChip(colorScheme, subtleFill),
                        const SizedBox(width: 8),
                        _buildReminderChip(colorScheme, subtleFill),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildTodoToggle(colorScheme),

                  if (_selectedLabel == AppState.otherLabel) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _customLabelController,
                      readOnly: _isLimitedEditor,
                      decoration: InputDecoration(
                        hintText: 'Nhãn tùy chỉnh...',
                        isDense: true,
                        filled: true,
                        fillColor: subtleFill,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],

                  if (_usesGroupTaskMetadata) ...[
                    const SizedBox(height: 16),
                    _buildGroupContextCard(colorScheme),
                  ],

                  const SizedBox(height: 24),
                  _buildSectionHeader(
                    icon: _isTodo
                        ? Icons.checklist_rounded
                        : Icons.notes_rounded,
                    title: _isTodo ? 'Công việc cần làm' : 'Nội dung',
                    subtitle: _isTodo
                        ? 'Theo dõi từng việc, người phụ trách và tệp liên quan'
                        : 'Soạn nội dung chính của ghi chú',
                  ),
                  const SizedBox(height: 12),
                  _isTodo ? _buildTodoList() : _buildTextContent(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.08),
              offset: const Offset(0, -2),
              blurRadius: 10,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildAttachmentChips(),
            if (_liveSpeechText.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _liveSpeechText,
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.image_outlined),
                      tooltip: 'Thêm ảnh',
                      onPressed: (_isUploading || _isLimitedEditor)
                          ? null
                          : () => _showImageSourceSheet(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.attach_file_rounded),
                      tooltip: 'Đính kèm tệp',
                      onPressed: (_isUploading || _isLimitedEditor)
                          ? null
                          : () => _pickFileAttachment(),
                    ),
                    IconButton(
                      icon: Icon(
                        _isListening
                            ? Icons.stop_circle
                            : Icons.mic_none_rounded,
                      ),
                      color: _isListening ? colorScheme.error : null,
                      tooltip: 'Nhập giọng nói',
                      onPressed: _isLimitedEditor ? null : _toggleVoiceInput,
                    ),
                    const Spacer(),
                    if (_isUploading)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.52),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 19, color: colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextContent() {
    final colorScheme = Theme.of(context).colorScheme;
    final contentColor =
        widget.note?.resolvedContentColor ??
        (_contentTextColor.isNotEmpty
            ? Color(int.parse(_contentTextColor, radix: 16))
            : colorScheme.onSurface);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: Icon(
                  Icons.format_size,
                  size: 20,
                  color: _isLimitedEditor ? colorScheme.outline : null,
                ),
                onPressed: _isLimitedEditor
                    ? null
                    : () => _showContentStyleSheet(),
                tooltip: 'Định dạng nội dung',
              ),
            ],
          ),
          TextField(
            controller: _contentController,
            readOnly: _isLimitedEditor,
            maxLength: 10000,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            style: TextStyle(
              fontSize: _contentFontSize,
              height: 1.7,
              fontWeight: _contentIsBold ? FontWeight.bold : FontWeight.normal,
              fontStyle: _contentIsItalic ? FontStyle.italic : FontStyle.normal,
              decoration: _contentIsUnderlined
                  ? TextDecoration.underline
                  : null,
              color: contentColor,
            ),
            decoration: const InputDecoration(
              hintText: 'Bắt đầu nhập nội dung ghi chú...',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.zero,
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodoList() {
    final colorScheme = Theme.of(context).colorScheme;
    final mutedText = colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < _todos.length; index++)
          _usesGroupTaskMetadata
              ? _buildDetailedTodoItem(index, colorScheme, mutedText)
              : _buildSimpleTodoItem(index, colorScheme, mutedText),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: _isGroupTaskLocked
                ? null
                : () => setState(() => _todos.add(TodoItem(task: ''))),
            icon: const Icon(Icons.add_rounded),
            label: const Text(
              'Thêm mục công việc',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              side: BorderSide(color: colorScheme.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSimpleTodoItem(
    int index,
    ColorScheme colorScheme,
    Color mutedText,
  ) {
    final isDone = _todos[index].isDone;
    final hasUpdatePerm = _canUpdateTodoStatusAndAttachments(index);
    final hasEditPerm = _canEditTodoDefinition(index);
    return Opacity(
      opacity: (hasUpdatePerm || hasEditPerm) ? 1.0 : 0.5,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: isDone,
                  activeColor: colorScheme.primary,
                  onChanged: !hasUpdatePerm
                      ? null
                      : (val) {
                          final newVal = val ?? false;
                          HapticFeedback.lightImpact();
                          setState(() {
                            _todos[index] = _todos[index].copyWith(
                              isDone: newVal,
                              markCompletedNow: newVal,
                              clearCompletedAt: !newVal,
                              status: newVal
                                  ? TodoStatus.done
                                  : TodoStatus.todo,
                            );
                          });
                        },
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextFormField(
                    key: ValueKey('todo_simple_$index'),
                    initialValue: _todos[index].task,
                    enabled: hasEditPerm,
                    maxLines: null,
                    onChanged: (val) => _todos[index].task = val,
                    style: TextStyle(
                      fontSize: _todos[index].fontSize,
                      fontWeight: _todos[index].isBold
                          ? FontWeight.bold
                          : FontWeight.w600,
                      fontStyle: _todos[index].isItalic
                          ? FontStyle.italic
                          : FontStyle.normal,
                      decoration: isDone
                          ? TextDecoration.lineThrough
                          : null,
                      color: isDone
                          ? mutedText
                          : (_todos[index].textColor.isNotEmpty
                                ? Color(
                                    int.parse(
                                      _todos[index].textColor,
                                      radix: 16,
                                    ),
                                  ).withValues(alpha: 1.0)
                                : colorScheme.onSurface),
                    ),
                    textCapitalization: _todos[index].isUppercase
                        ? TextCapitalization.characters
                        : TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Tên công việc...',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.format_paint_outlined,
                    color: colorScheme.primary.withValues(alpha: 0.7),
                    size: 20,
                  ),
                  onPressed: !hasEditPerm
                      ? null
                      : () => _showTodoFormattingSheet(index),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Định dạng',
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: mutedText, size: 20),
                  onPressed: !hasEditPerm
                      ? null
                      : () async {
                          final confirm = await _showConfirmDialog(
                            title: 'Xóa công việc?',
                            content:
                                'Bạn có chắc chắn muốn xóa công việc này không?',
                          );
                          if (confirm == true) {
                            setState(() => _todos.removeAt(index));
                          }
                        },
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailedTodoItem(
    int index,
    ColorScheme colorScheme,
    Color mutedText,
  ) {
    final hasEditPerm = _canEditTodoDefinition(index);
    final hasUpdatePerm = _canUpdateTodoStatusAndAttachments(index);

    return Opacity(
      opacity: (hasEditPerm || hasUpdatePerm) ? 1.0 : 0.5,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _todos[index].isDone,
                  onChanged: !hasUpdatePerm
                      ? null
                      : (val) {
                          HapticFeedback.lightImpact();
                          final isDone = val ?? false;
                          setState(() {
                            _todos[index] = _todos[index].copyWith(
                              isDone: isDone,
                              markCompletedNow: isDone,
                              clearCompletedAt: !isDone,
                              status: isDone
                                  ? TodoStatus.done
                                  : TodoStatus.todo,
                            );
                          });
                        },
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextFormField(
                    key: ValueKey('todo_$index'),
                    initialValue: _todos[index].task,
                    enabled: hasEditPerm,
                    maxLines: null, // Auto-expand
                    onChanged: (val) => _todos[index].task = val,
                    style: TextStyle(
                      fontSize: _todos[index].fontSize,
                      fontWeight: _todos[index].isBold
                          ? FontWeight.bold
                          : FontWeight.w600,
                      fontStyle: _todos[index].isItalic
                          ? FontStyle.italic
                          : FontStyle.normal,
                      decoration: _todos[index].isDone
                          ? TextDecoration.lineThrough
                          : null,
                      color: _todos[index].isDone
                          ? mutedText
                          : (_todos[index].textColor.isNotEmpty
                                ? Color(
                                    int.parse(
                                      _todos[index].textColor,
                                      radix: 16,
                                    ),
                                  ).withValues(alpha: 1.0)
                                : colorScheme.onSurface),
                    ),
                    textCapitalization: _todos[index].isUppercase
                        ? TextCapitalization.characters
                        : TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Nhập công việc',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.format_paint_outlined,
                    color: colorScheme.primary.withValues(alpha: 0.7),
                    size: 20,
                  ),
                  onPressed: !hasEditPerm
                      ? null
                      : () => _showTodoFormattingSheet(index),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Định dạng',
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: mutedText, size: 20),
                  onPressed: !hasEditPerm
                      ? null
                      : () async {
                          final confirm = await _showConfirmDialog(
                            title: 'Xóa công việc?',
                            content:
                                'Bạn có chắc chắn muốn xóa công việc này không?',
                          );
                          if (confirm == true) {
                            setState(() => _todos.removeAt(index));
                          }
                        },
                  visualDensity: VisualDensity.compact,
                  splashRadius: 18,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildTodoMetaField(
                    label: 'Người phụ trách',
                    child: _buildAssigneeField(index),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildTodoMetaField(
                    label: 'Trạng thái',
                    child: _buildStatusField(index),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: !hasEditPerm
                      ? null
                      : () => _pickTodoDeadline(index),
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text(
                    _todos[index].deadline == null
                        ? 'Chọn deadline'
                        : _formatDate(_todos[index].deadline!),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                if (_todos[index].deadline != null)
                  IconButton(
                    tooltip: 'Xóa deadline',
                    onPressed: !hasEditPerm
                        ? null
                        : () {
                            setState(() {
                              _todos[index] = _todos[index].copyWith(
                                clearDeadline: true,
                              );
                            });
                          },
                    icon: const Icon(Icons.event_busy_outlined),
                    visualDensity: VisualDensity.compact,
                  ),
                IconButton(
                  icon: const Icon(Icons.image_outlined, size: 20),
                  onPressed: !hasUpdatePerm
                      ? null
                      : () => _showImageSourceSheet(todoIndex: index),
                  tooltip: 'Thêm ảnh cho task',
                ),
                IconButton(
                  icon: const Icon(Icons.attach_file_rounded, size: 20),
                  onPressed: !hasUpdatePerm
                      ? null
                      : () => _pickTodoFile(index),
                  tooltip: 'Đính kèm tệp cho task',
                ),
              ],
            ),
            if (_todos[index].attachments.isNotEmpty || _uploadingAttachments.any((item) => item['todoIndex'] == index)) ...[
              const SizedBox(height: 8),
              _buildTodoAttachments(index),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTodoAttachments(int index) {
    final todo = _todos[index];
    final colorScheme = Theme.of(context).colorScheme;
    final todoUploading = _uploadingAttachments.where((item) => item['todoIndex'] == index).toList();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ...todo.attachments.map((url) {
          final fileName = attachmentLabel(url, todo.attachments.indexOf(url));
          final isImage = isImageValue(url);

          return InkWell(
            onTap: () {
              if (isImage) {
                _showImagePreview([url], 0);
              } else {
                _openAttachment(url, todo.attachments.indexOf(url));
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isImage
                        ? Icons.image_outlined
                        : Icons.insert_drive_file_outlined,
                    size: 14,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      fileName,
                      style: const TextStyle(fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: !_canUpdateTodoStatusAndAttachments(index)
                        ? null
                        : () => setState(() => todo.attachments.remove(url)),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: colorScheme.error.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        ...todoUploading.map((item) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.2),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    item['name'] as String,
                    style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _uploadingAttachments.removeWhere((x) => x['id'] == item['id']);
                    });
                  },
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: colorScheme.error.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTodoMetaField({required String label, required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  Widget _buildAssigneeField(int index) {
    final todo = _todos[index];
    if (_groupMembers.isNotEmpty) {
      final value = _groupMembers.contains(todo.assigneeEmail)
          ? todo.assigneeEmail
          : '';
      return DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: _taskFieldDecoration(
          'Chưa giao',
          Theme.of(context).colorScheme,
        ),
        items: [
          const DropdownMenuItem(value: '', child: Text('Chưa giao')),
          ..._groupMembers.map(
            (email) => DropdownMenuItem(value: email, child: Text(email)),
          ),
        ],
        onChanged: !_canEditTodoDefinition(index)
            ? null
            : (value) {
                setState(() {
                  _todos[index] = todo.copyWith(
                    assigneeEmail: value ?? '',
                    assigneeName: value ?? '',
                  );
                });
              },
      );
    }

    return TextFormField(
      key: ValueKey('assignee_$index'),
      initialValue: todo.assigneeEmail,
      enabled: _canEditTodoDefinition(index),
      onChanged: (value) {
        _todos[index].assigneeEmail = value.toLowerCase().trim();
        _todos[index].assigneeName = value.trim();
      },
      decoration: _taskFieldDecoration(
        'Nhập người phụ trách',
        Theme.of(context).colorScheme,
      ),
    );
  }

  Widget _buildStatusField(int index) {
    final value = TodoStatus.values.contains(_todos[index].status)
        ? _todos[index].status
        : TodoStatus.todo;
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: _taskFieldDecoration(
        'Chọn trạng thái',
        Theme.of(context).colorScheme,
      ),
      items: TodoStatus.values
          .map(
            (status) => DropdownMenuItem(
              value: status,
              child: Text(TodoStatus.label(status)),
            ),
          )
          .toList(),
      onChanged: !_canUpdateTodoStatusAndAttachments(index)
          ? null
          : (status) {
              if (status == null) return;
              setState(() {
                _todos[index] = _todos[index].copyWith(
                  status: status,
                  isDone: status == TodoStatus.done,
                  markCompletedNow: status == TodoStatus.done,
                  clearCompletedAt: status != TodoStatus.done,
                );
              });
            },
    );
  }

  void _showTitleFormattingSheet() {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Định dạng tiêu đề',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Màu chữ',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildTitleColorOption(
                        '',
                        Icons.format_color_reset,
                        setSheetState,
                      ),
                      _buildTitleColorOption('FF000000', null, setSheetState),
                      _buildTitleColorOption('FFF44336', null, setSheetState),
                      _buildTitleColorOption('FFE91E63', null, setSheetState),
                      _buildTitleColorOption('FF9C27B0', null, setSheetState),
                      _buildTitleColorOption('FF673AB7', null, setSheetState),
                      _buildTitleColorOption('FF3F51B5', null, setSheetState),
                      _buildTitleColorOption('FF2196F3', null, setSheetState),
                      _buildTitleColorOption('FF00BCD4', null, setSheetState),
                      _buildTitleColorOption('FF009688', null, setSheetState),
                      _buildTitleColorOption('FF4CAF50', null, setSheetState),
                      _buildTitleColorOption('FFFFC107', null, setSheetState),
                      _buildTitleColorOption('FFFF9800', null, setSheetState),
                      _buildTitleColorOption('FFFF5722', null, setSheetState),
                      _buildTitleColorOption('FF795548', null, setSheetState),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Kiểu chữ',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildFormatButton(
                      icon: Icons.format_bold,
                      isSelected: _titleIsBold,
                      onTap: () => setState(() {
                        _titleIsBold = !_titleIsBold;
                        setSheetState(() {});
                      }),
                    ),
                    _buildFormatButton(
                      icon: Icons.format_italic,
                      isSelected: _titleIsItalic,
                      onTap: () => setState(() {
                        _titleIsItalic = !_titleIsItalic;
                        setSheetState(() {});
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Cỡ chữ',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${_titleFontSize.toInt()}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _titleFontSize,
                  min: 20,
                  max: 36,
                  divisions: 16,
                  label: _titleFontSize.toInt().toString(),
                  onChanged: (val) => setState(() {
                    _titleFontSize = val;
                    setSheetState(() {});
                  }),
                ),
                const SizedBox(height: 10),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showTodoFormattingSheet(int index) {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final currentItem = _todos[index];
          return Container(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Định dạng công việc',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Màu chữ',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildColorOption(
                        '',
                        Icons.format_color_reset,
                        setSheetState,
                        index,
                      ),
                      _buildColorOption('FF000000', null, setSheetState, index),
                      _buildColorOption('FFF44336', null, setSheetState, index),
                      _buildColorOption('FFE91E63', null, setSheetState, index),
                      _buildColorOption('FF9C27B0', null, setSheetState, index),
                      _buildColorOption('FF673AB7', null, setSheetState, index),
                      _buildColorOption('FF3F51B5', null, setSheetState, index),
                      _buildColorOption('FF2196F3', null, setSheetState, index),
                      _buildColorOption('FF00BCD4', null, setSheetState, index),
                      _buildColorOption('FF009688', null, setSheetState, index),
                      _buildColorOption('FF4CAF50', null, setSheetState, index),
                      _buildColorOption('FFFFC107', null, setSheetState, index),
                      _buildColorOption('FFFF9800', null, setSheetState, index),
                      _buildColorOption('FFFF5722', null, setSheetState, index),
                      _buildColorOption('FF795548', null, setSheetState, index),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Kiểu chữ',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildFormatButton(
                      icon: Icons.format_bold,
                      isSelected: currentItem.isBold,
                      onTap: () => setState(() {
                        _todos[index] = currentItem.copyWith(
                          isBold: !currentItem.isBold,
                        );
                        setSheetState(() {});
                      }),
                    ),
                    _buildFormatButton(
                      icon: Icons.format_italic,
                      isSelected: currentItem.isItalic,
                      onTap: () => setState(() {
                        _todos[index] = currentItem.copyWith(
                          isItalic: !currentItem.isItalic,
                        );
                        setSheetState(() {});
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Cỡ chữ',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${currentItem.fontSize.toInt()}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: currentItem.fontSize,
                  min: 12,
                  max: 32,
                  divisions: 20,
                  label: currentItem.fontSize.toInt().toString(),
                  onChanged: (val) => setState(() {
                    _todos[index] = currentItem.copyWith(fontSize: val);
                    setSheetState(() {});
                  }),
                ),
                const SizedBox(height: 10),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildColorOption(
    String colorHex,
    IconData? icon,
    StateSetter setSheetState,
    int index,
  ) {
    final isSelected = _todos[index].textColor == colorHex;
    return GestureDetector(
      onTap: () => setState(() {
        _todos[index] = _todos[index].copyWith(textColor: colorHex);
        setSheetState(() {});
      }),
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: colorHex.isEmpty
              ? Colors.grey[200]
              : Color(int.parse(colorHex, radix: 16)),
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected
                ? Colors.blue
                : Colors.grey.withValues(alpha: 0.3),
            width: isSelected ? 3 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.blue.withValues(alpha: 0.3),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: icon != null
            ? Icon(icon, size: 20, color: Colors.grey[700])
            : null,
      ),
    );
  }

  Widget _buildTitleColorOption(
    String colorHex,
    IconData? icon,
    StateSetter setSheetState,
  ) {
    final isSelected = _titleTextColor == colorHex;
    return GestureDetector(
      onTap: () => setState(() {
        _titleTextColor = colorHex;
        setSheetState(() {});
      }),
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: colorHex.isEmpty
              ? Colors.grey[200]
              : Color(int.parse(colorHex, radix: 16)),
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected
                ? Colors.blue
                : Colors.grey.withValues(alpha: 0.3),
            width: isSelected ? 3 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.blue.withValues(alpha: 0.3),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: icon != null
            ? Icon(icon, size: 20, color: Colors.grey[700])
            : null,
      ),
    );
  }

  Widget _buildFormatButton({
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant,
            width: 1.5,
          ),
        ),
        child: Icon(
          icon,
          color: isSelected
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
          size: 24,
        ),
      ),
    );
  }

  void _showContentStyleSheet() {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Định dạng nội dung',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              const Text(
                'Màu chữ',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 50,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _buildContentColorOption(
                      '',
                      Icons.format_color_reset,
                      setSheetState,
                    ),
                    _buildContentColorOption('FF000000', null, setSheetState),
                    _buildContentColorOption('FFF44336', null, setSheetState),
                    _buildContentColorOption('FFE91E63', null, setSheetState),
                    _buildContentColorOption('FF9C27B0', null, setSheetState),
                    _buildContentColorOption('FF673AB7', null, setSheetState),
                    _buildContentColorOption('FF3F51B5', null, setSheetState),
                    _buildContentColorOption('FF2196F3', null, setSheetState),
                    _buildContentColorOption('FF00BCD4', null, setSheetState),
                    _buildContentColorOption('FF009688', null, setSheetState),
                    _buildContentColorOption('FF4CAF50', null, setSheetState),
                    _buildContentColorOption('FFFFC107', null, setSheetState),
                    _buildContentColorOption('FFFF9800', null, setSheetState),
                    _buildContentColorOption('FFFF5722', null, setSheetState),
                    _buildContentColorOption('FF795548', null, setSheetState),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildFormatButton(
                    icon: Icons.format_bold,
                    isSelected: _contentIsBold,
                    onTap: () => setState(() {
                      _contentIsBold = !_contentIsBold;
                      setSheetState(() {});
                    }),
                  ),
                  _buildFormatButton(
                    icon: Icons.format_italic,
                    isSelected: _contentIsItalic,
                    onTap: () => setState(() {
                      _contentIsItalic = !_contentIsItalic;
                      setSheetState(() {});
                    }),
                  ),
                  _buildFormatButton(
                    icon: Icons.format_underlined,
                    isSelected: _contentIsUnderlined,
                    onTap: () => setState(() {
                      _contentIsUnderlined = !_contentIsUnderlined;
                      setSheetState(() {});
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Cỡ chữ',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${_contentFontSize.toInt()}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _contentFontSize,
                min: 12,
                max: 30,
                divisions: 18,
                label: _contentFontSize.toInt().toString(),
                onChanged: (val) => setState(() {
                  _contentFontSize = val;
                  setSheetState(() {});
                }),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContentColorOption(
    String colorHex,
    IconData? icon,
    StateSetter setSheetState,
  ) {
    final isSelected = _contentTextColor == colorHex;
    return GestureDetector(
      onTap: () => setState(() {
        _contentTextColor = colorHex;
        setSheetState(() {});
      }),
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: colorHex.isEmpty
              ? Colors.white
              : Color(int.parse(colorHex, radix: 16)),
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected
                ? Colors.blue
                : Colors.grey.withValues(alpha: 0.3),
            width: isSelected ? 3 : 1,
          ),
        ),
        child: icon != null
            ? Icon(icon, size: 20, color: Colors.grey[700])
            : null,
      ),
    );
  }
}

class _NoteTemplate {
  final String title;
  final String label;
  final String content;
  final bool isTodo;
  final List<String> todos;

  const _NoteTemplate({
    required this.title,
    required this.label,
    this.content = '',
    this.isTodo = false,
    this.todos = const [],
  });
}
