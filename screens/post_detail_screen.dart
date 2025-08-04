import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:freegram/widgets/post_card.dart';

class PostDetailScreen extends StatelessWidget {
  final DocumentSnapshot postSnapshot;
  const PostDetailScreen({super.key, required this.postSnapshot});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Post'),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: SingleChildScrollView(
        // Reusing the PostCard widget for a consistent UI
        child: PostCard(post: postSnapshot),
      ),
    );
  }
}
