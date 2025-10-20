import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

enum LogLevel { info, warning, error, debug }

class LogEntry {
  final String message;
  final LogLevel level;
  final DateTime timestamp;
  final String isolateName;

  LogEntry({
    required this.message,
    required this.level,
    required this.timestamp,
    required this.isolateName,
  });

  String toFileString() {
    return '${timestamp.toIso8601String()}|${level.name}|$isolateName|$message';
  }

  static LogEntry? fromFileString(String line) {
    try {
      final parts = line.split('|');
      if (parts.length < 4) return null;

      return LogEntry(
        timestamp: DateTime.parse(parts[0]),
        level: LogLevel.values.firstWhere((e) => e.name == parts[1]),
        isolateName: parts[2],
        message: parts.sublist(3).join('|'),
      );
    } catch (e) {
      return null;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'message': message,
      'level': level.name,
      'timestamp': timestamp.toIso8601String(),
      'isolateName': isolateName,
    };
  }
}

class DiskLogger {
  static DiskLogger? _instance;
  static final _logQueue = StreamController<LogEntry>.broadcast();
  static File? _logFile;
  static bool _initialized = false;
  static final _lock = Completer<void>()..complete();

  DiskLogger._();

  static Future<DiskLogger> getInstance() async {
    if (_instance == null) {
      _instance = DiskLogger._();
      await _instance!._initialize();
    }
    return _instance!;
  }

  Future<void> _initialize() async {
    if (_initialized) return;

    final directory = await getApplicationDocumentsDirectory();
    _logFile = File('${directory.path}/app_logs.txt');

    if (!await _logFile!.exists()) {
      await _logFile!.create(recursive: true);
    }

    // Listen to log queue and write to disk
    _logQueue.stream.listen((entry) async {
      await _writeToFile(entry);
    });

    _initialized = true;
  }

  Future<void> _writeToFile(LogEntry entry) async {
    await _lock.future;
    final newLock = Completer<void>();

    try {
      await _logFile!.writeAsString(
        '${entry.toFileString()}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      print('Error writing log: $e');
    } finally {
      newLock.complete();
    }
  }

  static String _getIsolateName() {
    try {
      return Isolate.current.debugName ?? 'unknown';
    } catch (e) {
      return 'main';
    }
  }

  static Future<void> log(
    String message, [
    LogLevel level = LogLevel.info,
  ]) async {
    await getInstance();

    final entry = LogEntry(
      message: message,
      level: level,
      timestamp: DateTime.now(),
      isolateName: _getIsolateName(),
    );

    debugPrint('($level) $message');

    _logQueue.add(entry);
  }

  static Future<void> info(String message) => log(message, LogLevel.info);
  static Future<void> warning(String message) => log(message, LogLevel.warning);
  static Future<void> error(String message) => log(message, LogLevel.error);
  static Future<void> debug(String message) => log(message, LogLevel.debug);

  static Future<List<LogEntry>> getLogs({LogLevel? filter}) async {
    await getInstance();

    if (_logFile == null || !await _logFile!.exists()) {
      return [];
    }

    final lines = await _logFile!.readAsLines();
    final entries = <LogEntry>[];

    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      final entry = LogEntry.fromFileString(line);
      if (entry != null) {
        if (filter == null || entry.level == filter) {
          entries.add(entry);
        }
      }
    }

    return entries.reversed.toList(); // Most recent first
  }

  static Future<void> clearLogs() async {
    await getInstance();
    if (_logFile != null && await _logFile!.exists()) {
      await _logFile!.writeAsString('');
    }
  }

  static Future<int> getLogCount() async {
    final logs = await getLogs();
    return logs.length;
  }
}
