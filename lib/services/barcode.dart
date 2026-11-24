import '../models/item.dart';

/// Ne garde que les chiffres (et le X final d'un ISBN-10).
String cleanCode(String raw) {
  final s = raw.toUpperCase().replaceAll(RegExp(r'[^0-9X]'), '');
  // Le X n'est valide qu'en dernière position d'un ISBN-10.
  final body = s.replaceAll('X', '');
  return s.endsWith('X') && body.length == 9 ? '${body}X' : body;
}

bool _validEan13(String c) {
  if (!RegExp(r'^\d{13}$').hasMatch(c)) return false;
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    sum += int.parse(c[i]) * (i.isEven ? 1 : 3);
  }
  return (10 - sum % 10) % 10 == int.parse(c[12]);
}

/// Convertit un ISBN-10 en ISBN-13 ; renvoie null si ce n'est pas un ISBN-10 valide.
String? isbn10To13(String c) {
  if (!RegExp(r'^\d{9}[\dX]$').hasMatch(c)) return null;
  var sum = 0;
  for (var i = 0; i < 10; i++) {
    final d = c[i] == 'X' ? 10 : int.parse(c[i]);
    sum += d * (10 - i);
  }
  if (sum % 11 != 0) return null;
  final base = '978${c.substring(0, 9)}';
  var s13 = 0;
  for (var i = 0; i < 12; i++) {
    s13 += int.parse(base[i]) * (i.isEven ? 1 : 3);
  }
  return '$base${(10 - s13 % 10) % 10}';
}

/// Forme canonique d'un code : ISBN-13 pour les livres, sinon les chiffres tels quels.
String normalizeCode(String raw) {
  final c = cleanCode(raw);
  return isbn10To13(c) ?? c;
}

/// Un ISBN-13 commence par 978 ou 979 (le « pays » Bookland).
bool isIsbn(String code) {
  final c = normalizeCode(code);
  return _validEan13(c) && (c.startsWith('978') || c.startsWith('979'));
}

/// Un code produit plausible : EAN-13, EAN-8, UPC-A (12) ou ISBN-10.
bool isPlausibleCode(String raw) {
  final c = cleanCode(raw);
  if (isbn10To13(c) != null) return true;
  return switch (c.length) { 8 || 12 => true, 13 => _validEan13(c), _ => false };
}

/// Livres et BD ont un ISBN ; le reste est supposé être un disque.
ItemType guessTypeFromCode(String code) => isIsbn(code) ? ItemType.livre : ItemType.vinyle;

/// Deux codes désignent-ils le même produit ? (un UPC-A lu en EAN-13 a un zéro devant)
bool sameCode(String a, String b) {
  String k(String s) => normalizeCode(s).replaceFirst(RegExp(r'^0+'), '');
  final ka = k(a);
  return ka.isNotEmpty && ka == k(b);
}
