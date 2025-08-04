import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:freegram/services/firestore_service.dart';
import 'package.http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

class CreatePostScreen extends StatefulWidget {
  final ImageSource imageSource;
  const CreatePostScreen({super.key, required this.imageSource});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _captionController = TextEditingController();
  XFile? _imageFile;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _pickImage();
  }

  /// Picks an image from the source specified in the widget.
  Future<void> _pickImage() async {
    final XFile? pickedFile = await _picker.pickImage(source: widget.imageSource);
    if (pickedFile != null) {
      setState(() {
        _imageFile = pickedFile;
      });
    } else {
      // If the user cancels the image selection, go back to the previous screen.
      Navigator.of(context).pop();
    }
  }

  /// Uploads the selected image to Cloudinary.
  Future<String?> _uploadToCloudinary(XFile image) async {
    final url = Uri.parse('https://api.cloudinary.com/v1_1/dq0mb16fk/image/upload');
    final request = http.MultipartRequest('POST', url)
      ..fields['upload_preset'] = 'Prototype';

    final bytes = await image.readAsBytes();
    final multipartFile = http.MultipartFile.fromBytes('file', bytes, filename: image.name);
    request.files.add(multipartFile);

    final response = await request.send();
    if (response.statusCode == 200) {
      final responseData = await response.stream.toBytes();
      final responseString = String.fromCharCodes(responseData);
      final jsonMap = jsonDecode(responseString);
      return jsonMap['secure_url'];
    } else {
      return null;
    }
  }

  /// Creates the post using the FirestoreService.
  Future<void> _createPost() async {
    if (_imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select an image.')));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final imageUrl = await _uploadToCloudinary(_imageFile!);
      if (imageUrl == null) throw Exception('Image upload failed');

      final currentUser = FirebaseAuth.instance.currentUser!;
      // Use the centralized service to handle post creation
      await context.read<FirestoreService>().createPost(
        userId: currentUser.uid,
        username: currentUser.displayName ?? 'Anonymous',
        caption: _captionController.text.trim(),
        imageUrl: imageUrl,
        postType: 'image', // Set postType for future Reels feature
      );

      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed to create post: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('New Post', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_imageFile != null)
            TextButton(
              onPressed: _isLoading ? null : _createPost,
              child: const Text('Post', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 16)),
            )
        ],
      ),
      body: _imageFile == null
      // Show a loading indicator while the image is being picked
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Stack(
        children: [
          Center(
            child: kIsWeb
                ? Image.network(_imageFile!.path, fit: BoxFit.contain)
                : Image.file(File(_imageFile!.path), fit: BoxFit.contain),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              color: const Color.fromRGBO(0, 0, 0, 0.5),
              child: TextField(
                controller: _captionController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Write a caption...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                maxLines: 4,
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: const Color.fromRGBO(0, 0, 0, 0.7),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
