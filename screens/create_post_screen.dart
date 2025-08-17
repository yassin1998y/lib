import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:freegram/repositories/post_repository.dart'; // UPDATED
import 'package:http/http.dart' as http;
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
  final ImagePicker _picker = ImagePicker();

  XFile? _imageFile;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _pickImage();
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: widget.imageSource);
      if (pickedFile != null) {
        setState(() {
          _imageFile = pickedFile;
        });
      } else {
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error selecting image.')),
        );
        Navigator.of(context).pop();
      }
    }
  }

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
      debugPrint('Cloudinary upload failed with status: ${response.statusCode}');
      return null;
    }
  }

  Future<void> _createPost() async {
    if (_imageFile == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select an image.')));
      }
      return;
    }

    if (_isLoading) return;

    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final imageUrl = await _uploadToCloudinary(_imageFile!);
      if (imageUrl == null) {
        throw Exception('Image upload failed. Could not get URL.');
      }

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated.');
      }

      // UPDATED: Uses PostRepository
      if (!mounted) return;
      await context.read<PostRepository>().createPost(
        userId: currentUser.uid,
        username: currentUser.displayName ?? 'Anonymous',
        caption: _captionController.text.trim(),
        imageUrl: imageUrl,
        postType: 'image',
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
              child: const Text(
                'Post',
                style: TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          if (_imageFile == null)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else
            Column(
              children: [
                Expanded(
                  child: Center(
                    child: kIsWeb
                        ? Image.network(_imageFile!.path, fit: BoxFit.contain)
                        : Image.file(File(_imageFile!.path), fit: BoxFit.contain),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  color: Colors.black.withOpacity(0.5),
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
              ],
            ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
