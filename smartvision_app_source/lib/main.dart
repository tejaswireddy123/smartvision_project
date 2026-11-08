// SmartVision mobile app
//
// This talks to the FastAPI backend (main.py) you already have running.
// For now it uses the PHONE'S OWN CAMERA as the video source — once the
// ESP32-CAM headband is built, only _captureFrameBytes() needs to change
// to pull a frame from http://<esp32-ip>/stream instead. Everything else
// (voice, navigation, obstacle alerts, OCR) stays exactly the same.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
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
      title: 'SmartVision',
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
      TextEditingController(text: 'http://192.168.1.5:8000');

  CameraController? _cameraController;
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _backendConfigured = false;
  bool _isListening = false;
  bool _isBusy = false;

  String _statusText = 'Enter your laptop\'s backend address above and tap Connect.';
  String _obstacleText = '';
  List<String> _instructions = [];
  int _stepIndex = 0;

  Timer? _analysisTimer;
  DateTime _lastAlertTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const _alertCooldown = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [Permission.camera, Permission.microphone].request();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      setState(() => _statusText = 'No camera found on this device.');
      return;
    }
    final controller = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await controller.initialize();
    if (!mounted) return;
    setState(() => _cameraController = controller);
  }

  String get _backendUrl => _backendUrlController.text.trim();

  void _connectBackend() async {
    setState(() => _isBusy = true);
    try {
      final resp = await http
          .get(Uri.parse('$_backendUrl/health'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        await _initCamera();
        _startPeriodicAnalysis();
        setState(() {
          _backendConfigured = true;
          _statusText = 'Connected. Tap the mic and say where you want to go.';
        });
      } else {
        setState(() => _statusText = 'Backend responded with an error. Check the URL.');
      }
    } catch (e) {
      setState(() =>
          _statusText = 'Could not reach backend at $_backendUrl — check phone/laptop are on the same WiFi.');
    } finally {
      setState(() => _isBusy = false);
    }
  }

  // ---------------- Frame capture ----------------
  // Swap this method's body to fetch from the ESP32-CAM's /stream once the
  // headband is available — everything downstream (analysis, alerts, OCR)
  // stays unchanged.
  Future<Uint8List?> _captureFrameBytes() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return null;
    try {
      final XFile file = await controller.takePicture();
      return await file.readAsBytes();
    } catch (e) {
      return null;
    }
  }

  void _startPeriodicAnalysis() {
    _analysisTimer?.cancel();
    _analysisTimer = Timer.periodic(const Duration(seconds: 3), (_) => _analyzeFrame());
  }

  Future<void> _analyzeFrame({bool announceOcr = false}) async {
    if (_isBusy && !announceOcr) return; // don't overlap with a manual action
    final bytes = await _captureFrameBytes();
    if (bytes == null) return;

    try {
      final request = http.MultipartRequest('POST', Uri.parse('$_backendUrl/analyze_frame'));
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: 'frame.jpg'));
      final streamed = await request.send().timeout(const Duration(seconds: 10));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final obstacles = (data['obstacles'] as List).cast<Map<String, dynamic>>();

      final closeOnes = obstacles
          .where((o) => o['distance_category'] == 'close' || o['distance_category'] == 'very close')
          .toList();

      if (mounted) {
        setState(() {
          _obstacleText = obstacles.isEmpty
              ? 'No obstacles detected'
              : obstacles.map((o) => '${o['label']} (${o['distance_category']})').join(', ');
        });
      }

      final now = DateTime.now();
      if (closeOnes.isNotEmpty && now.difference(_lastAlertTime) > _alertCooldown) {
        final nearest = closeOnes.first;
        await _tts.speak('Caution, ${nearest['label']} ${nearest['distance_category']} ahead');
        _lastAlertTime = now;
      }

      if (announceOcr) {
        final ocr = data['ocr'] as Map<String, dynamic>;
        final matchedNode = ocr['matched_node'];
        final roomNumbers = (ocr['room_numbers'] as List);
        if (matchedNode != null) {
          await _tts.speak('Location confirmed: ${matchedNode.toString().replaceAll('_', ' ')}');
        } else if (roomNumbers.isNotEmpty) {
          await _tts.speak('Sign reads ${roomNumbers.join(' ')}');
        } else {
          await _tts.speak('No sign detected');
        }
      }
    } catch (e) {
      // Silently skip a failed analysis cycle — the next timer tick will retry.
    }
  }

  // ---------------- Voice destination ----------------
  Future<void> _listenForDestination() async {
    final available = await _speech.initialize();
    if (!available) {
      setState(() => _statusText = 'Speech recognition unavailable on this device.');
      return;
    }
    setState(() => _isListening = true);
    await _tts.speak('Where would you like to go?');

    _speech.listen(
      onResult: (result) async {
        if (result.finalResult) {
          setState(() => _isListening = false);
          await _speech.stop();
          _setDestination(result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
    );
  }

  Future<void> _setDestination(String text) async {
    if (text.trim().isEmpty) return;
    setState(() => _isBusy = true);
    try {
      final uri = Uri.parse('$_backendUrl/destination')
          .replace(queryParameters: {'spoken_text': text});
      final resp = await http.post(uri).timeout(const Duration(seconds: 10));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      if (data.containsKey('error')) {
        await _tts.speak('Sorry, I could not find that destination');
        setState(() => _statusText = data['error']);
        return;
      }

      final instructions = (data['instructions'] as List).cast<String>();
      setState(() {
        _instructions = instructions;
        _stepIndex = 1; // first instruction already about to be spoken
        _statusText = 'Route set to ${data['destination']}';
      });
      await _tts.speak('Route found. ${instructions.first}');
    } catch (e) {
      setState(() => _statusText = 'Could not set destination — check backend connection.');
    } finally {
      setState(() => _isBusy = false);
    }
  }

  Future<void> _nextInstruction() async {
    if (_stepIndex >= _instructions.length) {
      await _tts.speak('You have reached your destination');
      return;
    }
    final instruction = _instructions[_stepIndex];
    setState(() => _stepIndex++);
    await _tts.speak(instruction);
  }

  Future<void> _readSign() async {
    setState(() => _isBusy = true);
    await _tts.speak('Reading sign');
    await _analyzeFrame(announceOcr: true);
    setState(() => _isBusy = false);
  }

  @override
  void dispose() {
    _analysisTimer?.cancel();
    _cameraController?.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SmartVision')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            if (!_backendConfigured) ...[
              TextField(
                controller: _backendUrlController,
                decoration: const InputDecoration(
                  labelText: 'Backend URL (e.g. http://192.168.1.5:8000)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _isBusy ? null : _connectBackend,
                child: _isBusy ? const CircularProgressIndicator() : const Text('Connect'),
              ),
            ],
            const SizedBox(height: 8),
            Text(_statusText, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            if (_cameraController != null && _cameraController!.value.isInitialized)
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CameraPreview(_cameraController!),
                ),
              ),
            const SizedBox(height: 8),
            if (_obstacleText.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(8),
                width: double.infinity,
                color: Colors.amber.shade100,
                child: Text('Nearby: $_obstacleText'),
              ),
            const SizedBox(height: 8),
            if (_backendConfigured)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isBusy ? null : _listenForDestination,
                    icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
                    label: const Text('Destination'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isBusy ? null : _nextInstruction,
                    icon: const Icon(Icons.navigation),
                    label: const Text('Next'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isBusy ? null : _readSign,
                    icon: const Icon(Icons.text_fields),
                    label: const Text('Read Sign'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
