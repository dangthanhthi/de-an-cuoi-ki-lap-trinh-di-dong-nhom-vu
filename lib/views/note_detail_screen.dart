import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_models.dart';
import '../controllers/app_state.dart';
import '../utils/media_utils.dart';
import 'create_edit_note_screen.dart';
import 'image_grid_preview_screen.dart';
import '../utils/note_utils.dart';
import '../utils/snack_utils.dart';
import '../widgets/success_animation.dart';
import '../widgets/common/multi_image_gallery.dart';
import 'package:easy_image_viewer/easy_image_viewer.dart';
import 'package:cached_network_image/cached_network_image.dart';

class NoteDetailScreen extends StatefulWidget {
  final Note note;
  const NoteDetailScreen({super.key, required this.note});
  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  Note? _liveNote;
  Note get note => _liveNote ?? widget.note;
  bool _canManageGroupTodos = true;

  @override
  void initState() {
    super.initState();
    if (note.groupId.isNotEmpty) {
      _canManageGroupTodos = false;
    }
    _loadGroupTodoPermission();
    _markAsReadIfNeeded();
  }

  void _showSnack(String msg, {bool success = true}) {
    if (!mounted) return;
    SnackUtils.show(context, msg, success: success);
  }

  void _markAsReadIfNeeded() {
    if (note.isUnread) {
      FirebaseService.markNoteAsViewed(note.id);
    }
  }

  Future<void> _loadGroupTodoPermission() async {
    if (note.groupId.isEmpty) return;
    final canManage = await FirebaseService.canCurrentUserManageGroupTasks(
      note.groupId,
    );
    if (!mounted) return;
    setState(() => _canManageGroupTodos = canManage);
  }

  Future<void> _openAttachment(String value, int index) async {
    try {
      final bytes = bytesFromDataUri(value);
      if (bytes != null) {
        final fileName = sanitizeFileName(
          fileNameFromDataUri(value, fallback: 'tep-dinh-kem-${index + 1}'),
          fallback: 'tep-dinh-kem-${index + 1}',
        );
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(bytes, flush: true);
        await OpenFilex.open(file.path);
        return;
      }

      final uri = Uri.tryParse(value);
      final canOpenExternal =
          uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          await canLaunchUrl(uri);
      if (canOpenExternal) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }

      if (!mounted) return;
      _showSnack('Không mở được tệp đính kèm này', success: false);
    } catch (e) {
      if (!mounted) return;
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

  void _deleteNote() async {
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    bool hasUnfinishedTasks = false;
    if (note.isTodo) {
      if (note.groupId.isEmpty) {
        hasUnfinishedTasks = note.todos.any((t) => !t.isDone && t.status != TodoStatus.done);
      } else {
        hasUnfinishedTasks = note.todos.any((t) =>
            t.assigneeEmail.toLowerCase().trim() == myEmail &&
            !t.isDone &&
            t.status != TodoStatus.done);
      }
    }

    final String contentText;
    if (note.groupId.isNotEmpty) {
      if (hasUnfinishedTasks) {
        contentText = 'Ghi chú này còn công việc của bạn chưa hoàn thành. Hành động này sẽ xóa ghi chú của CẢ NHÓM. Bạn có chắc chắn muốn xóa không?';
      } else {
        contentText = 'Hành động này sẽ xóa ghi chú của CẢ NHÓM. Bạn có chắc không?';
      }
    } else {
      if (hasUnfinishedTasks) {
        contentText = 'Ghi chú này còn công việc chưa hoàn thành. Bạn có chắc chắn muốn xóa ghi chú này không?';
      } else {
        contentText = 'Bạn có chắc muốn xóa ghi chú này không?';
      }
    }

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(note.groupId.isNotEmpty ? 'Xóa vĩnh viễn?' : 'Xóa ghi chú?'),
        content: Text(contentText),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;
    if (!mounted) return;

    final navigator = Navigator.of(context);

    try {
      final result = await FirebaseService.deleteNote(
        note.id,
        note.title,
      );
      if (result != 'SUCCESS') {
        _showSnack(result, success: false);
        return;
      }

      _showSnack('Đã xóa ghi chú thành công', success: true);
      navigator.pop();
    } catch (e) {
      _showSnack('Lỗi khi xóa: $e', success: false);
    }
  }



  void _shareNote() {
    NoteUtils.showShareSheet(
      context,
      note,
      onShareSuccess: () {
        if (mounted) setState(() {});
      },
    );
  }


  String _todoExportText(TodoItem todo) {
    final isDone = todo.isDone || todo.status == TodoStatus.done;
    final statusChar = isDone ? 'x' : ' ';
    final base = '- [$statusChar] ${todo.task}';

    String deadlineStr = 'Không có';
    if (todo.deadline != null) {
      final d = todo.deadline!;
      final dateStr = '${d.day}/${d.month}/${d.year}';
      deadlineStr = (d.hour == 0 && d.minute == 0)
          ? dateStr
          : '$dateStr ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }

    if (note.groupId.isEmpty) {
      if (todo.deadline == null) return base;
      return '$base (Hạn: $deadlineStr)';
    }

    final assignee = todo.assigneeEmail.isEmpty
        ? 'Chưa giao'
        : todo.assigneeEmail;
    return '$base\n  Người phụ trách: $assignee | Deadline: $deadlineStr | Trạng thái: ${TodoStatus.label(todo.effectiveStatus)}';
  }

  String _noteShareText() {
    final buffer = StringBuffer()
      ..writeln(note.title)
      ..writeln('Nhãn: ${note.label}')
      ..writeln('Ưu tiên: ${NotePriority.label(note.priority)}')
      ..writeln('Ngày tạo: ${note.date}')
      ..writeln();

    if (note.isTodo) {
      for (final todo in note.todos) {
        buffer.writeln(_todoExportText(todo));
      }
    } else {
      buffer.writeln(note.content);
    }

    if (note.attachments.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Tệp đính kèm: ${note.attachments.length}');
    }
    return buffer.toString();
  }

  Future<void> _shareText() async {
    await SharePlus.instance.share(
      ShareParams(text: _noteShareText(), subject: note.title),
    );
  }

  Future<void> _exportPdf() async {
    try {
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          build: (context) => [
            pw.Text(
              note.title,
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Text('Nhãn: ${note.label}'),
            pw.Text('Ưu tiên: ${NotePriority.label(note.priority)}'),
            pw.Text('Ngày tạo: ${note.date}'),
            pw.SizedBox(height: 16),
            if (note.isTodo)
              ...note.todos.map(
                (todo) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 8),
                  child: pw.Text(_todoExportText(todo)),
                ),
              )
            else
              pw.Text(note.content),
          ],
        ),
      );

      final dir = await getTemporaryDirectory();
      final safeTitle = note.title
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .trim();
      final file = File(
        '${dir.path}/${safeTitle.isEmpty ? 'snote' : safeTitle}.pdf',
      );
      await file.writeAsBytes(await pdf.save(), flush: true);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: note.title,
          subject: note.title,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack('Lỗi xuất PDF: $e', success: false);
    }
  }

  void _showExportSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Xuất PDF'),
              onTap: () {
                Navigator.pop(context);
                _exportPdf();
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_outlined),
              title: const Text('Chia sẻ qua ứng dụng khác'),
              subtitle: const Text(
                'Zalo, Messenger, email hoặc ứng dụng có sẵn',
              ),
              onTap: () {
                Navigator.pop(context);
                _shareText();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showHistorySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.35,
        builder: (context, scrollController) {
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseService.getNoteHistoryStream(note.id),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(child: Text('Chưa có lịch sử chỉnh sửa'));
              }
              return ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: docs.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final ts = data['timestamp'];
                  final time = ts is Timestamp ? ts.toDate() : null;
                  final action = (data['action'] ?? '').toString();
                  final previousContent = (data['previousContent'] ?? '')
                      .toString();

                  String displayContent = previousContent;
                  if (previousContent.startsWith('[{') ||
                      previousContent.startsWith('{"')) {
                    try {
                      final doc = Document.fromJson(
                        jsonDecode(previousContent),
                      );
                      displayContent = doc.toPlainText().trim();
                    } catch (_) {
                      // Keep original if not valid quill JSON
                    }
                  }

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      child: Icon(
                        action == 'create'
                            ? Icons.add
                            : action == 'todo_status'
                            ? Icons.checklist
                            : Icons.edit,
                      ),
                    ),
                    title: Text(
                      data['userName'] ?? data['userEmail'] ?? 'Không rõ',
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          time == null
                              ? 'Vừa xong'
                              : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} - ${time.day}/${time.month}/${time.year}',
                        ),
                        if (action == 'todo_status')
                          Text(
                            'Todo "${data['todoTask'] ?? ''}": ${TodoStatus.label((data['previousStatus'] ?? '').toString())} -> ${TodoStatus.label((data['status'] ?? '').toString())}',
                          ),
                        if (displayContent.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Nội dung trước đó:',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            displayContent,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('notes').doc(widget.note.id).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.exists) {
          _liveNote = FirebaseService.noteFromDocument(snapshot.data!);
        } else {
          _liveNote = null;
        }
        String myEmail = AppState.currentUserEmail.toLowerCase().trim();
    bool isSharedWithMe = note.sharedWith.any(
      (e) => e.toLowerCase().trim() == myEmail,
    );
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final usesGroupTaskMetadata = note.groupId.isNotEmpty;
    final creatorEmail = note.createdByEmail.toLowerCase().trim();
    final myUid = FirebaseService.currentUid;
    final isAdmin = AppState.currentUserRole.toLowerCase() == 'admin';
    final isOwner = (creatorEmail.isNotEmpty && creatorEmail == myEmail) ||
        (note.userId.isNotEmpty && note.userId == myUid) ||
        (creatorEmail.isEmpty &&
            note.groupId.isEmpty &&
            note.sharedWith.isEmpty);
    
    // For group notes, system-wide admin does NOT automatically grant edit/delete/share permissions.
    // Only group leaders/managers or the note creator can edit/delete/share.
    final canEditNote = isOwner || 
        (!usesGroupTaskMetadata && isAdmin) || 
        (usesGroupTaskMetadata && _canManageGroupTodos);
        
    final canDelete = !isSharedWithMe && 
        (isOwner || (!usesGroupTaskMetadata && isAdmin) || (usesGroupTaskMetadata && _canManageGroupTodos));
    
    final canShare = (isOwner && !usesGroupTaskMetadata) || 
                     (usesGroupTaskMetadata && _canManageGroupTodos);
    Color activeColor = note.coverColor;
    if (isDark) {
      final hsl = HSLColor.fromColor(activeColor);
      activeColor = hsl
          .withSaturation((hsl.saturation + 0.18).clamp(0.0, 1.0).toDouble())
          .withLightness(0.58)
          .toColor();
    }
    final onActive = activeColor.computeLuminance() > 0.5
        ? Colors.black87
        : Colors.white;
    final mutedText = colorScheme.onSurfaceVariant;

    return Scaffold(
        backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200.0,
            floating: false,
            pinned: true,
            backgroundColor: activeColor,
            leading: BackButton(color: onActive),
            flexibleSpace: FlexibleSpaceBar(
              background: Center(
                child: Icon(
                  note.isTodo ? Icons.check_box : Icons.edit_document,
                  size: 80,
                  color: onActive.withValues(alpha: 0.58),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.history, color: onActive),
                tooltip: 'Lịch sử chỉnh sửa',
                onPressed: _showHistorySheet,
              ),
              IconButton(
                icon: Icon(Icons.file_upload_outlined, color: onActive),
                tooltip: canShare ? 'Xuất/chia sẻ' : 'Bạn không có quyền chia sẻ ghi chú này',
                onPressed: canShare ? _showExportSheet : () => _showSnack('Bạn không có quyền chia sẻ ghi chú nhóm này', success: false),
              ),
              // Always allow sharing for anyone who can view the note
              IconButton(
                icon: Icon(Icons.share, color: onActive),
                tooltip: canShare ? 'Chia sẻ nhanh' : 'Bạn không có quyền chia sẻ ghi chú này',
                onPressed: canShare ? _shareNote : () => _showSnack('Bạn không có quyền chia sẻ ghi chú nhóm này', success: false),
              ),
              IconButton(
                icon: Icon(
                  Icons.edit,
                  color: canEditNote ? onActive : onActive.withValues(alpha: 0.38),
                ),
                tooltip: canEditNote ? 'Sửa' : 'Bạn không có quyền sửa ghi chú này',
                onPressed: canEditNote
                    ? () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                CreateEditNoteScreen(note: note),
                          ),
                        );
                        if (mounted) setState(() {});
                      }
                    : () => _showSnack('Bạn không có quyền chỉnh sửa nội dung ghi chú này', success: false),
              ),

              if (canDelete) ...[
                IconButton(
                  icon: Icon(Icons.delete, color: onActive),
                  tooltip: 'Xóa vĩnh viễn',
                  onPressed: _deleteNote,
                ),
              ],
            ],
          ),
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              transform: Matrix4.translationValues(0.0, -24.0, 0.0),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: activeColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          note.label,
                          style: TextStyle(
                            color: activeColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        note.date,
                        style: TextStyle(color: mutedText),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    note.title,
                    style: TextStyle(
                      fontSize:
                          (note.titleFontSize.clamp(22.0, 36.0) as num)
                              .toDouble(),
                      fontWeight: note.titleIsBold
                          ? FontWeight.bold
                          : FontWeight.w600,
                      fontStyle: note.titleIsItalic
                          ? FontStyle.italic
                          : FontStyle.normal,
                      decoration: null,
                      color:
                          note.resolvedTitleColor ??
                          (isSharedWithMe
                              ? colorScheme.error
                              : colorScheme.onSurface),
                    ),
                  ),
                  if (isSharedWithMe ||
                      note.groupId.isNotEmpty ||
                      note.todos.any(
                        (t) => t.assigneeEmail.toLowerCase().trim() == myEmail,
                      )) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (isSharedWithMe)
                          _buildStatusBadge(
                            context,
                            'Được chia sẻ',
                            colorScheme.errorContainer,
                            colorScheme.onErrorContainer,
                          ),
                        if (note.groupId.isNotEmpty)
                          _buildStatusBadge(
                            context,
                            'Nhóm: ${note.groupName.isNotEmpty ? note.groupName : "Ghi chú nhóm"}',
                            colorScheme.primaryContainer,
                            colorScheme.onPrimaryContainer,
                          ),
                        if (note.todos.any(
                          (t) =>
                              t.assigneeEmail.toLowerCase().trim() == myEmail,
                        ))
                          _buildStatusBadge(
                            context,
                            'Bạn phụ trách',
                            Colors.orange.shade100,
                            Colors.orange.shade900,
                          ),
                      ],
                    ),
                  ],
                  if (note.sharedWith.isNotEmpty || isSharedWithMe) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2.0),
                          child: Icon(
                            isSharedWithMe ? Icons.person_pin_circle_outlined : Icons.group,
                            size: 16,
                            color: mutedText,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isSharedWithMe
                                ? 'Được chia sẻ bởi: ${note.createdByEmail}'
                                : 'Đã chia sẻ với: ${note.sharedWith.join(", ")}',
                            style: TextStyle(color: mutedText),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        avatar: const Icon(Icons.flag_outlined, size: 16),
                        label: Text(
                          'Ưu tiên: ${NotePriority.label(note.priority)}',
                        ),
                      ),
                      if (note.isPinned)
                        const Chip(
                          avatar: Icon(Icons.push_pin, size: 16, color: Colors.amber),
                          label: Text('Ghim trong nhóm'),
                        ),
                      if (note.isPinnedByUser)
                        const Chip(
                          avatar: Icon(Icons.push_pin, size: 16),
                          label: Text('Ghim trên Home'),
                        ),
                    ],
                  ),

                  if (note.isTodo && note.todos.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: AnimatedProgressBar(
                            value: note.todos.where((t) => t.isDone || t.status == TodoStatus.done).length / note.todos.length,
                            backgroundColor: colorScheme.surfaceContainerHighest,
                            color: activeColor,
                            height: 10,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${(note.todos.where((t) => t.isDone || t.status == TodoStatus.done).length / note.todos.length * 100).toInt()}%',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: activeColor,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const Divider(height: 40),

                  // Hiển thị tệp đính kèm.
                  if (note.attachments.any((a) => isImageValue(a))) ...[
                    Text(
                      'Hình ảnh đính kèm:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: mutedText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    MultiImageGallery(
                      images: note.attachments.where((a) => isImageValue(a)).toList(),
                      onTapImage: (index) {
                        final imagesOnly = note.attachments.where((a) => isImageValue(a)).toList();
                        _showImagePreview(imagesOnly, index);
                      },
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    const SizedBox(height: 8),
                  ],

                  if (note.attachments.any((a) => !isImageValue(a))) ...[
                    Text(
                      'Tệp đính kèm:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: mutedText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var a in note.attachments.where((a) => !isImageValue(a)))
                          ActionChip(
                            avatar: const Icon(
                              Icons.attach_file,
                              size: 16,
                            ),
                            label: Text(
                              attachmentLabel(a, note.attachments.indexOf(a)),
                              style: const TextStyle(fontSize: 12),
                            ),
                            backgroundColor: colorScheme.surfaceContainerHighest
                                .withValues(alpha: isDark ? 0.58 : 1),
                            onPressed: () =>
                                _openAttachment(a, note.attachments.indexOf(a)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (note.isTodo) ...[
                    if (usesGroupTaskMetadata && !_canManageGroupTodos) ...[
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.36),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.orange),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Bạn có thể hoàn thành công việc được giao, nhưng chỉ trưởng nhóm mới được sửa chi tiết ghi chú.',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    ...note.todos.asMap().entries.map((entry) {
                      final index = entry.key;
                      final todo = entry.value;
                      final isDone =
                          todo.isDone || todo.status == TodoStatus.done;
                      final isOverdue = usesGroupTaskMetadata && todo.isOverdue;
                      final isAssignee =
                          todo.assigneeEmail.toLowerCase().trim() == myEmail;
                      final isUnassigned = todo.assigneeEmail.trim().isEmpty;
                      final canToggleTodo = isAdmin ||
                          (usesGroupTaskMetadata
                              ? (isAssignee ||
                                  _canManageGroupTodos ||
                                  isUnassigned)
                              : (isOwner || isSharedWithMe));

                      return InkWell(
                        onTap: canToggleTodo
                            ? () async {
                                HapticFeedback.lightImpact();
                                final nextStatus =
                                    isDone ? TodoStatus.todo : TodoStatus.done;
                                final res = await FirebaseService.updateTodoStatus(
                                  note.id,
                                  index,
                                  nextStatus,
                                );
                                if (res != 'SUCCESS') {
                                  _showSnack(res, success: false);
                                  return;
                                }
                                if (!mounted) return;
                                setState(() {
                                  note.todos[index] = todo.copyWith(
                                    status: nextStatus,
                                    isDone: nextStatus == TodoStatus.done,
                                    markCompletedNow:
                                        nextStatus == TodoStatus.done,
                                    clearCompletedAt:
                                        nextStatus != TodoStatus.done,
                                  );

                                  if (nextStatus == TodoStatus.done) {
                                    HapticFeedback.lightImpact();
                                  }
                                });
                              }
                            : () {
                                HapticFeedback.heavyImpact();
                                _showSnack(
                                  'Chỉ người phụ trách hoặc quản trị viên mới được tích công việc này.',
                                  success: false,
                                );
                              },
                        child: Opacity(
                          opacity: canToggleTodo ? 1.0 : 0.5,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                              Icon(
                                isDone
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: isDone
                                    ? activeColor
                                    : (isOverdue
                                          ? colorScheme.error
                                          : mutedText),
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      todo.isUppercase
                                          ? todo.task.toUpperCase()
                                          : todo.task,
                                      style: TextStyle(
                                        fontSize: todo.fontSize,
                                        fontWeight: todo.isBold
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        fontStyle: todo.isItalic
                                            ? FontStyle.italic
                                            : FontStyle.normal,
                                        decoration: isDone
                                            ? TextDecoration.lineThrough
                                            : null,
                                        color: isDone
                                            ? mutedText
                                            : (todo.textColor.isNotEmpty
                                                  ? Color(
                                                      int.parse(
                                                        todo.textColor,
                                                        radix: 16,
                                                      ),
                                                    ).withValues(alpha: 1.0)
                                                  : colorScheme.onSurface),
                                      ),
                                    ),
                                    if (usesGroupTaskMetadata) ...[
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: [
                                          Text(
                                            TodoStatus.label(
                                              todo.effectiveStatus,
                                            ),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isDone
                                                  ? mutedText
                                                  : colorScheme.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if (todo.assigneeEmail.isNotEmpty)
                                            Text(
                                              'Phụ trách: ${todo.assigneeName.isNotEmpty ? todo.assigneeName : todo.assigneeEmail}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: mutedText,
                                              ),
                                            ),
                                          if (todo.deadline != null)
                                            Text(
                                              'Hạn: ${todo.deadline!.day}/${todo.deadline!.month} ${todo.deadline!.hour}:${todo.deadline!.minute}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isOverdue
                                                    ? colorScheme.error
                                                    : mutedText,
                                                fontWeight: isOverdue
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                    if (isDone && todo.completedAt != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          'Hoàn thành lúc: ${todo.completedAt!.hour}:${todo.completedAt!.minute.toString().padLeft(2, '0')}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: mutedText,
                                          ),
                                        ),
                                      ),
                                    if (todo.attachments.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: todo.attachments
                                            .asMap()
                                            .entries
                                            .map((attEntry) {
                                          final attIndex = attEntry.key;
                                          final url = attEntry.value;
                                          return ActionChip(
                                            avatar: Icon(
                                              isImageValue(url)
                                                  ? Icons.image_outlined
                                                  : Icons.attach_file,
                                              size: 14,
                                            ),
                                            label: Text(
                                              attachmentLabel(url, attIndex),
                                              style:
                                                  const TextStyle(fontSize: 10),
                                            ),
                                            onPressed: () {
                                              if (isImageValue(url)) {
                                                _showImagePreview([url], 0);
                                              } else {
                                                _openAttachment(url, attIndex);
                                              }
                                            },
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                          );
                                        }).toList(),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  ] else
                    note.isRichText
                        ? _buildRichTextContent()
                        : Text(
                            note.content,
                            style: TextStyle(
                              fontSize: note.contentFontSize,
                              height: 1.6,
                              fontWeight: note.contentIsBold ? FontWeight.bold : FontWeight.normal,
                              fontStyle: note.contentIsItalic ? FontStyle.italic : FontStyle.normal,
                              decoration: note.contentIsUnderlined ? TextDecoration.underline : null,
                              color: note.resolvedContentColor ?? colorScheme.onSurface,
                            ),
                          ),

                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
      },
    );
  }

  Widget _buildRichTextContent() {
    try {
      final doc = Document.fromJson(jsonDecode(note.content));
      final controller = QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
      )..readOnly = true;
      return QuillEditor.basic(
        controller: controller,
        config: const QuillEditorConfig(
          padding: EdgeInsets.zero,
          expands: false,
          scrollable: false, // Let the CustomScrollView handle scrolling
        ),
      );
    } catch (e) {
      return Text(note.content);
    }
  }

  Widget _buildStatusBadge(
    BuildContext context,
    String text,
    Color bgColor,
    Color textColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: textColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}




