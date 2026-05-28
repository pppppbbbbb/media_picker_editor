import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';

import 'flutter_media_editor_page.dart';
import 'flutter_media_picker_types.dart';

Future<List<FlutterPickedMedia>?> showFlutterMediaPicker(
  BuildContext context, {
  FlutterMediaPickerConfig config = const FlutterMediaPickerConfig(),
}) {
  return Navigator.of(context).push<List<FlutterPickedMedia>>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => FlutterMediaPickerPage(config: config),
    ),
  );
}

class FlutterMediaPickerPage extends StatefulWidget {
  const FlutterMediaPickerPage({required this.config, super.key});

  final FlutterMediaPickerConfig config;

  @override
  State<FlutterMediaPickerPage> createState() => _FlutterMediaPickerPageState();
}

class _FlutterMediaPickerPageState extends State<FlutterMediaPickerPage> {
  static const int _pageSize = 90;

  final _scrollController = ScrollController();
  final _items = <FlutterPickerAsset>[];
  final _selected = <String, FlutterPickerAsset>{};
  final _editedSelections = <String, FlutterPickedMedia>{};

  AssetPathEntity? _path;
  bool _loading = true;
  bool _loadingMore = false;
  bool _finishing = false;
  bool _hasMore = true;
  int _page = 0;
  _PickerTab _selectedTab = _PickerTab.all;

  FlutterMediaPickerConfig get config => widget.config;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredItems;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _PickerHeader(
              title: config.title,
              count: _selected.length,
              busy: _finishing,
              onClose: () => Navigator.of(context).pop(),
              onDone: _selected.isEmpty || _finishing ? null : _finish,
            ),
            _PickerTabs(
              tabs: _availableTabs,
              selected: _selectedTab,
              onSelected: (tab) => setState(() => _selectedTab = tab),
            ),
            const Divider(height: 1, color: Color(0xFFE0E0E0)),
            Expanded(child: _buildBody(filtered)),
            _PickerBottomBar(
              count: _selected.length,
              busy: _finishing,
              onPreview: _selected.isEmpty || _finishing ? null : _openPreview,
              onDone: _selected.isEmpty || _finishing ? null : _finish,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<FlutterPickerAsset> filtered) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (filtered.isEmpty) {
      return const Center(
        child: Text(
          '暂无媒体',
          style: TextStyle(color: Color(0xFF666666), fontSize: 14),
        ),
      );
    }
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        mainAxisExtent: 140,
      ),
      itemCount: filtered.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= filtered.length) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final item = filtered[index];
        final selectedIndex = _selected.keys.toList().indexOf(item.id);
        return _MediaGridTile(
          item: item,
          selectedIndex: selectedIndex,
          onTap: () => _toggleSelection(item),
        );
      },
    );
  }

  Future<void> _init() async {
    final permission = await PhotoManager.requestPermissionExtend(
      requestOption: PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: _requestType,
          mediaLocation: false,
        ),
      ),
    );
    if (!permission.hasAccess) {
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('需要相册权限')));
      return;
    }

    final paths = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: _requestType,
      filterOption: FilterOptionGroup(
        containsPathModified: true,
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      ),
    );
    _path = paths.isEmpty ? null : paths.first;
    await _loadNextPage();
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadNextPage() async {
    final path = _path;
    if (path == null || !_hasMore || _loadingMore) {
      return;
    }
    if (mounted) {
      setState(() => _loadingMore = true);
    }
    try {
      final entities = await path.getAssetListPaged(
        page: _page,
        size: _pageSize,
      );
      final parsed = <FlutterPickerAsset>[];
      for (final entity in entities) {
        final item = await FlutterPickerAsset.fromEntity(entity);
        if (config.allowedTypes.contains(item.type)) {
          parsed.add(item);
        }
      }
      parsed.sort((a, b) => b.dateSecond.compareTo(a.dateSecond));
      if (!mounted) {
        return;
      }
      setState(() {
        _items.addAll(parsed);
        _page++;
        _hasMore = entities.length == _pageSize;
      });
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loading || _loadingMore) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 480) {
      _loadNextPage();
    }
  }

  void _toggleSelection(FlutterPickerAsset item) {
    setState(() {
      if (_selected.containsKey(item.id)) {
        _selected.remove(item.id);
        _editedSelections.remove(item.id);
        return;
      }
      if (!config.multiSelect) {
        _selected.clear();
        _editedSelections.clear();
      }
      if (_selected.length >= config.maxSelection) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('最多选择 ${config.maxSelection} 个')),
        );
        return;
      }
      _selected[item.id] = item;
    });
  }

  Future<void> _finish() async {
    setState(() => _finishing = true);
    try {
      final result = <FlutterPickedMedia>[];
      for (final item in _selected.values) {
        final edited = _editedSelections[item.id];
        if (edited != null) {
          result.add(edited);
          continue;
        }
        final file = await _fileFor(item);
        if (file == null) {
          continue;
        }
        result.add(
          FlutterPickedMedia(
            asset: item.entity,
            file: file,
            name: item.name,
            type: item.type,
            mimeType: item.mimeType,
            durationMs: item.durationMs,
          ),
        );
      }
      if (!mounted) {
        return;
      }
      if (result.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('读取媒体失败')));
        setState(() => _finishing = false);
        return;
      }
      Navigator.of(context).pop(result);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('读取媒体失败')));
      setState(() => _finishing = false);
    }
  }

  Future<void> _openPreview() async {
    final selected = _selected.values.toList();
    final updated = await Navigator.of(context)
        .push<Map<String, FlutterPickedMedia>>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => _MediaPreviewPage(
              selected: selected,
              editedSelections: Map<String, FlutterPickedMedia>.of(
                _editedSelections,
              ),
            ),
          ),
        );
    if (updated != null && mounted) {
      setState(() {
        _editedSelections
          ..clear()
          ..addAll(updated);
      });
    }
  }

  Future<File?> _fileFor(FlutterPickerAsset item) async {
    if (item.type == FlutterPickerMediaType.gif) {
      return await item.entity.originFile ?? await item.entity.file;
    }
    return item.entity.file;
  }

  List<_PickerTab> get _availableTabs {
    final tabs = <_PickerTab>[_PickerTab.all];
    if (config.allowedTypes.contains(FlutterPickerMediaType.video)) {
      tabs.add(_PickerTab.video);
    }
    if (config.allowedTypes.contains(FlutterPickerMediaType.image)) {
      tabs.add(_PickerTab.image);
    }
    if (config.allowedTypes.contains(FlutterPickerMediaType.gif)) {
      tabs.add(_PickerTab.gif);
    }
    return tabs;
  }

  List<FlutterPickerAsset> get _filteredItems {
    return switch (_selectedTab) {
      _PickerTab.all => _items,
      _PickerTab.video =>
        _items
            .where((item) => item.type == FlutterPickerMediaType.video)
            .toList(),
      _PickerTab.image =>
        _items
            .where((item) => item.type == FlutterPickerMediaType.image)
            .toList(),
      _PickerTab.gif =>
        _items
            .where((item) => item.type == FlutterPickerMediaType.gif)
            .toList(),
    };
  }

  RequestType get _requestType {
    final types = <RequestType>[];
    if (config.allowedTypes.contains(FlutterPickerMediaType.image) ||
        config.allowedTypes.contains(FlutterPickerMediaType.gif)) {
      types.add(RequestType.image);
    }
    if (config.allowedTypes.contains(FlutterPickerMediaType.video)) {
      types.add(RequestType.video);
    }
    return RequestType.fromTypes(types);
  }
}

enum _PickerTab { all, video, image, gif }

class _PickerHeader extends StatelessWidget {
  const _PickerHeader({
    required this.title,
    required this.count,
    required this.busy,
    required this.onClose,
    required this.onDone,
  });

  final String title;
  final int count;
  final bool busy;
  final VoidCallback onClose;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          IconButton(
            onPressed: busy ? null : onClose,
            icon: const Icon(Icons.close_rounded, size: 34),
            color: const Color(0xFF666666),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF111111),
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 76),
        ],
      ),
    );
  }
}

class _PickerBottomBar extends StatelessWidget {
  const _PickerBottomBar({
    required this.count,
    required this.busy,
    required this.onPreview,
    required this.onDone,
  });

  final int count;
  final bool busy;
  final VoidCallback? onPreview;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF202020),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      child: Row(
        children: [
          TextButton(
            onPressed: onPreview,
            child: const Text(
              '预览',
              style: TextStyle(color: Colors.white, fontSize: 22),
            ),
          ),
          const Spacer(),
          FilledButton(
            onPressed: onDone,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF12C76A),
              disabledBackgroundColor: const Color(0xFF4A4A4A),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('发送 ($count)', style: const TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
  }
}

class _PickerTabs extends StatelessWidget {
  const _PickerTabs({
    required this.tabs,
    required this.selected,
    required this.onSelected,
  });

  final List<_PickerTab> tabs;
  final _PickerTab selected;
  final ValueChanged<_PickerTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      color: const Color(0xFFFFF7FF),
      child: Row(
        children: [
          for (final tab in tabs)
            Expanded(
              child: InkWell(
                onTap: () => onSelected(tab),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      _tabLabel(tab),
                      style: TextStyle(
                        color: selected == tab
                            ? const Color(0xFF111111)
                            : const Color(0xFF999999),
                        fontSize: 18,
                        fontWeight: selected == tab
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: selected == tab ? 34 : 0,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _tabLabel(_PickerTab tab) {
    return switch (tab) {
      _PickerTab.all => '全部',
      _PickerTab.video => '视频',
      _PickerTab.image => '图片',
      _PickerTab.gif => '动图',
    };
  }
}

class _MediaGridTile extends StatelessWidget {
  const _MediaGridTile({
    required this.item,
    required this.selectedIndex,
    required this.onTap,
  });

  final FlutterPickerAsset item;
  final int selectedIndex;
  final VoidCallback onTap;

  bool get _selected => selectedIndex >= 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: const Color(0xFFEDEDED),
            child: _AssetThumbnail(asset: item.entity),
          ),
          if (_selected) const ColoredBox(color: Color(0x33000000)),
          PositionedDirectional(
            top: 6,
            end: 6,
            child: _SelectionMark(selectedIndex: selectedIndex),
          ),
          if (item.type != FlutterPickerMediaType.image)
            PositionedDirectional(
              end: 6,
              bottom: 6,
              child: _MediaLabel(item: item),
            ),
        ],
      ),
    );
  }
}

class _SelectionMark extends StatelessWidget {
  const _SelectionMark({required this.selectedIndex});

  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xB3FFFFFF),
        border: Border.all(color: Colors.white, width: 1),
      ),
      child: selectedIndex >= 0
          ? const Icon(Icons.check_rounded, size: 19, color: Color(0xFF111111))
          : null,
    );
  }
}

class _MediaLabel extends StatelessWidget {
  const _MediaLabel({required this.item});

  final FlutterPickerAsset item;

  @override
  Widget build(BuildContext context) {
    final label = item.type == FlutterPickerMediaType.gif
        ? 'GIF'
        : _formatDuration(item.durationMs ?? 0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      color: const Color(0x66000000),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
  }

  String _formatDuration(int durationMs) {
    final totalSeconds = durationMs ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class _AssetThumbnail extends StatefulWidget {
  const _AssetThumbnail({required this.asset});

  final AssetEntity asset;

  @override
  State<_AssetThumbnail> createState() => _AssetThumbnailState();
}

class _AssetThumbnailState extends State<_AssetThumbnail> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _AssetThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset.id != widget.asset.id) {
      _future = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return const SizedBox.expand();
        }
        return Image.memory(
          data,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          width: double.infinity,
          height: double.infinity,
        );
      },
    );
  }

  Future<Uint8List?> _load() {
    return widget.asset.thumbnailDataWithSize(
      const ThumbnailSize(320, 320),
      format: ThumbnailFormat.jpeg,
    );
  }
}

class _MediaPreviewPage extends StatefulWidget {
  const _MediaPreviewPage({
    required this.selected,
    required this.editedSelections,
  });

  final List<FlutterPickerAsset> selected;
  final Map<String, FlutterPickedMedia> editedSelections;

  @override
  State<_MediaPreviewPage> createState() => _MediaPreviewPageState();
}

class _MediaPreviewPageState extends State<_MediaPreviewPage> {
  late final PageController _pageController;
  late final Map<String, FlutterPickedMedia> _editedSelections;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _editedSelections = Map<String, FlutterPickedMedia>.of(
      widget.editedSelections,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.selected[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 58,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_editedSelections),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${_index + 1}/${widget.selected.length}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ),
                  IconButton.filled(
                    onPressed: () =>
                        Navigator.of(context).pop(_editedSelections),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF12C76A),
                    ),
                    icon: const Icon(Icons.check_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.selected.length,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (context, index) {
                  final item = widget.selected[index];
                  return _PreviewMedia(
                    asset: item,
                    edited: _editedSelections[item.id],
                  );
                },
              ),
            ),
            Container(
              color: const Color(0xFF4A4A4A),
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Row(
                children: [
                  TextButton(
                    onPressed: current.type == FlutterPickerMediaType.image
                        ? () => _editCurrent(current)
                        : null,
                    child: Text(
                      '编辑',
                      style: TextStyle(
                        color: current.type == FlutterPickerMediaType.image
                            ? Colors.white
                            : Colors.white38,
                        fontSize: 22,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    '○ 原图',
                    style: TextStyle(color: Colors.white, fontSize: 22),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_editedSelections),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF12C76A),
                    ),
                    child: Text(
                      '发送 (${widget.selected.length})',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editCurrent(FlutterPickerAsset asset) async {
    final source = _editedSelections[asset.id]?.file ?? await asset.entity.file;
    if (source == null || !source.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('读取图片失败')));
      }
      return;
    }
    if (!mounted) return;
    final edited = await showFlutterImageEditor(context, imageFile: source);
    if (edited == null || !mounted) return;
    setState(() {
      _editedSelections[asset.id] = FlutterPickedMedia(
        asset: asset.entity,
        file: edited,
        name: p.basename(edited.path),
        type: FlutterPickerMediaType.image,
        mimeType: 'image/png',
        durationMs: null,
        originalAssetId: asset.id,
      );
    });
  }
}

class _PreviewMedia extends StatelessWidget {
  const _PreviewMedia({required this.asset, required this.edited});

  final FlutterPickerAsset asset;
  final FlutterPickedMedia? edited;

  @override
  Widget build(BuildContext context) {
    final editedFile = edited?.file;
    if (editedFile != null && editedFile.existsSync()) {
      return Center(child: Image.file(editedFile, fit: BoxFit.contain));
    }
    if (asset.type == FlutterPickerMediaType.video) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _AssetThumbnail(asset: asset.entity),
          const Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0x99000000),
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 46,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return _AssetFullImage(asset: asset.entity);
  }
}

class _AssetFullImage extends StatefulWidget {
  const _AssetFullImage({required this.asset});

  final AssetEntity asset;

  @override
  State<_AssetFullImage> createState() => _AssetFullImageState();
}

class _AssetFullImageState extends State<_AssetFullImage> {
  late Future<File?> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.asset.file;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: _future,
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return Center(child: Image.file(file, fit: BoxFit.contain));
      },
    );
  }
}
