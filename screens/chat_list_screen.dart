import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:freegram/services/firestore_service.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'chat_screen.dart';
import 'profile_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser!;
    final firestoreService = context.read<FirestoreService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Messages"),
        backgroundColor: Colors.white,
        elevation: 1,
        toolbarHeight: 70,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50.0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey[200],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: firestoreService.getChatsStream(currentUser.uid),
        builder: (context, chatSnapshot) {
          if (chatSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (chatSnapshot.hasError) {
            return Center(child: Text('Error: ${chatSnapshot.error}'));
          }
          if (!chatSnapshot.hasData || chatSnapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No active chats.'));
          }

          var chats = chatSnapshot.data!.docs;

          // Filter chats based on the search query
          if (_searchQuery.isNotEmpty) {
            chats = chats.where((chat) {
              final chatData = chat.data() as Map<String, dynamic>;
              final usernames = chatData['usernames'] as Map<String, dynamic>;
              final otherUserId = (chatData['users'] as List).firstWhere((id) => id != currentUser.uid, orElse: () => '');
              final otherUsername = usernames[otherUserId] ?? 'User';
              return otherUsername.toLowerCase().contains(_searchQuery.toLowerCase());
            }).toList();
          }

          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final chat = chats[index];
              return ChatListItem(
                chat: chat,
                currentUserId: currentUser.uid,
              );
            },
          );
        },
      ),
    );
  }
}

/// A widget representing a single conversation in the chat list.
class ChatListItem extends StatelessWidget {
  final DocumentSnapshot chat;
  final String currentUserId;

  const ChatListItem({
    super.key,
    required this.chat,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final firestoreService = context.read<FirestoreService>();
    final chatData = chat.data() as Map<String, dynamic>;
    final usernames = chatData['usernames'] as Map<String, dynamic>;
    final otherUserId = (chatData['users'] as List).firstWhere((id) => id != currentUserId, orElse: () => '');
    final otherUsername = usernames[otherUserId] ?? 'User';

    return StreamBuilder<DocumentSnapshot>(
      stream: firestoreService.getUserStream(otherUserId),
      builder: (context, userSnapshot) {
        if (!userSnapshot.hasData) {
          // Show a placeholder while the user data is loading
          return const ListTile();
        }

        final userData = userSnapshot.data!.data() as Map<String, dynamic>;
        final photoUrl = userData['photoUrl'];
        final isOnline = userData['presence'] ?? false;

        final unreadCount = (chatData['unreadCount'] as Map<String, dynamic>?)?[currentUserId] ?? 0;

        String lastMessage = chatData['lastMessage'] ?? '';
        if (chatData.containsKey('lastMessageIsImage') && chatData['lastMessageIsImage'] == true) {
          lastMessage = '📷 Photo';
        }

        final messageTimestamp = chatData['lastMessageTimestamp'] as Timestamp?;
        final formattedMessageTime = messageTimestamp != null ? timeago.format(messageTimestamp.toDate(), locale: 'en_short') : '';

        return Dismissible(
          key: Key(chat.id),
          direction: DismissDirection.endToStart,
          confirmDismiss: (direction) async {
            return await showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text("Confirm Delete"),
                  content: Text("Are you sure you want to delete your chat with $otherUsername? This action cannot be undone."),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text("Cancel"),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text("Delete", style: TextStyle(color: Colors.red)),
                    ),
                  ],
                );
              },
            );
          },
          onDismissed: (direction) {
            firestoreService.deleteChat(chat.id);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("$otherUsername chat deleted")),
            );
          },
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: const Icon(Icons.delete_forever, color: Colors.white),
          ),
          child: ListTile(
            leading: Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: otherUserId))),
                  child: CircleAvatar(
                    backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
                    child: (photoUrl == null || photoUrl.isEmpty)
                        ? Text(otherUsername.isNotEmpty ? otherUsername[0].toUpperCase() : '?')
                        : null,
                  ),
                ),
                if (isOnline)
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      height: 14,
                      width: 14,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  )
              ],
            ),
            title: Text(otherUsername, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formattedMessageTime, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                const SizedBox(height: 4),
                if (unreadCount > 0)
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: const Color(0xFFE74C3C),
                    child: Text(
                      unreadCount.toString(),
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(chatId: chat.id, otherUsername: otherUsername))),
          ),
        );
      },
    );
  }
}
