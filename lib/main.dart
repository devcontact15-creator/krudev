import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'video_engine.dart'; 

void main() => runApp(const UltraEditorApp());

class UltraEditorApp extends StatelessWidget {
  const UltraEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: const ProEditorScreen(),
    );
  }
}

class ProEditorScreen extends StatefulWidget {
  const ProEditorScreen({super.key});

  @override
  State<ProEditorScreen> createState() => _ProEditorScreenState();
}

class _ProEditorScreenState extends State<ProEditorScreen> {
  VideoPlayerController? _controller;
  String? _videoPath;
  bool _isExporting = false;

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickVideo(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _videoPath = pickedFile.path;
      });
      _initializeVideo();
    }
  }

  void _initializeVideo() {
    _controller = VideoPlayerController.file(File(_videoPath!))
      ..initialize().then((_) {
        setState(() {});
        _controller!.play();
        _controller!.setLooping(true);
      });
  }

  Future<void> _exportProVideo() async {
    if (_videoPath == null) return;
    
    setState(() => _isExporting = true);

    final resultPath = await ProVideoEngine.applyCinematicGrade(_videoPath!);

    setState(() => _isExporting = false);

    if (resultPath != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported to: $resultPath')),
      );
    } else {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export Failed!')),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('SkyScope Pro Editor'),
        backgroundColor: Colors.black87,
        actions: [
          if (_videoPath != null)
            IconButton(
              icon: const Icon(Icons.download, color: Colors.blue),
              onPressed: _isExporting ? null : _exportProVideo,
            )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Center(
              child: _controller != null && _controller!.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    )
                  : const Text('Pick a video to start editing', style: TextStyle(color: Colors.white54)),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.grey[900],
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isExporting) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 10),
                    const Text('Applying Pro Effects...', style: TextStyle(color: Colors.white)),
                  ] else ...[
                     ElevatedButton.icon(
                      icon: const Icon(Icons.add_a_photo),
                      label: const Text('Import Media'),
                      onPressed: _pickVideo,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildToolIcon(Icons.cut, 'Split'),
                        _buildToolIcon(Icons.color_lens, 'Color Grade'),
                        _buildToolIcon(Icons.animation, 'Keyframes'),
                        _buildToolIcon(Icons.audiotrack, 'Extract Audio'),
                      ],
                    )
                  ]
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildToolIcon(IconData icon, String label) {
    return Column(
      children: [
        IconButton(icon: Icon(icon, color: Colors.white70), onPressed: () {}),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
      ],
    );
  }
}
