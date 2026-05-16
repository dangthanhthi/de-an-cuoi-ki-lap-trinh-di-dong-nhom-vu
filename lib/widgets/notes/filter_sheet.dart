import 'package:flutter/material.dart';
import '../../controllers/note_provider.dart';
import '../../models/app_models.dart';

class FilterSheet extends StatefulWidget {
  final NoteProvider provider;

  const FilterSheet({super.key, required this.provider});

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late TextEditingController _creatorCtrl;
  late TextEditingController _assigneeCtrl;

  @override
  void initState() {
    super.initState();
    _creatorCtrl = TextEditingController(text: widget.provider.filterCreator);
    _assigneeCtrl = TextEditingController(text: widget.provider.filterAssignee);
  }

  @override
  void dispose() {
    _creatorCtrl.dispose();
    _assigneeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ListView(
          controller: scrollController,
          children: [
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Tìm kiếm nâng cao',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    provider.resetFilters();
                    _creatorCtrl.clear();
                    _assigneeCtrl.clear();
                    setState(() {});
                  },
                  child: const Text('Đặt lại'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            _SectionTitle('Thông tin người dùng'),
            TextField(
              controller: _creatorCtrl,
              decoration: InputDecoration(
                labelText: 'Người tạo',
                hintText: 'Tên hoặc email...',
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onChanged: (val) => provider.filterCreator = val,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _assigneeCtrl,
              decoration: InputDecoration(
                labelText: 'Người được giao',
                hintText: 'Tên hoặc email...',
                prefixIcon: const Icon(Icons.assignment_ind_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onChanged: (val) => provider.filterAssignee = val,
            ),
            
            const SizedBox(height: 24),
            _SectionTitle('Thời gian'),
            Row(
              children: [
                Expanded(
                  child: _DateTile(
                    label: 'Ngày tạo',
                    date: provider.filterCreatedDate,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => provider.filterCreatedDate = picked);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateTile(
                    label: 'Deadline',
                    date: provider.filterDeadline,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => provider.filterDeadline = picked);
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
            _SectionTitle('Mức độ ưu tiên'),
            Wrap(
              spacing: 8,
              children: ['all', NotePriority.low, NotePriority.medium, NotePriority.high, NotePriority.urgent].map((p) {
                final isSelected = provider.filterPriority == p;
                return ChoiceChip(
                  label: Text(p == 'all' ? 'Tất cả' : NotePriority.label(p)),
                  selected: isSelected,
                  onSelected: (selected) => setState(() => provider.filterPriority = p),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),
            _SectionTitle('Loại ghi chú & Trạng thái'),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _ChipGroup(
                    label: 'Loại',
                    options: const ['all', 'note', 'todo'],
                    labels: const {'all': 'Tất cả', 'note': 'Văn bản', 'todo': 'Công việc'},
                    current: provider.filterNoteType,
                    onSelected: (val) => setState(() => provider.filterNoteType = val),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            _SectionTitle('Tùy chọn khác'),
            SwitchListTile(
              title: const Text('Chỉ hiện ghi chú đã ghim'),
              value: provider.filterIsPinned ?? false,
              onChanged: (val) => setState(() => provider.filterIsPinned = val ? true : null),
            ),
            SwitchListTile(
              title: const Text('Có tệp đính kèm'),
              value: provider.filterHasAttachments ?? false,
              onChanged: (val) => setState(() => provider.filterHasAttachments = val ? true : null),
            ),

            const SizedBox(height: 32),
            FilledButton(
              onPressed: () {
                provider.refresh();
                Navigator.pop(context);
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Áp dụng bộ lọc'),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
    );
  }
}

class _DateTile extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  const _DateTile({required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(date == null ? 'Bất kỳ' : '${date!.day}/${date!.month}/${date!.year}', 
                 style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _ChipGroup extends StatelessWidget {
  final String label;
  final List<String> options;
  final Map<String, String> labels;
  final String current;
  final Function(String) onSelected;

  const _ChipGroup({required this.label, required this.options, required this.labels, required this.current, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: options.map((opt) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(labels[opt] ?? opt),
          selected: current == opt,
          onSelected: (s) => onSelected(opt),
        ),
      )).toList(),
    );
  }
}
