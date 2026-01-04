import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/playlist.dart';
import 'move_to_screen.dart';
import 'playlist_screen.dart';
import 'search_screen.dart';
import '../widgets/example_ad_banner.dart';
import '../widgets/home_folder_icon.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final Set<String> _selectedPlaylistIds = <String>{};
  bool _reorderMode = false;
  final ScrollController _scrollController = ScrollController();

  bool get _isSelecting => _selectedPlaylistIds.isNotEmpty;

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

    final result = await widget.controller.createPlaylist(name);
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

  void _toggleSelection(String playlistId) {
    setState(() {
      if (_selectedPlaylistIds.contains(playlistId)) {
        _selectedPlaylistIds.remove(playlistId);
      } else {
        _selectedPlaylistIds.add(playlistId);
      }
    });
  }

  void _clearSelection() {
    setState(() => _selectedPlaylistIds.clear());
  }

  void _toggleReorderMode() {
    setState(() => _reorderMode = !_reorderMode);
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
      _renameSelected();
    } else if (value == 'move') {
      _moveSelected();
    }
  }

  List<PopupMenuEntry<String>> _selectionMenuItems() {
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
      if (_selectedPlaylistIds.length == 1)
        const PopupMenuItem(
          value: 'rename',
          child: Text('Rename'),
        ),
      const PopupMenuItem(
        value: 'move',
        child: Text('Move to'),
      ),
    ];
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
    final ids = _selectedPlaylistIds.toList();
    await widget.controller.deletePlaylists(ids);
    if (mounted) {
      _clearSelection();
    }
  }

  Future<void> _moveSelected() async {
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
    if (mounted) {
      _clearSelection();
    }
  }


  Future<void> _openPlaylist(Playlist playlist) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaylistScreen(
          controller: widget.controller,
          playlist: playlist,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final playlists = widget.controller.repository.rootPlaylists();
        final filteredPlaylists = playlists;

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
                ? Text('${_selectedPlaylistIds.length} selected')
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/app_icon.png',
                        width: 24,
                        height: 24,
                      ),
                      const SizedBox(width: 8),
                      const Text('YouFolder'),
                    ],
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
                          widget.controller.isBusy ? null : _createPlaylist,
                      icon: const Icon(Icons.add),
                    ),
                    IconButton(
                      tooltip: _reorderMode ? 'Done' : 'Reorder',
                      onPressed: _toggleReorderMode,
                      icon: Icon(
                        _reorderMode ? Icons.check : Icons.swap_vert,
                      ),
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
                        _RootBreadcrumb(
                          onTap: () {
                            widget.controller.syncPlaylists();
                          },
                        ),
                        const SizedBox(height: 6),
                        const Divider(height: 12, thickness: 0.5),
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
                if (filteredPlaylists.isNotEmpty)
                  SliverReorderableList(
                    itemCount: filteredPlaylists.length,
                    onReorder: (oldIndex, newIndex) async {
                      if (newIndex > oldIndex) {
                        newIndex -= 1;
                      }
                      final orderedIds =
                          playlists.map((playlist) => playlist.id).toList();
                      final moved = orderedIds.removeAt(oldIndex);
                      orderedIds.insert(newIndex, moved);
                      await widget.controller.reorderRootPlaylists(orderedIds);
                    },
                    itemBuilder: (context, index) {
                      final playlist = filteredPlaylists[index];
                      final selected =
                          _selectedPlaylistIds.contains(playlist.id);
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
                              _toggleSelection(playlist.id);
                            } else {
                              _openPlaylist(playlist);
                            }
                          },
                          onLongPress: _reorderMode
                              ? null
                              : () => _toggleSelection(playlist.id),
                        ),
                      );
                    },
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

class _RootBreadcrumb extends StatelessWidget {
  const _RootBreadcrumb({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Root',
      child: TextButton(
        onPressed: onTap,
        child: const HomeFolderIcon(),
      ),
    );
  }
}
