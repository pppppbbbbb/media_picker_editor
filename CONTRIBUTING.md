# Contributing

Thanks for considering a contribution.

## Local Setup

```bash
flutter pub get
flutter analyze
flutter test
```

## Pull Request Checklist

- Keep the public API stable or document breaking changes.
- Add/update README examples for user-facing behavior changes.
- Run `dart format .` before committing.
- Verify iOS and Android permission behavior when touching picker internals.

## Design Goals

- Keep the package reusable and host-app agnostic.
- Avoid business-specific names or HeyChat-specific UI copy in public APIs.
- Keep editing non-destructive: never overwrite the original picked asset.
