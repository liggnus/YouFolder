import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/app_controller.dart';
import '../models/playlist.dart';
import '../models/video_item.dart';
import 'move_to_screen.dart';
import 'playlist_screen.dart';
import '../widgets/example_ad_banner.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final Set<String> _selectedPlaylistIds = <String>{};
  final Set<String> _selectedVideoItemIds = <String>{};
  String _query = '';
  final ScrollController _scrollController = ScrollController();

  bool get _isSelecting =>
      _selectedPlaylistIds.isNotEmpty || _selectedVideoItemIds.isNotEmpty;

  bool get _isSelectingVideos =>
      _selectedVideoItemIds.isNotEmpty && _selectedPlaylistIds.isEmpty;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _togglePlaylistSelection(String playlistId) {
    if (_selectedVideoItemIds.isNotEmpty) {
      setState(_selectedVideoItemIds.clear);
    }
    setState(() {
      if (_selectedPlaylistIds.contains(playlistId)) {
        _selectedPlaylistIds.remove(playlistId);
      } else {
        _selectedPlaylistIds.add(playlistId);
      }
    });
  }

  void _toggleVideoSelection(String playlistItemId) {
    if (_selectedPlaylistIds.isNotEmpty) {
      setState(_selectedPlaylistIds.clear);
    }
    setState(() {
      if (_selectedVideoItemIds.contains(playlistItemId)) {
        _selectedVideoItemIds.remove(playlistItemId);
      } else {
        _selectedVideoItemIds.add(playlistItemId);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedPlaylistIds.clear();
      _selectedVideoItemIds.clear();
    });
  }

  void _handleSelectionAction(String value) {
    if (value == 'delete') {
      _deleteSelected();
    } else if (value == 'share') {
      _shareSelectedBranches();
    } else if (value == 'pin') {
      _togglePinnedSelected();
    } else if (value == 'favorite') {
      _toggleFavoriteSelected();
    } else if (value == 'hide') {
      _toggleHiddenSelected();
    } else if (value == 'rename') {
      _renameSelected();
    } else if (value == 'move') {
      _moveSelected();
    }
  }

  List<PopupMenuEntry<String>> _selectionMenuItems() {
    if (_isSelectingVideos) {
      return const [
        PopupMenuItem(
          value: 'delete',
          child: Text('Delete'),
        ),
        PopupMenuItem(
          value: 'move',
          child: Text('Move to'),
        ),
      ];
    }
    final anyUnpinned = _selectedPlaylistIds.any((id) {
      final playlist = widget.controller.repository.playlistById(id);
      return playlist?.isPinned != true;
    });
    final anyNotFav = _selectedPlaylistIds.any((id) {
      final playlist = widget.controller.repository.playlistById(id);
      return playlist?.isFavorite != true;
    });
    final anyVisible = _selectedPlaylistIds.any((id) {
      final playlist = widget.controller.repository.playlistById(id);
      return playlist?.isHidden != true;
    });
    return [
      const PopupMenuItem(
        value: 'delete',
        child: Text('Delete'),
      ),
      const PopupMenuItem(
        value: 'move',
        child: Text('Move to'),
      ),
      if (_selectedPlaylistIds.length == 1)
        const PopupMenuItem(
          value: 'rename',
          child: Text('Rename'),
        ),
      const PopupMenuItem(
        value: 'share',
        child: Text('Share'),
      ),
      PopupMenuItem(
        value: 'hide',
        child: Text(anyVisible ? 'Hide' : 'Unhide'),
      ),
      PopupMenuItem(
        value: 'favorite',
        child: Text(anyNotFav ? 'Favorite' : 'Unfavorite'),
      ),
      PopupMenuItem(
        value: 'pin',
        child: Text(anyUnpinned ? 'Pin' : 'Unpin'),
      ),
    ];
  }

  Future<void> _shareSelectedBranches() async {
    if (_selectedPlaylistIds.isEmpty) {
      return;
    }
    final export = await widget.controller.buildTreeExportWithVideos(
      name: 'Shared branch',
      rootIds: _selectedPlaylistIds.toList(),
    );
    await _shareExport(export, 'youfolder-branch.json');
  }

  Future<void> _shareExport(
    Map<String, dynamic> export,
    String fileName,
  ) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(export));
    await Share.shareXFiles([XFile(file.path)]);
  }

  Future<void> _togglePinnedSelected() async {
    if (_selectedPlaylistIds.isEmpty) {
      return;
    }
    final anyUnpinned = _selectedPlaylistIds.any((id) {
      final playlist = widget.controller.repository.playlistById(id);
      return playlist?.isPinned != true;
    });
    await widget.controller.setPinned(_selectedPlaylistIds.toList(), anyUnpinned);
    if (mounted) {
      _clearSelection();
    }
  }

  Future<void> _toggleFavoriteSelected() async {
    if (_selectedPlaylistIds.isEmpty) {
      return;
    }
    final anyNotFav = _selectedPlaylistIds.any((id) {
      final playlist = widget.controller.repository.playlistById(id);
      return playlist?.isFavorite != true;
    });
    await widget.controller.setFavorite(_selectedPlaylistIds.toList(), anyNotFav);
    if (mounted) {
      _clearSelection();
    }
  }

  Future<void> _toggleHiddenSelected() async {
    if (_selectedPlaylistIds.isEmpty) {
      return;
    }
    final anyVisible = _selectedPlaylistIds.any((id) {
      final playlist = widget.controller.repository.playlistById(id);
      return playlist?.isHidden != true;
    });
    await widget.controller.setHidden(_selectedPlaylistIds.toList(), anyVisible);
    if (mounted) {
      _clearSelection();
    }
  }

  Future<void> _renameSelected() async {
    if (_selectedPlaylistIds.length != 1) {
      return;
    }
    final id = _selectedPlaylistIds.first;
    final playlist = widget.controller.repository.playlistById(id);
    if (playlist == null) {
      return;
    }
    final controller = TextEditingController(text: playlist.title);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Playlist name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) {
      return;
    }
    await widget.controller.renamePlaylist(id, name);
    if (mounted) {
      _clearSelection();
    }
  }

  Future<void> _deleteSelected() async {
    if (_isSelectingVideos) {
      final selectedIds = _selectedVideoItemIds.toSet();
      final allVideos = widget.controller.allCachedVideos();
      final byPlaylist = <String, List<String>>{};
      for (final video in allVideos) {
        if (!selectedIds.contains(video.playlistItemId)) {
          continue;
        }
        byPlaylist
            .putIfAbsent(video.playlistId, () => <String>[])
            .add(video.playlistItemId);
      }
      for (final entry in byPlaylist.entries) {
        await widget.controller.deletePlaylistItems(entry.key, entry.value);
      }
    } else {
      final ids = _selectedPlaylistIds.toList();
      await widget.controller.deletePlaylists(ids);
    }
    if (mounted) {
      _clearSelection();
    }
  }


  Future<void> _moveSelected() async {
    if (_isSelectingVideos) {
      final selectedIds = _selectedVideoItemIds.toSet();
      final items = widget.controller
          .allCachedVideos()
          .where((video) => selectedIds.contains(video.playlistItemId))
          .toList();
      final result = await Navigator.push<String?>(
        context,
        MaterialPageRoute(
          builder: (_) => MoveToScreen(
            controller: widget.controller,
            excludePlaylistIds: const [],
            initialParentId: null,
          ),
        ),
      );
      if (!mounted || result == null) {
        return;
      }
      final targetId = result == '__root__' ? null : result;
      if (targetId == null) {
        return;
      }
      final itemsByPlaylist = <String, List<VideoItem>>{};
      for (final item in items) {
        itemsByPlaylist
            .putIfAbsent(item.playlistId, () => <VideoItem>[])
            .add(item);
      }
      for (final entry in itemsByPlaylist.entries) {
        if (entry.key == targetId) {
          continue;
        }
        await widget.controller.movePlaylistItems(
          entry.key,
          targetId,
          entry.value,
        );
      }
    } else {
      final ids = _selectedPlaylistIds.toList();
      final result = await Navigator.push<String?>(
        context,
        MaterialPageRoute(
          builder: (_) => MoveToScreen(
            controller: widget.controller,
            excludePlaylistIds: ids,
            initialParentId: null,
          ),
        ),
      );
      if (!mounted || result == null) {
        return;
      }
      final targetId = result == '__root__' ? null : result;
      await widget.controller.movePlaylistsToFolder(ids, targetId);
    }
    if (mounted) {
      _clearSelection();
    }
  }

  Future<void> _openVideo(VideoItem video) async {
    if (video.videoId.isEmpty) {
      return;
    }
    final url = Uri.parse('https://www.youtube.com/watch?v=${video.videoId}');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final repository = widget.controller.repository;
        final playlists = repository.playlists;
        final videos = widget.controller.allCachedVideos();
        final favorites =
            playlists
                .where(
                  (playlist) =>
                      playlist.isFavorite && playlist.isHidden != true,
                )
                .toList();

        final filteredPlaylists = _query.trim().isEmpty
            ? <Playlist>[]
            : playlists
                .where(
                  (playlist) => playlist.title
                      .toLowerCase()
                      .contains(_query.trim().toLowerCase()),
                )
                .toList();
        final filteredVideos = _query.trim().isEmpty
            ? <VideoItem>[]
            : videos
                .where(
                  (video) => video.title
                      .toLowerCase()
                      .contains(_query.trim().toLowerCase()),
                )
                .toList();
        final hasPlaylists = filteredPlaylists.isNotEmpty;
        final hasVideos = filteredVideos.isNotEmpty;

        return Scaffold(
          appBar: AppBar(
            leading: _isSelecting
                ? IconButton(
                    tooltip: 'Cancel selection',
                    onPressed: _clearSelection,
                    icon: const Icon(Icons.close),
                  )
                : null,
            title: _isSelecting
                ? Text(
                    '${_selectedPlaylistIds.length + _selectedVideoItemIds.length} selected',
                  )
                : Image.asset(
                    'assets/tube-folder1.jpg',
                    width: 64,
                    height: 64,
                  ),
            actions: _isSelecting
                ? [
                    PopupMenuButton<String>(
                      tooltip: 'Actions',
                      onSelected: _handleSelectionAction,
                      itemBuilder: (context) => _selectionMenuItems(),
                      icon: const Icon(Icons.more_vert),
                    ),
                  ]
                : null,
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
                if (widget.controller.isSearchLoading) ...[
                  LinearProgressIndicator(
                    value: widget.controller.searchProgress,
                  ),
                  const SizedBox(height: 12),
                  const Text('Indexing videos...'),
                  const SizedBox(height: 12),
                ],
                if (widget.controller.isQuotaExceeded) ...[
                  _QuotaBanner(
                    onRetry: widget.controller.preloadAllVideos,
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search playlists and videos',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: 12),
                if (_query.trim().isEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (favorites.isNotEmpty) ...[
                        Text(
                          'Favorites',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        ...favorites.map(
                          (playlist) {
                            final selected =
                                _selectedPlaylistIds.contains(playlist.id);
                            return ListTile(
                              minLeadingWidth: 56,
                              contentPadding:
                                  const EdgeInsets.fromLTRB(16, 8, 16, 8),
                              titleAlignment: ListTileTitleAlignment.center,
                              leading: SizedBox(
                                width: 56,
                                height: 56,
                                child: Center(
                                  child: Icon(
                                    selected
                                        ? Icons.folder
                                        : Icons.folder_outlined,
                                    size: 40,
                                  ),
                                ),
                              ),
                              title: Text(playlist.title),
                              trailing: !_isSelecting && playlist.isHidden
                                  ? IconButton(
                                      tooltip: 'Unhide',
                                      onPressed: () {
                                        widget.controller
                                            .setHidden([playlist.id], false);
                                      },
                                      icon: const Icon(Icons.visibility_outlined),
                                    )
                                  : null,
                              onTap: () {
                                if (_isSelecting) {
                                  _togglePlaylistSelection(playlist.id);
                                  return;
                                }
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PlaylistScreen(
                                      controller: widget.controller,
                                      playlist: playlist,
                                    ),
                                    ),
                                  );
                                },
                              onLongPress: () =>
                                  _togglePlaylistSelection(playlist.id),
                              tileColor:
                                  selected ? Colors.grey.shade200 : null,
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      const Text('Type to search your playlists and videos.'),
                    ],
                  )
                else ...[
                  const SizedBox(height: 2),
                  if (hasPlaylists)
                    ...filteredPlaylists.map(
                      (playlist) {
                        final selected =
                            _selectedPlaylistIds.contains(playlist.id);
                        return ListTile(
                          minLeadingWidth: 56,
                          contentPadding:
                              const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          titleAlignment: ListTileTitleAlignment.center,
                          leading: SizedBox(
                            width: 56,
                            height: 56,
                            child: Center(
                              child: Icon(
                                selected ? Icons.folder : Icons.folder_outlined,
                                size: 40,
                              ),
                            ),
                          ),
                          title: Text(playlist.title),
                          trailing: !_isSelecting && playlist.isHidden
                              ? IconButton(
                                  tooltip: 'Unhide',
                                  onPressed: () {
                                    widget.controller
                                        .setHidden([playlist.id], false);
                                  },
                                  icon: const Icon(Icons.visibility_outlined),
                                )
                              : null,
                          onTap: () {
                            if (_isSelecting) {
                              _togglePlaylistSelection(playlist.id);
                              return;
                            }
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PlaylistScreen(
                                  controller: widget.controller,
                                  playlist: playlist,
                                ),
                                ),
                              );
                            },
                          onLongPress: () =>
                              _togglePlaylistSelection(playlist.id),
                          tileColor: selected ? Colors.grey.shade200 : null,
                        );
                      },
                    ),
                  if (hasPlaylists && hasVideos) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 18, thickness: 0.5),
                  ],
                  const SizedBox(height: 6),
                  if (hasVideos)
                    ...filteredVideos.map(
                      (video) {
                        final selected = _selectedVideoItemIds
                            .contains(video.playlistItemId);
                        return ListTile(
                          leading: _Thumbnail(url: video.thumbnailUrl),
                          title: Text(video.title),
                          tileColor: selected ? Colors.grey.shade200 : null,
                          onTap: () {
                            if (_isSelecting) {
                              _toggleVideoSelection(video.playlistItemId);
                            } else {
                              _openVideo(video);
                            }
                          },
                          onLongPress: () =>
                              _toggleVideoSelection(video.playlistItemId),
                        );
                      },
                    ),
                ],
              ],
            ),
          ),
          bottomNavigationBar: const SafeArea(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: ExampleAdBanner(),
            ),
          ),
        );
      },
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.play_circle_outline),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
      ),
    );
  }
}

class _QuotaBanner extends StatelessWidget {
  const _QuotaBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_outlined, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'YouTube API quota exceeded. Video lists may be empty until quota resets.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onErrorContainer),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
