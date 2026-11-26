/// Synchronisation : état, bouton « Synchroniser maintenant », appareils.
library;

import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../noyau/outils.dart';
import '../../sync/transport_http.dart';
import '../etat_app.dart';
import '../theme.dart';
import '../widgets/commun.dart';

class EcranSynchro extends StatefulWidget {
  const EcranSynchro({super.key});
  @override
  State<EcranSynchro> createState() => _EcranSynchroState();
}

class _EcranSynchroState extends State<EcranSynchro> {
  List<String> _adresses = [];

  @override
  void initState() {
    super.initState();
    NetworkInterface.list(type: InternetAddressType.IPv4).then((l) {
      if (mounted) setState(() => _adresses = [for (final i in l) for (final a in i.addresses) a.address]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    if (etat.estCentral) {
      final apps = b.lignes('SELECT * FROM appareils WHERE central=0 ORDER BY code');
      return PageContenu(largeurMax: 800, enfants: [
        Carte(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Ce PC est le PC central', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            Text('Les appareils se synchronisent sur le Wi-Fi local à l’adresse : '
                '${_adresses.isEmpty ? '…' : _adresses.join(' ou ')} (port $portParDefaut).'),
            if (etat.derniereErreurSync != null) ...[
              const SizedBox(height: 6),
              Text(etat.derniereErreurSync!, style: const TextStyle(color: Couleurs.baisse)),
            ],
          ]),
        ),
        const SizedBox(height: 16),
        const TitreSection('Appareils'),
        const SizedBox(height: 8),
        Card(
          child: Column(children: [
            for (final a in apps)
              ListTile(
                leading: Icon(a['type'] == 'pc' ? Icons.computer : Icons.smartphone),
                title: Text('${a['code']} · ${a['nom']}'),
                subtitle: Text(a['derniere_sync'] == null
                    ? 'Jamais synchronisé'
                    : 'Dernière synchronisation : ${dateFr(DateTime.parse(a['derniere_sync'] as String))} à ${heureFr(DateTime.parse(a['derniere_sync'] as String))}'),
                trailing: Pastille(a['statut'] as String,
                    couleur: a['statut'] == 'autorise' ? Couleurs.hausse : (a['statut'] == 'revoque' ? Couleurs.baisse : Couleurs.stable)),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Text('Anomalies à traiter : ${b.entier("SELECT COUNT(*) FROM anomalies_sync WHERE statut='a_traiter'")}'),
      ]);
    }
    final s = etat.etatSync!;
    return PageContenu(largeurMax: 640, enfants: [
      Carte(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.libelle(b.maintenant), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          const SizedBox(height: 6),
          Text('Opérations en attente d’envoi : ${s.enAttente}'),
          Text('Dernière synchronisation : ${s.derniere == null ? 'jamais' : '${dateFr(s.derniere!)} à ${heureFr(s.derniere!)}'}'),
          Text('PC central : ${etat.adresseCentral ?? 'non configuré'}'),
          if (etat.derniereErreurSync != null) ...[
            const SizedBox(height: 6),
            Text(etat.derniereErreurSync!, style: const TextStyle(color: Couleurs.baisse)),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: etat.synchronisationEnCours
                ? null
                : () async {
                    final m = await etat.synchroniser();
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
                  },
            icon: const Icon(Icons.sync),
            label: const Text('Synchroniser maintenant'),
          ),
          const SizedBox(height: 8),
          const Text('La synchronisation est aussi automatique toutes les 2 minutes dès que l’appareil est sur le Wi-Fi de la structure.',
              style: TextStyle(fontSize: 12)),
        ]),
      ),
    ]);
  }
}
