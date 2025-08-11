import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class ChatListItemSkeleton extends StatelessWidget {
  const ChatListItemSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListTile(
        leading: const CircleAvatar(radius: 28),
        title: Container(
          height: 16,
          width: 120,
          color: Colors.white,
        ),
        subtitle: Container(
          height: 14,
          width: 200,
          color: Colors.white,
        ),
        trailing: Container(
          height: 10,
          width: 30,
          color: Colors.white,
        ),
      ),
    );
  }
}
