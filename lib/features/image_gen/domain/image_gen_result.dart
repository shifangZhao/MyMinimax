class ImageGenResult {

  ImageGenResult({
    this.taskId,
    this.imageUrls = const [],
    this.base64Images = const [],
  });
  final String? taskId;
  final List<String> imageUrls;
  final List<String> base64Images;
}
