import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/playlist.dart';
import '../widgets/example_ad_banner.dart';
import '../widgets/home_folder_icon.dart';

class MoveToScreen extends StatefulWidget {
  const MoveToScreen({
    super.key,
    required this.controller,
    required this.excludePlaylistIds,
    this.initialParentId,
  });

  final AppController controller;
  final List<String> excludePlaylistIds;
  final String? initialParentId;

  @override
  State<MoveToScreen> createState() => _MoveToScreenState();
}

class _MoveToScreenState extends State<MoveToScreen> {
  static const String _rootMarker = '__root__';
  final List<String> _path = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.initialParentId != null) {
      final path = widget.controller.repository
          .pathToPlaylist(widget.initialParentId!);
      _path
        ..clear()
        ..addAll(path.map((playlist) => playlist.id));
    }
    if (widget.controller.isSignedIn) {
      Future.microtask(widget.controller.syncPlaylists);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _createPlaylist() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Folder name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) {
      return;
    }

    final result = await widget.controller.createPlaylist(
      name,
      parentId: _currentParentId,
    );
    if (!mounted) {
      return;
    }

    if (result == PlaylistCreateResult.syncFailed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Folder created, but YouTube sync failed.'),
        ),
      );
    }
  }

  Future<void> _moveHere() async {
    if (mounted) {
      Navigator.pop(
        context,
        _currentParentId ?? _rootMarker,
      );
    }
  }

  String? get _currentParentId => _path.isEmpty ? null : _path.last;

  void _enterFolder(String playlistId) {
    setState(() => _path.add(playlistId));
  }

  void _goUp() {
    if (_path.isNotEmpty) {
      setState(() => _path.removeLast());
    }
  }

  void _goRoot() {
    if (_path.isNotEmpty) {
      setState(_path.clear);
    }
  }

  void _jumpTo(String playlistId) {
    final index = _path.indexOf(playlistId);
    if (index == -1) {
      return;
    }
    setState(() {
      _path.removeRange(index + 1, _path.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final repository = widget.controller.repository;
        final playlists = (_currentParentId == null
                ? repository.rootPlaylists()
                : repository.childPlaylists(_currentParentId!))
            .toList();

        return Scaffold(
          appBar: AppBar(
            title: Image.asset(
              'assets/tube-folder1.jpg',
              width: 64,
              height: 64,
            ),
          ),
          body: Scrollbar(
            thumbVisibility: true,
            interactive: true,
            thickness: 6,
            controller: _scrollController,
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 11, 16, 16),
              children: [
              if (widget.controller.isBusy) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 16),
              ],
              _Breadcrumbs(
                path: _path
                    .map((id) => repository.playlistById(id))
                    .whereType<Playlist>()
                    .toList(),
                onRootTap: _goRoot,
                onSegmentTap: (playlist) => _jumpTo(playlist.id),
              ),
              const SizedBox(height: 6),
              const SizedBox(height: 12),
              if (_path.isNotEmpty)
                _FolderTile(
                  title: 'Up',
                  subtitle: 'Parent folder',
                  icon: Icons.arrow_upward,
                  onTap: _goUp,
                ),
              if (_path.isNotEmpty) const SizedBox(height: 8),
              ...playlists.map(
                (playlist) {
                  final isExcluded =
                      widget.excludePlaylistIds.contains(playlist.id);
                  return _FolderTile(
                    title: playlist.title,
                    subtitle:
                        '${repository.childPlaylists(playlist.id).length} playlists',
                    icon: Icons.folder_outlined,
                    iconSize: 40,
                    disabled: isExcluded,
                    onTap: () => _enterFolder(playlist.id),
                  );
                },
              ),
                if (playlists.isEmpty)
                  const Text('No playlists here.'),
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ExampleAdBanner(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed:
                              widget.controller.isBusy ? null : _createPlaylist,
                          child: const Text('New folder'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: widget.controller.isBusy ? null : _moveHere,
                          child: const Text('Move here'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.iconSize = 24,
    this.disabled = false,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final double iconSize;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        minLeadingWidth: 56,
        contentPadding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
        titleAlignment: ListTileTitleAlignment.center,
        leading: SizedBox(
          width: 56,
          height: 56,
          child: Center(
            child: Icon(icon, size: iconSize),
          ),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        enabled: !disabled,
        onTap: disabled ? null : onTap,
      ),
    );
  }
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({
    required this.path,
    required this.onRootTap,
    required this.onSegmentTap,
  });

  final List<Playlist> path;
  final VoidCallback onRootTap;
  final ValueChanged<Playlist> onSegmentTap;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      Tooltip(
        message: 'Root',
        child: TextButton(
          onPressed: onRootTap,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const HomeFolderIcon(),
        ),
      ),
    ];
    for (final playlist in path) {
      items.add(const Text(' > '));
      items.add(
        TextButton(
          onPressed: () => onSegmentTap(playlist),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(playlist.title),
        ),
      );
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: items,
    );
  }
}
