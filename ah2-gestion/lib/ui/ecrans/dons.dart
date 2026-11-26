/// Dons et subventions (ONG, SYCEBNL).
library;

import 'package:material_ui/material_ui.dart';

import '../../modules/dons/dons.dart';
import '../../noyau/outils.dart';
import '../etat_app.dart';
import '../widgets/commun.dart';
import '../widgets/pdf_ui.dart';

class EcranDons extends StatelessWidget {
  const EcranDons({super.key});

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final s = etat.session!;
    final dons = b.lignes('SELECT d.*, o.nom FROM dons d JOIN donateurs o ON o.id=d.donateur ORDER BY d.date DESC LIMIT 100');
    final total = b.entier('SELECT COALESCE(SUM(montant),0) FROM dons WHERE annule=0 AND date>=?', ['${b.maintenant.year}-01-01']);
    final subs = b.lignes('SELECT s.*, d.nom FROM subventions s JOIN donateurs d ON d.id=s.bailleur ORDER BY s.debut DESC');
    return PageContenu(enfants: [
      Wrap(spacing: 12, runSpacing: 12, children: [
        SizedBox(width: 280, child: CarteIndicateur(libelle: 'Dons reçus depuis le 1er janvier', valeur: fcfa(total))),
        if (s.peut('dons', 'creer')) ...[
          FilledButton.icon(onPressed: () => _don(context), icon: const Icon(Icons.volunteer_activism), label: const Text('Enregistrer un don')),
          OutlinedButton.icon(onPressed: () => _donateur(context), icon: const Icon(Icons.person_add_alt), label: const Text('Nouveau donateur')),
        ],
      ]),
      const SizedBox(height: 16),
      const TitreSection('Dons'),
      const SizedBox(height: 8),
      if (dons.isEmpty) const EtatVide('Aucun don enregistré.'),
      Card(
        child: Column(children: [
          for (final d in dons)
            ListTile(
              title: Text('${d['nom']}${d['annule'] == 1 ? ' (annulé)' : ''}'),
              subtitle: Text('${d['piece']} · ${dateFr(depuisIso(d['date'] as String))} · ${d['nature']}'),
              trailing: Text(fcfa(d['montant'] as int), style: const TextStyle(fontWeight: FontWeight.w700)),
              onTap: () => afficherRecu(context, d['uuid_op'] as String),
            ),
        ]),
      ),
      const SizedBox(height: 16),
      const TitreSection('Subventions'),
      const SizedBox(height: 8),
      if (subs.isEmpty) const EtatVide('Aucune convention de subvention.'),
      for (final sub in subs)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Carte(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${sub['reference']} · ${sub['nom']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('Accordé ${fcfa(sub['montant_accorde'] as int)} · du ${dateFr(depuisIso(sub['debut'] as String))} au ${dateFr(depuisIso(sub['fin'] as String))}'),
              const SizedBox(height: 8),
              for (final l in Dons.suiviSubvention(b, sub['id'] as String))
                Row(children: [
                  Expanded(child: Text('${l['libelle']}')),
                  Text('Budget ${fcfa(l['budget'] as int)} · Réalisé ${fcfa(l['realise'] as int)} · Solde ${fcfa(l['solde'] as int)}'),
                ]),
            ]),
          ),
        ),
    ]);
  }

  void _donateur(BuildContext context) {
    final nom = TextEditingController(), tel = TextEditingController(), pays = TextEditingController(text: 'Cameroun');
    String type = Dons.typesDonateur.first;
    showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, maj) => AlertDialog(
          title: const Text('Nouveau donateur ou bailleur'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nom, decoration: const InputDecoration(labelText: 'Nom ou dénomination')),
              const SizedBox(height: 10),
              ChoixPastilles<String>(options: [for (final t in Dons.typesDonateur) (t, t)], valeur: type, onChanged: (v) => maj(() => type = v)),
              const SizedBox(height: 10),
              TextField(controller: tel, decoration: const InputDecoration(labelText: 'Téléphone')),
              const SizedBox(height: 10),
              TextField(controller: pays, decoration: const InputDecoration(labelText: "Pays d'origine")),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                if (executer(c, () => Dons.creerDonateur(Etat.lire(c).session!, nom: nom.text, type: type, telephone: tel.text, pays: pays.text),
                        succes: 'Donateur créé.') !=
                    null) {
                  Navigator.pop(c);
                }
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
  }

  void _don(BuildContext context) {
    final b = Etat.lire(context).base!;
    final donateurs = b.lignes('SELECT * FROM donateurs ORDER BY nom');
    if (donateurs.isEmpty) {
      _donateur(context);
      return;
    }
    String donateur = donateurs.first['id'] as String;
    String nature = 'especes';
    final m = TextEditingController(), desc = TextEditingController(), ref = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, maj) => AlertDialog(
          title: const Text('Enregistrer un don'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  initialValue: donateur,
                  isExpanded: true,
                  items: [for (final d in donateurs) DropdownMenuItem(value: d['id'] as String, child: Text(d['nom'] as String))],
                  onChanged: (v) => maj(() => donateur = v!),
                  decoration: const InputDecoration(labelText: 'Donateur'),
                ),
                const SizedBox(height: 10),
                ChoixPastilles<String>(options: [for (final n in Dons.natures) (n, n)], valeur: nature, onChanged: (v) => maj(() => nature = v)),
                const SizedBox(height: 10),
                ChampMontant(controleur: m, libelle: nature == 'nature' ? 'Valeur estimée (FCFA)' : 'Montant (FCFA)'),
                if (nature == 'nature') ...[
                  const SizedBox(height: 10),
                  TextField(controller: desc, decoration: const InputDecoration(labelText: 'Description des biens reçus')),
                ],
                if (nature != 'especes' && nature != 'nature') ...[
                  const SizedBox(height: 10),
                  TextField(controller: ref, decoration: const InputDecoration(labelText: 'Référence')),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                final op = executer(
                    c,
                    () => Dons.recevoir(Etat.lire(c).session!,
                        donateur: donateur, montant: lireMontant(m), nature: nature, description: desc.text, reference: ref.text.isEmpty ? null : ref.text),
                    succes: 'Don enregistré.');
                if (op != null) {
                  Navigator.pop(c);
                  afficherRecu(context, op.uuid);
                }
              },
              child: const Text('Enregistrer et émettre le reçu'),
            ),
          ],
        ),
      ),
    );
  }
}
