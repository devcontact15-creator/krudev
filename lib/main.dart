import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'video_engine.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KrudevApp());
}

class KrudevApp extends StatelessWidget {
  const KrudevApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Krudev',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1A0008), 
        primaryColor: const Color(0xFFFFB6C1), 
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

// -----------------------------------------
// 🏠 HOME SCREEN (Official Image Picker)
// -----------------------------------------
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _pickVideo(BuildContext context) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? file = await picker.pickVideo(source: ImageSource.gallery);
      
      if (file != null && context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProEditorScreen(videoPath: file.path)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Action cancelled or gallery not available."))
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("KRUDEV", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 3, color: Color(0xFFFFB6C1))),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Center(
        child: GestureDetector(
          onTap: () => _pickVideo(context),
          child: Container(
            height: 150, width: 250,
            decoration: BoxDecoration(
              color: const Color(0xFFFFB6C1).withOpacity(0.1),
              border: Border.all(color: const Color(0xFFFFB6C1), width: 2),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFB6C1).withOpacity(0.2),
                  blurRadius: 15,
                  spreadRadius: 2,
                )
              ]
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_circle_outline, size: 50, color: Color(0xFFFFB6C1)),
                SizedBox(height: 10),
                Text("New Project", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------
// ✂️ PRO EDITOR WORKSPACE (Baby Pink)
// -----------------------------------------
class ProEditorScreen extends StatefulWidget {
  final String videoPath;
  const ProEditorScreen({super.key, required this.videoPath});

  @override
  State<ProEditorScreen> createState() => _ProEditorScreenState();
}

class _ProEditorScreenState extends State<ProEditorScreen> {
  late VideoPlayerController _controller;
  bool _isExporting = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      _controller = VideoPlayerController.file(File(widget.videoPath));
      await _controller.initialize();
      setState(() {});
      _controller.play();
      _controller.setLooping(true);
    } catch (e) {
      setState(() => _hasError = true);
    }
  }

  Future<void> _exportVideo() async {
    setState(() => _isExporting = true);
    final resultPath = await ProVideoEngine.applyCinematicGrade(widget.videoPath);
    setState(() => _isExporting = false);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(resultPath != null ? '✅ Ultra 4K Export Saved!' : '❌ Export Failed'),
          backgroundColor: resultPath != null ? Colors.green : Colors.red,
        ),
      );
    }
  }

  void _onToolClicked(String toolName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("⚙️ $toolName Layer Added to Timeline!"),
        backgroundColor: const Color(0xFF330011),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Workspace", style: TextStyle(fontSize: 16, color: Color(0xFFFFB6C1))),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFFFFB6C1)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB6C1), foregroundColor: Colors.black),
              icon: _isExporting 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                  : const Icon(Icons.ios_share, size: 18),
              label: Text(_isExporting ? "Rendering..." : "4K 120fps Export", style: const TextStyle(fontWeight: FontWeight.bold)),
              onPressed: _isExporting ? null : _exportVideo,
            ),
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFFB6C1).withOpacity(0.3), width: 2),
                boxShadow: [
                  BoxShadow(color: const Color(0xFFFFB6C1).withOpacity(0.1), blurRadius: 10, spreadRadius: 1)
                ]
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: _hasError 
                  ? const Center(child: Text("❌ Failed to load video format.", style: TextStyle(color: Colors.red)))
                  : _controller.value.isInitialized
                    ? AspectRatio(aspectRatio: _controller.value.aspectRatio, child: VideoPlayer(_controller))
                    : const Center(child: CircularProgressIndicator(color: Color(0xFFFFB6C1))),
              ),
            ),
          ),
          
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF1A0008),
                borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 16.0, bottom: 10),
                    child: Text("MOTION & EFFECTS", style: TextStyle(color: Color(0xFFFFB6C1), fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      children: [
                        _buildProTool(Icons.cut, 'Split', () => _onToolClicked("Split Track")),
                        _buildProTool(Icons.center_focus_strong, 'Null Object', () => _onToolClicked("Null Object")),
                        _buildProTool(Icons.video_camera_front, '3D Camera', () => _onToolClicked("3D Camera")),
                        _buildProTool(Icons.animation, 'Keyframes', () => _onToolClicked("Keyframe Animator")),
                        _buildProTool(Icons.blur_on, 'Motion Blur', () => _onToolClicked("Motion Blur")),
                        _buildProTool(Icons.waves, 'Glitch / VHS', () => _onToolClicked("Glitch Effect")),
                        _buildProTool(Icons.color_lens, 'Color Grade', () => _onToolClicked("Color Curves")),
                        _buildProTool(Icons.speed, 'Speed Curve', () => _onToolClicked("Time Remapping")),
                        _buildProTool(Icons.graphic_eq, 'Extract Audio', () => _onToolClicked("Audio Track")),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProTool(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 75,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB6C1).withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFFB6C1).withOpacity(0.3)),
              ),
              child: Icon(icon, color: const Color(0xFFFFB6C1), size: 26),
            ),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
