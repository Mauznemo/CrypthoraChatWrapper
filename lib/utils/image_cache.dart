import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class ImageCache {
  static final ImageCache _instance = ImageCache._internal();
  factory ImageCache() => _instance;
  ImageCache._internal();

  Future<Directory> _getCacheDir() async {
    final dir = await getTemporaryDirectory();
    final cacheDir = Directory('${dir.path}/notification_images');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  String _getCacheKey(String url) {
    return url.hashCode.abs().toString();
  }

  Future<Uint8List?> getImage(String? url) async {
    if (url == null) return null;
    try {
      final cacheDir = await _getCacheDir();
      final cacheKey = _getCacheKey(url);
      final cacheFile = File('${cacheDir.path}/$cacheKey.png');

      // Check if image exists in cache
      if (await cacheFile.exists()) {
        debugPrint('[image_cache] Loading image from cache');
        return await cacheFile.readAsBytes();
      }

      // Download image
      debugPrint('[image_cache] Downloading image from URL');
      final response = await http.get(Uri.parse('$url&size=512'));
      if (response.statusCode == 200) {
        final imageBytes = response.bodyBytes;
        debugPrint(
          '[image_cache] Content-Type: ${response.headers['content-type']}',
        );
        debugPrint('[image_cache] Image size: ${imageBytes.length} bytes');

        // Decode the image (handles webp, jpeg, png, etc.)
        final decodedImage = img.decodeImage(imageBytes);

        if (decodedImage != null) {
          // Re-encode as PNG (fully compatible with Android notifications)
          final pngBytes = Uint8List.fromList(img.encodePng(decodedImage));

          // Save to cache as PNG
          await cacheFile.writeAsBytes(pngBytes);
          return pngBytes;
        } else {
          debugPrint('[image_cache] Failed to decode image');
        }
      } else {
        debugPrint('[image_cache] Failed to download image');
      }
    } catch (e) {
      debugPrint('[image_cache] Error loading image: $e');
    }
    debugPrint('[image_cache] Failed to load image');
    return null;
  }

  Future<void> clearCache() async {
    final cacheDir = await _getCacheDir();
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
    }
  }
}
