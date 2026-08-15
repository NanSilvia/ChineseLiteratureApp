import 'package:flutter/material.dart';

class GlowingTitleField extends StatefulWidget {
  final TextEditingController controller;
  final bool isGenerating;
  final VoidCallback? onRegenerate;

  const GlowingTitleField({
    super.key,
    required this.controller,
    required this.isGenerating,
    this.onRegenerate,
  });

  @override
  State<GlowingTitleField> createState() => _GlowingTitleFieldState();
}

class _GlowingTitleFieldState extends State<GlowingTitleField>
    with TickerProviderStateMixin {
  late final AnimationController _glowController;
  late final AnimationController _shimmerController;
  late final Animation<double> _glowAnim;
  late final Animation<double> _shimmerAnim;

  @override
  void initState() {
    super.initState();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _glowAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _shimmerAnim = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );

    if (widget.isGenerating) {
      _startAnimations();
    }
  }

  @override
  void didUpdateWidget(GlowingTitleField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isGenerating && !oldWidget.isGenerating) {
      _startAnimations();
    } else if (!widget.isGenerating && oldWidget.isGenerating) {
      _stopAnimations();
    }
  }

  void _startAnimations() {
    _glowController.repeat(reverse: true);
    _shimmerController.repeat();
  }

  void _stopAnimations() {
    _glowController.stop();
    _shimmerController.stop();
    // Forward to resting state cleanly
    _glowController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, size: 16),
            const SizedBox(width: 6),
            Text(
              'AI Title',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (!widget.isGenerating && widget.onRegenerate != null)
              TextButton.icon(
                onPressed: widget.onRegenerate,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Regenerate'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        AnimatedBuilder(
          animation: Listenable.merge([_glowAnim, _shimmerAnim]),
          builder: (context, child) {
            final glow = _glowAnim.value;
            final t = _shimmerAnim.value;

            // Oscillating hue for the aurora effect
            final hue = (glow * 360 * 0.5 + 200) % 360;
            final glowColor = HSVColor.fromAHSV(0.85, hue, 0.9, 1.0).toColor();
            final glowColor2 = HSVColor.fromAHSV(
              0.6,
              (hue + 60) % 360,
              0.8,
              1.0,
            ).toColor();

            final borderColor = widget.isGenerating
                ? Color.lerp(primaryColor, glowColor, glow)!
                : primaryColor.withValues(alpha: 0.5);

            final shadowBlur = widget.isGenerating ? (6.0 + glow * 14.0) : 0.0;
            final shadowSpread = widget.isGenerating ? (1.0 + glow * 3.0) : 0.0;

            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: widget.isGenerating
                    ? [
                        BoxShadow(
                          color: glowColor.withValues(alpha: 0.45 * glow),
                          blurRadius: shadowBlur,
                          spreadRadius: shadowSpread,
                        ),
                        BoxShadow(
                          color: glowColor2.withValues(alpha: 0.3 * glow),
                          blurRadius: shadowBlur * 1.6,
                          spreadRadius: shadowSpread * 0.5,
                        ),
                      ]
                    : [],
              ),
              child: Stack(
                children: [
                  TextField(
                    controller: widget.controller,
                    enabled: !widget.isGenerating,
                    maxLines: 1,
                    style: theme.textTheme.titleMedium,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: widget.isGenerating
                          ? theme.colorScheme.surface
                          : theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                      hintText: widget.isGenerating
                          ? 'Generating title...'
                          : 'AI title (editable)',
                      hintStyle: TextStyle(
                        color: widget.isGenerating
                            ? Color.lerp(
                                theme.colorScheme.onSurface.withValues(
                                  alpha: 0.4,
                                ),
                                glowColor,
                                glow * 0.6,
                              )
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.4,
                              ),
                      ),
                      prefixIcon: widget.isGenerating
                          ? Padding(
                              padding: const EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Color.lerp(primaryColor, glowColor, glow)!,
                                  ),
                                ),
                              ),
                            )
                          : const Icon(Icons.title, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: borderColor, width: 2),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: borderColor, width: 2),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: primaryColor, width: 2.5),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: borderColor, width: 2),
                      ),
                    ),
                  ),
                  // Shimmer overlay while generating
                  if (widget.isGenerating)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _ShimmerPainter(
                              progress: t,
                              color: glowColor.withValues(alpha: 0.12),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        if (widget.isGenerating)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: AnimatedBuilder(
              animation: _shimmerAnim,
              builder: (context, _) {
                final dots =
                    '.' * (((_shimmerAnim.value.abs() * 3).floor() % 4));
                return Text(
                  'AI is crafting a title$dots',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary.withValues(alpha: 0.7),
                    fontStyle: FontStyle.italic,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _ShimmerPainter extends CustomPainter {
  final double progress;
  final Color color;

  _ShimmerPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment(progress - 0.6, 0),
        end: Alignment(progress + 0.6, 0),
        colors: [Colors.transparent, color, Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) =>
      old.progress != progress || old.color != color;
}
