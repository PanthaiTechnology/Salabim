import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/track.dart';
import '../../../data/services/api_client.dart';
import '../../../data/services/history_service.dart';
import 'widgets/artwork_thumbnail.dart';
import 'widgets/feedback_dialog.dart';

/// Histórico de músicas já identificadas — salvo localmente no aparelho
/// (ver HistoryService), então funciona desde a primeira busca, sem exigir
/// login/conta. Cada item tem capa, badge do modo usado, e um menu de
/// opções (compartilhar, selecionar, corrigir, excluir). Suporta exclusão
/// em lote via modo de seleção múltipla.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _historyService = HistoryService();
  final _apiClient = ApiClient();

  List<HistoryEntry> _entries = [];
  bool _loading = true;
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  static const _modeLabels = {
    'audd': 'Ouvida',
    'acrcloud': 'Cantada',
    'itunes': 'Buscada por texto',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await _historyService.getHistory();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  void _enterSelectionMode(String initialId) {
    setState(() {
      _selectionMode = true;
      _selectedIds
        ..clear()
        ..add(initialId);
    });
  }

  void _toggleSelected(String trackId) {
    setState(() {
      if (!_selectedIds.add(trackId)) _selectedIds.remove(trackId);
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  void _cancelSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _deleteSelected() async {
    await _historyService.removeEntries(_selectedIds);
    _cancelSelection();
    await _load();
  }

  Future<void> _deleteOne(String trackId) async {
    await _historyService.removeEntries({trackId});
    await _load();
  }

  Future<void> _clearAll() async {
    await _historyService.clear();
    await _load();
  }

  Future<void> _share(HistoryEntry entry) async {
    final track = entry.track;
    final link = track.platformLinks.isNotEmpty ? track.platformLinks.first.url : null;
    final text = [
      '${entry.displayTitle} — ${entry.displayArtist}',
      if (link != null) link,
      '',
      'Descoberto com o Salabim 🎵',
    ].join('\n');
    await Share.share(text);
  }

  Future<void> _openFeedback(HistoryEntry entry) async {
    final result = await FeedbackDialog.show(
      context,
      title: entry.displayTitle,
      artist: entry.displayArtist,
    );
    if (result == null) return;

    await _historyService.updateFeedback(
      entry.track.id,
      wasCorrect: result.wasCorrect,
      correctedTitle: result.correctedTitle,
      correctedArtist: result.correctedArtist,
    );
    await _apiClient.submitFeedback(
      matchedTitle: entry.track.title,
      matchedArtist: entry.track.artist,
      mode: entry.mode,
      wasCorrect: result.wasCorrect,
      correctedTitle: result.correctedTitle,
      correctedArtist: result.correctedArtist,
    );
    await _load();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.wasCorrect
              ? 'Valeu por confirmar!'
              : 'Anotado — o Salabim vai lembrar dessa correção da próxima vez.',
        ),
      ),
    );
  }

  void _handleMenuAction(String action, HistoryEntry entry) {
    switch (action) {
      case 'share':
        _share(entry);
      case 'select':
        _enterSelectionMode(entry.track.id);
      case 'feedback':
        _openFeedback(entry);
      case 'delete':
        _deleteOne(entry.track.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Suas músicas identificadas vão aparecer aqui.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _selectionMode ? '${_selectedIds.length} selecionado(s)' : 'Histórico',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              if (_selectionMode)
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Excluir selecionados',
                      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                      onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
                    ),
                    IconButton(
                      tooltip: 'Cancelar seleção',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: _cancelSelection,
                    ),
                  ],
                )
              else
                TextButton(onPressed: _clearAll, child: const Text('Limpar tudo')),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _entries.length,
            itemBuilder: (context, index) => _HistoryTile(
              entry: _entries[index],
              modeLabel: _modeLabels[_entries[index].mode] ?? _entries[index].mode,
              selectionMode: _selectionMode,
              selected: _selectedIds.contains(_entries[index].track.id),
              onTap: () {
                if (_selectionMode) {
                  _toggleSelected(_entries[index].track.id);
                } else {
                  context.push('/result', extra: _entries[index].track);
                }
              },
              onLongPress: _selectionMode ? null : () => _enterSelectionMode(_entries[index].track.id),
              onMenuAction: (action) => _handleMenuAction(action, _entries[index]),
            ),
          ),
        ),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.entry,
    required this.modeLabel,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onMenuAction,
  });

  final HistoryEntry entry;
  final String modeLabel;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<String> onMenuAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary.withValues(alpha: 0.14) : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: selected ? Border.all(color: AppColors.primary, width: 1.5) : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onTap: onTap,
        onLongPress: onLongPress,
        leading: selectionMode
            ? SizedBox(
                width: 52,
                height: 52,
                child: Center(
                  child: Icon(
                    selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    color: selected ? AppColors.primary : AppColors.textSecondary,
                    size: 26,
                  ),
                ),
              )
            : ArtworkThumbnail(url: entry.track.artworkUrl),
        title: Text(entry.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(entry.displayArtist, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(modeLabel, style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 6),
                Text(
                  DateFormat('dd/MM HH:mm').format(entry.searchedAt),
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
                if (entry.wasCorrect == false) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.edit_rounded, size: 12, color: AppColors.secondary),
                ],
              ],
            ),
          ],
        ),
        trailing: selectionMode
            ? null
            : PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
                onSelected: onMenuAction,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'share',
                    child: Row(children: [Icon(Icons.share_rounded, size: 18), SizedBox(width: 10), Text('Compartilhar')]),
                  ),
                  PopupMenuItem(
                    value: 'select',
                    child: Row(children: [Icon(Icons.checklist_rounded, size: 18), SizedBox(width: 10), Text('Selecionar')]),
                  ),
                  PopupMenuItem(
                    value: 'feedback',
                    child: Row(children: [Icon(Icons.flag_outlined, size: 18), SizedBox(width: 10), Text('Essa música está errada?')]),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                      SizedBox(width: 10),
                      Text('Excluir', style: TextStyle(color: AppColors.error)),
                    ]),
                  ),
                ],
              ),
      ),
    );
  }
}
