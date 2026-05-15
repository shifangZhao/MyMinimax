import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 加载用户定位图标 PNG 并返回字节（带可选的朝向旋转）。
///
/// [heading] 为弧度，默认 0 朝上。
/// 图标原图尖头朝上，原生端通过 rotateAngle 控制实际朝向。
Future<Uint8List> generateUserLocationIcon(
  BuildContext context, {
  double heading = 0,
}) async {
  // 从 assets 加载 PNG 字节
  final rawBytes = await rootBundle.load('assets/images/user_location_marker.png');
  final rawData = rawBytes.buffer.asUint8List();

  if (heading == 0) {
    // 无需旋转，直接返回原始字节
    return rawData;
  }

  // 解码 PNG 并做朝向旋转
  final codec = await ui.instantiateImageCodec(rawData);
  final frame = await codec.getNextFrame();
  final srcImage = frame.image;
  final w = srcImage.width;
  final h = srcImage.height;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  canvas.translate(w / 2, h / 2);
  canvas.rotate(heading);
  canvas.translate(-w / 2, -h / 2);
  canvas.drawImage(srcImage, Offset.zero, Paint());

  final picture = recorder.endRecording();
  final dstImage = await picture.toImage(w, h);
  final byteData = await dstImage.toByteData(format: ui.ImageByteFormat.png);

  srcImage.dispose();
  dstImage.dispose();

  return byteData!.buffer.asUint8List();
}
