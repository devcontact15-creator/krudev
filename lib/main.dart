import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

void main() => runApp(const KrudevApp());

class KrudevApp extends StatelessWidget {
  const KrudevApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Krudev',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const EditorPage(),
    );
  }
}

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  VideoPlayerController? _c;

  Future<void> _pick() async {
    final f = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (f == null) return;
    await _c?.dispose();
    final c = VideoPlayerController.file(File(f.path));
    await c.initialize();
    setState(() => _c = c);
    c.play();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      appBar: AppBar(title: const Text('Krudev')),
      body: Column(
        children: [
          Expanded(
            child: c == null
                ? const Center(child: Text('Koi video nahi chuna'))
                : Center(
                    child: AspectRatio(
                      aspectRatio: c.value.aspectRatio,
                      child: VideoPlayer(c),
                    ),
                  ),
          ),
          if (c != null) VideoProgressIndicator(c, allowScrubbing: true),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _pick,
                  icon: const Icon(Icons.video_library),
                  label: const Text('Video chuno'),
                ),
                if (c != null) ...[
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        c.value.isPlaying ? c.pause() : c.play();
                      });
                    },
                    icon: Icon(
                      c.value.isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
