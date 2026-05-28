import 'dart:io';

import 'package:photo_manager/photo_manager.dart';

enum FlutterPickerMediaType { image, video, gif }

class FlutterMediaPickerConfig {
  const FlutterMediaPickerConfig({
    this.title = '所有照片',
    this.multiSelect = true,
    this.maxSelection = 9,
    this.allowedTypes = const {
      FlutterPickerMediaType.image,
      FlutterPickerMediaType.video,
      FlutterPickerMediaType.gif,
    },
  }) : assert(maxSelection > 0);

  final String title;
  final bool multiSelect;
  final int maxSelection;
  final Set<FlutterPickerMediaType> allowedTypes;
}

class FlutterPickedMedia {
  const FlutterPickedMedia({
    required this.asset,
    required this.file,
    required this.name,
    required this.type,
    required this.mimeType,
    required this.durationMs,
    this.originalAssetId,
  });

  final AssetEntity asset;
  final File file;
  final String name;
  final FlutterPickerMediaType type;
  final String? mimeType;
  final int? durationMs;
  final String? originalAssetId;
}

class FlutterPickerAsset {
  const FlutterPickerAsset({
    required this.entity,
    required this.name,
    required this.type,
    required this.mimeType,
    required this.durationMs,
    required this.dateSecond,
  });

  final AssetEntity entity;
  final String name;
  final FlutterPickerMediaType type;
  final String? mimeType;
  final int? durationMs;
  final int dateSecond;

  String get id => entity.id;

  static Future<FlutterPickerAsset> fromEntity(AssetEntity entity) async {
    final mimeType = entity.mimeType ?? await entity.mimeTypeAsync;
    final title = entity.title?.isNotEmpty == true
        ? entity.title!
        : await entity.titleAsync;
    final type = _typeOf(entity, mimeType);
    return FlutterPickerAsset(
      entity: entity,
      name: title.isEmpty ? _fallbackName(entity, type) : title,
      type: type,
      mimeType: mimeType,
      durationMs: type == FlutterPickerMediaType.video
          ? entity.videoDuration.inMilliseconds
          : null,
      dateSecond: entity.createDateSecond ?? entity.modifiedDateSecond ?? 0,
    );
  }

  static FlutterPickerMediaType _typeOf(AssetEntity entity, String? mimeType) {
    if (entity.type == AssetType.video) {
      return FlutterPickerMediaType.video;
    }
    if (mimeType?.toLowerCase() == 'image/gif') {
      return FlutterPickerMediaType.gif;
    }
    return FlutterPickerMediaType.image;
  }

  static String _fallbackName(AssetEntity entity, FlutterPickerMediaType type) {
    final extension = switch (type) {
      FlutterPickerMediaType.image => 'jpg',
      FlutterPickerMediaType.video => 'mp4',
      FlutterPickerMediaType.gif => 'gif',
    };
    return '${entity.id}.$extension';
  }
}
