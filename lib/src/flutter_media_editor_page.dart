import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<File?> showFlutterImageEditor(
  BuildContext context, {
  required File imageFile,
}) {
  return Navigator.of(context).push<File>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => FlutterImageEditorPage(imageFile: imageFile),
    ),
  );
}

enum _EditTool { brush, sticker, text, mosaic }

enum _MosaicStyle { blur, frosted, pixel }

class FlutterImageEditorPage extends StatefulWidget {
  const FlutterImageEditorPage({required this.imageFile, super.key});

  final File imageFile;

  @override
  State<FlutterImageEditorPage> createState() => _FlutterImageEditorPageState();
}

class _FlutterImageEditorPageState extends State<FlutterImageEditorPage> {
  final _boundaryKey = GlobalKey();
  final _textController = TextEditingController();
  final _textFocusNode = FocusNode();
  final _actions = <_EditAction>[];

  _DrawStroke? _draftStroke;
  _MosaicStroke? _draftMosaic;
  _EditTool _tool = _EditTool.brush;
  Color _color = Colors.redAccent;
  double _strokeWidth = 6;
  double _textSize = 32;
  _MosaicStyle _mosaicStyle = _MosaicStyle.blur;
  Offset? _pendingTextOffset;
  bool _saving = false;

  @override
  void dispose() {
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  bool get _showTextPanel =>
      _tool == _EditTool.text && _pendingTextOffset != null;
  bool get _showStickerPanel => _tool == _EditTool.sticker;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              saving: _saving,
              onCancel: () => Navigator.of(context).pop(),
              onDone: _saving ? null : _save,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      DragTarget<String>(
                        onAcceptWithDetails: _addStickerFromDrop,
                        builder: (context, candidateData, rejectedData) {
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (details) =>
                                _handleTap(details.localPosition),
                            onPanStart: (details) =>
                                _handlePanStart(details.localPosition),
                            onPanUpdate: (details) =>
                                _handlePanUpdate(details.localPosition),
                            onPanEnd: (_) => _finishCurrentStroke(),
                            onPanCancel: _finishCurrentStroke,
                            child: RepaintBoundary(
                              key: _boundaryKey,
                              child: SizedBox(
                                width: constraints.maxWidth,
                                height: constraints.maxHeight,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ColoredBox(
                                      color: Colors.black,
                                      child: Image.file(
                                        widget.imageFile,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    _EditorOverlay(
                                      imageFile: widget.imageFile,
                                      actions: _actions,
                                      draftStroke: _draftStroke,
                                      draftMosaic: _draftMosaic,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      if (_showTextPanel)
                        PositionedDirectional(
                          start: 12,
                          end: 12,
                          bottom: 12,
                          child: _InlineTextPanel(
                            controller: _textController,
                            focusNode: _textFocusNode,
                            color: _color,
                            size: _textSize,
                            onColorChanged: (value) =>
                                setState(() => _color = value),
                            onSizeChanged: (value) =>
                                setState(() => _textSize = value),
                            onCancel: _cancelText,
                            onConfirm: _confirmText,
                          ),
                        ),
                      if (_showStickerPanel)
                        PositionedDirectional(
                          start: 12,
                          end: 12,
                          bottom: 12,
                          child: _InlineStickerPanel(),
                        ),
                    ],
                  );
                },
              ),
            ),
            _ToolOptions(
              tool: _tool,
              color: _color,
              strokeWidth: _strokeWidth,
              mosaicStyle: _mosaicStyle,
              onColorChanged: (value) => setState(() => _color = value),
              onStrokeWidthChanged: (value) =>
                  setState(() => _strokeWidth = value),
              onMosaicStyleChanged: (value) =>
                  setState(() => _mosaicStyle = value),
            ),
            _ToolBar(
              tool: _tool,
              onToolChanged: _selectTool,
              onUndo: _undo,
              onDone: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }

  void _selectTool(_EditTool tool) {
    _finishCurrentStroke();
    setState(() {
      _tool = tool;
      _pendingTextOffset = null;
      _textController.clear();
      if (tool != _EditTool.text) _textFocusNode.unfocus();
    });
  }

  void _handleTap(Offset position) {
    if (_tool == _EditTool.text) {
      setState(() {
        _pendingTextOffset = position;
        _textController.clear();
      });
      _textFocusNode.requestFocus();
    }
  }

  void _handlePanStart(Offset position) {
    if (_tool == _EditTool.brush) {
      setState(() {
        _draftStroke = _DrawStroke(
          color: _color,
          width: _strokeWidth,
          points: [position],
        );
      });
    } else if (_tool == _EditTool.mosaic) {
      setState(() {
        _draftMosaic = _MosaicStroke(
          size: _strokeWidth * 5,
          style: _mosaicStyle,
          points: [position],
        );
      });
    }
  }

  void _handlePanUpdate(Offset position) {
    if (_tool == _EditTool.brush && _draftStroke != null) {
      setState(() => _draftStroke!.points.add(position));
    } else if (_tool == _EditTool.mosaic && _draftMosaic != null) {
      setState(() => _draftMosaic!.points.add(position));
    }
  }

  void _finishCurrentStroke() {
    if (_draftStroke == null && _draftMosaic == null) return;
    setState(() {
      final stroke = _draftStroke;
      final mosaic = _draftMosaic;
      if (stroke != null && stroke.points.isNotEmpty) {
        _actions.add(_StrokeAction(stroke));
      }
      if (mosaic != null && mosaic.points.isNotEmpty) {
        _actions.add(_MosaicAction(mosaic));
      }
      _draftStroke = null;
      _draftMosaic = null;
    });
  }

  void _cancelText() {
    setState(() {
      _pendingTextOffset = null;
      _textController.clear();
    });
    _textFocusNode.unfocus();
  }

  void _confirmText() {
    final text = _textController.text.trim();
    final offset = _pendingTextOffset;
    if (text.isEmpty || offset == null) {
      _cancelText();
      return;
    }
    setState(() {
      _actions.add(
        _TextAction(
          _PlacedText(
            text: text,
            offset: offset,
            color: _color,
            size: _textSize,
          ),
        ),
      );
      _pendingTextOffset = null;
      _textController.clear();
    });
    _textFocusNode.unfocus();
  }

  void _addStickerFromDrop(DragTargetDetails<String> details) {
    final renderObject = _boundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return;
    final localPosition = renderObject.globalToLocal(details.offset);
    setState(() {
      _actions.add(
        _StickerAction(
          _PlacedSticker(text: details.data, offset: localPosition, size: 42),
        ),
      );
    });
  }

  void _undo() {
    _finishCurrentStroke();
    if (_actions.isEmpty) return;
    setState(() => _actions.removeLast());
  }

  Future<void> _save() async {
    _finishCurrentStroke();
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData?.buffer.asUint8List();
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final base = p.basenameWithoutExtension(widget.imageFile.path);
      final output = File(
        p.join(
          dir.path,
          '$base-edited-${DateTime.now().microsecondsSinceEpoch}.png',
        ),
      );
      await output.writeAsBytes(bytes, flush: true);
      if (mounted) Navigator.of(context).pop(output);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _EditorOverlay extends StatelessWidget {
  const _EditorOverlay({
    required this.imageFile,
    required this.actions,
    required this.draftStroke,
    required this.draftMosaic,
  });

  final File imageFile;
  final List<_EditAction> actions;
  final _DrawStroke? draftStroke;
  final _MosaicStroke? draftMosaic;

  @override
  Widget build(BuildContext context) {
    final mosaicStrokes = <_MosaicStroke>[
      for (final action in actions)
        if (action is _MosaicAction) action.stroke,
      ?_MosaicStrokeClipper._nullableStroke(draftMosaic),
    ];
    final foregroundActions = <_EditAction>[
      for (final action in actions)
        if (action is! _MosaicAction) action,
      ?_StrokeAction._nullableStroke(draftStroke),
    ];

    return Stack(
      fit: StackFit.expand,
      children: [
        for (final stroke in mosaicStrokes) ..._mosaicLayers(stroke),
        CustomPaint(
          painter: _EditorForegroundPainter(actions: foregroundActions),
        ),
      ],
    );
  }

  List<Widget> _mosaicLayers(_MosaicStroke stroke) {
    final clipper = _MosaicStrokeClipper(stroke);
    return switch (stroke.style) {
      _MosaicStyle.blur => [
        ClipPath(
          clipper: clipper,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Image.file(imageFile, fit: BoxFit.contain),
          ),
        ),
      ],
      _MosaicStyle.frosted => [
        ClipPath(
          clipper: clipper,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Image.file(imageFile, fit: BoxFit.contain),
          ),
        ),
        CustomPaint(painter: _FrostedMosaicPainter(stroke: stroke)),
      ],
      _MosaicStyle.pixel => [
        ClipPath(
          clipper: clipper,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Image.file(imageFile, fit: BoxFit.contain),
          ),
        ),
        CustomPaint(painter: _PixelMosaicPainter(stroke: stroke)),
      ],
    };
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.saving,
    required this.onCancel,
    required this.onDone,
  });

  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: Row(
        children: [
          TextButton(
            onPressed: saving ? null : onCancel,
            child: const Text(
              '取消返回',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
          const Spacer(),
          const Text(
            '处理历史',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          IconButton.filled(
            onPressed: onDone,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF12C76A),
              foregroundColor: Colors.white,
            ),
            icon: saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

class _InlineTextPanel extends StatelessWidget {
  const _InlineTextPanel({
    required this.controller,
    required this.focusNode,
    required this.color,
    required this.size,
    required this.onColorChanged,
    required this.onSizeChanged,
    required this.onCancel,
    required this.onConfirm,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Color color;
  final double size;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onSizeChanged;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xEE202020),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              focusNode: focusNode,
              maxLength: 40,
              style: TextStyle(
                color: color,
                fontSize: size,
                fontWeight: FontWeight.w700,
              ),
              decoration: const InputDecoration(
                counterText: '',
                hintText: '输入文字',
                hintStyle: TextStyle(color: Colors.white54),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final item in _palette)
                  GestureDetector(
                    onTap: () => onColorChanged(item),
                    child: CircleAvatar(
                      radius: color == item ? 14 : 11,
                      backgroundColor: item,
                    ),
                  ),
                SizedBox(
                  width: 150,
                  child: Slider(
                    value: size,
                    min: 18,
                    max: 64,
                    onChanged: onSizeChanged,
                  ),
                ),
                TextButton(onPressed: onCancel, child: const Text('取消')),
                FilledButton(onPressed: onConfirm, child: const Text('确定')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineStickerPanel extends StatelessWidget {
  const _InlineStickerPanel();

  @override
  Widget build(BuildContext context) {
    const stickers = [
      '😀',
      '😂',
      '😍',
      '👍',
      '🔥',
      '🎉',
      '❤️',
      '⭐',
      '😎',
      '😭',
      '🤔',
      '✅',
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xEE202020),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final sticker in stickers)
              Draggable<String>(
                data: sticker,
                dragAnchorStrategy: pointerDragAnchorStrategy,
                feedback: Material(
                  color: Colors.transparent,
                  child: Text(sticker, style: const TextStyle(fontSize: 42)),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.35,
                  child: _StickerChip(sticker: sticker),
                ),
                child: _StickerChip(sticker: sticker),
              ),
          ],
        ),
      ),
    );
  }
}

class _StickerChip extends StatelessWidget {
  const _StickerChip({required this.sticker});

  final String sticker;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: Center(child: Text(sticker, style: const TextStyle(fontSize: 32))),
    );
  }
}

class _ToolOptions extends StatelessWidget {
  const _ToolOptions({
    required this.tool,
    required this.color,
    required this.strokeWidth,
    required this.mosaicStyle,
    required this.onColorChanged,
    required this.onStrokeWidthChanged,
    required this.onMosaicStyleChanged,
  });

  final _EditTool tool;
  final Color color;
  final double strokeWidth;
  final _MosaicStyle mosaicStyle;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onStrokeWidthChanged;
  final ValueChanged<_MosaicStyle> onMosaicStyleChanged;

  @override
  Widget build(BuildContext context) {
    if (tool != _EditTool.brush && tool != _EditTool.mosaic) {
      return const SizedBox(height: 18);
    }
    return Container(
      color: const Color(0x66333333),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (tool == _EditTool.brush)
            for (final item in _palette)
              GestureDetector(
                onTap: () => onColorChanged(item),
                child: CircleAvatar(
                  radius: color == item ? 15 : 12,
                  backgroundColor: item,
                  child: color == item
                      ? const Icon(Icons.check, color: Colors.white, size: 14)
                      : null,
                ),
              ),
          if (tool == _EditTool.mosaic) ...[
            _MosaicStyleChip(
              label: '模糊',
              selected: mosaicStyle == _MosaicStyle.blur,
              onTap: () => onMosaicStyleChanged(_MosaicStyle.blur),
            ),
            _MosaicStyleChip(
              label: '磨砂',
              selected: mosaicStyle == _MosaicStyle.frosted,
              onTap: () => onMosaicStyleChanged(_MosaicStyle.frosted),
            ),
            _MosaicStyleChip(
              label: '像素',
              selected: mosaicStyle == _MosaicStyle.pixel,
              onTap: () => onMosaicStyleChanged(_MosaicStyle.pixel),
            ),
          ],
          SizedBox(
            width: 180,
            child: Slider(
              value: strokeWidth,
              min: 2,
              max: 18,
              onChanged: onStrokeWidthChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _MosaicStyleChip extends StatelessWidget {
  const _MosaicStyleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF12C76A) : const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ToolBar extends StatelessWidget {
  const _ToolBar({
    required this.tool,
    required this.onToolChanged,
    required this.onUndo,
    required this.onDone,
  });

  final _EditTool tool;
  final ValueChanged<_EditTool> onToolChanged;
  final VoidCallback onUndo;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xCC555555),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Row(
        children: [
          _ToolButton(
            icon: Icons.brush_rounded,
            selected: tool == _EditTool.brush,
            onTap: () => onToolChanged(_EditTool.brush),
          ),
          _ToolButton(
            icon: Icons.emoji_emotions_rounded,
            selected: tool == _EditTool.sticker,
            onTap: () => onToolChanged(_EditTool.sticker),
          ),
          _ToolButton(
            icon: Icons.text_fields_rounded,
            selected: tool == _EditTool.text,
            onTap: () => onToolChanged(_EditTool.text),
          ),
          _ToolButton(
            icon: Icons.grid_on_rounded,
            selected: tool == _EditTool.mosaic,
            onTap: () => onToolChanged(_EditTool.mosaic),
          ),
          IconButton(
            onPressed: onUndo,
            icon: const Icon(Icons.undo_rounded, color: Colors.white, size: 28),
          ),
          const Spacer(),
          FilledButton(
            onPressed: onDone,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF12C76A),
            ),
            child: const Text('完成', style: TextStyle(fontSize: 20)),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      style: IconButton.styleFrom(
        backgroundColor: selected
            ? const Color(0xFF12C76A)
            : Colors.transparent,
      ),
      icon: Icon(icon, color: Colors.white, size: 28),
    );
  }
}

class _EditorForegroundPainter extends CustomPainter {
  const _EditorForegroundPainter({required this.actions});

  final List<_EditAction> actions;

  @override
  void paint(Canvas canvas, Size size) {
    for (final action in actions) {
      switch (action) {
        case _StrokeAction(:final stroke):
          _paintStroke(canvas, stroke);
        case _StickerAction(:final sticker):
          _paintText(
            canvas,
            sticker.text,
            sticker.offset,
            Colors.white,
            sticker.size,
          );
        case _TextAction(:final text):
          _paintText(canvas, text.text, text.offset, text.color, text.size);
        case _MosaicAction():
          break;
      }
    }
  }

  void _paintStroke(Canvas canvas, _DrawStroke stroke) {
    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (var i = 1; i < stroke.points.length; i++) {
      canvas.drawLine(stroke.points[i - 1], stroke.points[i], paint);
    }
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset offset,
    Color color,
    double size,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 320);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _EditorForegroundPainter oldDelegate) => true;
}

class _FrostedMosaicPainter extends CustomPainter {
  const _FrostedMosaicPainter({required this.stroke});

  final _MosaicStroke stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final clip = _MosaicStrokeClipper(stroke).getClip(size);
    canvas.save();
    canvas.clipPath(clip);
    final paint = Paint()
      ..color = const Color(0x55FFFFFF)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke.size * 0.72
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    for (var i = 1; i < stroke.points.length; i++) {
      canvas.drawLine(stroke.points[i - 1], stroke.points[i], paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FrostedMosaicPainter oldDelegate) => true;
}

class _PixelMosaicPainter extends CustomPainter {
  const _PixelMosaicPainter({required this.stroke});

  final _MosaicStroke stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final clip = _MosaicStrokeClipper(stroke).getClip(size);
    canvas.save();
    canvas.clipPath(clip);
    final cell = (stroke.size / 3).clamp(6.0, 18.0);
    final bounds = clip.getBounds().inflate(cell);
    final colors = <Color>[
      const Color(0x66FFFFFF),
      const Color(0x66000000),
      const Color(0x44A0A0A0),
      const Color(0x33FFFFFF),
    ];
    for (double x = bounds.left; x < bounds.right; x += cell) {
      for (double y = bounds.top; y < bounds.bottom; y += cell) {
        final index = ((x / cell).floor() + (y / cell).floor()) % colors.length;
        canvas.drawRect(
          Rect.fromLTWH(x, y, cell - 1, cell - 1),
          Paint()..color = colors[index],
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PixelMosaicPainter oldDelegate) => true;
}

class _MosaicStrokeClipper extends CustomClipper<Path> {
  const _MosaicStrokeClipper(this.stroke);
  static _MosaicStroke? _nullableStroke(_MosaicStroke? stroke) => stroke;

  final _MosaicStroke stroke;

  @override
  Path getClip(Size size) {
    final path = Path();
    for (final point in stroke.points) {
      path.addOval(Rect.fromCircle(center: point, radius: stroke.size / 2));
    }
    return path;
  }

  @override
  bool shouldReclip(covariant _MosaicStrokeClipper oldClipper) => true;
}

sealed class _EditAction {
  const _EditAction();
}

class _StrokeAction extends _EditAction {
  const _StrokeAction(this.stroke);
  static _StrokeAction? _nullableStroke(_DrawStroke? stroke) =>
      stroke == null ? null : _StrokeAction(stroke);

  final _DrawStroke stroke;
}

class _MosaicAction extends _EditAction {
  const _MosaicAction(this.stroke);
  final _MosaicStroke stroke;
}

class _StickerAction extends _EditAction {
  const _StickerAction(this.sticker);
  final _PlacedSticker sticker;
}

class _TextAction extends _EditAction {
  const _TextAction(this.text);
  final _PlacedText text;
}

class _DrawStroke {
  _DrawStroke({required this.color, required this.width, required this.points});
  final Color color;
  final double width;
  final List<Offset> points;
}

class _MosaicStroke {
  _MosaicStroke({
    required this.size,
    required this.style,
    required this.points,
  });
  final double size;
  final _MosaicStyle style;
  final List<Offset> points;
}

class _PlacedText {
  const _PlacedText({
    required this.text,
    required this.offset,
    required this.color,
    required this.size,
  });
  final String text;
  final Offset offset;
  final Color color;
  final double size;
}

class _PlacedSticker {
  const _PlacedSticker({
    required this.text,
    required this.offset,
    required this.size,
  });
  final String text;
  final Offset offset;
  final double size;
}

const _palette = <Color>[
  Colors.redAccent,
  Colors.orangeAccent,
  Colors.yellowAccent,
  Colors.greenAccent,
  Colors.lightBlueAccent,
  Colors.purpleAccent,
  Colors.white,
  Colors.black,
];
