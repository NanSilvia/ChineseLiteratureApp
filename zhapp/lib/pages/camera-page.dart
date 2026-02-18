import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:io';

class CameraPage extends StatefulWidget {
  final Function(String) onTextExtracted;

  const CameraPage({super.key, required this.onTextExtracted});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  bool _isProcessing = false;

  Future<void> _takePhotoAndOcr() async {
    try {
      setState(() => _isProcessing = true);

      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.camera);
      if (image == null) {
        setState(() => _isProcessing = false);
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Processing image...')));

      final inputImage = InputImage.fromFilePath(image.path);
      // Try with Chinese script
      final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
      final result = await recognizer.processImage(inputImage);

      // Debug: Print the raw text to see what's being extracted
      print('Raw extracted text: "${result.text}"');
      print('Text length: ${result.text.length}');

      await recognizer.close();

      // Delete the temporary image file from cache
      try {
        File(image.path).deleteSync();
      } catch (e) {
        print('Could not delete image file: $e');
      }

      if (result.text.isEmpty || result.text == '/') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No text found in image. Try better lighting and focus.',
            ),
          ),
        );
        setState(() => _isProcessing = false);
        return;
      }

      widget.onTextExtracted(result.text);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Extracted: ${result.text.substring(0, result.text.length > 30 ? 30 : result.text.length)}',
          ),
        ),
      );
      setState(() => _isProcessing = false);
    } catch (e) {
      print('Error during OCR: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: _isProcessing ? null : _takePhotoAndOcr,
        child: Text(
          _isProcessing ? 'Processing...' : 'Take photo & extract text',
        ),
      ),
    );
  }
}
