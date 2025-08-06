import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

/// Enum to represent the status of a message for the Optimistic UI.
enum MessageStatus { sending, sent, delivered, seen, error }

/// A type-safe model representing a single chat message.
class Message {
  final String id;
  final String? text;
  final String? imageUrl;
  final String senderId;
  final Timestamp? timestamp;
  final bool isEdited;
  final Map<String, String> reactions;

  // Reply information
  final String? replyToMessageId;
  final String? replyToMessageText;
  final String? replyToImageUrl;
  final String? replyToSender;

  // Client-side status for Optimistic UI
  final MessageStatus status;

  Message({
    required this.id,
    this.text,
    this.imageUrl,
    required this.senderId,
    this.timestamp,
    this.isEdited = false,
    this.reactions = const {},
    this.replyToMessageId,
    this.replyToMessageText,
    this.replyToImageUrl,
    this.replyToSender,
    this.status = MessageStatus.sent, // Default to sent
  });

  /// Creates a Message object from a Firestore document snapshot.
  factory Message.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final bool isSeen = data['isSeen'] ?? false;
    final bool isDelivered = data['isDelivered'] ?? false;

    MessageStatus currentStatus;
    if (isSeen) {
      currentStatus = MessageStatus.seen;
    } else if (isDelivered) {
      currentStatus = MessageStatus.delivered;
    } else {
      currentStatus = MessageStatus.sent;
    }

    return Message(
      id: doc.id,
      text: data['text'],
      imageUrl: data['imageUrl'],
      senderId: data['senderId'] ?? '',
      timestamp: data['timestamp'] as Timestamp?,
      isEdited: data['edited'] ?? false,
      reactions: Map<String, String>.from(data['reactions'] ?? {}),
      replyToMessageId: data['replyToMessageId'],
      replyToMessageText: data['replyToMessageText'],
      replyToImageUrl: data['replyToImageUrl'],
      replyToSender: data['replyToSender'],
      status: currentStatus,
    );
  }

  /// Creates a temporary, client-side message for the Optimistic UI.
  factory Message.optimistic({
    required String senderId,
    String? text,
    String? imageUrl,
    String? replyToMessageId,
    String? replyToMessageText,
    String? replyToImageUrl,
    String? replyToSender,
  }) {
    return Message(
      id: const Uuid().v4(), // Generate a unique temporary ID
      senderId: senderId,
      text: text,
      imageUrl: imageUrl,
      timestamp: Timestamp.now(),
      status: MessageStatus.sending, // Set status to 'sending'
      replyToMessageId: replyToMessageId,
      replyToMessageText: replyToMessageText,
      replyToImageUrl: replyToImageUrl,
      replyToSender: replyToSender,
    );
  }
}
