import 'package:material_ui/material_ui.dart';

import '../services/catalog_lookup.dart';

/// Recherche par titre et auteur, pour un livre dont le code-barres n'est pas reconnu.
/// Renvoie l'édition choisie, ou null.
class TitleSearchScreen extends StatefulWidget {
  const TitleSearchScreen({super.key, this.initialTitle = ''});

  final String initialTitle;

  @override
  State<TitleSearchScreen> createState() => _TitleSearchScreenState();
}

class _TitleSearchScreenState extends State<TitleSearchScreen> {
  late final _title = TextEditingController(text: widget.initialTitle);
  final _author = TextEditingController();
  final _lookup = CatalogLookup();
  List<TitleMatch>? _results;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Indiquez au moins le titre.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final results = await _lookup.searchTitles(_title.text, author: _author.text);
      if (mounted) setState(() => _results = results);
    } on LookupException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Recherche impossible pour le moment.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Chercher par titre')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                TextField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Titre'),
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _author,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Auteur (facultatif)'),
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.search),
                    label: const Text('Rechercher'),
                    onPressed: _busy ? null : _search,
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ),
              ],
            ),
          ),
          const Divider(height: 24),
          Expanded(
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : _results == null
                ? const SizedBox.shrink()
                : _results!.isEmpty
                ? const Center(child: Text('Aucune édition trouvée. Essayez un autre titre.'))
                : ListView.separated(
                    itemCount: _results!.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final m = _results![i];
                      final details = [
                        if (m.creator.isNotEmpty) m.creator,
                        if (m.year != null) '${m.year}',
                        if (m.publisher.isNotEmpty) m.publisher,
                      ].join(' · ');
                      return ListTile(
                        title: Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(details.isEmpty ? 'Pas plus d\'informations' : details),
                        trailing: m.isbn == null ? null : const Icon(Icons.qr_code_2, size: 18),
                        onTap: () => Navigator.pop(context, m),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
