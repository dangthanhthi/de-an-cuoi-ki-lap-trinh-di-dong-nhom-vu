import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/app_state.dart';
import '../../controllers/note_provider.dart';

class FilterSection extends StatelessWidget {
  final VoidCallback onShowAdvancedFilters;
  final VoidCallback onShowSort;

  const FilterSection({
    super.key,
    required this.onShowAdvancedFilters,
    required this.onShowSort,
  });

  @override
  Widget build(BuildContext context) {
    final noteProvider = Provider.of<NoteProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: TextField(
            onChanged: (val) => noteProvider.setSearchQuery(val),
            decoration: InputDecoration(
              hintText: 'Tìm kiếm ghi chú, công việc...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: noteProvider.searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () => noteProvider.setSearchQuery(''),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),

        // Advanced Filter & Sort Buttons
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              _FilterActionButton(
                icon: Icons.tune_rounded,
                label: 'Bộ lọc',
                onTap: onShowAdvancedFilters,
                isActive: _hasActiveAdvancedFilters(noteProvider),
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              _FilterActionButton(
                icon: Icons.sort_rounded,
                label: 'Sắp xếp',
                onTap: onShowSort,
                color: colorScheme.secondary,
              ),
            ],
          ),
        ),

        // Active Filters Badges (if any)
        if (_hasActiveAdvancedFilters(noteProvider))
          _ActiveFiltersBar(noteProvider: noteProvider),

        // Label Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Row(
            children: [AppState.selectedLabel, ...AppState.labels].map((label) {
              final isSelected = noteProvider.selectedLabel == label;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(label),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) noteProvider.setSelectedLabel(label);
                  },
                  selectedColor: colorScheme.primaryContainer,
                  checkmarkColor: colorScheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  bool _hasActiveAdvancedFilters(NoteProvider provider) {
    return provider.filterCreator.isNotEmpty ||
        provider.filterAssignee.isNotEmpty ||
        provider.filterCreatedDate != null ||
        provider.filterDeadline != null ||
        provider.filterHasAttachments != null ||
        provider.filterTodoStatus != 'all' ||
        provider.filterPriority != 'all' ||
        provider.filterNoteType != 'all' ||
        provider.filterIsPinned != null ||
        provider.filterHasReminder != null;
  }
}

class _FilterActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;
  final Color color;

  const _FilterActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveColor = isActive ? colorScheme.primary : color;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? effectiveColor.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? effectiveColor : colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: effectiveColor),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: effectiveColor,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 6),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: effectiveColor,
                  shape: BoxShape.circle,
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}

class _ActiveFiltersBar extends StatelessWidget {
  final NoteProvider noteProvider;
  const _ActiveFiltersBar({required this.noteProvider});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final badges = _getBadges();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 14, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                'Đang lọc (${badges.length})',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => noteProvider.resetFilters(),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                child: const Text('Xóa tất cả', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: badges.map((badge) {
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _getBadges() {
    final badges = <String>[];
    if (noteProvider.filterCreator.isNotEmpty) badges.add('Người tạo: ${noteProvider.filterCreator}');
    if (noteProvider.filterPriority != 'all') badges.add('Ưu tiên: ${noteProvider.filterPriority}');
    if (noteProvider.filterNoteType != 'all') badges.add('Loại: ${noteProvider.filterNoteType}');
    // Add more as needed
    return badges;
  }
}
