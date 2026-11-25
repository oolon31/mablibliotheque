// Interroge les vrais serveurs. Ignoré par défaut ; pour le lancer :
//   LIVE=1 flutter test test/live_lookup_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ma_bibliotheque/models/item.dart';
import 'package:ma_bibliotheque/services/catalog_lookup.dart';

class _ProxyOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final ca = Platform.environment['SSL_CERT_FILE'];
    final ctx = SecurityContext(withTrustedRoots: true);
    if (ca != null && File(ca).existsSync()) ctx.setTrustedCertificates(ca);
    return super.createHttpClient(ctx)..findProxy = HttpClient.findProxyFromEnvironment;
  }
}

void main() {
  final live = Platform.environment['LIVE'] == '1';
  setUpAll(() => HttpOverrides.global = _ProxyOverrides());

  Future<void> check(String code, ItemType type, String titlePart) async {
    final r = await CatalogLookup().lookup(code);
    // ignore: avoid_print
    print(
      '$code → ${r?.type.label} | ${r?.title} | ${r?.creator} | ${r?.year} | ${r?.publisher} | '
      'série « ${r?.series} » T.${r?.volume} | ${r?.format} | ${r?.source} | ${r?.coverUrl}',
    );
    expect(r, isNotNull);
    expect(r!.type, type);
    expect(r.title.toLowerCase(), contains(titlePart));
  }

  test('roman', () => check('9782070360024', ItemType.livre, 'étranger'), skip: !live);
  test('BD', () => check('9782203001169', ItemType.bd, 'lune'), skip: !live);
  test('vinyle', () => check('196587737313', ItemType.vinyle, 'random access'), skip: !live);
  test('couverture téléchargeable', () async {
    final bytes = await CatalogLookup().downloadImage(
      'https://covers.openlibrary.org/b/isbn/9782203001169-L.jpg?default=false',
    );
    // ignore: avoid_print
    print('couverture : ${bytes?.length} octets');
  }, skip: !live);
}
