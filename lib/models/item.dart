import 'package:material_ui/material_ui.dart';

/// Les types d'objets gérés par l'application.
enum ItemType {
  vinyle(
    label: 'Vinyle',
    plural: 'Vinyles',
    icon: Icons.album,
    creatorLabel: 'Artiste',
    publisherLabel: 'Label',
    identifierLabel: 'Référence catalogue',
    formats: ['33 tours (LP)', '45 tours', 'Maxi 45 tours', 'Double album', 'Coffret'],
  ),
  livre(
    label: 'Livre',
    plural: 'Livres',
    icon: Icons.menu_book,
    creatorLabel: 'Auteur',
    publisherLabel: 'Éditeur',
    identifierLabel: 'ISBN',
    formats: ['Broché', 'Poche', 'Relié', 'Coffret'],
  ),
  bd(
    label: 'BD',
    plural: 'BD',
    icon: Icons.chat_bubble,
    creatorLabel: 'Auteurs (scénario / dessin)',
    publisherLabel: 'Éditeur',
    identifierLabel: 'ISBN',
    formats: ['Album', 'Intégrale', 'Manga', 'Comics', 'Roman graphique'],
  ),
  dvd(
    label: 'DVD',
    plural: 'DVD',
    icon: Icons.movie_outlined,
    creatorLabel: 'Réalisateur',
    publisherLabel: 'Éditeur / distributeur',
    identifierLabel: 'Code-barres (EAN)',
    formats: ['Simple', 'Double', 'Coffret', 'Édition spéciale'],
  ),
  bluray(
    label: 'Blu-ray',
    plural: 'Blu-ray',
    icon: Icons.hd_outlined,
    creatorLabel: 'Réalisateur',
    publisherLabel: 'Éditeur / distributeur',
    identifierLabel: 'Code-barres (EAN)',
    formats: ['Simple', 'Double', 'Steelbook', '4K UHD', 'Coffret'],
  ),
  lego(
    label: 'Lego',
    plural: 'Lego',
    icon: Icons.extension_outlined,
    creatorLabel: '',
    publisherLabel: 'Marque',
    identifierLabel: 'Numéro du set ou code-barres',
    formats: ['Neuf, scellé', 'Ouvert, complet', 'Incomplet', 'Monté (exposé)'],
    genreLabel: 'Thème',
    formatLabel: 'État',
    hasCreator: false,
  );

  const ItemType({
    required this.label,
    required this.plural,
    required this.icon,
    required this.creatorLabel,
    required this.publisherLabel,
    required this.identifierLabel,
    required this.formats,
    this.genreLabel = 'Genre',
    this.formatLabel = 'Format',
    this.hasCreator = true,
  });

  final String label;
  final String plural;
  final IconData icon;
  final String creatorLabel;
  final String publisherLabel;
  final String identifierLabel;
  final List<String> formats;
  final String genreLabel;
  final String formatLabel;

  /// Faux pour les Lego : un set n'a pas d'auteur.
  final bool hasCreator;

  /// Les vinyles n'ont pas de série ni de tome.
  bool get hasSeries => this != ItemType.vinyle && this != ItemType.lego;

  /// Lego : le nombre de pièces est rangé dans le champ `volume` (pas de série ni de tome).
  bool get usesPieces => this == ItemType.lego;

  /// Films : pas d'ISBN, mais un code-barres EAN.
  bool get isVideo => this == ItemType.dvd || this == ItemType.bluray;
}

enum ItemCondition {
  neuf('Neuf'),
  tresBon('Très bon état'),
  bon('Bon état'),
  moyen('État moyen'),
  abime('Abîmé');

  const ItemCondition(this.label);
  final String label;
}

const Object _unset = Object();

class Item {
  const Item({
    this.id,
    required this.type,
    required this.title,
    this.creator = '',
    this.year,
    this.publisher = '',
    this.series = '',
    this.volume = '',
    this.genre = '',
    this.format = '',
    this.identifier = '',
    this.condition,
    this.rating = 0,
    this.wishlist = false,
    this.loanedTo,
    this.loanDate,
    this.notes = '',
    this.coverPath,
    required this.createdAt,
    this.onLoanHidden = false,
  });

  final int? id;
  final ItemType type;
  final String title;
  final String creator;
  final int? year;
  final String publisher;
  final String series;
  final String volume;
  final String genre;
  final String format;
  final String identifier;
  final ItemCondition? condition;

  /// Note de 0 (non noté) à 5.
  final int rating;

  /// Vrai si l'objet est dans la liste d'envies (pas encore possédé).
  final bool wishlist;
  final String? loanedTo;
  final DateTime? loanDate;
  final String notes;
  final String? coverPath;
  final DateTime createdAt;

  /// Vrai quand l'objet est prêté mais que le nom de l'emprunteur n'est pas visible (bibliothèque partagée en lecture).
  /// Jamais sauvegardé : ne vient que du serveur.
  final bool onLoanHidden;

  bool get isLoaned => (loanedTo != null && loanedTo!.isNotEmpty) || onLoanHidden;

  /// « Série · T. 3 », ou une chaîne vide.
  String get seriesLabel {
    if (series.isEmpty) return '';
    return volume.isEmpty ? series : '$series · T. $volume';
  }

  Item copyWith({
    Object? id = _unset,
    ItemType? type,
    String? title,
    String? creator,
    Object? year = _unset,
    String? publisher,
    String? series,
    String? volume,
    String? genre,
    String? format,
    String? identifier,
    Object? condition = _unset,
    int? rating,
    bool? wishlist,
    Object? loanedTo = _unset,
    Object? loanDate = _unset,
    String? notes,
    Object? coverPath = _unset,
    DateTime? createdAt,
    bool? onLoanHidden,
  }) {
    return Item(
      id: identical(id, _unset) ? this.id : id as int?,
      type: type ?? this.type,
      title: title ?? this.title,
      creator: creator ?? this.creator,
      year: identical(year, _unset) ? this.year : year as int?,
      publisher: publisher ?? this.publisher,
      series: series ?? this.series,
      volume: volume ?? this.volume,
      genre: genre ?? this.genre,
      format: format ?? this.format,
      identifier: identifier ?? this.identifier,
      condition: identical(condition, _unset) ? this.condition : condition as ItemCondition?,
      rating: rating ?? this.rating,
      wishlist: wishlist ?? this.wishlist,
      loanedTo: identical(loanedTo, _unset) ? this.loanedTo : loanedTo as String?,
      loanDate: identical(loanDate, _unset) ? this.loanDate : loanDate as DateTime?,
      notes: notes ?? this.notes,
      coverPath: identical(coverPath, _unset) ? this.coverPath : coverPath as String?,
      createdAt: createdAt ?? this.createdAt,
      onLoanHidden: onLoanHidden ?? this.onLoanHidden,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'type': type.name,
    'title': title,
    'creator': creator,
    'year': year,
    'publisher': publisher,
    'series': series,
    'volume': volume,
    'genre': genre,
    'format': format,
    'identifier': identifier,
    'condition': condition?.name,
    'rating': rating,
    'wishlist': wishlist ? 1 : 0,
    'loaned_to': loanedTo,
    'loan_date': loanDate?.millisecondsSinceEpoch,
    'notes': notes,
    'cover_path': coverPath,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory Item.fromMap(Map<String, Object?> m) {
    final conditionName = m['condition'] as String?;
    final loan = m['loan_date'] as int?;
    return Item(
      id: m['id'] as int?,
      type: ItemType.values.byName(m['type'] as String),
      title: m['title'] as String,
      creator: (m['creator'] as String?) ?? '',
      year: m['year'] as int?,
      publisher: (m['publisher'] as String?) ?? '',
      series: (m['series'] as String?) ?? '',
      volume: (m['volume'] as String?) ?? '',
      genre: (m['genre'] as String?) ?? '',
      format: (m['format'] as String?) ?? '',
      identifier: (m['identifier'] as String?) ?? '',
      condition: conditionName == null ? null : ItemCondition.values.byName(conditionName),
      rating: (m['rating'] as int?) ?? 0,
      wishlist: (m['wishlist'] as int?) == 1,
      loanedTo: m['loaned_to'] as String?,
      loanDate: loan == null ? null : DateTime.fromMillisecondsSinceEpoch(loan),
      notes: (m['notes'] as String?) ?? '',
      coverPath: m['cover_path'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
    );
  }
}
