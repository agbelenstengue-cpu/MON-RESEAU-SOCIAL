/// Relevés journaliers : génération (par service ou groupée), PDF, retour
/// signé avec photo, fiches d'écart, tableau de suivi.
library;

import 'package:material_ui/material_ui.dart';

import '../../modules/releves/releves.dart';
import '../../noyau/outils.dart';
import '../../pdf/documents.dart';
import '../etat_app.dart';
import '../theme.dart';
import '../widgets/commun.dart';
import '../widgets/pdf_ui.dart';
import '../widgets/piece_jointe.dart';

class EcranReleves extends StatefulWidget {
  const EcranReleves({super.key});
  @override
  State<EcranReleves> createState() => _EcranRelevesState();
}

class _EcranRelevesState extends State<EcranReleves> {
  DateTime? _date;

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final s = etat.session!;
    final date = _date ?? b.maintenant.subtract(const Duration(days: 1));
    final suivi = Releves.suivi(b);
    final peutGenerer = etat.estCentral && s.peut('releves', 'creer');
    return PageContenu(enfants: [
      if (peutGenerer)
        Carte(
          child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('Générer les relevés du', style: TextStyle(fontWeight: FontWeight.w600)),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(dateFr(date)),
              onPressed: () async {
                final d = await showDatePicker(
                    context: context, initialDate: date, firstDate: DateTime(2024), lastDate: b.maintenant.subtract(const Duration(days: 1)));
                if (d != null) setState(() => _date = d);
              },
            ),
            FilledButton.icon(
              onPressed: () => executer(context, () => Releves.genererTous(s, dateIso(date)), succes: 'Relevés générés.'),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Générer tous les services'),
            ),
            for (final a in b.lignes('SELECT code, libelle FROM activites WHERE service=1 AND actif=1 ORDER BY code'))
              ActionChip(
                label: Text(a['libelle'] as String),
                onPressed: () => executer(context, () => Releves.generer(s, activite: a['code'] as String, date: dateIso(date)),
                    succes: 'Relevé ${a['libelle']} généré.'),
              ),
          ]),
        )
      else if (!etat.estCentral)
        const Carte(child: Text('Les relevés sont générés sur le PC central, après synchronisation de tous les appareils.')),
      const SizedBox(height: 16),
      TitreSection('Suivi des relevés', sousTitre: '${suivi.where((r) => r['statut'] == 'genere').length} en attente de retour signé'),
      const SizedBox(height: 8),
      if (suivi.isEmpty) const EtatVide('Aucun relevé généré.'),
      Card(
        child: Column(children: [
          for (final r in suivi)
            ListTile(
              title: Text('${r['numero']} · ${dateFr(depuisIso(r['date_actes'] as String))}'),
              subtitle: Text(r['statut'] == 'retourne_signe'
                  ? 'Retourné signé${(r['ecarts'] as int) > 0 ? ' · ${r['ecarts']} écart(s), ${r['ecarts_ouverts']} ouvert(s)' : ''}'
                  : 'En attente · ${r['retard_jours']} j de retard'),
              leading: Icon(r['statut'] == 'retourne_signe' ? Icons.task_alt : Icons.hourglass_top,
                  color: r['statut'] == 'retourne_signe' ? Couleurs.hausse : Couleurs.stable),
              trailing: Wrap(spacing: 4, children: [
                IconButton(
                  tooltip: 'PDF',
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  onPressed: () => afficherPdf(context, () => Documents.releve(b, r['numero'] as String), r['numero'] as String),
                ),
                if (s.peut('releves', 'creer') && r['statut'] == 'genere')
                  IconButton(
                    tooltip: 'Marquer retourné signé',
                    icon: const Icon(Icons.add_a_photo_outlined),
                    onPressed: () async {
                      final f = await prendrePieceJointe(context);
                      if (f != null && context.mounted) {
                        executer(context, () => Releves.marquerRetourne(s, r['numero'] as String, fichier: f), succes: 'Relevé marqué retourné signé.');
                      }
                    },
                  ),
                if (s.peut('releves', 'creer'))
                  IconButton(tooltip: "Saisir un écart", icon: const Icon(Icons.report_problem_outlined), onPressed: () => _ecart(context, r['numero'] as String)),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 16),
      const TitreSection("Fiches d'écart"),
      const SizedBox(height: 8),
      Card(
        child: Column(children: [
          for (final e in b.lignes('SELECT * FROM ecarts_releve ORDER BY numero DESC LIMIT 50'))
            ListTile(
              title: Text('${e['numero']} · relevé ${e['releve']} · ligne ${e['ligne']}'),
              subtitle: Text('${e['nature']}${(e['observation'] as String).isNotEmpty ? ' · ${e['observation']}' : ''}'),
              trailing: e['statut'] == 'ouvert' && s.peut('releves', 'creer')
                  ? TextButton(
                      onPressed: () => executer(context, () => Releves.suivreEcart(s, e['numero'] as String, statut: 'justifie'),
                          succes: 'Écart justifié.'),
                      child: const Text('Justifier'))
                  : Pastille(e['statut'] as String, couleur: e['statut'] == 'ouvert' ? Couleurs.baisse : Couleurs.hausse),
            ),
        ]),
      ),
    ]);
  }

  void _ecart(BuildContext context, String releve) {
    final ligne = TextEditingController(), obs = TextEditingController();
    String nature = Releves.naturesEcart.first;
    showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, maj) => AlertDialog(
          title: Text('Écart sur $releve'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: ligne, decoration: const InputDecoration(labelText: 'N° de ligne ou de reçu')),
              const SizedBox(height: 10),
              ChoixPastilles<String>(options: [for (final n in Releves.naturesEcart) (n, n)], valeur: nature, onChanged: (v) => maj(() => nature = v)),
              const SizedBox(height: 10),
              TextField(controller: obs, decoration: const InputDecoration(labelText: 'Observation')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                if (executer(c, () => Releves.saisirEcart(Etat.lire(c).session!, releve: releve, ligne: ligne.text, nature: nature, observation: obs.text),
                        succes: "Fiche d'écart créée.") !=
                    null) {
                  Navigator.pop(c);
                }
              },
              child: const Text('Créer la fiche'),
            ),
          ],
        ),
      ),
    );
  }
}
