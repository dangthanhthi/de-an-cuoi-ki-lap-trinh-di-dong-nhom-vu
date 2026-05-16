import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../controllers/app_state.dart';
import '../../controllers/note_provider.dart';
import '../../utils/media_utils.dart';
import '../../views/calendar_screen.dart';
import '../../views/contacts_screen.dart';
import '../../views/groups_list_screen.dart';
import '../../views/statistics_screen.dart';

class SidebarMenu extends StatelessWidget {
  const SidebarMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final noteProvider = Provider.of<NoteProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(
              color: colorScheme.primary,
            ),
            accountName: Text(
              AppState.currentUserName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorScheme.onPrimary,
              ),
            ),
            accountEmail: Text(
              AppState.currentUserEmail,
              style: TextStyle(
                color: colorScheme.onPrimary.withValues(alpha: 0.85),
              ),
            ),
            currentAccountPicture: CircleAvatar(
              backgroundColor: colorScheme.surface,
              backgroundImage: avatarImageProvider(
                AppState.currentUserAvatar,
                name: AppState.currentUserName,
              ),
              radius: 36,
            ),
          ),
          const _DrawerSectionLabel('Ghi chú'),
          _DrawerItem(
            icon: Icons.all_inbox_rounded,
            title: 'Tất cả ghi chú',
            selected: noteProvider.viewMode == 'ALL',
            selectedColor: isDark ? Colors.indigoAccent : Colors.indigo,
            onTap: () {
              noteProvider.setViewMode('ALL');
              Navigator.pop(context);
            },
          ),
          _DrawerItem(
            icon: Icons.person_outline_rounded,
            title: 'Ghi chú của tôi',
            selected: noteProvider.viewMode == 'MY',
            selectedColor: isDark ? Colors.indigoAccent : Colors.indigo,
            onTap: () {
              noteProvider.setViewMode('MY');
              Navigator.pop(context);
            },
          ),
          StreamBuilder<int>(
            stream: FirebaseService.unreadSharedNotesCountStream(),
            builder: (context, sharedCountSnap) {
              return _DrawerItem(
                icon: Icons.people_outline_rounded,
                title: 'Được chia sẻ với tôi',
                selected: noteProvider.viewMode == 'SHARED',
                badgeCount: sharedCountSnap.data ?? 0,
                selectedColor: isDark ? Colors.orangeAccent : Colors.orange,
                onTap: () {
                  noteProvider.setViewMode('SHARED');
                  FirebaseService.markAllSharedNotesAsViewed();
                  Navigator.pop(context);
                },
              );
            },
          ),
          _DrawerItem(
            icon: Icons.assignment_ind_outlined,
            title: 'Nhiệm vụ được giao',
            selected: noteProvider.viewMode == 'ASSIGNED',
            selectedColor: isDark ? Colors.tealAccent : Colors.teal,
            onTap: () {
              noteProvider.setViewMode('ASSIGNED');
              Navigator.pop(context);
            },
          ),
          const Divider(height: 16),
          const _DrawerSectionLabel('Nhóm'),
          StreamBuilder<int>(
            stream: FirebaseService.unreadGroupMessagesCountStream(),
            builder: (context, unreadSnap) {
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseService.getGroupInvitesStream(),
                builder: (context, invitesSnap) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseService.getGroupRequestsForLeaderStream(),
                    builder: (context, requestsSnap) {
                      final total = (invitesSnap.data?.docs.length ?? 0) +
                          (requestsSnap.data?.docs.length ?? 0) +
                          (unreadSnap.data ?? 0);
                      return _DrawerItem(
                        icon: Icons.group_work,
                        title: 'Nhóm của tôi',
                        badgeCount: total,
                        selectedColor: isDark ? Colors.tealAccent : Colors.teal,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const GroupsListScreen(),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
          const Divider(height: 16),
          const _DrawerSectionLabel('Công cụ'),
          _DrawerItem(
            icon: Icons.calendar_month,
            title: 'Lịch biểu',
            selectedColor: isDark ? Colors.deepPurpleAccent : Colors.deepPurple,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CalendarScreen()),
              );
            },
          ),
          _DrawerItem(
            icon: Icons.bar_chart,
            title: 'Thống kê',
            selectedColor: isDark ? Colors.orangeAccent : Colors.orange,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const StatisticsScreen(),
                ),
              );
            },
          ),
          const Divider(height: 16),
          const _DrawerSectionLabel('Liên lạc'),
          StreamBuilder<int>(
            stream: FirebaseService.unreadChatMessagesCountStream(),
            builder: (context, unreadSnap) {
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseService.getFriendRequestsStream(),
                builder: (context, snapshot) {
                  final friendCount = snapshot.data?.docs.length ?? 0;
                  final unreadCount = unreadSnap.data ?? 0;
                  return _DrawerItem(
                    icon: Icons.contacts,
                    title: 'Danh bạ của tôi',
                    badgeCount: friendCount + unreadCount,
                    selectedColor: isDark ? Colors.blueAccent : Colors.blue,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ContactsScreen(),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DrawerSectionLabel extends StatelessWidget {
  final String label;
  const _DrawerSectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool selected;
  final Color selectedColor;
  final int badgeCount;

  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.selected = false,
    required this.selectedColor,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(
        onTap: onTap,
        selected: selected,
        selectedTileColor: selectedColor.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(
          icon,
          color: selected ? selectedColor : colorScheme.onSurfaceVariant,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected ? selectedColor : colorScheme.onSurface,
          ),
        ),
        trailing: badgeCount > 0
            ? Badge(
                label: Text('$badgeCount'),
                backgroundColor: selectedColor,
              )
            : null,
      ),
    );
  }
}
