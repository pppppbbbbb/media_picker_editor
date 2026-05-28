# media_picker_editor

A reusable Flutter media picker with selected-media preview and lightweight image editing.

Current features:

- Pick images, videos, and GIFs from the local photo library.
- Multi-select with max selection limit.
- Preview selected media before returning.
- Horizontally swipe selected media in preview.
- Edit selected images before returning.
- Image editor tools: brush, draggable emoji stickers, text, mosaic styles, undo.
- Non-destructive editing: edited image is saved as a new temporary PNG file; the original asset is not overwritten.

## Install

For pub.dev usage after release:

```yaml
dependencies:
  media_picker_editor: ^0.1.0
```

For local development:

```yaml
dependencies:
  media_picker_editor:
    path: ../media_picker_editor
```

For GitHub usage after publishing the repository:

```yaml
dependencies:
  media_picker_editor:
    git:
      url: https://github.com/pppppbbbbb/media_picker_editor.git
      ref: main
```

## Platform Setup

This package uses [`photo_manager`](https://pub.dev/packages/photo_manager), so the host app must configure photo-library permissions.

### iOS

Add usage descriptions to `ios/Runner/Info.plist`:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>We need access to your photo library so you can select media.</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>We need permission to save edited media when required.</string>
```

### Android

Add media permissions to `android/app/src/main/AndroidManifest.xml` when your app targets Android media storage directly:

```xml
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />
```

`photo_manager` also contributes platform configuration through its plugin. Always test the permission flow on the Android versions you support, especially Android 13+.

## Publish Checklist

Before publishing to pub.dev:

```bash
flutter pub get
dart format .
flutter analyze
flutter test
dart pub publish --dry-run
```

Then publish:

```bash
dart pub publish
```

For GitHub-only usage, keep using the `git` dependency shown above. For pub.dev release, the package must pass `dart pub publish --dry-run` and you must be logged in with a pub.dev publisher account.

## Usage

```dart
import 'package:media_picker_editor/media_picker_editor.dart';

Future<void> pickMedia(BuildContext context) async {
  final result = await showFlutterMediaPicker(
    context,
    config: const FlutterMediaPickerConfig(
      title: '所有照片',
      multiSelect: true,
      maxSelection: 9,
      allowedTypes: {
        FlutterPickerMediaType.image,
        FlutterPickerMediaType.video,
        FlutterPickerMediaType.gif,
      },
    ),
  );

  if (result == null || result.isEmpty) return;

  for (final media in result) {
    debugPrint('file=${media.file.path}, type=${media.type}, name=${media.name}');
  }
}
```

### Edit A Single Image Directly

```dart
final edited = await showFlutterImageEditor(context, imageFile: imageFile);
if (edited != null) {
  // Upload/use edited file. Original file is unchanged.
}
```

## API Notes

`FlutterPickedMedia` contains:

- `asset`: original `AssetEntity` from `photo_manager`.
- `file`: selected file, or edited output file if edited in preview.
- `name`: display/file name.
- `type`: image/video/GIF.
- `mimeType`: source or edited MIME type.
- `durationMs`: video duration when applicable.
- `originalAssetId`: set when the file is an edited replacement of an original asset.

## Current Limitations

- Video is preview-only; video editing is intentionally not included yet.
- GIF is preview/select-only; GIF editing is intentionally not included yet.
- The built-in editor is lightweight and UI-opinionated. For production open-source release, consider adding theme/localization hooks.
- Edited images are stored in the temporary directory. The host app should upload/copy them if long-term retention is needed.

## Development

```bash
flutter pub get
flutter analyze
flutter test
```

## License

MIT
