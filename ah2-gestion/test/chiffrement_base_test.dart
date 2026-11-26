import 'dart:io';

import 'package:ah2_gestion/noyau/base.dart';
import 'package:test/test.dart';

void main() {
  test('la base locale est chiffrée sur le disque (téléphones)', () {
    final d = Directory.systemTemp.createTempSync('ah2-chiffre');
    final b = Base.ouvrir(chemin: '${d.path}/t.db', appareil: 'T01', cle: 'cle-secrete');
    b.transaction(() => b.definirParam('secret', 'NKOULOU-BRIGITTE'));
    b.fermer();
    final octets = File('${d.path}/t.db').readAsBytesSync();
    expect(String.fromCharCodes(octets).contains('NKOULOU'), isFalse);
    expect(String.fromCharCodes(octets.take(16)).startsWith('SQLite format'), isFalse);
    expect(() => Base.ouvrir(chemin: '${d.path}/t.db', appareil: 'T01', cle: 'mauvaise'), throwsA(anything));
    final r = Base.ouvrir(chemin: '${d.path}/t.db', appareil: 'T01', cle: 'cle-secrete');
    expect(r.param('secret'), 'NKOULOU-BRIGITTE');
    r.fermer();
    d.deleteSync(recursive: true);
  });
}
