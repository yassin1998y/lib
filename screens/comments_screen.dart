import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:freegram/services/firestore_service.dart';
import 'package:provider/provider.dart';

class CommentsScreen extends StatefulWidget {
  final String postId;
  const CommentsScreen({super.key, required this.postId});

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final _commentController = TextEditingController();

  /// Posts a new comment using the FirestoreService.
  Future<void> _postComment() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final commentText = _commentController.text.trim();

    if (currentUser != null && commentText.isNotEmpty) {
      // Use the centralized service to handle the logic
      await context.read<FirestoreService>().addComment(
        postId: widget.postId,
        userId: currentUser.uid,
        username: currentUser.displayName ?? 'Anonymous',
        commentText: commentText,
        userPhotoUrl: currentUser.photoURL,
      );

      // Clear the input field after posting
      _commentController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = context.read<FirestoreService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Comments'),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: Column(
        children: [
          Expanded(
            // Stream comments directly from the FirestoreService
            child: StreamBuilder<QuerySnapshot>(
              stream: firestoreService.getPostCommentsStream(widget.postId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No comments yet.'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final comment = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                    return ListTile(
                      title: Text(comment['username'] ?? 'user', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(comment['text'] ?? ''),
                    );
                  },
                );
              },
            ),
          ),
          // Input field for adding a new comment
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText: 'Add a comment...',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20.0),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Color(0xFF3498DB)),
                  onPressed: _postComment,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
