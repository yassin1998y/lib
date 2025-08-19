import 'dart:convert';
import 'dart:io';
import 'package:chewie/chewie.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:freegram/repositories/post_repository.dart';
import 'package:freegram/screens/video_editor_screen.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

class CreateReelScreen extends StatefulWidget {
  final ImageSource imageSource;
  const CreateReelScreen({super.key, required this.imageSource});

  @override
  State<CreateReelScreen> createState() => _CreateReelScreenState();
}

class _CreateReelScreenState extends State<CreateReelScreen> {
  final _captionController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  File? _editedVideoFile;
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = false;
  String _loadingMessage = "Uploading...";

  @override
  void initState() {
    super.initState();
    _pickAndEditVideo();
  }

  @override
  void dispose() {
    _captionController.dispose();
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    VideoCompress.dispose();
    super.dispose();
  }

  Future<void> _pickAndEditVideo() async {
    try {
      final XFile? pickedFile = await _picker.pickVideo(source: widget.imageSource);
      if (pickedFile == null) {
        if (mounted) Navigator.of(context).pop();
        return;
      }

      final editedFile = await Navigator.of(context).push<File?>(
        MaterialPageRoute(
          builder: (_) => VideoEditorScreen(file: File(pickedFile.path)),
        ),
      );

      if (editedFile != null) {
        setState(() {
          _editedVideoFile = editedFile;
        });
        await _initializePlayer();
      } else {
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('Error picking/editing video: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error selecting video.')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _initializePlayer() async {
    if (_editedVideoFile == null) return;

    _videoPlayerController?.dispose();
    _chewieController?.dispose();

    _videoPlayerController = VideoPlayerController.file(_editedVideoFile!);

    await _videoPlayerController!.initialize();
    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController!,
      autoPlay: true,
      looping: true,
      showControls: true,
      allowFullScreen: false,
    );
    setState(() {});
  }

  Future<Map<String, String>?> _uploadToCloudinary(File video) async {
    final url = Uri.parse('https://api.cloudinary.com/v1_1/dq0mb16fk/video/upload');
    final request = http.MultipartRequest('POST', url)
      ..fields['upload_preset'] = 'Prototype'
      ..fields['eager'] = 'sp_auto/w_400,h_600,c_fill,f_jpg';

    final bytes = await video.readAsBytes();
    final multipartFile = http.MultipartFile.fromBytes('file', bytes, filename: video.path);
    request.files.add(multipartFile);

    final response = await request.send();
    if (response.statusCode == 200) {
      final responseData = await response.stream.toBytes();
      final responseString = String.fromCharCodes(responseData);
      final jsonMap = jsonDecode(responseString);

      final videoUrl = jsonMap['secure_url'];
      final thumbnailUrl = jsonMap['eager'][0]['secure_url'];

      return {'videoUrl': videoUrl, 'thumbnailUrl': thumbnailUrl};
    } else {
      debugPrint('Cloudinary upload failed with status: ${response.statusCode}');
      return null;
    }
  }

  Future<void> _createReel() async {
    if (_editedVideoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a video.')));
      return;
    }
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _loadingMessage = "Compressing...";
    });

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final mediaInfo = await VideoCompress.compressVideo(
        _editedVideoFile!.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
      );

      if (mediaInfo?.file == null) {
        throw Exception('Video compression failed.');
      }

      setState(() => _loadingMessage = "Uploading...");

      final urls = await _uploadToCloudinary(mediaInfo!.file!);
      if (urls == null) {
        throw Exception('Video upload failed. Could not get URL.');
      }

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated.');
      }

      await context.read<PostRepository>().createPost(
        userId: currentUser.uid,
        username: currentUser.displayName ?? 'Anonymous',
        caption: _captionController.text.trim(),
        imageUrl: urls['videoUrl']!,
        thumbnailUrl: urls['thumbnailUrl']!,
        postType: 'reel',
      );

      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed to create reel: $e')));
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
        title: const Text('New Reel', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_editedVideoFile != null)
            TextButton(
              onPressed: _isLoading ? null : _createReel,
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
          if (_chewieController == null || !_videoPlayerController!.value.isInitialized)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else
            Column(
              children: [
                Expanded(
                  child: Center(
                    child: Chewie(
                      controller: _chewieController!,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  color: Colors.black.withAlpha(128),
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
              color: Colors.black.withAlpha(178),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 20),
                    Text(_loadingMessage, style: const TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
