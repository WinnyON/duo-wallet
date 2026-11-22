import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

const _prefix = 'data:image/png;base64,';
const _maxPhotoBytes = 300000;

// A bounded thumbnail travels with the existing private profile sync and backup.
Future<String> encodeProfilePhoto(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > 15 * 1024 * 1024) {
    throw const FormatException('Photo must be smaller than 15 MB');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      final scale =
          math.min(1.0, 256 / math.max(descriptor.width, descriptor.height));
      final codec = await descriptor.instantiateCodec(
          targetWidth: math.max(1, (descriptor.width * scale).round()),
          targetHeight: math.max(1, (descriptor.height * scale).round()));
      try {
        final frame = await codec.getNextFrame();
        try {
          final png =
              await frame.image.toByteData(format: ui.ImageByteFormat.png);
          if (png == null || png.lengthInBytes > _maxPhotoBytes) {
            throw const FormatException('Photo thumbnail is too large');
          }
          return '$_prefix${base64Encode(png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes))}';
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}

Uint8List? decodeProfilePhoto(String? value) {
  if (value == null ||
      !value.startsWith(_prefix) ||
      value.length > _prefix.length + ((_maxPhotoBytes + 2) ~/ 3) * 4) {
    return null;
  }
  try {
    final bytes = base64Decode(value.substring(_prefix.length));
    return bytes.isEmpty ? null : bytes;
  } on FormatException {
    return null;
  }
}
