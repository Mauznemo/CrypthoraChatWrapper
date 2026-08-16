import 'package:crypthora_chat_wrapper/pages/add_server_page.dart';
import 'package:crypthora_chat_wrapper/pages/log_viewer_page.dart';
import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        // Pops back to the still-alive ChatPage. Pushing a new one here used to recreate the
        // WebView, so opening settings and going back reloaded the whole web app.
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AddServerPage(canGoBack: true),
                    ),
                  );
                },
                child: const Text('Set Server'),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => LogViewerPage()),
                  );
                },
                child: const Text('Show Logs'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
