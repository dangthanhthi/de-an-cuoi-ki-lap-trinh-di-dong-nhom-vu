import 'package:flutter/material.dart';
import '../utils/media_utils.dart';

class MessageDetailsScreen extends StatelessWidget {
  final String messageText;
  final DateTime? createdAt;
  final List<String> seenBy;
  final List<String> receivedBy;
  final Map<String, dynamic>? memberInfoMap; // email -> {name, avatar}
  final Map<String, String> reactions; // email -> emoji

  const MessageDetailsScreen({
    super.key,
    required this.messageText,
    this.createdAt,
    this.seenBy = const [],
    this.receivedBy = const [],
    this.memberInfoMap,
    this.reactions = const {},
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final notSeen = receivedBy.where((e) => !seenBy.contains(e)).toList();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Chi tiết tin nhắn', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: CustomScrollView(
        slivers: [
          // Message Preview Card
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primaryContainer.withValues(alpha: 0.4),
                    colorScheme.secondaryContainer.withValues(alpha: 0.2),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    messageText.isEmpty ? '[Hình ảnh/Tệp]' : messageText,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      height: 1.5,
                    ),
                  ),
                  if (createdAt != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 14, color: colorScheme.outline),
                        const SizedBox(width: 4),
                        Text(
                          _formatTime(createdAt!),
                          style: textTheme.labelSmall?.copyWith(color: colorScheme.outline),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Reactions Section
          if (reactions.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _buildSectionHeader(context, 'Cảm xúc (${reactions.length})', Icons.favorite_border),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final email = reactions.keys.elementAt(index);
                  final emoji = reactions[email]!;
                  final info = memberInfoMap?[email];
                  final name = info?['name'] ?? email;
                  final avatar = info?['avatar'];

                  return _buildMemberTile(
                    context,
                    name: name,
                    email: email,
                    avatar: avatar,
                    trailing: Text(emoji, style: const TextStyle(fontSize: 24)),
                  );
                },
                childCount: reactions.length,
              ),
            ),
          ],

          // Seen By Section
          if (seenBy.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _buildSectionHeader(context, 'Đã xem (${seenBy.length})', Icons.done_all, color: Colors.blue),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final email = seenBy[index];
                  final info = memberInfoMap?[email];
                  final name = info?['name'] ?? email;
                  final avatar = info?['avatar'];

                  return _buildMemberTile(context, name: name, email: email, avatar: avatar);
                },
                childCount: seenBy.length,
              ),
            ),
          ],

          // Received By Section
          if (notSeen.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _buildSectionHeader(context, 'Đã nhận (${notSeen.length})', Icons.done),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final email = notSeen[index];
                  final info = memberInfoMap?[email];
                  final name = info?['name'] ?? email;
                  final avatar = info?['avatar'];

                  return _buildMemberTile(context, name: name, email: email, avatar: avatar);
                },
                childCount: notSeen.length,
              ),
            ),
          ],
          
          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon, {Color? color}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color ?? colorScheme.onSurface,
            ),
          ),
          const Expanded(child: Divider(indent: 16)),
        ],
      ),
    );
  }

  Widget _buildMemberTile(BuildContext context, {
    required String name,
    required String email,
    String? avatar,
    Widget? trailing,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: CircleAvatar(
        radius: 20,
        backgroundImage: avatarImageProvider(avatar, name: name),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(email, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
      trailing: trailing,
    );
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} - ${date.day}/${date.month}/${date.year}';
  }
}
