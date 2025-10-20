import 'package:crypthora_chat_wrapper/components/custom_dropdown_button.dart';
import 'package:crypthora_chat_wrapper/components/custom_text_form_field.dart';
import 'package:crypthora_chat_wrapper/pages/chat_page.dart';
import 'package:crypthora_chat_wrapper/services/push_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush/unifiedpush.dart';

class AddServerPage extends StatefulWidget {
  final bool canGoBack;
  const AddServerPage({super.key, required this.canGoBack});

  @override
  State<AddServerPage> createState() => _AddServerPageState();
}

class _AddServerPageState extends State<AddServerPage> {
  final TextEditingController _serverUrlController = TextEditingController();
  String _pushProvider = 'none';
  List<String> distributors = ['none'];

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _serverUrlController.text = prefs.getString('server_url') ?? '';
    distributors = await UnifiedPush.getDistributors();
    debugPrint('distributors: $distributors');
    if (distributors.isEmpty) return;
    _pushProvider = distributors[0];
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
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
                  Navigator.pop(context);
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
              Align(
                alignment: Alignment.topLeft,
                child: Text(
                  FlutterI18n.translate(context, 'server-settings.server-url'),
                ),
              ),
              CustomTextFormField(controller: _serverUrlController),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.topLeft,
                child: Text(
                  FlutterI18n.translate(
                    context,
                    'server-settings.push-provider',
                  ),
                ),
              ),
              CustomDropdownButton(
                value: _pushProvider,
                items: distributors
                    .map(
                      (e) => DropdownMenuItem<String>(value: e, child: Text(e)),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _pushProvider = value as String;
                  });
                },
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  if (_serverUrlController.text.isEmpty) return;
                  if (_pushProvider.isEmpty) return;

                  var prefs = await SharedPreferences.getInstance();
                  await prefs.setString(
                    'server_url',
                    _serverUrlController.text,
                  );
                  // await prefs.setString(
                  //   'notification_server_url',
                  //   _notificationServerUrlController.text,
                  // );
                  await PushService.unregister();

                  final oldDistributor = await UnifiedPush.getDistributor();
                  if (oldDistributor != _pushProvider) {
                    debugPrint('save distributor: $_pushProvider');
                    await UnifiedPush.saveDistributor(_pushProvider);
                  }

                  await PushService.register();

                  if (mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => ChatPage()),
                      (route) => false,
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
