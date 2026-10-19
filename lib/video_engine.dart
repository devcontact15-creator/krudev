import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

class ProVideoEngine {
  
  static Future<String?> applyCinematicGrade(String inputPath) async {
    final dir = await getTemporaryDirectory();
    final outputPath = '${dir.path}/skyscope_4K_120fps_${DateTime.now().millisecondsSinceEpoch}.mp4';

    // 🚀 ULTRA-LEVEL EXPORT COMMAND
    // scale=3840:2160 -> 4K Resolution
    // fps=120         -> 120 Frames Per Second (Ultra Extreme Smooth)
    // b:v 100M        -> 100 Mbps Bitrate (Lossless Quality)
    final command = '-y -i "$inputPath" -vf "scale=3840:2160,fps=120,eq=contrast=1.3:brightness=0.02:saturation=1.5" -c:v libx264 -preset ultrafast -b:v 100M -threads 2 -c:a copy "$outputPath"';

    print("4K 120FPS 100Mbps Export Started: $command");

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      print("Export Done: $outputPath");
      return outputPath;
    } else {
      print("Export Failed.");
      return null;
    }
  }

  static Future<String?> extractAudio(String inputPath) async {
    final dir = await getTemporaryDirectory();
    final outputPath = '${dir.path}/extracted_audio_${DateTime.now().millisecondsSinceEpoch}.mp3';

    final command = '-y -i "$inputPath" -q:a 0 -map a "$outputPath"';

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      return outputPath;
    }
    return null;
  }
}
