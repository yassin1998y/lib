import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:video_editor/video_editor.dart';
import 'package:ffmpeg_kit_flutter_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_video/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart'; // FIX: Added missing import for VideoPlayer

// A simple class to hold text overlay data
class TextOverlay {
  final String id;
  String text;
  Offset position;
  double size;
  Color color;
  TextAlign align;

  TextOverlay({
    required this.text,
    required this.position,
    this.size = 24.0,
    this.color = Colors.white,
    this.align = TextAlign.center,
  }) : id = const Uuid().v4();
}


class VideoEditorScreen extends StatefulWidget {
  final File file;

  const VideoEditorScreen({super.key, required this.file});

  @override
  State<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<VideoEditorScreen> {
  final _exportingProgress = ValueNotifier<double>(0.0);
  final _isExporting = ValueNotifier<bool>(false);
  final double height = 60;

  late final VideoEditorController _controller;
  bool _isControllerInitialized = false;
  int _selectedIndex = 0;

  // --- State for new features ---
  String? _selectedMusicAsset;
  List<double>? _selectedFilterMatrix;
  final List<TextOverlay> _textOverlays = [];
  TextOverlay? _selectedTextOverlay;
  // ---

  // Placeholder data for new features
  final List<Map<String, dynamic>> _musicTracks = [
    {'name': 'None', 'asset': null},
    {'name': 'Uplifting', 'asset': 'assets/music/uplifting.mp3'},
    {'name': 'Chill', 'asset': 'assets/music/chill.mp3'},
  ];

  final List<Color> _textColors = [
    Colors.white, Colors.black, Colors.red, Colors.blue, Colors.green, Colors.yellow, Colors.purple, Colors.orange
  ];

  final List<Map<String, dynamic>> _filters = [
    {'name': 'None', 'matrix': null},
    {'name': 'Grayscale', 'matrix': const [
      0.2126, 0.7152, 0.0722, 0, 0.2126, 0.7152, 0.0722, 0,
      0.2126, 0.7152, 0.0722, 0, 0,      0,      0,      1,
    ]},
    {'name': 'Sepia', 'matrix': const [
      0.393, 0.769, 0.189, 0, 0.349, 0.686, 0.168, 0,
      0.272, 0.534, 0.131, 0, 0,     0,     0,     1,
    ]},
  ];

  @override
  void initState() {
    super.initState();
    _controller = VideoEditorController.file(
      widget.file,
      minDuration: const Duration(seconds: 1),
      maxDuration: const Duration(seconds: 60),
    );

    _controller.initialize().then((_) {
      if (mounted) {
        setState(() => _isControllerInitialized = true);
      }
    }).catchError((error) {
      Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _exportingProgress.dispose();
    _isExporting.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _exportVideo() async {
    // Deselect any active text overlay before exporting
    setState(() => _selectedTextOverlay = null);
    await Future.delayed(const Duration(milliseconds: 100));

    _isExporting.value = true;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final tempDir = await getTemporaryDirectory();
    final outputPath = '${tempDir.path}/${const Uuid().v4()}.mp4';

    // FIX: Removed all crop-related logic from the FFmpeg command.
    const String crop = "";

    // Handle music asset
    String musicInput = "";
    String audioMix = "[0:a]volume=1.0[a0];";
    String mapAudio = "-map 0:a?";

    if (_selectedMusicAsset != null) {
      final musicAsset = await rootBundle.load(_selectedMusicAsset!);
      final musicFile = File('${tempDir.path}/temp_music.mp3');
      await musicFile.writeAsBytes(musicAsset.buffer.asUint8List());
      musicInput = "-i '${musicFile.path}'";
      audioMix = "[0:a]volume=0.5[a0];[1:a]volume=1.0[a1];[a0][a1]amix=inputs=2:duration=first[a];";
      mapAudio = "-map [a]";
    }

    // Handle filter
    final filter = _selectedFilterMatrix != null
        ? "colorchannelmixer=matrix=${_selectedFilterMatrix!.join('\\:')},"
        : "";

    // Handle text overlays (this is a simplified example)
    String drawText = "";
    for (var overlay in _textOverlays) {
      final sanitizedText = overlay.text.replaceAll("'", "'\\''");
      drawText += "drawtext=text='$sanitizedText':x=${overlay.position.dx}:y=${overlay.position.dy}:fontsize=${overlay.size}:fontcolor=${_colorToHex(overlay.color)},";
    }

    // Construct the FFmpeg command
    final command =
        "-i '${widget.file.path}' $musicInput "
        "-ss ${_controller.startTrim.inMilliseconds / 1000} "
        "-to ${_controller.endTrim.inMilliseconds / 1000} "
        "-filter_complex \"[0:v]${crop}format=yuv420p,${filter}${drawText}scale=720:-2[v];$audioMix\" "
        "-map \"[v]\" $mapAudio "
        "-c:v libx264 -preset ultrafast "
        "'$outputPath'";

    debugPrint("FFmpeg Command: $command");

    await FFmpegKit.execute(command).then((session) async {
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode)) {
        navigator.pop(File(outputPath));
      } else {
        final logs = await session.getLogsAsString();
        debugPrint("FFmpeg failed: $logs");
        messenger.showSnackBar(const SnackBar(
          content: Text('Error exporting video. Please try again.'),
          backgroundColor: Colors.red,
        ));
      }
    });

    _isExporting.value = false;
  }

  String _colorToHex(Color color) {
    return '0x${color.value.toRadixString(16).substring(2)}';
  }

  void _showAddTextDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Add Text"),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(hintText: "Enter your text"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              if (textController.text.isNotEmpty) {
                setState(() {
                  final newOverlay = TextOverlay(
                    text: textController.text,
                    position: const Offset(100, 100),
                  );
                  _textOverlays.add(newOverlay);
                  _selectedTextOverlay = newOverlay;
                });
              }
              Navigator.of(context).pop();
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: !_isControllerInitialized
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _topNavBar(),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedTextOverlay = null),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // FIX: Replaced CropGridViewer with a standard VideoPlayer.
                        // This removes the crop UI and associated logic.
                        Center(
                          child: AspectRatio(
                            aspectRatio: _controller.video.value.aspectRatio,
                            child: VideoPlayer(_controller.video),
                          ),
                        ),
                        ..._textOverlays.map((overlay) => DraggableText(
                          overlay: overlay,
                          isSelected: _selectedTextOverlay?.id == overlay.id,
                          onTap: () => setState(() => _selectedTextOverlay = overlay),
                          onUpdate: () => setState(() {}),
                        )),
                        AnimatedBuilder(
                          animation: _controller.video,
                          builder: (_, __) => AnimatedOpacity(
                            opacity: _controller.isPlaying ? 0 : 1,
                            duration: const Duration(milliseconds: 300),
                            child: GestureDetector(
                              onTap: _controller.video.play,
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.play_arrow, color: Colors.black),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _bottomNavBar(),
                _bottomToolView(),
              ],
            ),
            ValueListenableBuilder(
              valueListenable: _isExporting,
              builder: (_, bool isExporting, __) => isExporting
                  ? Center(
                child: AlertDialog(
                  backgroundColor: Colors.black.withOpacity(0.7),
                  title: const Text(
                    "Processing video...",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              )
                  : const SizedBox.shrink(),
            )
          ],
        ),
      ),
    );
  }

  Widget _topNavBar() {
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            Expanded(
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
            const Expanded(
              child: Text(
                'Editor',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            Expanded(
              child: IconButton(
                onPressed: _exportVideo,
                icon: const Icon(Icons.check, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomNavBar() {
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildNavBarIcon(0, Icons.cut, "Trim"),
            _buildNavBarIcon(1, Icons.music_note, "Music"),
            _buildNavBarIcon(2, Icons.text_fields, "Text"),
            _buildNavBarIcon(3, Icons.filter, "Filter"),
            // FIX: Removed the Crop button from the navigation bar.
          ],
        ),
      ),
    );
  }

  Widget _buildNavBarIcon(int index, IconData icon, String text) {
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedIndex = index;
            _selectedTextOverlay = null; // Deselect text when switching tools
          });
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _selectedIndex == index ? Colors.blue : Colors.white),
            Text(text, style: TextStyle(color: _selectedIndex == index ? Colors.blue : Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _bottomToolView() {
    switch (_selectedIndex) {
      case 0: // Trim
        return TrimSlider(
          controller: _controller,
          height: height,
          horizontalMargin: height / 4,
        );
      case 1: // Music
        return _buildMusicSelector();
      case 2: // Text
        return _buildTextTool();
      case 3: // Filter
        return _buildFilterSelector();
    // FIX: Removed the case for the Crop tool.
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildMusicSelector() {
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _musicTracks.length,
        itemBuilder: (context, index) {
          final track = _musicTracks[index];
          final isSelected = _selectedMusicAsset == track['asset'];
          return InkWell(
            onTap: () => setState(() => _selectedMusicAsset = track['asset']),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blue : Colors.grey[800],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      track['asset'] == null ? Icons.music_off : Icons.music_note,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  Text(track['name']!, style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTextTool() {
    if (_selectedTextOverlay != null) {
      // Show editing tools if a text is selected
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            // Color Palette
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _textColors.length,
                itemBuilder: (context, index) {
                  final color = _textColors[index];
                  return GestureDetector(
                    onTap: () => setState(() => _selectedTextOverlay!.color = color),
                    child: Container(
                      width: 40,
                      height: 40,
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: _selectedTextOverlay!.color == color ? 2 : 0),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Size Slider
            Row(
              children: [
                const Icon(Icons.format_size, color: Colors.white),
                Expanded(
                  child: Slider(
                    value: _selectedTextOverlay!.size,
                    min: 12.0,
                    max: 72.0,
                    onChanged: (value) => setState(() => _selectedTextOverlay!.size = value),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    setState(() {
                      _textOverlays.removeWhere((o) => o.id == _selectedTextOverlay!.id);
                      _selectedTextOverlay = null;
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      // Show "Add Text" button if no text is selected
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: ElevatedButton(
          onPressed: _showAddTextDialog,
          child: const Text("Add Text"),
        ),
      );
    }
  }

  Widget _buildFilterSelector() {
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _filters.length,
        itemBuilder: (context, index) {
          final filter = _filters[index];
          final isSelected = _selectedFilterMatrix == filter['matrix'];
          return InkWell(
            onTap: () => setState(() => _selectedFilterMatrix = filter['matrix']),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      border: isSelected ? Border.all(color: Colors.blue, width: 2) : null,
                      color: Colors.grey,
                    ),
                    child: Center(child: Text(filter['name']!, style: const TextStyle(color: Colors.white))),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

// FIX: Removed the _buildCropTool method entirely.
}

// A widget to make text overlays draggable and editable
class DraggableText extends StatefulWidget {
  final TextOverlay overlay;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onUpdate;

  const DraggableText({
    super.key,
    required this.overlay,
    required this.isSelected,
    required this.onTap,
    required this.onUpdate,
  });

  @override
  State<DraggableText> createState() => _DraggableTextState();
}

class _DraggableTextState extends State<DraggableText> {
  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.overlay.position.dx,
      top: widget.overlay.position.dy,
      child: GestureDetector(
        onTap: widget.onTap,
        onPanUpdate: (details) {
          setState(() {
            widget.overlay.position += details.delta;
            widget.onUpdate();
          });
        },
        child: Container(
          padding: const EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            border: widget.isSelected ? Border.all(color: Colors.blue, width: 2, style: BorderStyle.solid) : null,
          ),
          child: Text(
            widget.overlay.text,
            style: TextStyle(
              color: widget.overlay.color,
              fontSize: widget.overlay.size,
              fontWeight: FontWeight.bold,
              shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
            ),
          ),
        ),
      ),
    );
  }
}
