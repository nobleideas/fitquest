import 'dart:typed_data';

class CompressedFormVideo {
  final Uint8List bytes;
  final String mimeType;
  final int originalSize;
  final int compressedSize;

  const CompressedFormVideo({
    required this.bytes,
    required this.mimeType,
    required this.originalSize,
    required this.compressedSize,
  });
}

Future<CompressedFormVideo> compressFormVideo(
  Uint8List bytes,
  String mimeType,
) async {
  throw UnsupportedError('Video compression currently requires Flutter Web.');
}
