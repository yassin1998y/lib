import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:freegram/screens/friends_list_screen.dart';
import 'package:freegram/screens/post_detail_screen.dart';
import 'package:freegram/screens/profile_screen.dart';
import 'package:freegram/services/firestore_service.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  /// Marks all unread notifications as read using the FirestoreService.
  Future<void> _markAllAsRead() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final success = await context
        .read<FirestoreService>()
        .markAllNotificationsAsRead(currentUser.uid);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(success
                ? 'All notifications marked as read.'
                : 'No new notifications.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text('Please log in.')));
    }

    final firestoreService = context.read<FirestoreService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Activity"),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'mark_all_read') {
                _markAllAsRead();
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'mark_all_read',
                child: Text('Mark all as read'),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: firestoreService.getNotificationsStream(currentUser.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No notifications yet.'));
          }

          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final notifDoc = snapshot.data!.docs[index];
              final notif = notifDoc.data() as Map<String, dynamic>;

              // Mark notification as read when it's built
              if (notif['read'] == false) {
                firestoreService.markNotificationAsRead(
                    currentUser.uid, notifDoc.id);
              }

              return NotificationTile(notification: notif);
            },
          );
        },
      ),
    );
  }
}

/// A widget that displays a single notification item.
class NotificationTile extends StatelessWidget {
  final Map<String, dynamic> notification;
  const NotificationTile({super.key, required this.notification});

  @override
  Widget build(BuildContext context) {
    final String type = notification['type'] ?? '';
    final String fromUsername = notification['fromUsername'] ?? 'Someone';
    final String fromUserId = notification['fromUserId'] ?? '';
    final String? fromUserPhotoUrl = notification['fromUserPhotoUrl'];
    final String? postImageUrl = notification['postImageUrl'];
    final String? commentText = notification['commentText'];
    final String? postId = notification['postId'];
    final Timestamp? timestamp = notification['timestamp'];

    Widget title;
    Widget? trailing;
    VoidCallback? onTap;
    Color? tileColor;
    IconData leadingIcon = Icons.person;
    Color leadingIconColor = Colors.grey;

    // Determine the text and icon based on the notification type
    switch (type) {
      case 'like':
        title = RichText(
          text: TextSpan(
            style: DefaultTextStyle.of(context).style,
            children: [
              TextSpan(
                  text: fromUsername,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const TextSpan(text: ' liked your post.'),
            ],
          ),
        );
        leadingIcon = Icons.favorite;
        leadingIconColor = Colors.red;
        if (postImageUrl != null && postImageUrl.isNotEmpty) {
          trailing = SizedBox(
            width: 50,
            height: 50,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4.0),
              child: Image.network(postImageUrl, fit: BoxFit.cover),
            ),
          );
        }
        onTap = () async {
          if (postId != null) {
            final postDoc =
            await context.read<FirestoreService>().getPost(postId);
            if (postDoc.exists && context.mounted) {
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PostDetailScreen(postSnapshot: postDoc)));
            }
          }
        };
        break;
      case 'comment':
        title = RichText(
          text: TextSpan(
            style: DefaultTextStyle.of(context).style,
            children: [
              TextSpan(
                  text: fromUsername,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              TextSpan(text: ' commented: ${commentText ?? ''}'),
            ],
          ),
        );
        leadingIcon = Icons.comment;
        leadingIconColor = Colors.blue;
        if (postImageUrl != null && postImageUrl.isNotEmpty) {
          trailing = SizedBox(
            width: 50,
            height: 50,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4.0),
              child: Image.network(postImageUrl, fit: BoxFit.cover),
            ),
          );
        }
        onTap = () async {
          if (postId != null) {
            final postDoc =
            await context.read<FirestoreService>().getPost(postId);
            if (postDoc.exists && context.mounted) {
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PostDetailScreen(postSnapshot: postDoc)));
            }
          }
        };
        break;
      case 'friend_request_received':
        title = RichText(
          text: TextSpan(
            style: DefaultTextStyle.of(context).style,
            children: [
              TextSpan(
                  text: fromUsername,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const TextSpan(text: ' sent you a friend request.'),
            ],
          ),
        );
        leadingIcon = Icons.person_add;
        leadingIconColor = Colors.green;
        onTap = () {
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const FriendsListScreen(initialIndex: 1)));
        };
        break;
      case 'request_accepted':
        title = RichText(
          text: TextSpan(
            style: DefaultTextStyle.of(context).style,
            children: [
              TextSpan(
                  text: fromUsername,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const TextSpan(text: ' accepted your friend request.'),
            ],
          ),
        );
        leadingIcon = Icons.check_circle;
        leadingIconColor = Colors.blue;
        onTap = () {
          if (fromUserId.isNotEmpty) {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ProfileScreen(userId: fromUserId)));
          }
        };
        break;
    // NEW: Handle Super Like notifications
      case 'super_like':
        title = RichText(
          text: TextSpan(
            style: DefaultTextStyle.of(context).style,
            children: [
              TextSpan(
                  text: fromUsername,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const TextSpan(text: ' Super Liked you!'),
            ],
          ),
        );
        leadingIcon = Icons.star;
        leadingIconColor = Colors.white; // Icon color for the gradient
        tileColor = Colors.blue.shade100.withOpacity(0.5); // Highlight color
        onTap = () {
          if (fromUserId.isNotEmpty) {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ProfileScreen(userId: fromUserId)));
          }
        };
        break;
      default:
        title = Text('$fromUsername sent you a notification.');
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: tileColor,
      child: ListTile(
        leading: GestureDetector(
          onTap: () {
            if (fromUserId.isNotEmpty) {
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ProfileScreen(userId: fromUserId)));
            }
          },
          child: CircleAvatar(
            backgroundImage: (fromUserPhotoUrl != null && fromUserPhotoUrl.isNotEmpty)
                ? NetworkImage(fromUserPhotoUrl)
                : null,
            child: (fromUserPhotoUrl == null || fromUserPhotoUrl.isEmpty)
                ? Icon(leadingIcon, color: leadingIconColor, size: 20)
                : null,
          ),
        ),
        title: title,
        subtitle: Text(
          timestamp != null ? timeago.format(timestamp.toDate()) : '',
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}
