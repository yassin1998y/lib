import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:freegram/models/user_model.dart';
import 'package:freegram/repositories/chat_repository.dart'; // UPDATED IMPORT
import 'package:freegram/repositories/user_repository.dart';
import 'package:freegram/widgets/chat_list_item_skeleton.dart';
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
    // UPDATED: Get ChatRepository from context
    final chatRepository = context.read<ChatRepository>();

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
                hintText: 'Search chats or users...',
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
      body: _searchQuery.isEmpty
          ? _buildChatList(chatRepository, currentUser.uid)
          : _buildSearchResults(context.read<UserRepository>(), context.read<ChatRepository>(), currentUser.uid),
    );
  }

  Widget _buildChatList(ChatRepository chatRepository, String currentUserId) {
    return StreamBuilder<QuerySnapshot>(
      // UPDATED: Using ChatRepository
      stream: chatRepository.getChatsStream(currentUserId),
      builder: (context, chatSnapshot) {
        if (chatSnapshot.connectionState == ConnectionState.waiting) {
          return ListView.builder(
            itemCount: 10,
            itemBuilder: (context, index) => const ChatListItemSkeleton(),
          );
        }
        if (chatSnapshot.hasError) {
          return Center(child: Text('Error: ${chatSnapshot.error}'));
        }
        if (!chatSnapshot.hasData || chatSnapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No active chats.'));
        }

        final chats = chatSnapshot.data!.docs;
        return ListView.builder(
          itemCount: chats.length,
          itemBuilder: (context, index) {
            final chat = chats[index];
            return ChatListItem(
              chat: chat,
              currentUserId: currentUserId,
            );
          },
        );
      },
    );
  }

  Widget _buildSearchResults(UserRepository userRepository, ChatRepository chatRepository, String currentUserId) {
    return StreamBuilder<QuerySnapshot>(
      stream: userRepository.searchUsers(_searchQuery),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!userSnapshot.hasData) {
          return const Center(child: Text('No users found.'));
        }

        final users = userSnapshot.data!.docs
            .where((doc) => doc.id != currentUserId)
            .toList();

        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, index) {
            final userDoc = users[index];
            final user = UserModel.fromDoc(userDoc);
            return ListTile(
              leading: CircleAvatar(
                backgroundImage: user.photoUrl.isNotEmpty ? NetworkImage(user.photoUrl) : null,
                child: user.photoUrl.isEmpty ? Text(user.username.isNotEmpty ? user.username[0].toUpperCase() : '?') : null,
              ),
              title: Text(user.username),
              subtitle: const Text('Tap to message'),
              // UPDATED: Using ChatRepository
              onTap: () => chatRepository.startOrGetChat(context, user.id, user.username),
            );
          },
        );
      },
    );
  }
}

class ChatListItem extends StatelessWidget {
  final DocumentSnapshot chat;
  final String currentUserId;

  const ChatListItem({
    super.key,
    required this.chat,
    required this.currentUserId,
  });

  String _formatLastSeenShort(DateTime? lastSeen) {
    if (lastSeen == null) {
      return '';
    }
    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    if (difference.inSeconds < 60) {
      return '';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h';
    } else {
      return '${difference.inDays}d';
    }
  }

  @override
  Widget build(BuildContext context) {
    // UPDATED: Get repositories from context
    final chatRepository = context.read<ChatRepository>();
    final userRepository = context.read<UserRepository>();
    final chatData = chat.data() as Map<String, dynamic>;
    final usernames = chatData['usernames'] as Map<String, dynamic>;
    final otherUserId = (chatData['users'] as List).firstWhere((id) => id != currentUserId, orElse: () => '');
    final otherUsername = usernames[otherUserId] ?? 'User';

    return StreamBuilder<UserModel>(
      stream: userRepository.getUserStream(otherUserId),
      builder: (context, userSnapshot) {
        if (!userSnapshot.hasData) {
          return const ListTile();
        }

        final user = userSnapshot.data!;
        final photoUrl = user.photoUrl;
        final isOnline = user.presence;
        final lastSeen = user.lastSeen;
        final formattedLastSeen = _formatLastSeenShort(lastSeen);

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
          // UPDATED: Using ChatRepository
          onDismissed: (direction) {
            chatRepository.deleteChat(chat.id);
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
                    backgroundImage: (photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
                    child: (photoUrl.isEmpty)
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
                else if (formattedLastSeen.isNotEmpty)
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green, width: 1),
                      ),
                      child: Text(
                        formattedLastSeen,
                        style: const TextStyle(color: Colors.green, fontSize: 8, fontWeight: FontWeight.bold),
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
                if (unreadCount > 0)
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: const Color(0xFFE74C3C),
                    child: Text(
                      unreadCount.toString(),
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  )
                else
                  Text(formattedMessageTime, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(chatId: chat.id, otherUsername: otherUsername))),
          ),
        );
      },
    );
  }
}
