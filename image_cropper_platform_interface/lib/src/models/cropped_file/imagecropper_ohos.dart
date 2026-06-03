import 'dart:io';

import 'package:flutter/services.dart';


class ImagecropperOhos {
  final methodChannel = const MethodChannel('imagecropper');
  Future<File?> sampleImage({
    required String path,
    required int maximumSize,
  }) async {
      String? filePath = await methodChannel.invokeMethod<String>('sampleImage',<String,dynamic>{
      'path':path,
      'maximumWidth':maximumSize,
      'maximumHeight':maximumSize,
    });
    return File(filePath!);
  }

  Future<File> cropImage({
    required File file,
    required Rect area,
    double? scale,
    double? angle,
    double? cx,
    double? cy,
  }) async {
      final path = await methodChannel.invokeMethod<String>('cropImage',{
      'path': file.path,
      'left': area.left,
      'top': area.top,
      'right': area.right,
      'bottom': area.bottom,
      'scale': scale ?? 1.0,
      'angle': angle ?? 0,
      'cx': cx ?? 0,
      'cy': cy ?? 0,
    });

    if (path != null) {
      return File(path);
    } else {
      throw Exception('Image cropping failed');
    }
  }

  Future<String?> recoverImage() async {
    return await methodChannel.invokeMethod<String>('recoverImage');
  }
}
