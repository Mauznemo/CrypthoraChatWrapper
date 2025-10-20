import 'package:crypthora_chat_wrapper/utils/disk_logger.dart';
import 'package:flutter/material.dart';

class LogViewerPage extends StatefulWidget {
  const LogViewerPage({Key? key}) : super(key: key);

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  List<LogEntry> _logs = [];
  LogLevel? _filterLevel;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);

    final logs = await DiskLogger.getLogs(filter: _filterLevel);

    setState(() {
      _logs = logs;
      _isLoading = false;
    });
  }

  Color _getLevelColor(LogLevel level) {
    switch (level) {
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
      case LogLevel.debug:
        return Colors.grey;
    }
  }

  IconData _getLevelIcon(LogLevel level) {
    switch (level) {
      case LogLevel.info:
        return Icons.info_outline;
      case LogLevel.warning:
        return Icons.warning_amber;
      case LogLevel.error:
        return Icons.error_outline;
      case LogLevel.debug:
        return Icons.bug_report;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Viewer'),
        actions: [
          PopupMenuButton<LogLevel?>(
            icon: const Icon(Icons.filter_list),
            onSelected: (level) {
              setState(() => _filterLevel = level);
              _loadLogs();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: null, child: Text('All Logs')),
              ...LogLevel.values.map(
                (level) => PopupMenuItem(
                  value: level,
                  child: Text(level.name.toUpperCase()),
                ),
              ),
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadLogs),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear Logs'),
                  content: const Text(
                    'Are you sure you want to delete all logs?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await DiskLogger.clearLogs();
                _loadLogs();
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.article_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No logs available',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                if (_filterLevel != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.grey[200],
                    child: Row(
                      children: [
                        const Text('Filtered by: '),
                        Chip(
                          label: Text(_filterLevel!.name.toUpperCase()),
                          backgroundColor: _getLevelColor(
                            _filterLevel!,
                          ).withOpacity(0.2),
                          deleteIcon: const Icon(Icons.close, size: 18),
                          onDeleted: () {
                            setState(() => _filterLevel = null);
                            _loadLogs();
                          },
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: ListTile(
                          leading: Icon(
                            _getLevelIcon(log.level),
                            color: _getLevelColor(log.level),
                          ),
                          title: Text(
                            log.message,
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            '${_formatTime(log.timestamp)} • ${log.isolateName}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          trailing: Chip(
                            label: Text(
                              log.level.name.toUpperCase(),
                              style: const TextStyle(fontSize: 10),
                            ),
                            backgroundColor: _getLevelColor(
                              log.level,
                            ).withOpacity(0.2),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          // Test logging from current isolate
          await DiskLogger.info('Test log from main isolate');
          await DiskLogger.warning('Test warning message');
          await DiskLogger.error('Test error message');
          await DiskLogger.debug('Test debug message');
          _loadLogs();

          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Test logs added!')));
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }
}
