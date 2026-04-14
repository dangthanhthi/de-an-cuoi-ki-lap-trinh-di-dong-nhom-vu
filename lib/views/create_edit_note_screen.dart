import 'package:flutter/material.dart';
import 'dart:math';
import '../models/app_models.dart';
import '../controllers/app_state.dart';

class CreateEditNoteScreen extends StatefulWidget {
  final Note? note;
  const CreateEditNoteScreen({super.key, this.note});

  @override
  State<CreateEditNoteScreen> createState() => _CreateEditNoteScreenState();
}

class _CreateEditNoteScreenState extends State<CreateEditNoteScreen> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  String _selectedLabel = AppState.labels.first;
  bool _isTodo = false;
  List<TodoItem> _todos = [];
  bool _isAILoading = false;
  String _lastAITitle = "";
  int _aiClickCount = 0;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController = TextEditingController(text: widget.note?.content ?? '');
    if (widget.note != null) {
      _selectedLabel = widget.note!.label;
      _isTodo = widget.note!.isTodo;
      _todos = widget.note!.todos.map((t) => TodoItem(task: t.task, isDone: t.isDone)).toList();
    }
  }

  void _saveNote() {
    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập tiêu đề')));
      return;
    }

    if (widget.note == null) {
      final newNote = Note(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: _titleController.text,
        content: _contentController.text,
        label: _selectedLabel,
        date: 'Hôm nay',
        coverColor: Colors.primaries[Random().nextInt(Colors.primaries.length)],
        isTodo: _isTodo,
        todos: _todos,
      );
      AppState.notes.insert(0, newNote);
      AppState.logActivity('Tạo ghi chú', 'Đã tạo ghi chú mới: "${newNote.title}"');
    } else {
      widget.note!.title = _titleController.text;
      widget.note!.content = _contentController.text;
      widget.note!.label = _selectedLabel;
      widget.note!.isTodo = _isTodo;
      widget.note!.todos = _todos;
      AppState.logActivity('Sửa ghi chú', 'Đã cập nhật ghi chú: "${widget.note!.title}"');
    }
    Navigator.pop(context);
  }

  void _askAI() async {
    String title = _titleController.text.trim().toLowerCase();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập tiêu đề để AI có thể gợi ý!')));
      return;
    }

    if (_lastAITitle != title) {
      _lastAITitle = title;
      _aiClickCount = 0;
    }

    setState(() => _isAILoading = true);
    await Future.delayed(const Duration(milliseconds: 1200));

    _aiClickCount++;
    int variationIndex = (_aiClickCount - 1) % 3;

    List<List<String>> todoVariations = [];
    List<String> contentVariations = [];
    if (title.contains('họp') || title.contains('meeting')) {
      todoVariations = [
        ['Chuẩn bị tài liệu báo cáo', 'Gửi link Google Meet', 'Ghi chú biên bản'],
        ['Làm slide thuyết trình', 'Mua nước/cafe cho phòng họp', 'Kiểm tra máy chiếu'],
        ['Gửi email tóm tắt (Recap)', 'Cập nhật task lên hệ thống', 'Lên lịch họp lần sau']
      ];
      contentVariations = [
        'Nội dung cuộc họp:\n1. Cập nhật tiến độ dự án.\n2. Giải quyết các vấn đề tồn đọng.',
        'Gợi ý thêm:\n- Dành 10 phút cuối để Q&A.\n- Yêu cầu mọi người tắt điện thoại.',
        'Mục tiêu đầu ra:\n- Chốt được deadline.\n- Phân công rõ người chịu trách nhiệm (PIC).'
      ];
    } else if (title.contains('mua') || title.contains('siêu thị') || title.contains('chợ')) {
      todoVariations = [
        ['Kiểm tra tủ lạnh trước khi đi', 'Mang theo túi vải', 'Mua đồ ăn tươi sống'],
        ['Mua gia vị (Mắm, muối, đường)', 'Mua giấy vệ sinh', 'Mua sữa tắm/dầu gội'],
        ['Mua trái cây tráng miệng', 'Mua đồ ăn vặt', 'Thanh toán bằng thẻ tín dụng']
      ];
      contentVariations = [
        'Danh sách cần mua:\n- Thực phẩm: ...\n- Đồ gia dụng: ...',
        'Lưu ý:\n- Mua đồ hộp dự trữ.\n- Kiểm tra hạn sử dụng kỹ càng.',
        'Mẹo đi siêu thị:\n- Lên danh sách trước để không mua lố tay.\n- Đi vào buổi sáng để có đồ tươi.'
      ];
    } else {
      todoVariations = [
        ['Lên kế hoạch chi tiết', 'Phân bổ thời gian thực hiện', 'Chuẩn bị nguồn lực'],
        ['Tìm kiếm tài liệu tham khảo', 'Xin ý kiến chuyên gia', 'Bắt đầu triển khai bước 1'],
        ['Đánh giá tiến độ', 'Tối ưu hóa quy trình', 'Báo cáo kết quả cuối cùng']
      ];
      contentVariations = [
        'Dàn ý cơ bản (Lần 1):\n1. Giới thiệu/Mục tiêu.\n2. Các bước triển khai.\n3. Kết luận.',
        'Phân tích chuyên sâu (Lần 2):\n- Điểm mạnh (Strengths).\n- Điểm yếu (Weaknesses).\n- Cơ hội (Opportunities).',
        'Lưu ý bổ sung (Lần 3):\n- Luôn có phương án dự phòng (Plan B).\n- Theo dõi sát sao tiến độ.'
      ];
    }

    List<String> currentTodos = todoVariations[variationIndex];
    String currentContent = contentVariations[variationIndex];

    setState(() {
      _isAILoading = false;

      if (_isTodo) {
        int addedCount = 0;
        for (var task in currentTodos) {
          bool isExist = _todos.any((t) => t.task.toLowerCase() == task.toLowerCase());
          if (!isExist) {
            _todos.add(TodoItem(task: task));
            addedCount++;
          }
        }
        if (addedCount == 0 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bạn đã có đủ các gợi ý này rồi!')));
        }
      } else {
        String aiText = '✨ [AI Gợi ý lần $_aiClickCount]:\n$currentContent';
        if (!_contentController.text.contains(currentContent)) {
          if (_contentController.text.isNotEmpty) {
            _contentController.text += '\n\n';
          }
          _contentController.text += aiText;
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nội dung này đã được gợi ý rồi!')));
        }
      }
    });

    if(mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✨ AI đã tạo xong (Gợi ý mẫu số ${_aiClickCount})!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.note == null ? 'Tạo ghi chú' : 'Sửa ghi chú', style: const TextStyle(fontSize: 18)),
        actions: [
          _isAILoading
              ? const Padding(padding: EdgeInsets.all(16.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
              : FilledButton.icon(
            onPressed: _askAI,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Viết bằng AI'),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade400),
          ),
          const SizedBox(width: 8),
          IconButton(icon: const Icon(Icons.check), onPressed: _saveNote),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(hintText: 'Nhập tiêu đề (VD: Đi siêu thị)', border: InputBorder.none),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                  child: DropdownButton<String>(
                    value: _selectedLabel,
                    underline: const SizedBox(),
                    icon: const Icon(Icons.arrow_drop_down, size: 20),
                    items: AppState.labels.map((l) => DropdownMenuItem(value: l, child: Text(l, style: const TextStyle(fontSize: 14)))).toList(),
                    onChanged: (val) => setState(() => _selectedLabel = val!),
                  ),
                ),
                const Spacer(),
                const Text('To-do', style: TextStyle(color: Colors.grey)),
                Switch(
                  value: _isTodo,
                  onChanged: (val) => setState(() => _isTodo = val),
                  activeColor: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
            const Divider(height: 30),
            Expanded(child: _isTodo ? _buildTodoList() : _buildTextContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildTextContent() {
    return TextField(
      controller: _contentController,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      style: const TextStyle(fontSize: 16, height: 1.6),
      decoration: const InputDecoration(hintText: 'Bắt đầu nhập nội dung...', border: InputBorder.none),
    );
  }

  Widget _buildTodoList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: _todos.length,
            itemBuilder: (context, index) {
              return Row(
                children: [
                  Checkbox(
                    value: _todos[index].isDone,
                    onChanged: (val) => setState(() => _todos[index].isDone = val!),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  Expanded(
                    child: TextFormField(
                      initialValue: _todos[index].task,
                      onChanged: (val) => _todos[index].task = val,
                      style: TextStyle(
                        decoration: _todos[index].isDone ? TextDecoration.lineThrough : null,
                        color: _todos[index].isDone ? Colors.grey : Colors.black,
                      ),
                      decoration: const InputDecoration(border: InputBorder.none, hintText: 'Nhập công việc'),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close, color: Colors.grey, size: 20), onPressed: () => setState(() => _todos.removeAt(index)))
                ],
              );
            },
          ),
        ),
        TextButton.icon(
          onPressed: () => setState(() => _todos.add(TodoItem(task: ''))),
          icon: const Icon(Icons.add),
          label: const Text('Thêm mục'),
        )
      ],
    );
  }
}