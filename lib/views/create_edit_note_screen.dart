import 'package:flutter/material.dart';
import 'dart:math';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../models/app_models.dart';
import '../controllers/app_state.dart';
import '../controllers/notification_service.dart';

class CreateEditNoteScreen extends StatefulWidget {
  final Note? note;
  final String? docId;
  const CreateEditNoteScreen({super.key, this.note, this.docId});

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

  // --- BIẾN CHO TÍNH NĂNG MỚI ---
  bool _hasReminder = false;
  DateTime? _selectedReminderTime;
  List<String> _attachments = [];
  bool _isUploading = false;

  final List<Color> _noteColors = [
    Colors.blue.shade100, Colors.red.shade100, Colors.green.shade100, Colors.orange.shade100,
    Colors.purple.shade100, Colors.yellow.shade100, Colors.teal.shade100, Colors.pink.shade100,
  ];
  late Color _selectedColor;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController = TextEditingController(text: widget.note?.content ?? '');
    _selectedColor = widget.note?.coverColor ?? _noteColors.first;

    if (widget.note != null) {
      _selectedLabel = widget.note!.label;
      _isTodo = widget.note!.isTodo;
      _todos = widget.note!.todos.map((t) => TodoItem(task: t.task, isDone: t.isDone)).toList();
      _hasReminder = widget.note!.hasReminder;
      _selectedReminderTime = widget.note!.reminderTime;
      _attachments = List.from(widget.note!.attachments);
    }
  }

  // Hàm chọn ngày giờ
  Future<void> _pickReminderTime() async {
    DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedReminderTime ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );

    if (pickedDate != null && mounted) {
      TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedReminderTime ?? DateTime.now()),
      );

      if (pickedTime != null) {
        setState(() {
          _selectedReminderTime = DateTime(
            pickedDate.year, pickedDate.month, pickedDate.day,
            pickedTime.hour, pickedTime.minute,
          );
          _hasReminder = true;
        });
      } else {
        // Nếu người dùng hủy chọn giờ, tắt công tắc hẹn giờ
        setState(() => _hasReminder = false);
      }
    } else {
      setState(() => _hasReminder = false);
    }
  }

  void _saveNote() async {
    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập tiêu đề')));
      return;
    }

    final noteData = Note(
      id: widget.note?.id ?? "",
      title: _titleController.text,
      content: _contentController.text,
      label: _selectedLabel,
      date: widget.note?.date ?? DateTime.now().toString().substring(0, 10),
      isTodo: _isTodo,
      todos: _todos,
      sharedWith: widget.note?.sharedWith ?? [],
      coverColor: _selectedColor,
      hasReminder: _hasReminder,
      reminderTime: _selectedReminderTime,
      attachments: _attachments,
    );

    final navigator = Navigator.of(context);
    final scaffoldMsg = ScaffoldMessenger.of(context);

    try {
      if (widget.note == null) {
        await FirebaseService.addNote(noteData);
        scaffoldMsg.showSnackBar(const SnackBar(content: Text('Đã tạo ghi chú mới!')));
      } else {
        await FirebaseService.updateNote(widget.note!.id, noteData);
        scaffoldMsg.showSnackBar(const SnackBar(content: Text('Đã cập nhật thay đổi!')));
      }

      // --- KÍCH HOẠT BÁO THỨC TẠI ĐÂY ---
      if (_hasReminder && _selectedReminderTime != null) {
        await NotificationService.scheduleNotification(
          id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
          title: 'SNote Nhắc Nhở: ${_titleController.text}',
          body: _contentController.text.isNotEmpty ? _contentController.text : 'Đến giờ thực hiện công việc rồi!',
          scheduledTime: _selectedReminderTime!,
        );
      }

      if (mounted) navigator.pop();
    } catch (e) {
      scaffoldMsg.showSnackBar(SnackBar(content: Text('Lỗi khi lưu: $e')));
    }
  }

  void _askAI() async {
    String title = _titleController.text.trim().toLowerCase();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bạn phải nhập tiêu đề để AI có manh mối phân tích nhé!')));
      return;
    }

    if (_lastAITitle != title) {
      _lastAITitle = title;
      _aiClickCount = 0;
    }

    setState(() => _isAILoading = true);
    await Future.delayed(Duration(milliseconds: 1200 + Random().nextInt(1000)));

    List<String> generatedTodos = [];
    String generatedContent = "";

    if (title.contains('họp') || title.contains('meeting') || title.contains('thảo luận') || title.contains('báo cáo')) {
      generatedTodos = ['Chuẩn bị tài liệu/Slide thuyết trình', 'Gửi lịch mời (Calendar) cho người tham gia', 'Đặt phòng họp/Tạo link Google Meet', 'Chuẩn bị sổ bút để ghi biên bản (Minutes)', 'Tổng hợp số liệu tuần trước', 'Gửi email tóm tắt (Recap) sau khi họp xong'];
      generatedContent = '🎯 Mục tiêu cuộc họp:\n- Đồng bộ tiến độ công việc giữa các thành viên.\n- Giải quyết các vướng mắc (Blockers).\n\n📌 Agenda dự kiến:\n1. Review công việc đã qua (10p)\n2. Thảo luận vấn đề cốt lõi (30p)\n3. Chốt Next steps & Phân công người chịu trách nhiệm (10p)';
    }
    else if (title.contains('mua') || title.contains('chợ') || title.contains('siêu thị') || title.contains('shopping')) {
      generatedTodos = ['Lên trước danh sách đồ cần mua để tránh quên', 'Mang theo túi vải bảo vệ môi trường', 'Kiểm tra mã giảm giá (Voucher/Coupon)', 'Rút tiền mặt phòng hờ', 'Mua đồ tươi sống trước, đồ khô sau'];
      generatedContent = '🛒 Ghi chú mua sắm:\n- Nên ăn no trước khi đi siêu thị để tránh mua sắm bốc đồng.\n- Kiểm tra kỹ hạn sử dụng (Date) của sản phẩm.\n- Cân nhắc mua đồ dự trữ đóng hộp nếu có khuyến mãi tốt.';
    }
    else if (title.contains('học') || title.contains('thi') || title.contains('bài tập') || title.contains('đồ án') || title.contains('luận văn')) {
      generatedTodos = ['Đọc lại toàn bộ slide bài giảng', 'Tóm tắt các ý chính ra giấy (Sơ đồ tư duy)', 'Giải thử đề thi năm ngoái', 'Hỏi lại thầy/bạn bè những chỗ chưa hiểu', 'Tắt Wifi điện thoại trong 2 tiếng', 'Lên thư viện mượn thêm sách tham khảo'];
      generatedContent = '📚 Kế hoạch học tập hiệu quả:\n- Áp dụng phương pháp Pomodoro (25p học tập trung, 5p nghỉ ngơi).\n- Dọn dẹp góc học tập cho gọn gàng để tăng cảm hứng.\n- Đặt mục tiêu: Hoàn thành ít nhất 80% khối lượng bài hôm nay.';
    }
    else if (title.contains('đi chơi') || title.contains('du lịch') || title.contains('phượt') || title.contains('bay') || title.contains('chuyến đi')) {
      generatedTodos = ['Lên lịch trình chi tiết cho từng ngày', 'Đặt vé máy bay/xe khách sớm để có giá tốt', 'Book phòng khách sạn/Homestay (Agoda/Booking)', 'Sắp xếp hành lý (Quần áo, sạc dự phòng)', 'Chuẩn bị túi thuốc y tế cơ bản', 'Mang theo giấy tờ tùy thân (CCCD/Passport)'];
      generatedContent = '✈️ Cẩm nang chuyến đi:\n- Lưu ý check-in và check-out khách sạn đúng giờ.\n- Tìm hiểu trước các quán ăn đặc sản địa phương (Local food).\n- Mang theo ô/dù và kem chống nắng để đối phó với thời tiết thất thường.';
    }
    else if (title.contains('tập') || title.contains('gym') || title.contains('chạy') || title.contains('giảm cân') || title.contains('thể thao')) {
      generatedTodos = ['Khởi động thật kỹ các khớp (10-15p)', 'Chuẩn bị bình nước và khăn lau mồ hôi', 'Tập theo giáo án chuẩn bị sẵn', 'Giãn cơ sau khi tập (Stretching) để chống đau mỏi', 'Cân đo lại chỉ số cơ thể đầu ngày'];
      generatedContent = '💪 Kế hoạch rèn luyện cơ thể:\n- Tuyệt đối không bỏ bữa, ưu tiên ăn đủ đạm (Protein) để phục hồi.\n- Cố gắng ngủ đủ 7-8 tiếng mỗi đêm.\n- Lắng nghe cơ thể, nếu thấy đau nhói thì phải dừng tập ngay (Tránh chấn thương).';
    }
    else if (title.contains('code') || title.contains('bug') || title.contains('fix') || title.contains('lập trình') || title.contains('app') || title.contains('flutter')) {
      generatedTodos = ['Tái hiện lại lỗi (Reproduce bug) để xem nó nằm ở đâu', 'Đọc kỹ Terminal/Log lỗi', 'Tìm kiếm giải pháp trên StackOverflow hoặc Google', 'Commit code hiện tại trước khi sửa', 'Xóa cache và Restart lại App', 'Nhờ đồng đội review code'];
      generatedContent = '💻 Kế hoạch Lập trình:\n- Chia nhỏ chức năng phức tạp thành các task bé hơn.\n- Đừng quên Commit và Push code lên Github thường xuyên.\n- Viết comment giải thích logic ở những file quan trọng để sau này dễ đọc lại.';
    }
    else {
      generatedTodos = ['Phân tích yêu cầu chi tiết', 'Chia nhỏ công việc (Breakdown task)', 'Bắt tay vào làm từ việc dễ nhất', 'Kiểm tra lại toàn bộ và hoàn thiện', 'Nhờ người khác đánh giá giúp'];
      generatedContent = '✨ Gợi ý để hoàn thành mục tiêu "${_titleController.text}":\n- Xác định rõ kết quả cuối cùng bạn muốn đạt được là gì.\n- Đặt một Deadline cụ thể để không bị trì hoãn.\n- Hành động ngay hôm nay, bắt đầu từ những bước nhỏ nhất.';
    }

    generatedTodos.shuffle();
    int taskCount = min(3, generatedTodos.length);
    List<String> finalTodos = generatedTodos.sublist(0, taskCount);

    setState(() {
      _isAILoading = false;
      _aiClickCount++;

      if (_isTodo) {
        int addedCount = 0;
        for (var task in finalTodos) {
          if (!_todos.any((t) => t.task.toLowerCase() == task.toLowerCase())) {
            _todos.add(TodoItem(task: task));
            addedCount++;
          }
        }
        if (addedCount == 0 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI thấy các ý tưởng này đã có sẵn trong danh sách của bạn rồi!')));
        }
      } else {
        String aiText = '✨ [AI Phân tích lần $_aiClickCount]:\n$generatedContent';

        if (!_contentController.text.contains(generatedContent.substring(0, 15))) {
          if (_contentController.text.isNotEmpty) _contentController.text += '\n\n';
          _contentController.text += aiText;
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nội dung này đã được AI viết cho bạn rồi, hãy nhập tiêu đề khác nhé!')));
        }
      }
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✨ AI đã phân tích xong tiêu đề của bạn!')));
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
            const Text('Màu sắc ghi chú:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _noteColors.length,
                itemBuilder: (ctx, i) => GestureDetector(
                  onTap: () => setState(() => _selectedColor = _noteColors[i]),
                  child: Container(
                    width: 36, height: 36,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: _noteColors[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: _selectedColor == _noteColors[i] ? Colors.black54 : Colors.transparent,
                          width: 2
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

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
                  activeThumbColor: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),

            // --- GIAO DIỆN HẸN GIỜ ---
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.alarm, color: Colors.blue),
                  const SizedBox(width: 8),
                  const Text('Hẹn giờ báo thức', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  const Spacer(),
                  Switch(
                    value: _hasReminder,
                    activeColor: Colors.blue,
                    onChanged: (val) {
                      if (val) {
                        _pickReminderTime();
                      } else {
                        setState(() {
                          _hasReminder = false;
                          _selectedReminderTime = null;
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
            if (_hasReminder && _selectedReminderTime != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0, left: 12),
                child: Text(
                  'Sẽ đổ chuông vào: ${_selectedReminderTime!.hour.toString().padLeft(2, '0')}:${_selectedReminderTime!.minute.toString().padLeft(2, '0')} - ${_selectedReminderTime!.day}/${_selectedReminderTime!.month}/${_selectedReminderTime!.year}',
                  style: TextStyle(color: Colors.blue.shade800, fontStyle: FontStyle.italic, fontSize: 13),
                ),
              ),

            // --- GIAO DIỆN ĐÍNH KÈM FILE/ẢNH ---
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  tooltip: 'Thêm ảnh',
                  icon: const Icon(Icons.image, color: Colors.green),
                  onPressed: () async {
                    final ImagePicker picker = ImagePicker();
                    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                    if (image != null) {
                      setState(() => _isUploading = true);
                      var bytes = await image.readAsBytes();
                      String? url = await FirebaseService.uploadAttachment(bytes, image.name);
                      if (url != null) setState(() => _attachments.add(url));
                      setState(() => _isUploading = false);
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Thêm tệp (PDF, Doc...)',
                  icon: const Icon(Icons.attach_file, color: Colors.orange),
                  onPressed: () async {
                    FilePickerResult? result = await FilePicker.pickFiles();
                    if (result != null) {
                      setState(() => _isUploading = true);
                      var bytes = result.files.first.bytes;
                      String name = result.files.first.name;
                      if(bytes != null) {
                        String? url = await FirebaseService.uploadAttachment(bytes, name);
                        if (url != null) setState(() => _attachments.add(url));
                      }
                      setState(() => _isUploading = false);
                    }
                  },
                ),
                if (_isUploading) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                if (_attachments.isNotEmpty)
                  Text('  Đã đính kèm ${_attachments.length} tệp', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 20),

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