import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypthora_chat_wrapper/utils/disk_logger.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Downloads and caches profile pictures for notifications and shortcuts.
///
/// Everything here runs in the FCM background isolate as often as it does on the main one, so it
/// has to be defensive: a stalled download in doze is the difference between a notification with a
/// picture and one with a generated letter.
class AvatarCache {
  static final AvatarCache _instance = AvatarCache._internal();
  factory AvatarCache() => _instance;
  AvatarCache._internal();

  /// The shade renders avatars at roughly 48dp and large icons at 64dp, so 256px covers even
  /// xxxhdpi. Anything bigger is only parcel weight.
  static const _imageSize = 256;

  /// Past this the encoded image is re-done as JPEG. Notification extras cross a 1MB binder
  /// transaction, and a lossless PNG of a photo blows through that far too easily.
  static const _maxBytes = 60 * 1024;

  static const _maxAge = Duration(days: 7);
  static const _requestTimeout = Duration(seconds: 8);

  Future<Directory> _getCacheDir() async {
    final dir = await getTemporaryDirectory();
    final cacheDir = Directory('${dir.path}/notification_images');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  String _getCacheKey(String url) =>
      md5.convert(utf8.encode(url)).toString();

  /// Path to a cached square image for [url], or null if it could not be fetched.
  ///
  /// A path rather than the bytes on purpose: both `flutter_local_notifications` and the shortcut
  /// plugin can decode a file natively, which keeps the image off the method channel and out of
  /// the notification's extras.
  Future<String?> getImagePath(String? url) async {
    if (url == null || url.isEmpty) return null;
    try {
      final cacheDir = await _getCacheDir();
      final cacheFile = File('${cacheDir.path}/${_getCacheKey(url)}.img');

      if (await cacheFile.exists()) {
        final age = DateTime.now().difference(await cacheFile.lastModified());
        if (age < _maxAge) return cacheFile.path;
        // Profile pictures are served under a stable path, so a stale entry is the only way a
        // changed picture ever gets picked up.
        await cacheFile.delete();
      }

      final bytes = await _download(url);
      if (bytes == null) return null;

      await cacheFile.writeAsBytes(bytes);
      unawaited(_prune());
      return cacheFile.path;
    } catch (e) {
      DiskLogger.error('[avatar_cache] Error loading image: $e');
      return null;
    }
  }

  Future<Uint8List?> _download(String url) async {
    final uri = Uri.parse(url).replace(
      queryParameters: {
        ...Uri.parse(url).queryParameters,
        'size': '$_imageSize',
      },
    );

    final response = await http.get(uri).timeout(_requestTimeout);
    if (response.statusCode != 200) {
      DiskLogger.warning(
        '[avatar_cache] Download failed with ${response.statusCode}',
      );
      return null;
    }

    final decoded = img.decodeImage(response.bodyBytes);
    if (decoded == null) {
      DiskLogger.warning('[avatar_cache] Failed to decode image');
      return null;
    }

    final resized = decoded.width > _imageSize || decoded.height > _imageSize
        ? img.copyResize(decoded, width: _imageSize, height: _imageSize)
        : decoded;

    final png = Uint8List.fromList(img.encodePng(resized));
    if (png.length <= _maxBytes) return png;

    // JPEG has no alpha, so anything transparent has to land on something.
    final flattened = img.Image(width: resized.width, height: resized.height);
    img.fill(flattened, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(flattened, resized);
    final jpg = Uint8List.fromList(img.encodeJpg(flattened, quality: 85));
    debugPrint(
      '[avatar_cache] Re-encoded ${png.length}B png as ${jpg.length}B jpg',
    );
    return jpg;
  }

  /// Drops entries that outlived [_maxAge]. The cache is keyed by url and nothing else ever
  /// removes them.
  Future<void> _prune() async {
    try {
      final cacheDir = await _getCacheDir();
      final now = DateTime.now();
      await for (final entity in cacheDir.list()) {
        if (entity is! File) continue;
        if (now.difference(await entity.lastModified()) > _maxAge) {
          await entity.delete();
        }
      }
    } catch (e) {
      debugPrint('[avatar_cache] Prune failed: $e');
    }
  }

  Future<void> clearCache() async {
    final cacheDir = await _getCacheDir();
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
    }
  }
}
