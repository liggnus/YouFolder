import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/app_controller.dart';
import '../models/playlist.dart';
import 'move_to_screen.dart';
import 'search_screen.dart';
import '../widgets/example_ad_banner.dart';
import '../widgets/home_folder_icon.dart';

class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({
    super.key,
    required this.controller,
    required this.playlist,
  });

  final AppController controller;
  final Playlist playlist;

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  final Set<String> _selectedVideoItemIds = <String>{};
  final Set<String> _selectedChildPlaylistIds = <String>{};
  bool _reorderMode = false;
  bool _deleteMode = false;
  final ScrollController _scrollController = ScrollController();

  bool get _isSelecting =>
      _selectedVideoItemIds.isNotEmpty || _selectedChildPlaylistIds.isNotEmpty;

  bool get _isSelectingVideos =>
      _selectedVideoItemIds.isNotEmpty && _selectedChildPlaylistIds.isEmpty;

  bool get _isSelectingPlaylists =>
      _selectedChildPlaylistIds.isNotEmpty && _selectedVideoItemIds.isEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.loadPlaylistVideos(widget.playlist.id);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleSelection(String playlistItemId) {
    if (_selectedChildPlaylistIds.isNotEmpty) {
      setState(_selectedChildPlaylistIds.clear);
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
      _selectedVideoItemIds.clear();
      _selectedChildPlaylistIds.clear();
    });
  }

  void _enterDeleteMode() {
    setState(() {
      _deleteMode = true;
      _reorderMode = false;
      _selectedVideoItemIds.clear();
      _selectedChildPlaylistIds.clear();
    });
  }

  void _exitDeleteMode() {
    setState(() {
      _deleteMode = false;
      _selectedVideoItemIds.clear();
      _selectedChildPlaylistIds.clear();
    });
  }

  Future<void> _confirmDelete() async {
    if (!_isSelecting) {
      return;
    }
    await _deleteSelected();
    if (mounted) {
      setState(() => _deleteMode = false);
    }
  }

  void _toggleReorderMode() {
    setState(() => _reorderMode = !_reorderMode);
  }

  Future<void> _createChildPlaylist() async {
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
      parentId: widget.playlist.id,
    );
    if (!mounted) {
      return;
    }
    if (result == PlaylistCreateResult.localOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Folder created locally. Connect YouTube to sync.'),
        ),
      );
    } else if (result == PlaylistCreateResult.syncedToYouTube) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Folder synced to YouTube.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Folder created, but YouTube sync failed.'),
        ),
      );
    }
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
      _renameSelectedPlaylist();
    } else if (value == 'move') {
      _moveSelected();
    }
  }

  List<PopupMenuEntry<String>> _selectionMenuItems() {
    final items = <PopupMenuEntry<String>>[
      const PopupMenuItem(
        value: 'delete',
        child: Text('Delete'),
      ),
      const PopupMenuItem(
        value: 'move',
        child: Text('Move to'),
      ),
    ];

    if (_isSelectingPlaylists) {
      final anyUnpinned = _selectedChildPlaylistIds.any((id) {
        final playlist = widget.controller.repository.playlistById(id);
        return playlist?.isPinned != true;
      });
      final anyNotFav = _selectedChildPlaylistIds.any((id) {
        final playlist = widget.controller.repository.playlistById(id);
        return playlist?.isFavorite != true;
      });
      final anyVisible = _selectedChildPlaylistIds.any((id) {
        final playlist = widget.controller.repository.playlistById(id);
        return playlist?.isHidden != true;
      });
      items
        ..addAll(
          _selectedChildPlaylistIds.length == 1
              ? const [
                  PopupMenuItem(
                    value: 'rename',
                    child: Text('Rename'),
                  ),
                ]
              : const [],
        )
        ..add(
          const PopupMenuItem(
            value: 'share',
            child: Text('Share'),
          ),
        )
        ..add(
          PopupMenuItem(
            value: 'hide',
            child: Text(anyVisible ? 'Hide' : 'Unhide'),
          ),
        )
        ..add(
          PopupMenuItem(
            value: 'favorite',
            child: Text(anyNotFav ? 'Favorite' : 'Unfavorite'),
          ),
        )
        ..add(
          PopupMenuItem(
            value: 'pin',
            child: Text(anyUnpinned ? 'Pin' : 'Unpin'),
          ),
        );
    }

    return items;
  }

  Future<void> _shareSelectedBranches() async {
    if (!_isSelectingPlaylists) {
      return;
    }
    final export = await widget.controller.buildTreeExportWithVideos(
      name: 'Shared branch',
      rootIds: _selectedChildPlaylistIds.toList(),
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

  Future<void> _deleteSelected() async {
    if (_isSelectingVideos) {
      final ids = _selectedVideoItemIds.toList();
      await widget.controller.deletePlaylistItems(widget.playlist.id, ids);
    } else if (_isSelectingPlaylists) {
      final ids = _selectedChildPlaylistIds.toList();
      await widget.controller.deletePlaylists(ids);
    }
    if (mounted) {
      _clearSelection();
    }
  }


  Future<void> _togglePinnedSelected() async {
    if (_selectedChildPlaylistIds.isEmpty) {
      return;
    }
    final anyUnpinned = _selectedChildPlaylistIds.any((id) {
      final playlist = widget.controller.repository.playlistById(id);
      return playlist?.isPinned != true;
    });
    await widget.controller.setPinned(_selectedChildPlaylistIds.toList(), anyUnpinned);
    if (mounted) {
      _clearSelection();
    }
  }

  Future<void> _toggleFavoriteSelected() async {
    if (_selectedChildPlaylistIds.isEmpty) {
      return;
    }
    final anyNotFav = _selectedChildPlaylistIds.any((id) {
      final playlist = widget.controller.repository.playlistById(id);
      return playlist?.isFavorite != true;
    });
    await widget.controller.setFavorite(_selectedChildPlaylistIds.toList(), anyNotFav);
    if (mounted) {
      _clearSelection();
    }
  }

  Future<void> _toggleHiddenSelected() async {
    if (_selectedChildPlaylistIds.isEmpty) {
      return;
    }
    final anyVisible = _selectedChildPlaylistIds.any((id) {
      final playlist = widget.controller.repository.playlistById(id);
      return playlist?.isHidden != true;
    });
    await widget.controller.setHidden(_selectedChildPlaylistIds.toList(), anyVisible);
    if (mounted) {
      _clearSelection();
    }
  }

  Future<void> _renameSelectedPlaylist() async {
    if (_selectedChildPlaylistIds.length != 1) {
      return;
    }
    final id = _selectedChildPlaylistIds.first;
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

  Future<void> _moveSelected() async {
    if (_isSelectingVideos) {
      final ids = _selectedVideoItemIds.toList();
      final items = widget.controller
          .videosForPlaylist(widget.playlist.id)
          .where((item) => ids.contains(item.playlistItemId))
          .toList();
      final result = await Navigator.push<String?>(
        context,
        MaterialPageRoute(
          builder: (_) => MoveToScreen(
            controller: widget.controller,
            excludePlaylistIds: const [],
            initialParentId: widget.playlist.id,
          ),
        ),
      );
      if (!mounted || result == null) {
        return;
      }
      final targetId = result == '__root__' ? null : result;
      if (items.isNotEmpty && targetId != null) {
        await widget.controller.movePlaylistItems(
          widget.playlist.id,
          targetId,
          items,
        );
      }
    } else if (_isSelectingPlaylists) {
      final ids = _selectedChildPlaylistIds.toList();
      final result = await Navigator.push<String?>(
        context,
        MaterialPageRoute(
          builder: (_) => MoveToScreen(
            controller: widget.controller,
            excludePlaylistIds: ids,
            initialParentId: widget.playlist.id,
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

  void _toggleChildPlaylistSelection(String playlistId) {
    if (_selectedVideoItemIds.isNotEmpty) {
      setState(_selectedVideoItemIds.clear);
    }
    setState(() {
      if (_selectedChildPlaylistIds.contains(playlistId)) {
        _selectedChildPlaylistIds.remove(playlistId);
      } else {
        _selectedChildPlaylistIds.add(playlistId);
      }
    });
  }


  Future<void> _openVideo(String videoId) async {
    if (videoId.isEmpty) {
      return;
    }
    final url = Uri.parse('https://www.youtube.com/watch?v=$videoId');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final childPlaylists =
            widget.controller.repository.childPlaylists(widget.playlist.id);
        final videos = widget.controller.videosForPlaylist(widget.playlist.id);
        final filteredPlaylists = childPlaylists;
        final filteredVideos = videos;
        final hasChildPlaylists = filteredPlaylists.isNotEmpty;
        final hasVideos = filteredVideos.isNotEmpty;
        final isLoading = widget.controller.isLoadingVideos(widget.playlist.id);
        final path = widget.controller.repository.pathToPlaylist(
          widget.playlist.id,
        );

        return Scaffold(
          appBar: AppBar(
            leading: _deleteMode
                ? IconButton(
                    tooltip: 'Cancel delete',
                    onPressed: _exitDeleteMode,
                    icon: const Icon(Icons.close),
                  )
                : _isSelecting
                    ? IconButton(
                        tooltip: 'Cancel selection',
                        onPressed: _clearSelection,
                        icon: const Icon(Icons.close),
                      )
                    : null,
            title: _deleteMode || _isSelecting
                ? Text(
                    _deleteMode
                        ? _isSelecting
                            ? '${_selectedVideoItemIds.length + _selectedChildPlaylistIds.length} selected'
                            : 'Select folders or videos'
                        : '${_selectedVideoItemIds.length + _selectedChildPlaylistIds.length} selected',
                  )
                : Image.asset(
                    'assets/tube-folder1.png',
                    width: 70.4,
                    height: 70.4,
                  ),
            actions: _deleteMode
                ? [
                    IconButton(
                      tooltip: 'Confirm delete',
                      onPressed: _isSelecting ? _confirmDelete : null,
                      icon: const Icon(Icons.check),
                    ),
                  ]
                : _isSelecting
                    ? [
                        PopupMenuButton<String>(
                          tooltip: 'Actions',
                          onSelected: _handleSelectionAction,
                          itemBuilder: (context) => _selectionMenuItems(),
                          icon: const Icon(Icons.more_vert),
                        ),
                      ]
                    : [
                        IconButton(
                          tooltip: 'Search',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    SearchScreen(controller: widget.controller),
                              ),
                            );
                          },
                          icon: const Icon(Icons.search),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Account',
                          onSelected: (value) async {
                            if (value == 'switch') {
                              widget.controller.switchAccount();
                            } else if (value == 'signout') {
                              final navigator = Navigator.of(context);
                              await widget.controller.signOut();
                              if (!mounted) {
                                return;
                              }
                              navigator.popUntil(
                                (route) => route.isFirst,
                              );
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'switch',
                              child: Text('Switch account'),
                            ),
                            PopupMenuItem(
                              value: 'signout',
                              child: Text('Sign out'),
                            ),
                          ],
                          icon: const Icon(Icons.account_circle_outlined),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                        ),
                        IconButton(
                          tooltip: 'New folder',
                          onPressed: widget.controller.isBusy
                              ? null
                              : _createChildPlaylist,
                          icon: const Icon(Icons.add),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          onPressed: _enterDeleteMode,
                          icon: const Icon(Icons.delete_outline),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          tooltip: _reorderMode ? 'Done' : 'Reorder',
                          onPressed: _toggleReorderMode,
                          icon: Icon(
                            _reorderMode ? Icons.check : Icons.swap_vert,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        if (widget.playlist.isHidden)
                          IconButton(
                            tooltip: 'Unhide folder',
                            onPressed: () {
                              widget.controller
                                  .setHidden([widget.playlist.id], false);
                            },
                            icon: const Icon(Icons.visibility_outlined),
                          ),
                      ],
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              await widget.controller
                  .loadPlaylistVideos(widget.playlist.id, force: true);
            },
            child: Scrollbar(
              thumbVisibility: true,
              interactive: true,
              thickness: 6,
              controller: _scrollController,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 1, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.controller.isBusy) ...[
                            const LinearProgressIndicator(),
                            const SizedBox(height: 16),
                          ],
                          if (widget.controller.isQuotaExceeded) ...[
                            _QuotaBanner(
                              onRetry: () {
                                widget.controller
                                    .loadPlaylistVideos(widget.playlist.id);
                              },
                            ),
                            const SizedBox(height: 12),
                          ],
                          _Breadcrumbs(
                            path: path,
                            onRootTap: () {
                              Navigator.popUntil(
                                context,
                                (route) => route.isFirst,
                              );
                            },
                            onSegmentTap: (playlist) {
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
                          ),
                          const SizedBox(height: 6),
                          const SizedBox(height: 8),
                          if (_reorderMode)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 6),
                              child: Text(
                                'Drag the handle to reorder playlists.',
                              ),
                            ),
                          const SizedBox(height: 2),
                        ],
                      ),
                    ),
                  ),
                  if (hasChildPlaylists)
                    SliverReorderableList(
                      itemCount: filteredPlaylists.length,
                      onReorder: (oldIndex, newIndex) async {
                        if (newIndex > oldIndex) {
                          newIndex -= 1;
                        }
                        final orderedIds = childPlaylists
                            .map((playlist) => playlist.id)
                            .toList();
                        final moved = orderedIds.removeAt(oldIndex);
                        orderedIds.insert(newIndex, moved);
                        await widget.controller.reorderChildPlaylists(
                          widget.playlist.id,
                          orderedIds,
                        );
                      },
                      itemBuilder: (context, index) {
                        final playlist = filteredPlaylists[index];
                        final selected =
                            _selectedChildPlaylistIds.contains(playlist.id);
                        return Material(
                          key: ValueKey(playlist.id),
                          color: Colors.transparent,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: ListTile(
                              minLeadingWidth: 56,
                              contentPadding:
                                  const EdgeInsets.fromLTRB(0, 8, 0, 8),
                              titleAlignment: ListTileTitleAlignment.center,
                              leading: _reorderMode
                                  ? ReorderableDragStartListener(
                                      index: index,
                                      child: const Icon(Icons.drag_handle),
                                    )
                                  : SizedBox(
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
                              trailing: _buildFlags(playlist),
                              tileColor: selected ? Colors.grey.shade200 : null,
                              onTap: () {
                                if (_reorderMode) {
                                  return;
                                }
                                if (_deleteMode || _isSelecting) {
                                  _toggleChildPlaylistSelection(playlist.id);
                                } else {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => PlaylistScreen(
                                        controller: widget.controller,
                                        playlist: playlist,
                                      ),
                                    ),
                                  );
                                }
                              },
                              onLongPress: _reorderMode
                                  ? null
                                  : () =>
                                      _toggleChildPlaylistSelection(playlist.id),
                            ),
                          ),
                        );
                      },
                    ),
                  if (hasChildPlaylists && hasVideos) ...[
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Divider(height: 1, thickness: 0.5),
                      ),
                    ),
                  ],
                  if (isLoading)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: LinearProgressIndicator(),
                      ),
                    )
                  else if (filteredVideos.isNotEmpty)
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final video = filteredVideos[index];
                          final selected = _selectedVideoItemIds
                              .contains(video.playlistItemId);
                          return ListTile(
                            contentPadding:
                                const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            titleAlignment: ListTileTitleAlignment.center,
                            leading: _Thumbnail(url: video.thumbnailUrl),
                            title: Text(video.title),
                            tileColor: selected ? Colors.grey.shade200 : null,
                            onTap: () {
                              if (_deleteMode || _isSelecting) {
                                _toggleSelection(video.playlistItemId);
                              } else {
                                _openVideo(video.videoId);
                              }
                            },
                            onLongPress: () =>
                                _toggleSelection(video.playlistItemId),
                          );
                        },
                        childCount: filteredVideos.length,
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),
                ],
              ),
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
              'YouTube API quota exceeded. Videos may be unavailable until quota resets.',
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

Widget _buildFlags(Playlist playlist) {
  final items = <Widget>[];
  if (playlist.isPinned) {
    items.add(const Icon(Icons.push_pin, size: 16));
  }
  if (playlist.isFavorite) {
    items.add(const SizedBox(width: 6));
    items.add(const Icon(Icons.star, size: 16));
  }
  if (items.isEmpty) {
    return const SizedBox.shrink();
  }
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: items,
  );
}
