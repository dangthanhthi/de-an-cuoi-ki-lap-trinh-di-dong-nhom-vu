import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../controllers/app_state.dart';

class ActivityHistoryScreen extends StatefulWidget {
  const ActivityHistoryScreen({super.key});

  @override
  State<ActivityHistoryScreen> createState() => _ActivityHistoryScreenState();
}

class _ActivityHistoryScreenState extends State<ActivityHistoryScreen> {
  String _searchQuery = '';
  final FocusNode _searchFocusNode = FocusNode();
  late Stream<QuerySnapshot> _activitiesStream;

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _activitiesStream = FirebaseService.getActivitiesStream();
  }

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_searchFocusNode.hasFocus) {
          _searchFocusNode.unfocus();
        }
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử hoạt động'),
        actions: [
          IconButton(
            tooltip: 'Xóa toàn bộ lịch sử',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Xóa lịch sử?'),
                  content: const Text(
                    'Toàn bộ lịch sử hoạt động của bạn sẽ bị xóa.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Hủy'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Xóa'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await FirebaseService.clearMyActivities();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              focusNode: _searchFocusNode,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Tìm kiếm lịch sử...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _activitiesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Đã xảy ra lỗi: ${snapshot.error}',
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  );
                }

                final query = _searchQuery.toLowerCase().trim();
                final docs = (snapshot.data?.docs ?? []).where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final action = (data['action'] ?? '')
                      .toString()
                      .toLowerCase();
                  final detail = (data['detail'] ?? '')
                      .toString()
                      .toLowerCase();
                  return query.isEmpty ||
                      action.contains(query) ||
                      detail.contains(query);
                }).toList();

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.history,
                          size: 64,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Chưa có hoạt động nào',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;

                    final String action = data['action'] ?? 'Không rõ';
                    // Hỗ trợ cả detail (mới) và details (cũ)
                    final String details = (data['detail'] ?? data['details'] ?? '').toString();

                    // Hỗ trợ cả timestamp (mới) và date (cũ)
                    final dynamic rawTs = data['timestamp'];
                    final dynamic rawDate = data['date'];
                    
                    String dateStr = 'Vừa xong';
                    if (rawTs is Timestamp) {
                      final DateTime dt = rawTs.toDate();
                      dateStr =
                          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} - ${dt.day}/${dt.month}/${dt.year}';
                    } else if (rawDate is String) {
                      try {
                        final DateTime dt = DateTime.parse(rawDate);
                        dateStr =
                            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} - ${dt.day}/${dt.month}/${dt.year}';
                      } catch (_) {}
                    }

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 0,
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          child: Icon(
                            Icons.check_circle_outline,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                        title: Text(
                          action,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        trailing: IconButton(
                          tooltip: 'Xóa lịch sử này',
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                          ),
                          onPressed: () =>
                              FirebaseService.deleteActivity(docs[index].id),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(details),
                            const SizedBox(height: 4),
                            Text(
                              dateStr,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}


