import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:video_player/video_player.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:flutter/services.dart';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
  runApp(const MaterialApp(home: GestureKicauApp()));
}

class GestureKicauApp extends StatefulWidget {
  const GestureKicauApp({super.key});

  @override
  State<GestureKicauApp> createState() => _GestureKicauAppState();
}

class _GestureKicauAppState extends State<GestureKicauApp> {
  CameraController? _CameraController;
  VideoPlayerController? _VideoController;

  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(),
  );

  bool _isprocessing = false;
  bool _isVideoPlaying = false;

  double _previousX = 0;
  int _wavecount = 0;
  int _currentDirection = 0;
  DateTime? _lastMovementTime;

  @override
  void initState() {
    _initVideo();
    _initCamera();
  }

  void _initVideo() {
    _VideoController = VideoPlayerController.asset("assets/kicau_mania.mp4")
      ..initialize()
          .then((_) {
            setState(() {});
            _VideoController?.setLooping(true);
          })
          .catchError((error) {
            debugPrint("error Video");
          });
  }

  void _initCamera() {
    final frontcamera = _cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras.first,
    );

    _CameraController = CameraController(
      frontcamera,
      ResolutionPreset.medium,
      enableAudio: false,

      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    _CameraController?.initialize().then((_) {
      if (!mounted) return;
      setState(() {});

      _CameraController?.startImageStream((CameraImage image) {
        if (!_isprocessing && !_isVideoPlaying) {
          _processCameraImage(image);
        }
      });
    });
  }

  Future<void> _processCameraImage(CameraImage image) async {
    _isprocessing = true;

    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final Size imageSize = Size(
      image.width.toDouble(),
      image.height.toDouble(),
    );

    final camera = _CameraController!.description;

    final imageRotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
        InputImageRotation.rotation0deg;

    final inputImageFormat =
        InputImageFormatValue.fromRawValue(image.format.raw) ??
        InputImageFormat.nv21;

    final inputImageData = InputImageMetadata(
      size: imageSize,
      rotation: imageRotation,
      format: inputImageFormat,
      bytesPerRow: image.planes[0].bytesPerRow,
    );

    final inputImage = InputImage.fromBytes(
      bytes: bytes,
      metadata: inputImageData,
    );

    await _detectPose(inputImage);

    _isprocessing = false;
  }

  Future<void> _detectPose(InputImage inputImage) async {
    final List<Pose> poses = await _poseDetector.processImage(inputImage);
    debugPrint("${poses.length}");

    if (poses.isNotEmpty) {
      final pose = poses.first;

      final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];

      if (rightWrist != null && rightWrist.likelihood > 0.2) {
        debugPrint("Tangan kanan di ${rightWrist.x}");
        _processWaveLogic(rightWrist.x);
      }
    }
  }

  void _processWaveLogic(double currentX) {
    double deltaX = currentX - _previousX;

    if (deltaX.abs() > 30) {
      int newDirection = deltaX > 0 ? 1 : -1;

      if (newDirection != _currentDirection) {
        _wavecount++;
        _currentDirection = newDirection;
        _lastMovementTime = DateTime.now();
        debugPrint("$_wavecount");
      }
    }

    if (_lastMovementTime != null &&
        DateTime.now().difference(_lastMovementTime!).inMilliseconds > 1500) {
      _wavecount = 0;
    }

    _previousX = currentX;

    if (_wavecount >= 4) {
      debugPrint("🎬 TRIGGER VIDEO KICAU MANIA!");
      _triggerKicauMania();
      _wavecount = 0;
    }
  }

  void _triggerKicauMania() {
    setState(() {
      _isVideoPlaying = true;
    });
    _VideoController?.play();
  }

  void _stopKicauMania() {
    _VideoController?.pause();
    _VideoController?.seekTo(Duration.zero);
    setState(() {
      _isVideoPlaying = false;
      _wavecount = 0;
    });
  }

  @override
  void dispose() {
    _CameraController?.dispose();
    _VideoController?.dispose();
    _poseDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_CameraController == null || !_CameraController!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_CameraController!),

          if (_isVideoPlaying && _VideoController!.value.isInitialized)
            Container(
              color: Colors.black.withOpacity(0.8),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AspectRatio(
                      aspectRatio: _VideoController!.value.aspectRatio,
                      child: VideoPlayer(_VideoController!),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.close),
                      label: const Text("Tutup Video"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _stopKicauMania,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
