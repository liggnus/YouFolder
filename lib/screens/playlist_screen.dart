import 'package:flutter/material.dart';
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
      items.insertAll(
        1,
        [
          PopupMenuItem(
            value: 'pin',
            child: Text(anyUnpinned ? 'Pin' : 'Unpin'),
          ),
          PopupMenuItem(
            value: 'favorite',
            child: Text(anyNotFav ? 'Favorite' : 'Unfavorite'),
          ),
          PopupMenuItem(
            value: 'hide',
            child: Text(anyVisible ? 'Hide' : 'Unhide'),
          ),
          if (_selectedChildPlaylistIds.length == 1)
            const PopupMenuItem(
              value: 'rename',
              child: Text('Rename'),
            ),
        ],
      );
    }

    return items;
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
            leading: _isSelecting
                ? IconButton(
                    tooltip: 'Cancel selection',
                    onPressed: _clearSelection,
                    icon: const Icon(Icons.close),
                  )
                : null,
            title: Text(
              _isSelecting
                  ? '${_selectedVideoItemIds.length + _selectedChildPlaylistIds.length} selected'
                  : widget.playlist.title,
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
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Account',
                      onSelected: (value) {
                        if (value == 'switch') {
                          widget.controller.switchAccount();
                        } else if (value == 'signout') {
                          widget.controller.signOut();
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
                    ),
                    IconButton(
                      tooltip: 'New folder',
                      onPressed:
                          widget.controller.isBusy ? null : _createChildPlaylist,
                      icon: const Icon(Icons.add),
                    ),
                    IconButton(
                      tooltip: _reorderMode ? 'Done' : 'Reorder',
                      onPressed: _toggleReorderMode,
                      icon: Icon(
                        _reorderMode ? Icons.check : Icons.swap_vert,
                      ),
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
          body: Scrollbar(
            thumbVisibility: true,
            interactive: true,
            thickness: 6,
            controller: _scrollController,
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.controller.isBusy) ...[
                          const LinearProgressIndicator(),
                          const SizedBox(height: 16),
                        ],
                        const Divider(height: 12, thickness: 0.5),
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
                        const Divider(height: 14, thickness: 0.5),
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
                      final orderedIds =
                          childPlaylists.map((playlist) => playlist.id).toList();
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
                        child: ListTile(
                          leading: _reorderMode
                              ? ReorderableDragStartListener(
                                  index: index,
                                  child: const Icon(Icons.drag_handle),
                                )
                              : selected
                                  ? Icon(
                                      Icons.check_circle,
                                      color: Theme.of(context).colorScheme.primary,
                                    )
                                  : const Icon(Icons.folder_outlined),
                          title: Text(playlist.title),
                          trailing: _buildFlags(playlist),
                          tileColor: selected ? Colors.grey.shade200 : null,
                          onTap: () {
                            if (_reorderMode) {
                              return;
                            }
                            if (_isSelecting) {
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
                              : () => _toggleChildPlaylistSelection(playlist.id),
                        ),
                      );
                    },
                  ),
                if (hasChildPlaylists && hasVideos) ...[
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Divider(height: 18, thickness: 0.5),
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 6)),
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
                          leading: _Thumbnail(url: video.thumbnailUrl),
                          title: Text(video.title),
                          tileColor: selected ? Colors.grey.shade200 : null,
                          onTap: () {
                            if (_isSelecting) {
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
          child: const HomeFolderIcon(),
        ),
      ),
    ];
    for (final playlist in path) {
      items.add(const Text(' > '));
      items.add(
        TextButton(
          onPressed: () => onSegmentTap(playlist),
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
