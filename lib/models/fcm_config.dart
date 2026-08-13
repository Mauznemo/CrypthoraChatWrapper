import 'package:firebase_core/firebase_core.dart';

/// The Firebase values needed to initialize FCM at runtime.
///
/// The wrapper ships as a single apk for every self hosted CrypthoraChat instance, so it can't have
/// a `google-services.json` baked in at build time. Instead the server this app is pointed at
/// serves these four values from `/api/push-config` and they are passed to [Firebase.initializeApp].
///
/// They are not secret, the same values sit inside every apk of every Firebase app.
class FcmConfig {
  final String projectId;
  final String appId;
  final String apiKey;
  final String messagingSenderId;

  const FcmConfig({
    required this.projectId,
    required this.appId,
    required this.apiKey,
    required this.messagingSenderId,
  });

  factory FcmConfig.fromJson(Map<String, dynamic> json) => FcmConfig(
    projectId: json['projectId'] as String,
    appId: json['appId'] as String,
    apiKey: json['apiKey'] as String,
    messagingSenderId: json['messagingSenderId'] as String,
  );

  Map<String, dynamic> toJson() => {
    'projectId': projectId,
    'appId': appId,
    'apiKey': apiKey,
    'messagingSenderId': messagingSenderId,
  };

  FirebaseOptions toFirebaseOptions() => FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
  );
}
