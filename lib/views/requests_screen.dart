import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../controllers/app_state.dart';
import '../controllers/firebase_service.dart';
import '../utils/media_utils.dart';

class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool success = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green : Theme.of(context).colorScheme.error,
      ),
    );
  }

  Widget _buildTab(String label, Stream<QuerySnapshot> stream) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return Tab(
          child: Badge(
            label: Text('$count'),
            isLabelVisible: count > 0,
            child: Text(label),
          ),
        );
      },
    );
  }

  Widget _buildGroupTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.getGroupInvitesStream(),
      builder: (context, invitesSnap) {
        final invitesCount = invitesSnap.data?.docs.length ?? 0;
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseService.getGroupRequestsForLeaderStream(),
          builder: (context, requestsSnap) {
            final requestsCount = requestsSnap.data?.docs.length ?? 0;
            final total = invitesCount + requestsCount;
            return Tab(
              child: Badge(
                label: Text('$total'),
                isLabelVisible: total > 0,
                child: const Text('Nhóm'),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thông báo & Yêu cầu'),
        bottom: TabBar(
          controller: _tabController,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
          tabs: [
            _buildTab('Ghi chú', FirebaseService.getNoteInvitesStream()),
            _buildGroupTab(),
            _buildTab('Bạn bè', FirebaseService.getFriendRequestsStream()),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildNoteInvitesTab(),
          _buildGroupInvitesTab(),
          _buildFriendRequestsTab(),
        ],
      ),
    );
  }

  Widget _buildNoteInvitesTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.getNoteInvitesStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const _EmptyState(
            icon: Icons.note_add_outlined,
            text: 'Không có lời mời chia sẻ ghi chú nào.',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final colorScheme = Theme.of(context).colorScheme;

            return Card(
              elevation: 0,
              color: colorScheme.surfaceContainerLow,
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.description_outlined,
                    color: colorScheme.primary,
                  ),
                ),
                title: Text(
                  data['noteTitle'] ?? 'Ghi chú',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('Từ: ${data['fromName'] ?? data['fromEmail']}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.filledTonal(
                      icon: const Icon(Icons.check),
                      onPressed: () async {
                        final res = await FirebaseService.respondToNoteInvite(
                          doc.id,
                          true,
                        );
                        _showSnack(
                          res == 'SUCCESS' ? 'Đã chấp nhận lời mời chia sẻ ghi chú' : res,
                          success: res == 'SUCCESS',
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.close),
                      style: IconButton.styleFrom(
                        foregroundColor: colorScheme.error,
                      ),
                      onPressed: () async {
                        final res = await FirebaseService.respondToNoteInvite(
                          doc.id,
                          false,
                        );
                        _showSnack(
                          res == 'SUCCESS' ? 'Đã từ chối lời mời chia sẻ ghi chú' : res,
                          success: res == 'SUCCESS',
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildGroupInvitesTab() {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseService.getGroupInvitesStream(),
            builder: (context, snapshot) {
              final invites = snapshot.data?.docs ?? [];
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseService.getGroupRequestsForLeaderStream(),
                builder: (context, leaderSnap) {
                  final joinRequests = leaderSnap.data?.docs ?? [];
                  final all = [...invites, ...joinRequests];

                  if (all.isEmpty) {
                    return const _EmptyState(
                      icon: Icons.group_add_outlined,
                      text: 'Không có lời mời hoặc yêu cầu vào nhóm nào.',
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: all.length,
                    itemBuilder: (context, index) {
                      final doc = all[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final colorScheme = Theme.of(context).colorScheme;
                      final isJoinRequest = joinRequests.contains(doc);

                      return Card(
                        elevation: 0,
                        color: colorScheme.surfaceContainerLow,
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isJoinRequest
                                  ? colorScheme.tertiaryContainer
                                  : colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isJoinRequest
                                  ? Icons.person_add_alt_1_outlined
                                  : Icons.groups_outlined,
                              color: isJoinRequest
                                  ? colorScheme.tertiary
                                  : colorScheme.secondary,
                            ),
                          ),
                          title: Text(
                            isJoinRequest
                                ? 'Yêu cầu vào nhóm: ${data['groupName']}'
                                : (data['groupName'] ?? 'Nhóm'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            isJoinRequest
                                ? 'Từ: ${data['userName']} (${data['userEmail']})'
                                : 'Mời bởi: ${data['fromName'] ?? data['fromEmail']}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton.filledTonal(
                                icon: const Icon(Icons.check),
                                onPressed: () async {
                                  if (isJoinRequest) {
                                    final res = await FirebaseService.respondToGroupRequest(
                                      doc.id,
                                      true,
                                    );
                                    _showSnack(
                                      res == 'SUCCESS' ? 'Đã chấp nhận thành viên' : res,
                                      success: res == 'SUCCESS',
                                    );
                                  } else {
                                    final res = await FirebaseService.respondToGroupInvite(
                                      doc.id,
                                      true,
                                    );
                                    _showSnack(
                                      res == 'SUCCESS' ? 'Đã chấp nhận lời mời vào nhóm' : res,
                                      success: res == 'SUCCESS',
                                    );
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              IconButton.filledTonal(
                                icon: const Icon(Icons.close),
                                style: IconButton.styleFrom(
                                  foregroundColor: colorScheme.error,
                                ),
                                onPressed: () async {
                                  if (isJoinRequest) {
                                    final res = await FirebaseService.respondToGroupRequest(
                                      doc.id,
                                      false,
                                    );
                                    _showSnack(
                                      res == 'SUCCESS' ? 'Đã từ chối yêu cầu thành viên' : res,
                                      success: res == 'SUCCESS',
                                    );
                                  } else {
                                    final res = await FirebaseService.respondToGroupInvite(
                                      doc.id,
                                      false,
                                    );
                                    _showSnack(
                                      res == 'SUCCESS' ? 'Đã từ chối lời mời vào nhóm' : res,
                                      success: res == 'SUCCESS',
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFriendRequestsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.getFriendRequestsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const _EmptyState(
            icon: Icons.person_add_outlined,
            text: 'Không có lời mời kết bạn nào.',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final colorScheme = Theme.of(context).colorScheme;

            return Card(
              elevation: 0,
              color: colorScheme.surfaceContainerLow,
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: CircleAvatar(
                  backgroundImage: avatarImageProvider(
                    data['fromAvatar'] ?? '',
                    name: data['fromName'] ?? data['fromEmail'],
                  ),
                ),
                title: Text(
                  data['fromName'] ?? 'Người dùng',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(data['fromEmail'] ?? ''),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.filledTonal(
                      icon: const Icon(Icons.check),
                      onPressed: () async {
                        final res = await FirebaseService.acceptFriendRequest(
                          doc.id,
                          data,
                        );
                        _showSnack(
                          res == 'SUCCESS' ? 'Đã kết bạn thành công' : res,
                          success: res == 'SUCCESS',
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.close),
                      style: IconButton.styleFrom(
                        foregroundColor: colorScheme.error,
                      ),
                      onPressed: () async {
                        final res = await FirebaseService.rejectFriendRequest(doc.id);
                        _showSnack(
                          res == 'SUCCESS' ? 'Đã từ chối lời mời kết bạn' : res,
                          success: res == 'SUCCESS',
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EmptyState({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 48,
              color: colorScheme.primary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}




