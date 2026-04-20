import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Thêm thư viện Firestore
import '../controllers/app_state.dart';

class ActivityHistoryScreen extends StatelessWidget {
  const ActivityHistoryScreen({super.key});
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lịch sử hoạt động')),
      // Đổi từ AppState.activities sang StreamBuilder để nghe dữ liệu thật
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseService.getActivitiesStream(),
        builder: (context, snapshot) {
          // 1. Trạng thái đang tải
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // 2. Trạng thái lỗi
          if (snapshot.hasError) {
            return Center(
              child: Text('Đã xảy ra lỗi: ${snapshot.error}', style: TextStyle(color: Colors.red.shade400)),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          // 3. Trạng thái trống (Không có hoạt động nào)
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text('Chưa có hoạt động nào', style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
            );
          }

          // 4. Trạng thái có dữ liệu
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              // Ép kiểu dữ liệu lấy từ Firebase
              final data = docs[index].data() as Map<String, dynamic>;
              
              final String action = data['action'] ?? 'Không rõ';
              final String details = data['detail'] ?? '';
              
              // Xử lý hiển thị thời gian (Chuyển Timestamp của Firebase thành DateTime)
              final Timestamp? ts = data['timestamp'] as Timestamp?;
              String dateStr = 'Vừa xong';
              if (ts != null) {
                final DateTime dt = ts.toDate();
                // Format kiểu: 14:30 - 20/10/2025
                dateStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} - ${dt.day}/${dt.month}/${dt.year}';
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.indigo.shade50,
                    child: const Icon(Icons.check_circle_outline, color: Colors.indigo),
                  ),
                  title: Text(action, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(details),
                      const SizedBox(height: 4),
                      Text(dateStr, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}