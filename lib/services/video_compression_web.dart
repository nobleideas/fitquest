
import 'dart:js_interop';
import 'dart:typed_data';

@JS('fitQuestCompressVideo')
external JSPromise<JSCompressedVideo> _compressVideo(
  JSUint8Array bytes,
  JSString mimeType,
  JSNumber maxSeconds,
);

@JS()
extension type JSCompressedVideo._(JSObject _) implements JSObject {
  external JSUint8Array get bytes;
  external JSString get mimeType;
  external JSNumber get originalSize;
  external JSNumber get compressedSize;
}

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
  final result = await _compressVideo(
    bytes.toJS,
    mimeType.toJS,
    60.toJS,
  ).toDart;

  return CompressedFormVideo(
    bytes: result.bytes.toDart,
    mimeType: result.mimeType.toDart,
    originalSize: result.originalSize.toDartInt,
    compressedSize: result.compressedSize.toDartInt,
  );
}
