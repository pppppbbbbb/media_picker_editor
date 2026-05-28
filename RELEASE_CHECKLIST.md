# Release Checklist

Before publishing to GitHub:

1. Confirm repository exists:
   - https://github.com/pppppbbbbb/media_picker_editor
2. Run local checks:

```bash
flutter pub get
dart format .
flutter analyze
flutter test
```

3. Test on devices:
   - iOS simulator/device photo permission flow.
   - Android 13+ permission flow.
   - Image edit save/return flow.
   - Video/GIF preview-only behavior.

Before publishing to pub.dev:

1. Confirm package name `media_picker_editor` is available on pub.dev.
2. Confirm `publish_to: none` is not present in `pubspec.yaml`.
3. Run:

```bash
dart pub publish --dry-run
```

4. If dry-run passes, publish:

```bash
dart pub publish
```

5. After release, create a Git tag matching `pubspec.yaml` version:

```bash
git tag v0.1.0
git push origin v0.1.0
```

Optional future package improvements:

- Add localization hooks.
- Add theme/custom style hooks.
- Add host-configurable sticker list.
- Add callbacks for edited image persistence.
- Add screenshot/GIF assets for pub.dev.
- Add integration tests once the public API stabilizes.
