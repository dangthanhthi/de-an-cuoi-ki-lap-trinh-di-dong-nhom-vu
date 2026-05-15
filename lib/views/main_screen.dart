import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../controllers/app_state.dart';
import '../controllers/notification_service.dart';
import '../models/app_models.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final List<StreamSubscription> _subscriptions = [];
  final Map<String, StreamSubscription> _groupNoteSubscriptions = {};
  final Set<String> _seenFriendRequests = {};
  Timer? _presenceTimer;
  final Set<String> _seenSharedNotes = {};
  final Set<String> _seenGroupNotes = {};
  final Set<String> _seenOverdueTodos = {};
  final Set<String> _seenNoteInvites = {};
  final Set<String> _seenGroupInvites = {};
  final Set<String> _seenGroupRequests = {};
  final Map<String, int> _chatUnreadCounts = {};
  final Map<String, int> _groupUnreadCounts = {};
  bool _handledForcedLogout = false;

  final List<Widget> _screens = const [HomeScreen(), ProfileScreen()];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _watchRealtimeNotifications();
      _startPresenceHeartbeat();
      _showLoginSummary();
    });
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    for (final subscription in _groupNoteSubscriptions.values) {
      subscription.cancel();
    }
    _presenceTimer?.cancel();
    super.dispose();
  }

  void _watchRealtimeNotifications() {
    if (AppState.currentUserEmail.isEmpty) return;

    _subscriptions.add(
      FirebaseService.getUserProfileStream().listen((snapshot) async {
        if (!mounted || _handledForcedLogout) return;
        if (!snapshot.exists) {
          await _forceLogout('Tài khoản của bạn đã bị xóa khỏi hệ thống.');
          return;
        }

        final data = snapshot.data() as Map<String, dynamic>? ?? {};
        if (data['isDeleted'] == true) {
          await _forceLogout('Tài khoản của bạn đã bị xóa khỏi hệ thống.');
          return;
        }
        if (data['isBanned'] == true) {
          await _forceLogout('Tài khoản của bạn đã bị khóa bởi Admin.');
          return;
        }

        AppState.currentUserName = (data['name'] ?? AppState.currentUserName)
            .toString();
        AppState.currentUserAvatar =
            (data['avatar'] ?? AppState.currentUserAvatar).toString();
        AppState.currentUserRole = (data['role'] ?? AppState.currentUserRole)
            .toString();
        if (data['settings'] is Map<String, dynamic>) {
          AppState.applyUserSettings(data['settings'] as Map<String, dynamic>);
        }
      }),
    );

    _subscriptions.add(
      FirebaseService.getMyNotesStream().listen((snapshot) async {
        await _notifyOverdueTodos(snapshot.docs);
      }),
    );

    _subscriptions.add(
      FirebaseService.getFriendRequestsStream().listen((snapshot) async {
        if (_seenFriendRequests.isEmpty) {
          _seenFriendRequests.addAll(snapshot.docs.map((doc) => doc.id));
          return;
        }

        for (final doc in snapshot.docs) {
          if (!_seenFriendRequests.add(doc.id)) continue;
          final data = doc.data() as Map<String, dynamic>;
          final fromEmail = (data['from'] ?? '').toString();
          if (await FirebaseService.isTargetMuted(
            type: 'user',
            targetId: fromEmail,
          )) {
            continue;
          }
          await NotificationService.showNow(
            id: doc.id.hashCode,
            title: 'Lời mời kết bạn mới',
            body: '${data['fromName'] ?? fromEmail} muốn kết bạn với bạn',
          );
        }
      }),
    );

    _subscriptions.add(
      FirebaseService.getSharedNotesStream().listen((snapshot) async {
        await _notifyOverdueTodos(snapshot.docs);
        if (_seenSharedNotes.isEmpty) {
          _seenSharedNotes.addAll(snapshot.docs.map((doc) => doc.id));
          return;
        }

        for (final doc in snapshot.docs) {
          if (!_seenSharedNotes.add(doc.id)) continue;
          final data = doc.data() as Map<String, dynamic>;
          final ownerEmail = (data['createdByEmail'] ?? '').toString();
          if (ownerEmail == AppState.currentUserEmail.toLowerCase().trim()) {
            continue;
          }
          if (await FirebaseService.isTargetMuted(
            type: 'user',
            targetId: ownerEmail,
          )) {
            continue;
          }
          await NotificationService.showNow(
            id: doc.id.hashCode,
            title: 'Bạn có ghi chú mới',
            body: data['title'] ?? 'Một ghi chú vừa được chia sẻ với bạn',
          );
        }
      }),
    );

    _subscriptions.add(
      FirebaseService.getNoteInvitesStream().listen((snapshot) async {
        if (_seenNoteInvites.isEmpty) {
          _seenNoteInvites.addAll(snapshot.docs.map((doc) => doc.id));
          return;
        }
        for (final doc in snapshot.docs) {
          if (!_seenNoteInvites.add(doc.id)) continue;
          final data = doc.data() as Map<String, dynamic>;
          await NotificationService.showNow(
            id: doc.id.hashCode,
            title: 'Lời mời cộng tác',
            body: '${data['fromName'] ?? 'Ai đó'} mời bạn cộng tác trong ghi chú: ${data['noteTitle'] ?? ''}',
          );
        }
      }),
    );

    _subscriptions.add(
      FirebaseService.getMyGroupsStream().listen((snapshot) {
        for (final groupDoc in snapshot.docs) {
          final groupData = groupDoc.data() as Map<String, dynamic>;
          final groupId = groupDoc.id;
          final myEmail = AppState.currentUserEmail.toLowerCase().trim();
          
          // Watch for unread message notifications in groups
          final unread = (groupData['unreadCount']?[myEmail] ?? 0) as int;
          final lastUnread = _groupUnreadCounts[groupId] ?? 0;
          if (unread > lastUnread && unread > 0) {
            final lastMsg = groupData['lastMessage'] ?? 'Tin nhắn mới trong nhóm';
            final lastSender = groupData['lastSender'] ?? '';
            if (lastSender != myEmail) {
              FirebaseService.isTargetMuted(
                type: 'group',
                targetId: groupId,
              ).then((isMuted) {
                if (!isMuted) {
                  NotificationService.showNow(
                    id: groupId.hashCode,
                    title: 'Tin nhắn nhóm: ${groupData['name'] ?? 'Nhóm'}',
                    body: lastMsg,
                  );
                }
              });
            }
          }
          _groupUnreadCounts[groupId] = unread;

          if (_groupNoteSubscriptions.containsKey(groupId)) continue;
          bool firstSnapshot = true;
          _groupNoteSubscriptions[groupId] = FirebaseService.getGroupNotesStream(groupId).listen((
            notesSnapshot,
          ) async {
            await _notifyOverdueTodos(
              notesSnapshot.docs,
              isGroupLeader: groupData['leaderId'] == FirebaseService.currentUid,
              groupName: (groupData['name'] ?? '').toString(),
            );
            if (firstSnapshot) {
              _seenGroupNotes.addAll(notesSnapshot.docs.map((doc) => doc.id));
              firstSnapshot = false;
              return;
            }
            for (final noteDoc in notesSnapshot.docs) {
              if (!_seenGroupNotes.add(noteDoc.id)) continue;
              final data = noteDoc.data() as Map<String, dynamic>;
              if ((data['createdByEmail'] ?? '').toString() ==
                  AppState.currentUserEmail.toLowerCase().trim()) {
                continue;
              }
              if (await FirebaseService.isTargetMuted(
                type: 'group',
                targetId: groupId,
              )) {
                continue;
              }
              await NotificationService.showNow(
                id: noteDoc.id.hashCode,
                title: 'Ghi chú mới trong ${groupData['name'] ?? 'nhóm'}',
                body: data['title'] ?? 'Nhóm vừa có ghi chú mới',
              );
            }
          });
        }
      }),
    );

    // Watch for unread private chat notifications
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    _subscriptions.add(
      FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: myEmail)
          .snapshots()
          .listen((snapshot) {
        for (var doc in snapshot.docs) {
          final data = doc.data();
          final unread = (data['unreadCount']?[myEmail] ?? 0) as int;
          final chatId = doc.id;
          final lastUnread = _chatUnreadCounts[chatId] ?? 0;

          if (unread > lastUnread && unread > 0) {
            final lastMsg = data['lastMessage'] ?? 'Bạn có tin nhắn mới';
            final lastSender = data['lastSender'] ?? '';
            if (lastSender != myEmail && lastSender.isNotEmpty) {
              FirebaseService.isTargetMuted(
                type: 'user',
                targetId: lastSender,
              ).then((isMuted) {
                if (!isMuted) {
                  NotificationService.showNow(
                    id: chatId.hashCode,
                    title: 'Tin nhắn mới',
                    body: lastMsg,
                  );
                }
              });
            }
          }
          _chatUnreadCounts[chatId] = unread;
        }
      }),
    );

    _subscriptions.add(
      FirebaseService.getGroupInvitesStream().listen((snapshot) async {
        if (_seenGroupInvites.isEmpty) {
          _seenGroupInvites.addAll(snapshot.docs.map((doc) => doc.id));
          return;
        }
        for (final doc in snapshot.docs) {
          if (!_seenGroupInvites.add(doc.id)) continue;
          final data = doc.data() as Map<String, dynamic>;
          await NotificationService.showNow(
            id: doc.id.hashCode,
            title: 'Lời mời vào nhóm',
            body: '${data['fromName'] ?? 'Ai đó'} mời bạn vào nhóm: ${data['groupName'] ?? ''}',
          );
        }
      }),
    );

    _subscriptions.add(
      FirebaseService.getGroupRequestsForLeaderStream().listen((snapshot) async {
        if (_seenGroupRequests.isEmpty) {
          _seenGroupRequests.addAll(snapshot.docs.map((doc) => doc.id));
          return;
        }
        for (final doc in snapshot.docs) {
          if (!_seenGroupRequests.add(doc.id)) continue;
          final data = doc.data() as Map<String, dynamic>;
          await NotificationService.showNow(
            id: doc.id.hashCode,
            title: 'Yêu cầu vào nhóm mới',
            body: '${data['userName'] ?? 'Ai đó'} muốn tham gia nhóm: ${data['groupName'] ?? ''}',
          );
        }
      }),
    );
  }

  Future<void> _showLoginSummary() async {
    if (AppState.currentUserEmail.isEmpty) return;
    
    // Đợi 2 giây sau khi vào app để các stream ổn định và UI mượt mà
    await Future.delayed(const Duration(seconds: 2));
    
    final summary = await FirebaseService.getReLoginSummary();
    if (summary.isEmpty) return;

    int totalUnread = summary['unreadMessages'] ?? 0;
    int totalReqs = (summary['friendRequests'] ?? 0) +
        (summary['noteInvites'] ?? 0) +
        (summary['groupInvites'] ?? 0) +
        (summary['groupRequests'] ?? 0);
    int reminders = summary['todayReminders'] ?? 0;

    if (totalUnread == 0 && totalReqs == 0 && reminders == 0) return;

    List<String> lines = [];
    if (totalUnread > 0) lines.add('• $totalUnread tin nhắn mới chưa đọc');
    if (totalReqs > 0) lines.add('• $totalReqs lời mời/yêu cầu mới');
    if (reminders > 0) lines.add('• $reminders công việc/nhắc nhở hôm nay');

    if (lines.isEmpty) return;

    await NotificationService.showNow(
      id: 999,
      title: 'Chào mừng trở lại, ${AppState.currentUserName}!',
      body: 'Bạn có các thông báo mới:\n${lines.join('\n')}',
    );
  }

  Future<void> _forceLogout(String message) async {
    if (_handledForcedLogout) return;
    _handledForcedLogout = true;
    AppState.clearAllData();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(initialMessage: message)),
      (route) => false,
    );
  }

  void _startPresenceHeartbeat() {
    FirebaseService.updateUserActiveStatus();
    _presenceTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      FirebaseService.updateUserActiveStatus();
    });
  }

  Future<void> _notifyOverdueTodos(
    Iterable<QueryDocumentSnapshot> docs, {
    bool isGroupLeader = false,
    String groupName = '',
  }) async {
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    if (myEmail.isEmpty) return;

    for (final doc in docs) {
      final note = FirebaseService.noteFromDocument(doc);
      if (note.groupId.isEmpty) continue;
      for (var index = 0; index < note.todos.length; index++) {
        final todo = note.todos[index];
        if (!todo.isOverdue || todo.status == TodoStatus.done) continue;

        final assigneeEmail = todo.assigneeEmail.toLowerCase().trim();
        final assignedToMe = assigneeEmail == myEmail;
        final unassignedOwnedByMe =
            assigneeEmail.isEmpty && note.createdByEmail == myEmail;
        if (!assignedToMe && !isGroupLeader && !unassignedOwnedByMe) continue;

        final key =
            '${note.id}:$index:${todo.deadline?.toIso8601String() ?? ''}';
        if (!_seenOverdueTodos.add(key)) continue;

        await NotificationService.showNow(
          id: key.hashCode,
          title: 'Todo trễ hạn${groupName.isEmpty ? '' : ' - $groupName'}',
          body: '${todo.task} (${note.title})',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Trang chủ',
          ),
          NavigationDestination(
            icon: StreamBuilder<int>(
              stream: FirebaseService.bellRequestsCountStream(),
              builder: (context, snapshot) {
                final count = snapshot.data ?? 0;
                return Badge(
                  label: Text('$count'),
                  isLabelVisible: count > 0,
                  child: const Icon(Icons.person_outline),
                );
              },
            ),
            selectedIcon: const Icon(Icons.person),
            label: 'Hồ sơ',
          ),
        ],
      ),
    );
  }
}


