import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Simple image cropping widget that allows selecting a rectangular region
class ImageCropWidget extends StatefulWidget {
  final String imagePath;
  final Function(File croppedImage)? onCropComplete;
  final VoidCallback? onCancel;

  const ImageCropWidget({
    super.key,
    required this.imagePath,
    this.onCropComplete,
    this.onCancel,
  });

  @override
  State<ImageCropWidget> createState() => _ImageCropWidgetState();
}

class _ImageCropWidgetState extends State<ImageCropWidget> {
  Rect _cropRect = Rect.zero;
  Size _imageSize = Size.zero;
  Size _displaySize = Size.zero;
  bool _isLoading = true;
  bool _isCropping = false;
  ui.Image? _uiImage;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final file = File(widget.imagePath);
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();

    setState(() {
      _uiImage = frame.image;
      _imageSize = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      _isLoading = false;
    });
  }

  void _initCropRect(Size displaySize) {
    if (_cropRect == Rect.zero && displaySize != Size.zero) {
      // Default crop rect is 80% of the image centered
      final margin = displaySize.width * 0.1;
      _cropRect = Rect.fromLTWH(
        margin,
        margin,
        displaySize.width - margin * 2,
        displaySize.height - margin * 2,
      );
      _displaySize = displaySize;
    }
  }

  Future<void> _performCrop() async {
    if (_uiImage == null) return;

    setState(() => _isCropping = true);

    try {
      // Calculate the actual crop rectangle in image coordinates
      final scaleX = _imageSize.width / _displaySize.width;
      final scaleY = _imageSize.height / _displaySize.height;

      final srcRect = Rect.fromLTWH(
        _cropRect.left * scaleX,
        _cropRect.top * scaleY,
        _cropRect.width * scaleX,
        _cropRect.height * scaleY,
      );

      // Create a cropped image
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      final paint = Paint()..filterQuality = FilterQuality.high;

      canvas.drawImageRect(
        _uiImage!,
        srcRect,
        Rect.fromLTWH(0, 0, srcRect.width, srcRect.height),
        paint,
      );

      final picture = recorder.endRecording();
      final croppedImage = await picture.toImage(
        srcRect.width.toInt(),
        srcRect.height.toInt(),
      );

      // Convert to PNG bytes
      final byteData = await croppedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData == null) {
        throw Exception('Failed to encode cropped image');
      }

      // Save to a new temporary file
      final originalFile = File(widget.imagePath);
      final directory = originalFile.parent;
      final croppedPath =
          '${directory.path}/cropped_${DateTime.now().millisecondsSinceEpoch}.png';
      final croppedFile = File(croppedPath);
      await croppedFile.writeAsBytes(byteData.buffer.asUint8List());

      widget.onCropComplete?.call(croppedFile);
    } catch (e) {
      debugPrint('Crop error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Crop failed: $e')));
      }
    } finally {
      setState(() => _isCropping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Calculate display size maintaining aspect ratio
              final aspectRatio = _imageSize.width / _imageSize.height;
              double displayWidth = constraints.maxWidth;
              double displayHeight = displayWidth / aspectRatio;

              if (displayHeight > constraints.maxHeight) {
                displayHeight = constraints.maxHeight;
                displayWidth = displayHeight * aspectRatio;
              }

              final displaySize = Size(displayWidth, displayHeight);
              _initCropRect(displaySize);

              return Center(
                child: SizedBox(
                  width: displayWidth,
                  height: displayHeight,
                  child: Stack(
                    children: [
                      // Image
                      Image.file(
                        File(widget.imagePath),
                        width: displayWidth,
                        height: displayHeight,
                        fit: BoxFit.contain,
                      ),
                      // Darkened overlay outside crop area
                      CustomPaint(
                        size: displaySize,
                        painter: _CropOverlayPainter(_cropRect),
                      ),
                      // Crop rectangle border
                      Positioned.fromRect(
                        rect: _cropRect,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                      // Corner handles
                      ..._buildCornerHandles(displaySize),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Action buttons
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isCropping ? null : widget.onCancel,
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: OutlinedButton(
                  onPressed: _isCropping
                      ? null
                      : () {
                          // Skip cropping, use original
                          widget.onCropComplete?.call(File(widget.imagePath));
                        },
                  child: const Text('Skip Crop'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isCropping ? null : _performCrop,
                  icon: _isCropping
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.crop),
                  label: Text(_isCropping ? 'Cropping...' : 'Crop'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildCornerHandles(Size displaySize) {
    const handleSize = 24.0;

    Widget buildHandle(Alignment alignment, VoidCallback onDrag) {
      double left = 0, top = 0;

      if (alignment == Alignment.topLeft) {
        left = _cropRect.left - handleSize / 2;
        top = _cropRect.top - handleSize / 2;
      } else if (alignment == Alignment.topRight) {
        left = _cropRect.right - handleSize / 2;
        top = _cropRect.top - handleSize / 2;
      } else if (alignment == Alignment.bottomLeft) {
        left = _cropRect.left - handleSize / 2;
        top = _cropRect.bottom - handleSize / 2;
      } else if (alignment == Alignment.bottomRight) {
        left = _cropRect.right - handleSize / 2;
        top = _cropRect.bottom - handleSize / 2;
      }

      return Positioned(
        left: left,
        top: top,
        child: GestureDetector(
          onPanUpdate: (details) {
            setState(() {
              _updateCropRect(alignment, details.delta, displaySize);
            });
          },
          child: Container(
            width: handleSize,
            height: handleSize,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.blue, width: 2),
            ),
          ),
        ),
      );
    }

    // Center drag handle
    final centerHandle = Positioned(
      left: _cropRect.center.dx - 20,
      top: _cropRect.center.dy - 20,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            final newRect = _cropRect.translate(
              details.delta.dx,
              details.delta.dy,
            );
            // Keep within bounds
            if (newRect.left >= 0 &&
                newRect.top >= 0 &&
                newRect.right <= displaySize.width &&
                newRect.bottom <= displaySize.height) {
              _cropRect = newRect;
            }
          });
        },
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.7),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.open_with, size: 24),
        ),
      ),
    );

    return [
      buildHandle(Alignment.topLeft, () {}),
      buildHandle(Alignment.topRight, () {}),
      buildHandle(Alignment.bottomLeft, () {}),
      buildHandle(Alignment.bottomRight, () {}),
      centerHandle,
    ];
  }

  void _updateCropRect(Alignment corner, Offset delta, Size bounds) {
    const minSize = 50.0;
    Rect newRect = _cropRect;

    if (corner == Alignment.topLeft) {
      newRect = Rect.fromLTRB(
        (_cropRect.left + delta.dx).clamp(0, _cropRect.right - minSize),
        (_cropRect.top + delta.dy).clamp(0, _cropRect.bottom - minSize),
        _cropRect.right,
        _cropRect.bottom,
      );
    } else if (corner == Alignment.topRight) {
      newRect = Rect.fromLTRB(
        _cropRect.left,
        (_cropRect.top + delta.dy).clamp(0, _cropRect.bottom - minSize),
        (_cropRect.right + delta.dx).clamp(
          _cropRect.left + minSize,
          bounds.width,
        ),
        _cropRect.bottom,
      );
    } else if (corner == Alignment.bottomLeft) {
      newRect = Rect.fromLTRB(
        (_cropRect.left + delta.dx).clamp(0, _cropRect.right - minSize),
        _cropRect.top,
        _cropRect.right,
        (_cropRect.bottom + delta.dy).clamp(
          _cropRect.top + minSize,
          bounds.height,
        ),
      );
    } else if (corner == Alignment.bottomRight) {
      newRect = Rect.fromLTRB(
        _cropRect.left,
        _cropRect.top,
        (_cropRect.right + delta.dx).clamp(
          _cropRect.left + minSize,
          bounds.width,
        ),
        (_cropRect.bottom + delta.dy).clamp(
          _cropRect.top + minSize,
          bounds.height,
        ),
      );
    }

    _cropRect = newRect;
  }
}

class _CropOverlayPainter extends CustomPainter {
  final Rect cropRect;

  _CropOverlayPainter(this.cropRect);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    // Draw darkened areas around crop rectangle
    // Top
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, cropRect.top), paint);
    // Bottom
    canvas.drawRect(
      Rect.fromLTWH(
        0,
        cropRect.bottom,
        size.width,
        size.height - cropRect.bottom,
      ),
      paint,
    );
    // Left
    canvas.drawRect(
      Rect.fromLTWH(0, cropRect.top, cropRect.left, cropRect.height),
      paint,
    );
    // Right
    canvas.drawRect(
      Rect.fromLTWH(
        cropRect.right,
        cropRect.top,
        size.width - cropRect.right,
        cropRect.height,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect;
  }
}
