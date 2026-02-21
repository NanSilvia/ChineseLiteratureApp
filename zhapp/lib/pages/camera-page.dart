import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:io';
import '../services/api_service.dart';
import '../services/card_notifier.dart';
import '../services/connectivity_service.dart';
import '../widgets/image_crop_widget.dart';

/// Screen 2: Camera OCR (Chinese Text Extraction)
/// Allows user to take a photo, crop it, extract Chinese text using OCR,
/// edit the text, and save it as a new card (online-only save)
class CameraPage extends StatefulWidget {
  final VoidCallback? onCardSaved;

  const CameraPage({super.key, this.onCardSaved});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

enum CameraPageState { idle, cropping, processing, preview, saving }

class _CameraPageState extends State<CameraPage> with ConnectivityAware {
  final ApiService _api = ApiService();
  final TextEditingController _textController = TextEditingController();

  CameraPageState _state = CameraPageState.idle;
  String? _extractedText;
  String? _imagePath;
  String? _originalImagePath; // Keep track of original for cleanup
  String? _error;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    try {
      setState(() {
        _state = CameraPageState.processing;
        _error = null;
        _extractedText = null;
        _imagePath = null;
        _originalImagePath = null;
        _textController.clear();
      });

      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.camera);

      if (image == null) {
        setState(() => _state = CameraPageState.idle);
        return;
      }

      setState(() {
        _imagePath = image.path;
        _originalImagePath = image.path;
        _state = CameraPageState.cropping;
      });
    } catch (e) {
      print('Error taking photo: $e');
      setState(() {
        _state = CameraPageState.idle;
        _error = 'Camera error: $e';
      });
    }
  }

  void _onCropComplete(File croppedImage) {
    setState(() {
      _imagePath = croppedImage.path;
      _state = CameraPageState.processing;
    });
    _performOCR();
  }

  void _onCropCancel() {
    _cleanupImage();
    setState(() {
      _state = CameraPageState.idle;
      _imagePath = null;
      _originalImagePath = null;
    });
  }

  Future<void> _performOCR() async {
    try {
      // Show processing indicator
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Processing image...')));
      }

      // Perform OCR
      final inputImage = InputImage.fromFilePath(_imagePath!);
      final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
      final result = await recognizer.processImage(inputImage);
      await recognizer.close();

      // Debug output
      print('Raw extracted text: "${result.text}"');
      print('Text length: ${result.text.length}');

      if (result.text.isEmpty ||
          result.text.trim() == '/' ||
          result.text.trim().isEmpty) {
        setState(() {
          _state = CameraPageState.idle;
          _error =
              'No Chinese text found in image. Try better lighting and focus.';
        });
        _cleanupImage();
        return;
      }

      setState(() {
        _extractedText = result.text;
        _textController.text = result.text;
        _state = CameraPageState.preview;
      });
    } catch (e) {
      print('Error during OCR: $e');
      setState(() {
        _state = CameraPageState.idle;
        _error = 'OCR error: $e';
      });
      _cleanupImage();
    }
  }

  Future<void> _saveAsCard() async {
    final textToSave = _textController.text.trim();
    if (textToSave.isEmpty) {
      _showMessage('Please enter some text to save.');
      return;
    }

    // Check connectivity
    if (isOffline) {
      _showMessage('You must be online to save a new card.');
      return;
    }

    setState(() {
      _state = CameraPageState.saving;
      _error = null;
    });

    try {
      final result = await _api.createCard(textZh: textToSave, source: 'ocr');

      if (result.isSuccess) {
        _showMessage('Card saved successfully!');
        _cleanupImage();
        setState(() {
          _state = CameraPageState.idle;
          _extractedText = null;
          _imagePath = null;
          _originalImagePath = null;
          _textController.clear();
        });
        CardNotifier().notifyCardsChanged();
        widget.onCardSaved?.call();
      } else if (result.isOffline) {
        _showMessage('You must be online to save a new card.');
        setState(() => _state = CameraPageState.preview);
      } else {
        setState(() {
          _state = CameraPageState.preview;
          _error = result.error;
        });
      }
    } catch (e) {
      setState(() {
        _state = CameraPageState.preview;
        _error = 'Failed to save: $e';
      });
    }
  }

  void _discardAndRetry() {
    _cleanupImage();
    setState(() {
      _state = CameraPageState.idle;
      _extractedText = null;
      _imagePath = null;
      _originalImagePath = null;
      _error = null;
      _textController.clear();
    });
  }

  void _cleanupImage() {
    // Clean up cropped image if different from original
    if (_imagePath != null && _imagePath != _originalImagePath) {
      try {
        File(_imagePath!).deleteSync();
      } catch (e) {
        print('Could not delete cropped image file: $e');
      }
    }
    // Clean up original image
    if (_originalImagePath != null) {
      try {
        File(_originalImagePath!).deleteSync();
      } catch (e) {
        print('Could not delete original image file: $e');
      }
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const OfflineBanner(),
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildContent() {
    switch (_state) {
      case CameraPageState.idle:
        return _buildIdleState();
      case CameraPageState.cropping:
        return _buildCroppingState();
      case CameraPageState.processing:
        return _buildProcessingState();
      case CameraPageState.preview:
        return _buildPreviewState();
      case CameraPageState.saving:
        return _buildSavingState();
    }
  }

  Widget _buildIdleState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.camera_alt_outlined, size: 80, color: Colors.grey),
            const SizedBox(height: 24),
            const Text(
              'Extract Chinese Text',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Take a photo of Chinese text to extract and save it as a card',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),

            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            ElevatedButton.icon(
              onPressed: _takePhoto,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Take Photo'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCroppingState() {
    if (_imagePath == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Crop Image',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Adjust the crop area to focus on the text you want to extract',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ImageCropWidget(
            imagePath: _imagePath!,
            onCropComplete: _onCropComplete,
            onCancel: _onCropCancel,
          ),
        ),
      ],
    );
  }

  Widget _buildProcessingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Show image preview while processing
          if (_imagePath != null)
            Container(
              width: 200,
              height: 200,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(_imagePath!), fit: BoxFit.cover),
              ),
            ),
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          const Text('Extracting Chinese text...'),
        ],
      ),
    );
  }

  Widget _buildPreviewState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image preview
          if (_imagePath != null)
            Container(
              width: double.infinity,
              height: 200,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(_imagePath!), fit: BoxFit.contain),
              ),
            ),

          // Extracted text section - editable
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Edit Extracted Text',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: () {
                  _textController.text = _extractedText ?? '';
                },
                icon: const Icon(Icons.restore, size: 18),
                label: const Text('Reset'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'You can edit the text below before saving',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _textController,
            maxLines: null,
            minLines: 5,
            style: const TextStyle(fontSize: 18, height: 1.8),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).primaryColor,
                  width: 2,
                ),
              ),
              hintText: 'Enter or edit Chinese text...',
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Offline warning
          if (isOffline) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.wifi_off, color: Colors.orange.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'You must be online to save a new card.',
                      style: TextStyle(color: Colors.orange.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _discardAndRetry,
                  icon: const Icon(Icons.close),
                  label: const Text('Discard'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isOnline ? _saveAsCard : null,
                  icon: const Icon(Icons.save),
                  label: const Text('Save as Card'),
                ),
              ),
            ],
          ),

          if (isOffline) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await connectivity.checkConnection();
                  if (isOnline) {
                    _saveAsCard();
                  }
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSavingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Saving card...'),
        ],
      ),
    );
  }
}
