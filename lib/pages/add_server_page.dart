import 'package:crypthora_chat_wrapper/components/custom_dropdown_button.dart';
import 'package:crypthora_chat_wrapper/components/custom_text_form_field.dart';
import 'package:crypthora_chat_wrapper/i18n/strings.g.dart';
import 'package:crypthora_chat_wrapper/models/fcm_config.dart';
import 'package:crypthora_chat_wrapper/pages/chat_page.dart';
import 'package:crypthora_chat_wrapper/services/fcm_service.dart';
import 'package:crypthora_chat_wrapper/services/push_service.dart';
import 'package:flutter/material.dart';
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

  /// Non null once the server told us it has Firebase set up, only then can FCM be picked.
  FcmConfig? _fcmConfig;
  bool _loadingConfig = false;
  bool _saving = false;
  bool _hasSavedProvider = false;

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _serverUrlController.text = prefs.getString('server_url') ?? '';

    final foundDistributors = await UnifiedPush.getDistributors();
    if (foundDistributors.isNotEmpty) distributors = foundDistributors;
    debugPrint('distributors: $distributors');

    final savedProvider = prefs.getString('push_provider');
    _hasSavedProvider = savedProvider != null;
    _pushProvider = savedProvider ?? distributors[0];
    if (mounted) setState(() {});

    if (_serverUrlController.text.isNotEmpty) await _loadPushConfig();
  }

  /// Asks the server whether it supports FCM, so the dropdown can offer it.
  Future<void> _loadPushConfig() async {
    final url = _serverUrlController.text.trim();
    if (url.isEmpty) return;

    setState(() => _loadingConfig = true);
    final config = await FcmService.fetchConfig(url);
    if (!mounted) return;

    setState(() {
      _fcmConfig = config;
      _loadingConfig = false;
      // Default to FCM, it doesn't need a separate distributor app to stay running
      if (config != null && !_hasSavedProvider) {
        _pushProvider = PushProvider.fcm;
      }
      if (config == null && _pushProvider == PushProvider.fcm) {
        _pushProvider = distributors[0];
      }
    });
  }

  List<String> get _providerOptions => [
    if (_fcmConfig != null) PushProvider.fcm,
    ...distributors,
  ];

  String _providerLabel(String provider) => provider == PushProvider.fcm
      ? context.t.serverSettings.pushProviderFcm
      : provider;

  Future<void> _save() async {
    if (_serverUrlController.text.isEmpty) return;
    if (_pushProvider.isEmpty) return;

    setState(() => _saving = true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', _serverUrlController.text);
    await PushProvider.save(_pushProvider);

    if (_pushProvider == PushProvider.fcm) {
      // Stop any UnifiedPush registration first, a session only gets one provider
      await PushService.unregister();
      await prefs.remove('topic');

      await FcmService.saveConfig(_fcmConfig!);
      // Sets up the message handlers too, so this works without restarting the app
      if (await PushService().initFcm()) {
        await FcmService.registerAndSaveToken();
      }
    } else {
      await FcmService.unregister();

      await PushService.unregister();
      final oldDistributor = await UnifiedPush.getDistributor();
      if (oldDistributor != _pushProvider) {
        debugPrint('save distributor: $_pushProvider');
        await UnifiedPush.saveDistributor(_pushProvider);
      }
      await PushService.register();
    }

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => ChatPage()),
        (route) => false,
      );
    }
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
        title: Text(context.t.serverSettings.setServer),
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
                child: Text(context.t.serverSettings.serverUrl),
              ),
              CustomTextFormField(
                controller: _serverUrlController,
                onEditingComplete: _loadPushConfig,
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.topLeft,
                child: Text(context.t.serverSettings.pushProvider),
              ),
              CustomDropdownButton(
                value: _providerOptions.contains(_pushProvider)
                    ? _pushProvider
                    : null,
                items: _providerOptions
                    .map(
                      (e) => DropdownMenuItem<String>(
                        value: e,
                        child: Text(_providerLabel(e)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _pushProvider = value as String;
                  });
                },
              ),
              const SizedBox(height: 8),
              if (_loadingConfig)
                Align(
                  alignment: Alignment.topLeft,
                  child: Text(context.t.serverSettings.checkingServer),
                )
              else if (_fcmConfig == null && _serverUrlController.text.isNotEmpty)
                Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    context.t.serverSettings.fcmUnavailable,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(context.t.common.save),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
