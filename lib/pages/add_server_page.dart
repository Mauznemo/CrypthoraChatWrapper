import 'dart:math';

import 'package:crypthora_chat_wrapper/pages/chat_page.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AddServerPage extends StatefulWidget {
  const AddServerPage({super.key});

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
      appBar: AppBar(title: const Text('Add Server')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextField(
                controller: _serverUrlController,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://chat.my-server.com',
                ),
              ),
              TextField(
                controller: _notificationServerUrlController,

                decoration: const InputDecoration(
                  labelText: 'Notification Server URL',
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
                child: const Text('Add'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
