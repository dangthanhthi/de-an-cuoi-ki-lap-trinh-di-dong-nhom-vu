import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart'; 
import '../controllers/app_state.dart';
import 'group_notes_screen.dart';

class GroupsListScreen extends StatefulWidget {
  const GroupsListScreen({super.key});

  @override
  State<GroupsListScreen> createState() => _GroupsListScreenState();
}

class _GroupsListScreenState extends State<GroupsListScreen> {

  void _showCreateGroupDialog(BuildContext context) {
    TextEditingController nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tạo nhóm mới'),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(hintText: 'Tên nhóm...')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.isNotEmpty) {
                FirebaseService.createGroup(nameCtrl.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Tạo'),
          ),
        ],
      ),
    );
  }

  void _showJoinGroupDialog(BuildContext context) {
    TextEditingController codeCtrl = TextEditingController();
    bool isJoining = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Tham gia bằng mã'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Nhập mã gồm 8 ký tự do trưởng nhóm cung cấp:'),
                const SizedBox(height: 12),
                TextField(
                  controller: codeCtrl,
                  maxLength: 8, 
                  textCapitalization: TextCapitalization.characters, 
                  decoration: InputDecoration(
                    hintText: 'Mã nhóm...',
                    prefixIcon: const Icon(Icons.sensor_door_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy', style: TextStyle(color: Colors.grey))),
              FilledButton(
                onPressed: isJoining ? null : () async {
                  if (codeCtrl.text.trim().isEmpty) return;
                  setDialogState(() => isJoining = true);

                  String result = await FirebaseService.joinGroupByCode(codeCtrl.text.trim());
                  
                  if (context.mounted) {
                    setDialogState(() => isJoining = false);
                    Navigator.pop(ctx);
                    if (result == "SUCCESS") {
                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vào nhóm thành công!'), backgroundColor: Colors.green));
                    } else {
                       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result), backgroundColor: Colors.red));
                    }
                  }
                },
                child: isJoining 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Tham gia'),
              ),
            ],
          );
        }
      ),
    );
  }

  void _showAddMemberDialog(BuildContext context, String groupId) {
    TextEditingController emailCtrl = TextEditingController();
    bool isAdding = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Thêm thành viên'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Nhập email của người muốn thêm vào nhóm:'),
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  decoration: InputDecoration(
                    hintText: 'ví dụ: abc@gmail.com',
                    prefixIcon: const Icon(Icons.email),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy', style: TextStyle(color: Colors.grey))),
              FilledButton(
                onPressed: isAdding ? null : () async {
                  String email = emailCtrl.text.trim().toLowerCase();
                  if (email.isEmpty) return;

                  setDialogState(() => isAdding = true);

                  final checkUser = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: email).get();
                  if (checkUser.docs.isEmpty) {
                    setDialogState(() => isAdding = false);
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tài khoản không tồn tại!'), backgroundColor: Colors.red));
                    return;
                  }

                  await FirebaseService.addMemberToGroup(groupId, email);
                  
                  if (context.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã thêm thành viên thành công!'), backgroundColor: Colors.green));
                  }
                },
                child: isAdding 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Thêm'),
              ),
            ],
          );
        }
      ),
    );
  }

  void _showMembersDialog(BuildContext context, String groupId, bool isLeader, String leaderId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (context, scrollController) {
            return Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40, height: 5,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text('Thành viên nhóm', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal)),
                ),
                const Divider(),
                Expanded(
                  child: StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance.collection('groups').doc(groupId).snapshots(),
                    builder: (context, groupSnap) {
                      if (!groupSnap.hasData || !groupSnap.data!.exists) return const SizedBox();
                      List<dynamic> members = groupSnap.data!.get('members') ?? [];

                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('users').snapshots(),
                        builder: (context, usersSnap) {
                          if (!usersSnap.hasData) return const Center(child: CircularProgressIndicator());

                          var membersData = usersSnap.data!.docs.where((doc) {
                            return members.contains((doc.data() as Map)['email']);
                          }).toList();

                          return ListView.builder(
                            controller: scrollController,
                            itemCount: membersData.length,
                            itemBuilder: (context, index) {
                              var user = membersData[index].data() as Map<String, dynamic>;
                              String userEmail = user['email'];
                              bool isThisUserLeader = membersData[index].id == leaderId; 

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundImage: NetworkImage(user['avatar'] ?? 'https://ui-avatars.com/api/?background=random'),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(child: Text(user['name'] ?? 'Không tên', style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                                    if (isThisUserLeader) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)),
                                        child: const Text('Trưởng nhóm', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                      )
                                    ]
                                  ]
                                ),
                                subtitle: Text(userEmail, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                
                                trailing: (isLeader && !isThisUserLeader) 
                                  ? IconButton(
                                      icon: const Icon(Icons.person_remove, color: Colors.redAccent),
                                      tooltip: 'Mời ra khỏi nhóm',
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (confirmCtx) => AlertDialog(
                                            title: const Text('Kick thành viên?'),
                                            content: Text('Bạn có chắc muốn mời tài khoản\n$userEmail\nra khỏi nhóm này?'),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(confirmCtx), child: const Text('Hủy')),
                                              FilledButton(
                                                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                                onPressed: () {
                                                  FirebaseService.removeMemberFromGroup(groupId, userEmail);
                                                  Navigator.pop(confirmCtx);
                                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã mời thành viên rời nhóm!')));
                                                }, 
                                                child: const Text('Đuổi ngay')
                                              ),
                                            ],
                                          )
                                        );
                                      },
                                    )
                                  : null,
                              );
                            }
                          );
                        }
                      );
                    }
                  )
                )
              ]
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhóm của tôi', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton.icon(
            onPressed: () => _showJoinGroupDialog(context), 
            icon: const Icon(Icons.login, color: Colors.indigo), 
            label: const Text('Nhập mã', style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseService.getMyGroupsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.group_off, size: 80, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  const Text('Bạn chưa tham gia nhóm nào', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          
          final groups = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              var group = groups[index].data() as Map<String, dynamic>;
              String groupId = groups[index].id;
              
              bool isLeader = group['leaderId'] == FirebaseService.currentUid;
              List<dynamic> members = group['members'] ?? [];
              String groupCode = group['groupCode'] ?? 'Chưa có mã'; 

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isLeader) ...[
                        Container(
                          width: 5,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.redAccent, 
                            borderRadius: BorderRadius.circular(4)
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.teal.shade100, 
                        child: const Icon(Icons.groups, color: Colors.teal, size: 28)
                      ),
                    ],
                  ),
                  
                  title: Text(
                    group['name'], 
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    maxLines: 1, 
                    overflow: TextOverflow.ellipsis, 
                  ),
                  
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      // Đã gỡ bỏ chữ "Trưởng nhóm" ở đây, chỉ giữ lại số thành viên
                      Text('${members.length} thành viên', style: const TextStyle(fontSize: 13)),
                      if (groupCode != 'Chưa có mã') ...[
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: groupCode));
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã chép mã nhóm vào khay nhớ tạm!')));
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
                            child: Text('Mã: $groupCode 📄', style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        )
                      ]
                    ],
                  ),
                  
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        constraints: const BoxConstraints(), 
                        padding: const EdgeInsets.all(6),
                        icon: const Icon(Icons.people, color: Colors.teal),
                        tooltip: 'Xem thành viên',
                        onPressed: () => _showMembersDialog(context, groupId, isLeader, group['leaderId']),
                      ),
                      if (isLeader) ...[
                        IconButton(
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(6),
                          icon: const Icon(Icons.person_add, color: Colors.blue), 
                          tooltip: 'Thêm thành viên',
                          onPressed: () => _showAddMemberDialog(context, groupId)
                        ),
                        IconButton(
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(6),
                          icon: const Icon(Icons.delete_outline, color: Colors.red), 
                          tooltip: 'Giải tán nhóm',
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Xóa nhóm?'),
                                content: const Text('Bạn có chắc chắn muốn giải tán nhóm này? Toàn bộ ghi chú trong nhóm sẽ bị xóa sạch không thể khôi phục.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
                                  FilledButton(
                                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                    onPressed: () {
                                      FirebaseService.deleteGroup(groupId);
                                      Navigator.pop(ctx);
                                    }, 
                                    child: const Text('Xóa ngay')
                                  ),
                                ],
                              )
                            );
                          }
                        ),
                      ] else ...[
                        IconButton(
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(6),
                          icon: const Icon(Icons.exit_to_app, color: Colors.orange),
                          tooltip: 'Rời nhóm',
                          onPressed: () {
                             showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Rời nhóm?'),
                                  content: const Text('Bạn có chắc muốn rời khỏi nhóm này không?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
                                    FilledButton(
                                      style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                                      onPressed: () {
                                        FirebaseService.removeMemberFromGroup(groupId, AppState.currentUserEmail);
                                        Navigator.pop(ctx);
                                      }, 
                                      child: const Text('Rời nhóm')
                                    ),
                                  ],
                                )
                              );
                          },
                        ),
                      ]
                    ],
                  ),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => GroupNotesScreen(groupId: groupId, groupName: group['name'])));
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateGroupDialog(context),
        icon: const Icon(Icons.group_add),
        label: const Text('Tạo nhóm'),
      ),
    );
  }
}