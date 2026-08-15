import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:io';
import '../services/api_service.dart';
import '../services/card_notifier.dart';
import '../services/connectivity_service.dart';
import '../widgets/image_crop_widget.dart';
import '../widgets/glowing_title_field.dart';

// Screen 2: Camera OCR (Chinese Text Extraction)
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
  final TextEditingController _titleController = TextEditingController();

  CameraPageState _state = CameraPageState.idle;
  String? _extractedText;
  String? _imagePath;
  String? _originalImagePath; // Keep track of original for cleanup
  String? _error;
  bool _isGeneratingTitle = false;
  bool _isManualEntry = false;

  @override
  void dispose() {
    _textController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickFromGallery() async {
    try {
      setState(() {
        _state = CameraPageState.processing;
        _error = null;
        _extractedText = null;
        _imagePath = null;
        _originalImagePath = null;
        _isManualEntry = false;
        _textController.clear();
      });

      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);

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
      print('Error picking image: $e');
      setState(() {
        _state = CameraPageState.idle;
        _error = 'Gallery error: $e';
      });
    }
  }

  void _enterManualMode() {
    setState(() {
      _state = CameraPageState.preview;
      _isManualEntry = true;
      _extractedText = null;
      _imagePath = null;
      _originalImagePath = null;
      _error = null;
      _textController.clear();
      _titleController.clear();
      _isGeneratingTitle = false;
    });
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
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (image == null) {
        setState(() => _state = CameraPageState.idle);
        return;
      }

      setState(() {
        _imagePath = image.path;
        _originalImagePath = image.path;
        _state = CameraPageState.cropping;
        _isManualEntry = false;
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
        _titleController.clear();
        _state = CameraPageState.preview;
      });
      // Kick off async title generation immediately
      _generateTitle(result.text);
    } catch (e) {
      print('Error during OCR: $e');
      setState(() {
        _state = CameraPageState.idle;
        _error = 'OCR error: $e';
      });
      _cleanupImage();
    }
  }

  Future<void> _generateTitle(String text) async {
    if (isOffline) return;
    setState(() => _isGeneratingTitle = true);
    final result = await _api.generateCardTitle(text);
    if (!mounted) return;
    setState(() {
      _isGeneratingTitle = false;
      if (result.isSuccess && result.data != null && result.data!.isNotEmpty) {
        _titleController.text = result.data!;
      }
    });
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

    final titleToSave = _titleController.text.trim();
    try {
      final result = await _api.createCard(
        textZh: textToSave,
        source: 'ocr',
        title: titleToSave.isEmpty ? null : titleToSave,
      );

      if (result.isSuccess) {
        _showMessage('Card saved successfully!');
        _cleanupImage();
        setState(() {
          _state = CameraPageState.idle;
          _extractedText = null;
          _imagePath = null;
          _originalImagePath = null;
          _isManualEntry = false;
          _textController.clear();
          _titleController.clear();
          _isGeneratingTitle = false;
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
      _isManualEntry = false;
      _textController.clear();
      _titleController.clear();
      _isGeneratingTitle = false;
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),
          const Icon(Icons.add_card_outlined, size: 72, color: Colors.grey),
          const SizedBox(height: 20),
          const Text(
            'Add a Card',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose how you want to add a new card',
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

          _AddOptionTile(
            icon: Icons.document_scanner_outlined,
            title: 'Scan with Camera',
            subtitle: 'Take a photo and extract text with OCR',
            onTap: _takePhoto,
          ),
          const SizedBox(height: 12),
          _AddOptionTile(
            icon: Icons.photo_library_outlined,
            title: 'Upload a Photo',
            subtitle: 'Pick an image from your gallery and scan it',
            onTap: _pickFromGallery,
          ),
          const SizedBox(height: 12),
          _AddOptionTile(
            icon: Icons.edit_outlined,
            title: 'Type Manually',
            subtitle: 'Enter Chinese text directly without a photo',
            onTap: _enterManualMode,
          ),
        ],
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

          // Text section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _isManualEntry ? 'Enter Text' : 'Edit Extracted Text',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (!_isManualEntry)
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
          Text(
            _isManualEntry
                ? 'Type the Chinese text you want to save as a card'
                : 'You can edit the text below before saving',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
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

          const SizedBox(height: 20),

          // AI-generated title field
          GlowingTitleField(
            controller: _titleController,
            isGenerating: _isGeneratingTitle,
            onRegenerate: _isGeneratingTitle
                ? null
                : () => _generateTitle(_textController.text.trim()),
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

class _AddOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AddOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Theme.of(context).primaryColor),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
