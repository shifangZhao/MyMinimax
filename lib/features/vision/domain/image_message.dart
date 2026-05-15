import 'package:equatable/equatable.dart';

class ImageMessage extends Equatable {

  const ImageMessage({
    required this.id,
    required this.imageBase64,
    required this.createdAt, this.prompt,
    this.response,
  });
  final String id;
  final String imageBase64;
  final String? prompt;
  final String? response;
  final DateTime createdAt;

  bool get hasResponse => response != null;

  @override
  List<Object?> get props => [id, imageBase64, prompt, response, createdAt];
}
