import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../models/item.dart';
import '../services/barcode.dart';
import '../state/library.dart';
import '../widgets/cover.dart';
import '../widgets/item_tile.dart';
import 'scan_flow.dart';

/// Ajout (item == null) ou modification d'un objet.
class ItemFormScreen extends StatefulWidget {
  const ItemFormScreen({super.key, this.item, this.draft, this.initialType, this.initialWishlist = false});

  /// Objet à modifier ; null pour un ajout.
  final Item? item;

  /// Valeurs de départ d'un ajout (par exemple issues d'un code-barres).
  final Item? draft;
  final ItemType? initialType;
  final bool initialWishlist;

  @override
  State<ItemFormScreen> createState() => _ItemFormScreenState();
}

class _ItemFormScreenState extends State<ItemFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late ItemType _type;
  late final TextEditingController _title, _creator, _year, _publisher, _series, _volume, _genre, _identifier, _notes;
  String _format = '';
  ItemCondition? _condition;
  int _rating = 0;
  bool _wishlist = false;
  String? _coverPath;
  bool _saving = false;
  bool _saved = false;

  bool get _isNew => widget.item == null;

  @override
  void initState() {
    super.initState();
    final i = widget.item ?? widget.draft;
    _type = i?.type ?? widget.initialType ?? ItemType.vinyle;
    _title = TextEditingController(text: i?.title);
    _creator = TextEditingController(text: i?.creator);
    _year = TextEditingController(text: i?.year?.toString());
    _publisher = TextEditingController(text: i?.publisher);
    _series = TextEditingController(text: i?.series);
    _volume = TextEditingController(text: i?.volume);
    _genre = TextEditingController(text: i?.genre);
    _identifier = TextEditingController(text: i?.identifier);
    _notes = TextEditingController(text: i?.notes);
    _format = i?.format ?? '';
    _condition = i?.condition;
    _rating = i?.rating ?? 0;
    _wishlist = i?.wishlist ?? widget.initialWishlist;
    _coverPath = i?.coverPath;
  }

  /// Change la couverture en supprimant l'image provisoire remplacée.
  void _setCover(String? path) {
    final previous = _coverPath;
    if (previous != null && previous != widget.item?.coverPath) deleteCoverFile(previous);
    setState(() => _coverPath = path);
  }

  @override
  void dispose() {
    // Formulaire abandonné : l'image choisie ou téléchargée ne sert plus.
    if (!_saved && _coverPath != null && _coverPath != widget.item?.coverPath) {
      deleteCoverFile(_coverPath);
    }
    for (final c in [_title, _creator, _year, _publisher, _series, _volume, _genre, _identifier, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final library = LibraryScope.read(context);
    final hasSeries = _type.hasSeries;
    final data = Item(
      id: widget.item?.id,
      type: _type,
      title: _title.text.trim(),
      creator: _type.hasCreator ? _creator.text.trim() : '',
      year: int.tryParse(_year.text.trim()),
      publisher: _publisher.text.trim(),
      series: hasSeries ? _series.text.trim() : '',
      volume: (hasSeries || _type.usesPieces) ? _volume.text.trim() : '',
      genre: _genre.text.trim(),
      format: _format,
      identifier: _identifier.text.trim(),
      condition: _condition,
      rating: _rating,
      wishlist: _wishlist,
      loanedTo: _wishlist ? null : widget.item?.loanedTo,
      loanDate: _wishlist ? null : widget.item?.loanDate,
      notes: _notes.text.trim(),
      coverPath: _coverPath,
      createdAt: widget.item?.createdAt ?? DateTime.now(),
    );
    if (_isNew) {
      await library.add(data);
    } else {
      await library.save(data);
      if (widget.item!.coverPath != _coverPath) await deleteCoverFile(widget.item!.coverPath);
    }
    _saved = true;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _chooseCover() async {
    final source = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            if (_coverPath != null)
              ListTile(
                leading: const Icon(Icons.hide_image_outlined),
                title: const Text('Retirer l\'image'),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (source == null) return;
    if (source == 'remove') {
      _setCover(null);
      return;
    }
    try {
      final path = await pickCover(source as ImageSource);
      if (path != null) _setCover(path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Impossible de récupérer l\'image : $e')));
      }
    }
  }

  /// Lit un code-barres et complète les champs encore vides avec la fiche trouvée.
  Future<void> _scanIntoForm() async {
    final messenger = ScaffoldMessenger.of(context);
    final code = await scanCode(context);
    if (code == null || !mounted) return;
    final outcome = await lookupWithProgress(context, code);
    if (outcome == null || !mounted) return;
    final d = draftFromLookup(code, outcome);
    void fill(TextEditingController c, String v) {
      if (c.text.trim().isEmpty && v.isNotEmpty) c.text = v;
    }

    setState(() {
      // Le type n'est changé que si rien n'a encore été saisi.
      if (_title.text.trim().isEmpty && outcome.result != null) {
        _type = d.type;
        if (!_type.formats.contains(_format)) _format = '';
      }
      fill(_title, d.title);
      fill(_creator, d.creator);
      fill(_year, d.year?.toString() ?? '');
      fill(_publisher, d.publisher);
      fill(_series, d.series);
      fill(_volume, d.volume);
      fill(_genre, d.genre);
      if (_format.isEmpty && _type.formats.contains(d.format)) _format = d.format;
      _identifier.text = code;
    });
    if (d.coverPath != null) {
      if (_coverPath == null) {
        _setCover(d.coverPath);
      } else {
        deleteCoverFile(d.coverPath);
      }
    }
    messenger.showSnackBar(SnackBar(content: Text(outcome.message())));
  }

  @override
  Widget build(BuildContext context) {
    final library = LibraryScope.read(context);
    const gap = SizedBox(height: 16);
    final preview = Item(type: _type, title: '', coverPath: _coverPath, createdAt: DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Ajouter' : 'Modifier'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(onPressed: _saving ? null : _save, child: const Text('Enregistrer')),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        // Une colonne (et non une ListView) : tous les champs restent construits,
        // donc tous sont validés même s'ils sont hors de l'écran.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in ItemType.values)
                    ChoiceChip(
                      avatar: Icon(t.icon, size: 18),
                      label: Text(t.label),
                      selected: _type == t,
                      onSelected: (_) => setState(() {
                        _type = t;
                        if (!_type.formats.contains(_format)) _format = '';
                        // Pratique : la marque est presque toujours LEGO.
                        if (t == ItemType.lego && _publisher.text.trim().isEmpty) _publisher.text = 'LEGO';
                      }),
                    ),
                ],
              ),
              gap,
              Center(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: kIsWeb ? null : _chooseCover,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Cover(item: preview, width: 120, radius: 12),
                      if (!kIsWeb)
                        const Padding(
                          padding: EdgeInsets.all(6),
                          child: CircleAvatar(radius: 16, child: Icon(Icons.add_a_photo_outlined, size: 18)),
                        ),
                    ],
                  ),
                ),
              ),
              if (_isNew && widget.draft == null && !kIsWeb) ...[
                gap,
                OutlinedButton.icon(
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Remplir avec le code-barres'),
                  onPressed: _scanIntoForm,
                ),
              ],
              gap,
              TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Titre *'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Le titre est obligatoire' : null,
              ),
              if (_type.hasCreator) ...[
                gap,
                _AutocompleteField(
                  controller: _creator,
                  label: _type.creatorLabel,
                  options: library.suggestions((i) => i.creator, type: _type),
                ),
              ],
              if (_type.usesPieces) ...[
                gap,
                TextFormField(
                  controller: _volume,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Nombre de pièces'),
                  validator: (v) => (v == null || v.trim().isEmpty || RegExp(r'^\d{1,6}$').hasMatch(v.trim()))
                      ? null
                      : 'Nombre invalide',
                ),
              ],
              if (_type.hasSeries) ...[
                gap,
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _AutocompleteField(
                        controller: _series,
                        label: 'Série',
                        options: library.suggestions((i) => i.series, type: _type),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _volume,
                        decoration: const InputDecoration(labelText: 'Tome'),
                      ),
                    ),
                  ],
                ),
              ],
              gap,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _AutocompleteField(
                      controller: _publisher,
                      label: _type.publisherLabel,
                      options: library.suggestions((i) => i.publisher, type: _type),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _year,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Année'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final n = int.tryParse(v.trim());
                        return (n == null || n < 1000 || n > DateTime.now().year + 1) ? 'Année invalide' : null;
                      },
                    ),
                  ),
                ],
              ),
              gap,
              _AutocompleteField(
                controller: _genre,
                label: _type.genreLabel,
                options: library.suggestions((i) => i.genre, type: _type),
              ),
              gap,
              DropdownButtonFormField<String?>(
                key: ValueKey('format-$_type'),
                initialValue: _format.isEmpty ? null : _format,
                decoration: InputDecoration(labelText: _type.formatLabel),
                items: [
                  const DropdownMenuItem(value: null, child: Text('—')),
                  for (final f in _type.formats) DropdownMenuItem(value: f, child: Text(f)),
                ],
                onChanged: (v) => setState(() => _format = v ?? ''),
              ),
              gap,
              DropdownButtonFormField<ItemCondition?>(
                initialValue: _condition,
                decoration: const InputDecoration(labelText: 'État'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('—')),
                  for (final c in ItemCondition.values) DropdownMenuItem(value: c, child: Text(c.label)),
                ],
                onChanged: (v) => setState(() => _condition = v),
              ),
              gap,
              TextFormField(
                controller: _identifier,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _type.identifierLabel,
                  suffixIcon: kIsWeb
                      ? null
                      : IconButton(
                          tooltip: 'Scanner le code-barres',
                          icon: const Icon(Icons.qr_code_scanner),
                          onPressed: _scanIntoForm,
                        ),
                ),
                // Seuls les livres et les BD ont un ISBN à contrôler ; un numéro de set Lego ou une référence
                // de disque est libre.
                validator: (v) =>
                    (v == null ||
                        v.trim().isEmpty ||
                        isPlausibleCode(v) ||
                        (_type != ItemType.livre && _type != ItemType.bd))
                    ? null
                    : 'ISBN invalide',
              ),
              gap,
              Text('Ma note', style: Theme.of(context).textTheme.labelLarge),
              RatingStars(rating: _rating, onChanged: (r) => setState(() => _rating = r)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Liste d\'envies'),
                subtitle: const Text('Je ne l\'ai pas encore'),
                value: _wishlist,
                onChanged: (v) => setState(() => _wishlist = v),
              ),
              gap,
              TextFormField(
                controller: _notes,
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Notes', alignLabelWithHint: true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Champ texte qui propose les valeurs déjà saisies (auteurs, éditeurs, genres…).
class _AutocompleteField extends StatefulWidget {
  const _AutocompleteField({required this.controller, required this.label, required this.options});

  final TextEditingController controller;
  final String label;
  final List<String> options;

  @override
  State<_AutocompleteField> createState() => _AutocompleteFieldState();
}

class _AutocompleteFieldState extends State<_AutocompleteField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: (value) {
        final q = normalize(value.text);
        if (q.isEmpty) return const [];
        return widget.options.where((o) => normalize(o).contains(q) && o != value.text).take(6);
      },
      fieldViewBuilder: (context, ctrl, focus, onSubmit) => TextFormField(
        controller: ctrl,
        focusNode: focus,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: widget.label),
      ),
      optionsViewBuilder: (context, onSelected, opts) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 320),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [for (final o in opts) ListTile(dense: true, title: Text(o), onTap: () => onSelected(o))],
            ),
          ),
        ),
      ),
    );
  }
}
