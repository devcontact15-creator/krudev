import 'dart:io';
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';

class ProVideoEngine {
  
  static Future<String?> applyCinematicGrade(String inputPath) async {
    final dir = await getTemporaryDirectory();
    final outputPath = '${dir.path}/cinematic_export_${DateTime.now().millisecondsSinceEpoch}.mp4';

    // Pro Color Grade Command
    final command = '-y -i "$inputPath" -vf "eq=contrast=1.3:brightness=0.02:saturation=1.5" -c:v libx264 -preset veryfast -crf 22 -c:a copy "$outputPath"';

    print("Export Started: $command");

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      return outputPath;
    } else {
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
