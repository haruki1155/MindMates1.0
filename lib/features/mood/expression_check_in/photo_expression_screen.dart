import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class PhotoExpressionScreen extends StatefulWidget {
  const PhotoExpressionScreen({super.key});

  @override
  State<PhotoExpressionScreen> createState() => _PhotoExpressionScreenState();
}

class _PhotoExpressionScreenState extends State<PhotoExpressionScreen> {
  static const _channel = MethodChannel('mindmate/photo_expression');

  final ImagePicker _picker = ImagePicker();

  XFile? _photo;
  String? _label;
  String? _error;

  bool _busy = false;

  static const _emojis = <String, String>{
    'Happy': '😊',
    'Sad': '😢',
    'Angry': '😠',
    'Fear': '😨',
    'Surprise': '😮',
    'Disgust': '😖',
    'Neutral': '😐',
    'Expression unclear': '🤔',
  };

  static const _descriptions = <String, String>{
    'Happy': 'Your facial expression appears happy.',
    'Sad': 'Your facial expression appears sad.',
    'Angry': 'Your facial expression appears angry.',
    'Fear': 'Your facial expression appears fearful.',
    'Surprise': 'Your facial expression appears surprised.',
    'Disgust': 'Your facial expression appears to show disgust.',
    'Neutral': 'Your facial expression appears neutral.',
    'Expression unclear': 'We could not identify a clear facial expression.',
  };

  Future<void> _pickPhoto(ImageSource source) async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final photo = await _picker.pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 95,
      );

      if (!mounted || photo == null) return;

      setState(() {
        _photo = photo;
        _label = null;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = source == ImageSource.camera
            ? 'Unable to open the camera. Please check camera permission.'
            : 'Unable to open the gallery. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _takePhoto() => _pickPhoto(ImageSource.camera);

  Future<void> _uploadPhoto() => _pickPhoto(ImageSource.gallery);

  Future<void> _analyzePhoto() async {
    final photo = _photo;

    if (photo == null || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
      _label = null;
    });

    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'analyzePhoto',
        {'path': photo.path},
      );

      if (!mounted) return;

      final status = response?['status'] as String?;
      final label = response?['label'] as String?;

      if (status == 'success' && label != null && _emojis.containsKey(label)) {
        setState(() => _label = label);
      } else if (status == 'unclear') {
        setState(() => _label = 'Expression unclear');
      } else {
        setState(() {
          _error =
              response?['message'] as String? ??
              'Unable to analyze this photo. Please try again.';
        });
      }
    } on PlatformException {
      if (!mounted) return;

      setState(() {
        _error = 'Photo analysis failed. Please try again.';
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'Expression analysis is unavailable.';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final label = _label;
    final photo = _photo;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expression Check-in'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                label == null
                    ? 'Discover your facial expression'
                    : 'Your Expression Result',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              if (photo == null)
                Text(
                  'Capture a selfie or upload a clear photo of your face.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              const SizedBox(height: 20),

              // Captured photo, not live expression scanning.
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: photo == null
                      ? Container(
                          color: colors.surfaceContainerHighest,
                          child: Center(
                            child: Icon(
                              Icons.camera_alt_outlined,
                              size: 72,
                              color: colors.primary,
                            ),
                          ),
                        )
                      : Image.file(File(photo.path), fit: BoxFit.cover),
                ),
              ),

              const SizedBox(height: 24),

              if (_busy) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 12),
                Text(
                  photo == null ? 'Opening photo picker...' : 'Please wait...',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
              ],

              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.errorContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onErrorContainer),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              if (label != null) ...[
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _emojis[label] ?? '🤔',
                        style: const TextStyle(fontSize: 64),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Detected Expression',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _descriptions[label] ??
                            'Your expression could not be identified.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              if (photo == null) ...[
                FilledButton.icon(
                  onPressed: _busy ? null : _takePhoto,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Capture Photo'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _uploadPhoto,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Upload Photo'),
                ),
              ] else ...[
                if (label == null) ...[
                  FilledButton(
                    onPressed: _busy ? null : _analyzePhoto,
                    child: const Text('Analyze Photo'),
                  ),
                  const SizedBox(height: 12),
                ],
                OutlinedButton.icon(
                  onPressed: _busy ? null : _takePhoto,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Capture Another Photo'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _uploadPhoto,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Choose from Gallery'),
                ),
                if (label != null) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ],
              ],

              const SizedBox(height: 20),

              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Continue without photo'),
              ),

              const SizedBox(height: 12),
              Text(
                'Your photo is analyzed on this device. '
                'A facial expression does not determine '
                'how you actually feel.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
