import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../../core/api/minimax_client.dart';

class VisionRepository {

  VisionRepository({required MinimaxClient client}) : _client = client, _picker = ImagePicker();
  final MinimaxClient _client;
  final ImagePicker _picker;

  Future<String?> pickImage({ImageSource source = ImageSource.gallery}) async {
    final image = await _picker.pickImage(source: source, maxWidth: 1024, maxHeight: 1024, imageQuality: 85);
    if (image == null) return null;
    final bytes = await File(image.path).readAsBytes();
    return base64Encode(bytes);
  }

  Future<String> analyzeImage(String imageBase64, String prompt) async {
    return _client.vision(imageBase64, prompt);
  }
}
