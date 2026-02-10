import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
  bool _deleteMode = false;
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

  void _enterDeleteMode() {
    setState(() {
      _deleteMode = true;
      _reorderMode = false;
      _selectedPlaylistIds.clear();
    });
  }

  void _exitDeleteMode() {
    setState(() {
      _deleteMode = false;
      _selectedPlaylistIds.clear();
    });
  }

  Future<void> _confirmDelete() async {
    if (_selectedPlaylistIds.isEmpty) {
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

  Future<void> _shareEntireTree() async {
    final export = await widget.controller.buildTreeExportWithVideos(
      name: 'Shared tree',
    );
    await _shareExport(export, 'youfolder-tree.json');
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

  Future<void> _importSharedTree() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'youfolder'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    final file = result.files.first;
    final bytes = file.bytes;
    final content = bytes != null
        ? utf8.decode(bytes)
        : await File(file.path!).readAsString();
    final treeName =
        widget.controller.parseSharedTreeJson(content).name;
    await widget.controller.importSharedTreeJson(content);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Imported "$treeName".')),
    );
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
        final sharedRoots =
            playlists.where((playlist) => playlist.isShared).toList();
        final filteredPlaylists =
            playlists.where((playlist) => !playlist.isShared).toList();

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
            title: _deleteMode
                ? Text(
                    _selectedPlaylistIds.isEmpty
                        ? 'Select folders'
                        : '${_selectedPlaylistIds.length} selected',
                  )
                : _isSelecting
                    ? Text('${_selectedPlaylistIds.length} selected')
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              'assets/tube-folder1.png',
                              width: 70.4,
                              height: 70.4,
                            ),
                          ],
                        ),
                      ),
            actions: _deleteMode
                ? [
                    IconButton(
                      tooltip: 'Confirm delete',
                      onPressed:
                          _selectedPlaylistIds.isEmpty ? null : _confirmDelete,
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
                            } else if (value == 'share_tree') {
                              await _shareEntireTree();
                            } else if (value == 'import_tree') {
                              await _importSharedTree();
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'switch',
                              child: Text('Switch account'),
                            ),
                            PopupMenuItem(
                              value: 'share_tree',
                              child: Text('Share my tree'),
                            ),
                            PopupMenuItem(
                              value: 'import_tree',
                              child: Text('Import tree'),
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
                          onPressed:
                              widget.controller.isBusy ? null : _createPlaylist,
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
                      ],
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              await widget.controller.syncPlaylists();
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
                              onRetry: widget.controller.syncPlaylists,
                            ),
                            const SizedBox(height: 12),
                          ],
                          _RootBreadcrumb(
                            onTap: () {
                              widget.controller.syncPlaylists();
                            },
                          ),
                          if (sharedRoots.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Shared with me',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            ...sharedRoots.map(
                              (playlist) => ListTile(
                                contentPadding:
                                    const EdgeInsets.fromLTRB(0, 8, 0, 8),
                                minLeadingWidth: 56,
                                titleAlignment: ListTileTitleAlignment.center,
                                leading: SizedBox(
                                  width: 56,
                                  height: 56,
                                  child: Center(
                                    child: Icon(
                                      _selectedPlaylistIds.contains(playlist.id)
                                          ? Icons.folder
                                          : Icons.folder_outlined,
                                      size: 40,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                    ),
                                  ),
                                ),
                                title: Text(playlist.title),
                                subtitle: Text(
                                  playlist.sharedBy == null ||
                                          playlist.sharedBy!.isEmpty
                                      ? 'Shared tree'
                                      : 'Shared by ${playlist.sharedBy}',
                                ),
                                onTap: () {
                                  if (_reorderMode) {
                                    return;
                                  }
                                  if (_deleteMode || _isSelecting) {
                                    _toggleSelection(playlist.id);
                                  } else {
                                    _openPlaylist(playlist);
                                  }
                                },
                                onLongPress: _reorderMode
                                    ? null
                                    : () => _toggleSelection(playlist.id),
                                tileColor: _selectedPlaylistIds
                                        .contains(playlist.id)
                                    ? Colors.grey.shade200
                                    : null,
                              ),
                            ),
                          ],
                          const SizedBox(height: 2),
                          if (_reorderMode)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 6),
                              child: Text(
                                'Drag the handle to reorder playlists.',
                              ),
                            ),
                          const SizedBox(height: 0),
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
                        final normalIds = filteredPlaylists
                            .map((playlist) => playlist.id)
                            .toList();
                        final moved = normalIds.removeAt(oldIndex);
                        normalIds.insert(newIndex, moved);
                        final sharedIds = sharedRoots
                            .map((playlist) => playlist.id)
                            .toList();
                        await widget.controller
                            .reorderRootPlaylists([...sharedIds, ...normalIds]);
                      },
                      itemBuilder: (context, index) {
                        final playlist = filteredPlaylists[index];
                        final selected =
                            _selectedPlaylistIds.contains(playlist.id);
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
                                  _toggleSelection(playlist.id);
                                } else {
                                  _openPlaylist(playlist);
                                }
                              },
                              onLongPress: _reorderMode
                                  ? null
                                  : () => _toggleSelection(playlist.id),
                            ),
                          ),
                        );
                      },
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
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const HomeFolderIcon(),
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
              'YouTube API quota exceeded. Some data may not refresh until quota resets.',
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
