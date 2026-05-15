import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import '../models/app_models.dart';
import '../controllers/firebase_service.dart';
import '../controllers/app_state.dart';
import 'media_utils.dart';

class NoteUtils {
  static void showShareSheet(BuildContext context, Note note, {VoidCallback? onShareSuccess}) async {
    final colorScheme = Theme.of(context).colorScheme;
    // Fetch friends
    final contactsSnapshot = await FirebaseFirestore.instance
        .collection('contacts')
        .where('userId', isEqualTo: FirebaseService.currentUid)
        .get();
    List<Map<String, dynamic>> myFriends = contactsSnapshot.docs
        .map((doc) => doc.data())
        .toList();

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        String emailInput = '';
        List<String> selectedContacts = [];

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Chia sẻ ghi chú',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.ios_share_outlined),
                          tooltip: 'Chia sẻ qua ứng dụng khác',
                          onPressed: () {
                            Navigator.pop(context);
                            _shareExternal(note);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      onChanged: (val) => emailInput = val.trim(),
                      decoration: InputDecoration(
                        hintText: 'Nhập tay email người nhận...',
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 20),

                    Text(
                      'Chọn từ danh bạ:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    myFriends.isEmpty
                        ? Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Bạn chưa có ai trong danh bạ. Hãy vào mục Danh bạ để kết bạn nhé!',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          )
                        : Container(
                            constraints: const BoxConstraints(maxHeight: 250),
                            decoration: BoxDecoration(
                              border: Border.all(color: colorScheme.outlineVariant),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: myFriends.length,
                              itemBuilder: (context, index) {
                                final friend = myFriends[index];
                                final friendEmail = (friend['email'] ?? '').toString();
                                final isSelected = selectedContacts.contains(friendEmail);
                                final alreadyShared = note.sharedWith.contains(friendEmail);

                                return CheckboxListTile(
                                  value: alreadyShared ? true : isSelected,
                                  enabled: !alreadyShared,
                                  title: Text(
                                    friend['name'] ?? 'Bạn bè',
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                  subtitle: Text(friendEmail, style: const TextStyle(fontSize: 12)),
                                  secondary: CircleAvatar(
                                    backgroundImage: avatarImageProvider(
                                      friend['avatar']?.toString(),
                                      name: friend['name']?.toString(),
                                    ),
                                  ),
                                  onChanged: (bool? val) {
                                    setModalState(() {
                                      if (val == true) {
                                        selectedContacts.add(friendEmail);
                                      } else {
                                        selectedContacts.remove(friendEmail);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.send_rounded),
                        label: const Text('Chia sẻ ngay'),
                        onPressed: () async {
                          List<String> finalEmails = [...selectedContacts];
                          String typedEmail = emailInput.toLowerCase();

                          if (typedEmail.isNotEmpty && !finalEmails.contains(typedEmail)) {
                            // Check if user exists
                            final checkUser = await FirebaseFirestore.instance
                                .collection('users')
                                .where('email', isEqualTo: typedEmail)
                                .get();
                            if (checkUser.docs.isEmpty) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Tài khoản "$typedEmail" không tồn tại!'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }
                            finalEmails.add(typedEmail);
                          }

                          finalEmails.removeWhere((e) => note.sharedWith.contains(e));
                          
                          if (finalEmails.isNotEmpty) {
                            if (!context.mounted) return;
                            final scaffoldMsg = ScaffoldMessenger.of(context);
                            final navigator = Navigator.of(context);

                            for (String targetEmail in finalEmails) {
                              await FirebaseService.shareNote(note.id, targetEmail);
                            }
                            
                            navigator.pop();
                            scaffoldMsg.showSnackBar(
                              SnackBar(content: Text('Đã chia sẻ thành công với ${finalEmails.length} người')),
                            );
                            onShareSuccess?.call();
                          } else {
                            if (context.mounted) Navigator.of(context).pop();
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static void _shareExternal(Note note) {
    final buffer = StringBuffer()
      ..writeln(note.title)
      ..writeln('Ngày: ${note.date}')
      ..writeln()
      ..writeln(note.content);
      
    SharePlus.instance.share(
      ShareParams(text: buffer.toString(), subject: note.title),
    );
  }

  static String removeDiacritics(String str) {
    var withDia = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềểễếệìỉĩíịòỏõóọôồổỗốộơờởỡớợùủũúụưừửữứựỳỷỹýỵđÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỔỖỐỘƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ';
    var withoutDia = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyydAAAAAAAAAAAAAAAAAEEEEEEEEEEEIIIIIOOOOOOOOOOOOOOOOOUUUUUUUUUUUYYYYYD';
    var result = str;
    for (int i = 0; i < withDia.length; i++) {
      result = result.replaceAll(withDia[i], withoutDia[i]);
    }
    return result.toLowerCase();
  }
}


