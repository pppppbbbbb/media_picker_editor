import 'package:flutter/material.dart';
import 'package:media_picker_editor/media_picker_editor.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: PickerExamplePage(),
    );
  }
}

class PickerExamplePage extends StatefulWidget {
  const PickerExamplePage({super.key});

  @override
  State<PickerExamplePage> createState() => _PickerExamplePageState();
}

class _PickerExamplePageState extends State<PickerExamplePage> {
  List<FlutterPickedMedia> _items = const [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('media_picker_editor example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.photo_library_rounded),
            label: const Text('Pick media'),
          ),
          const SizedBox(height: 16),
          for (final item in _items)
            ListTile(
              leading: Icon(_iconFor(item.type)),
              title: Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                item.file.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pick() async {
    final result = await showFlutterMediaPicker(
      context,
      config: const FlutterMediaPickerConfig(maxSelection: 9),
    );
    if (result == null || !mounted) return;
    setState(() => _items = result);
  }

  IconData _iconFor(FlutterPickerMediaType type) {
    return switch (type) {
      FlutterPickerMediaType.image => Icons.image_outlined,
      FlutterPickerMediaType.video => Icons.videocam_outlined,
      FlutterPickerMediaType.gif => Icons.gif_box_outlined,
    };
  }
}
