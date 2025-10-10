import 'dart:math';

import 'package:crypthora_chat_wrapper/pages/chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AddServerPage extends StatefulWidget {
  final bool canGoBack;
  const AddServerPage({super.key, required this.canGoBack});

  @override
  State<AddServerPage> createState() => _AddServerPageState();
}

class _AddServerPageState extends State<AddServerPage> {
  final TextEditingController _serverUrlController = TextEditingController();
  final TextEditingController _notificationServerUrlController =
      TextEditingController();

  String generateRandomTopic([int length = 16]) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random.secure();
    return List.generate(
      length,
      (index) => chars[rand.nextInt(chars.length)],
    ).join();
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _notificationServerUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          FlutterI18n.translate(context, 'server-settings.set-server'),
        ),
        leading: widget.canGoBack
            ? IconButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => ChatPage()),
                  );
                },
                icon: const Icon(Icons.arrow_back),
              )
            : null,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextField(
                controller: _serverUrlController,
                decoration: InputDecoration(
                  labelText: FlutterI18n.translate(
                    context,
                    'server-settings.server-url',
                  ),
                  hintText: 'https://chat.my-server.com',
                ),
              ),
              TextField(
                controller: _notificationServerUrlController,

                decoration: InputDecoration(
                  labelText: FlutterI18n.translate(
                    context,
                    'server-settings.notification-server-url',
                  ),
                  hintText: 'wss://ntfy.my-server.com',
                ),
              ),
              FilledButton(
                onPressed: () async {
                  if (_serverUrlController.text.isEmpty) return;
                  if (_notificationServerUrlController.text.isEmpty) return;

                  String topic = generateRandomTopic();

                  var prefs = await SharedPreferences.getInstance();
                  await prefs.setString('serverUrl', _serverUrlController.text);
                  await prefs.setString(
                    'notificationServerUrl',
                    _notificationServerUrlController.text,
                  );
                  await prefs.setString('topic', topic);
                  if (mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => ChatPage()),
                    );
                  }
                },
                child: Text(FlutterI18n.translate(context, 'common.save')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
