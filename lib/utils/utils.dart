import 'dart:math';

class Utils {
  static String generateRandomTopic([int length = 16]) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random.secure();
    return List.generate(
      length,
      (index) => chars[rand.nextInt(chars.length)],
    ).join();
  }

  static String extractNtfyTopic(String url) {
    try {
      final uri = Uri.parse(url);

      final topic = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';

      // Preserve the ?up=1 parameter if it exists
      if (uri.queryParameters.containsKey('up')) {
        return '$topic?up=${uri.queryParameters['up']}';
      }

      return topic;
    } catch (e) {
      return '';
    }
  }
}
