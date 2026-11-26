import 'package:ah2_gestion/modules/actes/actes.dart';
import 'package:ah2_gestion/modules/tresorerie/tresorerie.dart';
import 'package:ah2_gestion/noyau/base.dart';
import 'package:ah2_gestion/noyau/session.dart';
import 'package:ah2_gestion/sync/synchronisation.dart';
import 'package:ah2_gestion/sync/transport_http.dart';
import 'package:test/test.dart';

import 'aide.dart';

void main() {
  test('synchronisation réelle par HTTP sur le réseau local (boucle locale)', () async {
    final env = Environnement();
    final serveur = ServeurHttpSync(env.serveur);
    final port = await serveur.demarrer(port: 0);
    try {
      expect(await centralJoignable('127.0.0.1', port: port), isTrue);
      final b = Base.ouvrir(appareil: 'T01', horloge: env.horloge.call);
      ClientSync.enroler(b, cleSync: env.cles['T01']!);
      final client = ClientSync(b, transport: transportHttp('127.0.0.1', port: port), effacerDonnees: () {});
      await client.synchroniser();
      Actes.enregistrer(Session.pour(b, 'labo'), activite: 'LAB', actes: const [DemandeActe('LAB-NFS')], mode: Modes.especes);
      final r = await client.synchroniser();
      expect(r.envoyees, 1);
      expect(Tresorerie.solde(env.central, 'CS-CAISSE-T01'), 3500);
    } finally {
      await serveur.arreter();
    }
    expect(await centralJoignable('127.0.0.1', port: 1), isFalse);
  });
}
