/// Rapports journaliers (§8) : rapport financier, brouillards, reçus,
/// versements de désintoxication. Export PDF.
library;

import 'package:material_ui/material_ui.dart';

import '../../modules/rapports/rapports.dart';
import '../../modules/tresorerie/tresorerie.dart';
import '../../noyau/outils.dart';
import '../../pdf/documents.dart';
import '../etat_app.dart';
import '../widgets/commun.dart';
import '../widgets/pdf_ui.dart';

class EcranRapports extends StatefulWidget {
  const EcranRapports({super.key});
  @override
  State<EcranRapports> createState() => _EcranRapportsState();
}

class _EcranRapportsState extends State<EcranRapports> {
  DateTime? _date;

  @override
  Widget build(BuildContext context) {
    final b = Etat.de(context).base!;
    final date = _date ?? b.maintenant;
    final iso = dateIso(date);
    final r = Rapports.financierDuJour(b, iso);
    final lignes = (r['lignes'] as List).cast<Map>();
    final recus = Rapports.recus(b, iso);
    final versements = Rapports.versementsDesintox(b, iso);
    return PageContenu(enfants: [
      Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.event),
          label: Text(dateFr(date)),
          onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2024), lastDate: b.maintenant);
            if (d != null) setState(() => _date = d);
          },
        ),
        FilledButton.icon(
          onPressed: () => afficherPdf(context, () => Documents.rapportJour(b, iso), 'Rapport financier du ${dateFr(date)}'),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Rapport financier (PDF)'),
        ),
      ]),
      const SizedBox(height: 16),
      Carte(child: Text(r['note'] as String, style: const TextStyle(fontSize: 16))),
      const SizedBox(height: 12),
      Card(
        child: Column(children: [
          for (final l in lignes)
            ListTile(dense: true, title: Text(l['libelle'] as String), trailing: Text('${fcfa(l['montant'] as int)} · ${l['pourcentage']} %')),
          ListTile(
            title: const Text('Total des recettes', style: TextStyle(fontWeight: FontWeight.w700)),
            trailing: Text(fcfa(r['recettes'] as int), style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          ListTile(dense: true, title: const Text('Charges'), trailing: Text(fcfa(r['charges'] as int))),
          ListTile(dense: true, title: const Text('Résultat du jour'), trailing: Text(fcfa(r['resultat'] as int))),
        ]),
      ),
      const SizedBox(height: 16),
      const TitreSection('Brouillards de caisse'),
      const SizedBox(height: 8),
      Card(
        child: Column(children: [
          for (final c in b.lignes("SELECT id FROM tresoreries WHERE type='caisse' AND actif=1 ORDER BY entite, centrale DESC, id"))
            () {
              final br = Rapports.brouillard(b, c['id'] as String, iso);
              final t = Tresorerie.compte(b, c['id'] as String);
              return ListTile(
                dense: true,
                title: Text('${t['libelle']} (${t['entite']})'),
                subtitle: Text('Ouverture ${fcfa(br['ouverture'] as int)} · entrées ${fcfa(br['entrees'] as int)} · sorties ${fcfa(br['sorties'] as int)}'),
                trailing: Text(fcfa(br['cloture'] as int), style: const TextStyle(fontWeight: FontWeight.w700)),
              );
            }(),
        ]),
      ),
      const SizedBox(height: 16),
      TitreSection('Reçus émis et annulés', sousTitre: '${recus.length}'),
      const SizedBox(height: 8),
      Card(
        child: Column(children: [
          for (final x in recus)
            ListTile(
              dense: true,
              title: Text('${x['piece']}${x['motif_annulation'] != null ? ' · ANNULÉ (${x['motif_annulation']})' : ''}'),
              subtitle: Text('${heureFr(DateTime.parse(x['horodatage'] as String))} · ${x['type']} · ${x['appareil']}'),
              onTap: () => afficherRecu(context, x['uuid'] as String),
            ),
        ]),
      ),
      const SizedBox(height: 16),
      TitreSection('Versements reçus en désintoxication', sousTitre: '${versements.length}'),
      const SizedBox(height: 8),
      Card(
        child: Column(children: [
          for (final v in versements)
            ListTile(
              dense: true,
              title: Text('${v['numero']} · ${v['payeur']}'),
              subtitle: Text('${v['piece']} · ${Modes.libelles[v['mode']]}'),
              trailing: Text(fcfa(v['montant'] as int)),
            ),
        ]),
      ),
    ]);
  }
}
