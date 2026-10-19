import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'video_engine.dart'; 

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    _cameras = await availableCameras();
  } catch (e) {
    print("Camera error: $e");
  }
  runApp(const SkyScopeProApp());
}

class SkyScopeProApp extends StatelessWidget {
  const SkyScopeProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SkyScope Pro',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        primaryColor: Colors.blueAccent,
        useMaterial3: true,
      ),
      home: const CameraScreen(),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _cameraController;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (_cameras.isEmpty) return;
    _cameraController = CameraController(_cameras[0], ResolutionPreset.max);
    await _cameraController!.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _recordVideo() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    
    if (_isRecording) {
      final file = await _cameraController!.stopVideoRecording();
      setState(() => _isRecording = false);
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => ProEditorScreen(videoPath: file.path),
        ));
      }
    } else {
      await _cameraController!.startVideoRecording();
      setState(() => _isRecording = true);
    }
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final file = await picker.pickVideo(source: ImageSource.gallery);
    if (file != null && mounted) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ProEditorScreen(videoPath: file.path),
      ));
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.blueAccent)));
    }
    
    return Scaffold(
      body: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(child: CameraPreview(_cameraController!)),
          Positioned(
            top: 50,
            child: Text(
              _isRecording ? "🔴 REC" : "SKY-SCOPE PRO",
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2),
            ),
          ),
          Positioned(
            bottom: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.photo_library, size: 30, color: Colors.white),
                  onPressed: _pickFromGallery,
                ),
                const SizedBox(width: 40),
                GestureDetector(
                  onTap: _recordVideo,
                  child: Container(
                    height: 70, width: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      color: _isRecording ? Colors.red : Colors.transparent,
                    ),
                  ),
                ),
                const SizedBox(width: 40),
                IconButton(
                  icon: const Icon(Icons.cameraswitch, size: 30, color: Colors.white),
                  onPressed: () {},
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class ProEditorScreen extends StatefulWidget {
  final String videoPath;
  const ProEditorScreen({super.key, required this.videoPath});

  @override
  State<ProEditorScreen> createState() => _ProEditorScreenState();
}

class _ProEditorScreenState extends State<ProEditorScreen> {
  late VideoPlayerController _controller;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.videoPath))
      ..initialize().then((_) {
        setState(() {});
        _controller.play();
        _controller.setLooping(true);
      });
  }

  Future<void> _exportVideo() async {
    setState(() => _isExporting = true);
    
    final resultPath = await ProVideoEngine.applyCinematicGrade(widget.videoPath);
    
    setState(() => _isExporting = false);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(resultPath != null ? '✅ Ultra Export Saved!' : '❌ Export Failed'),
          backgroundColor: resultPath != null ? Colors.green : Colors.red,
        ),
      );
    }
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
        title: const Text("Workspace", style: TextStyle(fontSize: 16)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
              icon: _isExporting 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.ios_share, size: 18),
              label: Text(_isExporting ? "Rendering..." : "4K 120fps Export"),
              onPressed: _isExporting ? null : _exportVideo,
            ),
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 4,
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10)],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _controller.value.isInitialized
                    ? AspectRatio(aspectRatio: _controller.value.aspectRatio, child: VideoPlayer(_controller))
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
          
          Expanded(
            flex: 3,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF181818),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("MOTION GRAPHICS & TOOLS", style: TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 1.5)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildProTool(Icons.cut, 'Split Track'),
                      _buildProTool(Icons.motion_photos_auto, 'Keyframes'),
                      _buildProTool(Icons.color_lens, 'Color Grade'),
                      _buildProTool(Icons.graphic_eq, 'Audio Splitting'),
                      _buildProTool(Icons.speed, 'Speed Curve'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProTool(IconData icon, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
      ],
    );
  }
}
