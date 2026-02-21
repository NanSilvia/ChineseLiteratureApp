import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Image cropping widget with 4-point polygon selection.
/// Users drag 4 corners to define an arbitrary quadrilateral region,
/// which is then perspective-corrected (projected) to a rectangle for OCR.
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
  /// Four corner points in display coordinates: TL, TR, BR, BL (clockwise).
  List<Offset> _corners = [];
  Size _imageSize = Size.zero;
  Size _displaySize = Size.zero;
  bool _isLoading = true;
  bool _isCropping = false;
  ui.Image? _uiImage;
  int? _activeCorner; // index of corner currently being dragged

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

  void _initCorners(Size displaySize) {
    _displaySize = displaySize;
    if (_corners.isEmpty && displaySize != Size.zero) {
      final mx = displaySize.width * 0.1;
      final my = displaySize.height * 0.1;
      _corners = [
        Offset(mx, my), // top-left
        Offset(displaySize.width - mx, my), // top-right
        Offset(displaySize.width - mx, displaySize.height - my), // bottom-right
        Offset(mx, displaySize.height - my), // bottom-left
      ];
    }
  }

  /// Find the nearest corner within a touch threshold.
  int? _hitTestCorner(Offset point) {
    const threshold = 40.0;
    double minDist = double.infinity;
    int? closest;
    for (int i = 0; i < _corners.length; i++) {
      final d = (_corners[i] - point).distance;
      if (d < minDist && d < threshold) {
        minDist = d;
        closest = i;
      }
    }
    return closest;
  }

  // ─────────────── Perspective crop ───────────────

  Future<void> _performCrop() async {
    if (_uiImage == null) return;
    setState(() => _isCropping = true);

    try {
      // Map display-space corners to image-pixel coordinates
      final scaleX = _imageSize.width / _displaySize.width;
      final scaleY = _imageSize.height / _displaySize.height;
      final imgCorners = _corners
          .map((c) => Offset(c.dx * scaleX, c.dy * scaleY))
          .toList();

      // Output size derived from average edge lengths
      final topEdge = (imgCorners[1] - imgCorners[0]).distance;
      final bottomEdge = (imgCorners[2] - imgCorners[3]).distance;
      final leftEdge = (imgCorners[3] - imgCorners[0]).distance;
      final rightEdge = (imgCorners[2] - imgCorners[1]).distance;

      int outW = ((topEdge + bottomEdge) / 2).round();
      int outH = ((leftEdge + rightEdge) / 2).round();

      // Cap for performance
      const maxDim = 2000;
      if (outW > maxDim || outH > maxDim) {
        final s = maxDim / max(outW, outH);
        outW = (outW * s).round();
        outH = (outH * s).round();
      }
      if (outW < 10) outW = 10;
      if (outH < 10) outH = 10;

      // Destination rectangle corners
      final rectCorners = [
        const Offset(0, 0),
        Offset(outW.toDouble(), 0),
        Offset(outW.toDouble(), outH.toDouble()),
        Offset(0, outH.toDouble()),
      ];

      // Forward homography: image coords → output coords
      final h = _computeHomography(imgCorners, rectCorners);

      // Embed 3×3 homography in a 4×4 column-major matrix
      final m = Float64List(16);
      m[0] = h[0];
      m[1] = h[3];
      m[2] = 0;
      m[3] = h[6];
      m[4] = h[1];
      m[5] = h[4];
      m[6] = 0;
      m[7] = h[7];
      m[8] = 0;
      m[9] = 0;
      m[10] = 1;
      m[11] = 0;
      m[12] = h[2];
      m[13] = h[5];
      m[14] = 0;
      m[15] = 1;

      // Render the perspective-corrected image
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.clipRect(Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()));
      canvas.transform(m);
      canvas.drawImage(
        _uiImage!,
        Offset.zero,
        Paint()..filterQuality = FilterQuality.high,
      );

      final picture = recorder.endRecording();
      final outImage = await picture.toImage(outW, outH);

      final pngData = await outImage.toByteData(format: ui.ImageByteFormat.png);
      if (pngData == null) throw Exception('Failed to encode image');

      final dir = File(widget.imagePath).parent;
      final path =
          '${dir.path}/cropped_${DateTime.now().millisecondsSinceEpoch}.png';
      final croppedFile = File(path);
      await croppedFile.writeAsBytes(pngData.buffer.asUint8List());

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

  // ─────────────── Homography math ───────────────

  /// Compute the 3×3 homography that maps [src] points to [dst] points.
  /// Returns the 8 coefficients [h0..h7] with h8 normalised to 1.
  List<double> _computeHomography(List<Offset> src, List<Offset> dst) {
    assert(src.length == 4 && dst.length == 4);

    final a = List.generate(8, (_) => List.filled(8, 0.0));
    final b = List.filled(8, 0.0);

    for (int i = 0; i < 4; i++) {
      final sx = src[i].dx, sy = src[i].dy;
      final dx = dst[i].dx, dy = dst[i].dy;

      a[2 * i] = [sx, sy, 1, 0, 0, 0, -dx * sx, -dx * sy];
      b[2 * i] = dx;

      a[2 * i + 1] = [0, 0, 0, sx, sy, 1, -dy * sx, -dy * sy];
      b[2 * i + 1] = dy;
    }

    return _gaussianElimination(a, b);
  }

  /// Solve A·x = b via Gaussian elimination with partial pivoting.
  List<double> _gaussianElimination(List<List<double>> a, List<double> b) {
    final n = b.length;
    final aug = List.generate(n, (i) => [...a[i], b[i]]);

    for (int col = 0; col < n; col++) {
      // Pivot
      int maxRow = col;
      double maxVal = aug[col][col].abs();
      for (int row = col + 1; row < n; row++) {
        if (aug[row][col].abs() > maxVal) {
          maxVal = aug[row][col].abs();
          maxRow = row;
        }
      }
      if (maxRow != col) {
        final tmp = aug[col];
        aug[col] = aug[maxRow];
        aug[maxRow] = tmp;
      }
      // Eliminate
      for (int row = col + 1; row < n; row++) {
        final f = aug[row][col] / aug[col][col];
        for (int j = col; j <= n; j++) {
          aug[row][j] -= f * aug[col][j];
        }
      }
    }

    // Back-substitute
    final x = List.filled(n, 0.0);
    for (int i = n - 1; i >= 0; i--) {
      x[i] = aug[i][n];
      for (int j = i + 1; j < n; j++) {
        x[i] -= aug[i][j] * x[j];
      }
      x[i] /= aug[i][i];
    }
    return x;
  }

  // ─────────────── Build UI ───────────────

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
              final aspectRatio = _imageSize.width / _imageSize.height;
              double dw = constraints.maxWidth;
              double dh = dw / aspectRatio;
              if (dh > constraints.maxHeight) {
                dh = constraints.maxHeight;
                dw = dh * aspectRatio;
              }
              _initCorners(Size(dw, dh));

              return Center(
                child: SizedBox(
                  width: dw,
                  height: dh,
                  child: GestureDetector(
                    onPanStart: (d) {
                      _activeCorner = _hitTestCorner(d.localPosition);
                    },
                    onPanUpdate: (d) {
                      if (_activeCorner != null) {
                        setState(() {
                          _corners[_activeCorner!] = Offset(
                            d.localPosition.dx.clamp(0, dw),
                            d.localPosition.dy.clamp(0, dh),
                          );
                        });
                      }
                    },
                    onPanEnd: (_) => _activeCorner = null,
                    child: Stack(
                      children: [
                        // Source image
                        Image.file(
                          File(widget.imagePath),
                          width: dw,
                          height: dh,
                          fit: BoxFit.contain,
                        ),
                        // Darkened overlay outside the polygon
                        if (_corners.length == 4)
                          CustomPaint(
                            size: Size(dw, dh),
                            painter: _PolygonOverlayPainter(_corners),
                          ),
                        // Corner handles
                        ..._buildHandles(),
                      ],
                    ),
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

  List<Widget> _buildHandles() {
    const size = 28.0;
    final labels = ['TL', 'TR', 'BR', 'BL'];

    return List.generate(_corners.length, (i) {
      return Positioned(
        left: _corners[i].dx - size / 2,
        top: _corners[i].dy - size / 2,
        child: IgnorePointer(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: _activeCorner == i ? Colors.blue : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.blue, width: 2),
              boxShadow: const [
                BoxShadow(blurRadius: 4, color: Colors.black26),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              labels[i],
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: _activeCorner == i ? Colors.white : Colors.blue,
              ),
            ),
          ),
        ),
      );
    });
  }
}

// ─────────────── Overlay painter ───────────────

class _PolygonOverlayPainter extends CustomPainter {
  final List<Offset> corners;

  _PolygonOverlayPainter(this.corners);

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) return;

    final polyPath = Path()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();

    // Darken everything outside the selected polygon
    final fullPath = Path()..addRect(Offset.zero & size);
    final darkPath = Path.combine(PathOperation.difference, fullPath, polyPath);
    canvas.drawPath(
      darkPath,
      Paint()..color = Colors.black.withValues(alpha: 0.5),
    );

    // Polygon border
    canvas.drawPath(
      polyPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Rule-of-thirds guide lines inside the quad
    final guidePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int t = 1; t <= 2; t++) {
      final f = t / 3.0;
      // Horizontal
      final left = Offset.lerp(corners[0], corners[3], f)!;
      final right = Offset.lerp(corners[1], corners[2], f)!;
      canvas.drawLine(left, right, guidePaint);
      // Vertical
      final top = Offset.lerp(corners[0], corners[1], f)!;
      final bottom = Offset.lerp(corners[3], corners[2], f)!;
      canvas.drawLine(top, bottom, guidePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PolygonOverlayPainter oldDelegate) => true;
}
