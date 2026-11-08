import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const SmartVisionApp());
}

class SmartVisionApp extends StatelessWidget {
  const SmartVisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PathSense AI',
      theme: ThemeData(primarySwatch: Colors.indigo, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _backendUrlController =
      TextEditingController(text: 'http://192.168.1.1:8000');
  final TextEditingController _esp32UrlController =
      TextEditingController(text: 'http://192.168.1.2');

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _backendConfigured = false;
  bool _isListening = false;
  bool _isBusy = false;
  bool _analysisInFlight = false;

  String _statusText = 'Enter backend and ESP32 addresses, then tap Connect.';
  String _obstacleText = '';
  String _sensorText = '';
  String _voiceStatus = '';
  List<String> _instructions = [];
  int _stepIndex = 0;

  Timer? _analysisTimer;
  Timer? _sensorTimer;

  DateTime _lastAlertTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSensorAlertTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const _alertCooldown = Duration(seconds: 4);
  static const _sensorCooldown = Duration(seconds: 3);

  String get _backendUrl => _backendUrlController.text.trim();
  String get _esp32Url => _esp32UrlController.text.trim();

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    // Restart mic loop after TTS finishes speaking
    _tts.setCompletionHandler(() {
      if (_backendConfigured) {
        Future.delayed(const Duration(milliseconds: 600), _startVoiceCommandLoop);
      }
    });
  }

  Future<void> _requestPermissions() async {
    await [Permission.microphone].request();
  }

  // ── Connect ────────────────────────────────────────────────────────────────
  void _connectBackend() async {
    setState(() => _isBusy = true);
    try {
      final backendResp = await http
          .get(Uri.parse('$_backendUrl/health'))
          .timeout(const Duration(seconds: 5));
      if (backendResp.statusCode != 200) {
        setState(() => _statusText = 'Backend error — check the URL.');
        return;
      }

      final esp32Resp = await http
          .get(Uri.parse('$_esp32Url/distance'))
          .timeout(const Duration(seconds: 5));
      if (esp32Resp.statusCode != 200) {
        setState(() =>
            _statusText = 'ESP32 not responding — check its IP.');
        return;
      }

      _startPeriodicAnalysis();
      _startSensorPolling();
      setState(() {
        _backendConfigured = true;
        _statusText = 'Connected! Listening for voice commands...';
      });
      await _tts.speak('PathSense ready. Say your destination.');
      // After TTS finishes, _startVoiceCommandLoop() fires via completion handler
    } catch (e) {
      setState(() => _statusText = 'Could not connect: $e');
    } finally {
      setState(() => _isBusy = false);
    }
  }

  // ── Always-on voice command loop ───────────────────────────────────────────
  Future<void> _startVoiceCommandLoop() async {
    if (!_backendConfigured) return;
    if (_isListening) return;

    final available = await _speech.initialize(
      onError: (e) {
        setState(() => _isListening = false);
        Future.delayed(const Duration(seconds: 2), _startVoiceCommandLoop);
      },
    );
    if (!available) return;

    setState(() {
      _isListening = true;
      _voiceStatus = '🎤 Listening...';
    });

    _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          final words = result.recognizedWords.toLowerCase().trim();
          setState(() {
            _isListening = false;
            _voiceStatus = 'Heard: "$words"';
          });
          _speech.stop();
          _handleVoiceCommand(words);
        }
      },
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 3),
      onSoundLevelChange: null,
    );

    // If nobody speaks for 8 s, restart loop
    Future.delayed(const Duration(seconds: 9), () {
      if (_isListening) {
        _speech.stop();
        setState(() => _isListening = false);
        _startVoiceCommandLoop();
      }
    });
  }

  void _handleVoiceCommand(String words) {
    if (words.contains('next') || words.contains('next step')) {
      _nextInstruction();
    } else if (words.contains('repeat') || words.contains('again')) {
      _repeatInstruction();
    } else if (words.contains('read sign') || words.contains('scan sign')) {
      _readSign();
    } else if (words.contains('where am i') || words.contains('location')) {
      _tts.speak(_statusText);
    } else if (words.contains('stop') || words.contains('cancel')) {
      setState(() {
        _instructions = [];
        _stepIndex = 0;
        _statusText = 'Navigation stopped.';
      });
      _tts.speak('Navigation stopped.');
    } else {
      // Treat anything else as a destination
      _setDestination(words);
    }
  }

  // ── ESP32-CAM frame capture ────────────────────────────────────────────────
  Future<Uint8List?> _captureFrameBytes() async {
    try {
      final resp = await http
          .get(Uri.parse('$_esp32Url/capture'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) return resp.bodyBytes;
    } catch (_) {}
    return null;
  }

  // ── Periodic vision analysis ───────────────────────────────────────────────
  void _startPeriodicAnalysis() {
    _analysisTimer?.cancel();
    _analysisTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _analyzeFrame());
  }

  Future<void> _analyzeFrame({bool announceOcr = false}) async {
    if (_analysisInFlight) return;
    _analysisInFlight = true;
    try {
      final bytes = await _captureFrameBytes();
      if (bytes == null) return;

      final uri = Uri.parse('$_backendUrl/analyze_frame')
          .replace(queryParameters: {'ocr': announceOcr ? 'true' : 'false'});
      final request = http.MultipartRequest('POST', uri);
      request.files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: 'frame.jpg'));
      final streamed =
          await request.send().timeout(Duration(seconds: announceOcr ? 45 : 20));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final obstacles =
          (data['obstacles'] as List).cast<Map<String, dynamic>>();
      final closeOnes = obstacles
          .where((o) =>
              o['distance_category'] == 'close' ||
              o['distance_category'] == 'very close')
          .toList();

      if (mounted) {
        setState(() {
          _obstacleText = obstacles.isEmpty
              ? 'No obstacles detected'
              : obstacles
                  .map((o) => '${o['label']} (${o['distance_category']})')
                  .join(', ');
        });
      }

      final now = DateTime.now();
      if (closeOnes.isNotEmpty &&
          now.difference(_lastAlertTime) > _alertCooldown) {
        final nearest = closeOnes.first;
        await _tts
            .speak('Caution, ${nearest['label']} ${nearest['distance_category']} ahead');
        _lastAlertTime = now;
      }

      if (announceOcr) {
        final ocr = data['ocr'] as Map<String, dynamic>;
        final matchedNode = ocr['matched_node'];
        final roomNumbers = (ocr['room_numbers'] as List);
        if (matchedNode != null) {
          await _tts.speak(
              'Location confirmed: ${matchedNode.toString().replaceAll('_', ' ')}');
        } else if (roomNumbers.isNotEmpty) {
          await _tts.speak('Sign reads ${roomNumbers.join(' ')}');
        } else {
          await _tts.speak('No sign detected');
        }
      }
    } catch (_) {
    } finally {
      _analysisInFlight = false;
    }
  }

  // ── Sensor polling ─────────────────────────────────────────────────────────
  void _startSensorPolling() {
    _sensorTimer?.cancel();
    _sensorTimer = Timer.periodic(
        const Duration(milliseconds: 500), (_) => _pollSensors());
  }

  Future<void> _pollSensors() async {
    try {
      final resp = await http
          .get(Uri.parse('$_esp32Url/distance'))
          .timeout(const Duration(seconds: 2));
      if (resp.statusCode != 200) return;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final leftCm = (data['left_cm'] as num).toDouble();
      final rightCm = (data['right_cm'] as num).toDouble();
      final alert = data['alert'] as String;

      if (mounted) {
        setState(() {
          _sensorText = alert == 'none'
              ? 'Sensors: clear'
              : 'L: ${leftCm.toStringAsFixed(0)} cm  '
                  'R: ${rightCm.toStringAsFixed(0)} cm  ⚠ $alert';
        });
      }

      final now = DateTime.now();
      if (alert != 'none' &&
          now.difference(_lastSensorAlertTime) > _sensorCooldown) {
        String msg;
        switch (alert) {
          case 'urgent':
            msg = 'Stop! Obstacle very close';
            break;
          case 'both':
            msg = 'Obstacles on both sides';
            break;
          case 'left':
            msg = 'Obstacle on the left';
            break;
          case 'right':
            msg = 'Obstacle on the right';
            break;
          default:
            msg = '';
        }
        if (msg.isNotEmpty) {
          await _tts.speak(msg);
          _lastSensorAlertTime = now;
        }
      }
    } catch (_) {}
  }

  // ── Navigation actions ─────────────────────────────────────────────────────
  Future<void> _setDestination(String text) async {
    if (text.trim().isEmpty) return;
    setState(() => _isBusy = true);
    try {
      final uri = Uri.parse('$_backendUrl/destination')
          .replace(queryParameters: {'spoken_text': text});
      final resp = await http.post(uri).timeout(const Duration(seconds: 10));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      if (data.containsKey('error')) {
        await _tts.speak('Sorry, I could not find that destination. Please try again.');
        setState(() => _statusText = 'Not found: $text');
        return;
      }

      final instructions = (data['instructions'] as List).cast<String>();
      setState(() {
        _instructions = instructions;
        _stepIndex = 1;
        _statusText = 'Going to ${data['destination'].toString().replaceAll('_', ' ')}';
      });
      await _tts.speak('Route found. ${instructions.first}');
    } catch (e) {
      await _tts.speak('Connection error. Please try again.');
      setState(() => _statusText = 'Error: $e');
    } finally {
      setState(() => _isBusy = false);
    }
  }

  Future<void> _nextInstruction() async {
    if (_instructions.isEmpty) {
      await _tts.speak('No route set. Say a destination first.');
      return;
    }
    if (_stepIndex >= _instructions.length) {
      await _tts.speak('You have reached your destination.');
      return;
    }
    final instruction = _instructions[_stepIndex];
    setState(() => _stepIndex++);
    await _tts.speak(instruction);
  }

  Future<void> _repeatInstruction() async {
    if (_instructions.isEmpty) {
      await _tts.speak('No route set.');
      return;
    }
    final idx = (_stepIndex - 1).clamp(0, _instructions.length - 1);
    await _tts.speak(_instructions[idx]);
  }

  Future<void> _readSign() async {
    await _tts.speak('Reading sign');
    while (_analysisInFlight) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    await _analyzeFrame(announceOcr: true);
  }

  @override
  void dispose() {
    _analysisTimer?.cancel();
    _sensorTimer?.cancel();
    _speech.stop();
    _tts.stop();
    super.dispose();
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PathSense AI')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            if (!_backendConfigured) ...[
              TextField(
                controller: _backendUrlController,
                decoration: const InputDecoration(
                  labelText: 'Backend URL',
                  hintText: 'http://10.35.210.40:8000',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _esp32UrlController,
                decoration: const InputDecoration(
                  labelText: 'ESP32-CAM URL',
                  hintText: 'http://192.168.1.XX',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _isBusy ? null : _connectBackend,
                child: _isBusy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Connect'),
              ),
            ],

            const SizedBox(height: 8),
            Text(_statusText,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16)),

            // Voice status indicator
            if (_backendConfigured) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _isListening
                      ? Colors.green.shade100
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: _isListening ? Colors.green : Colors.grey),
                ),
                child: Text(
                  _isListening ? '🎤 Listening... speak now' : _voiceStatus,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _isListening ? Colors.green.shade800 : Colors.black54,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Say: "lab" • "washroom" • "room 101"\n"next" • "repeat" • "read sign" • "stop"',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],

            // Sensor bar
            if (_sensorText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _sensorText.contains('⚠')
                      ? Colors.red.shade100
                      : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(_sensorText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],

            // Obstacle bar
            if (_obstacleText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                width: double.infinity,
                color: Colors.amber.shade100,
                child: Text('Camera: $_obstacleText'),
              ),
            ],

            // Navigation step
            if (_instructions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Step $_stepIndex of ${_instructions.length}:\n'
                  '${_stepIndex > 0 && _stepIndex <= _instructions.length ? _instructions[_stepIndex - 1] : ""}',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ],

            const Spacer(),

            // Manual buttons as backup (useful for demo)
            if (_backendConfigured)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _startVoiceCommandLoop,
                    icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
                    label: const Text('Mic'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _nextInstruction,
                    icon: const Icon(Icons.navigation),
                    label: const Text('Next'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _readSign,
                    icon: const Icon(Icons.text_fields),
                    label: const Text('Read Sign'),
                  ),
                ],
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}