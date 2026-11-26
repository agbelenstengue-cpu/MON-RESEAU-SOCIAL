/// Patients : recherche, création, fiche (actes, paiements, créance).
library;

import 'package:material_ui/material_ui.dart';

import '../../modules/actes/actes.dart';
import '../../modules/facturation/facturation.dart';
import '../../pdf/documents.dart';
import '../../rapports/etats_stocks_hospitalisation.dart';
import '../../rapports/modele.dart';
import '../../modules/patients/patients.dart';
import '../../modules/tresorerie/tresorerie.dart';
import '../../noyau/outils.dart';
import '../etat_app.dart';
import '../widgets/commun.dart';
import '../widgets/formulaire.dart';
import '../widgets/pdf_ui.dart';
import 'desintox.dart';

class EcranPatients extends StatefulWidget {
  const EcranPatients({super.key});
  @override
  State<EcranPatients> createState() => _EcranPatientsState();
}

class _EcranPatientsState extends State<EcranPatients> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final s = etat.session!;
    final liste = Patients.rechercher(etat.base!, _q, limite: 100);
    return PageContenu(largeurMax: 900, enfants: [
      Row(children: [
        Expanded(
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Nom ou numéro de dossier'),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        const SizedBox(width: 12),
        if (s.peut('patients', 'creer'))
          FilledButton.icon(onPressed: () => nouveauPatient(context), icon: const Icon(Icons.person_add_alt), label: const Text('Nouveau')),
      ]),
      const SizedBox(height: 16),
      if (liste.isEmpty) const EtatVide('Aucun patient.'),
      Card(
        child: Column(children: [
          for (final p in liste)
            ListTile(
              leading: CircleAvatar(child: Text((p['nom'] as String).substring(0, 1))),
              title: Text(Patients.libelle(s, p)),
              subtitle: Text('${p['numero_dossier']}${(p['contact'] as String).isNotEmpty ? ' · ${p['contact']}' : ''}'),
              trailing: () {
                final c = Actes.creance(etat.base!, p['id'] as String);
                return c > 0 ? Pastille('Doit ${fcfa(c)}', couleur: const Color(0xFFB91C1C)) : null;
              }(),
              onTap: () => ouvrirFichePatient(context, p['id'] as String),
            ),
        ]),
      ),
    ]);
  }
}

/// Formulaire court et guidé de création de patient. Renvoie son id.
Future<String?> nouveauPatient(BuildContext context) {
  final nom = TextEditingController();
  final prenoms = TextEditingController();
  final contact = TextEditingController();
  final prevenir = TextEditingController();
  String sexe = '';
  return showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, maj) => AlertDialog(
        title: const Text('Nouveau patient'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nom, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Nom *')),
              const SizedBox(height: 10),
              TextField(controller: prenoms, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Prénoms')),
              const SizedBox(height: 10),
              ChoixPastilles<String>(options: const [('F', 'Femme'), ('M', 'Homme')], valeur: sexe, onChanged: (v) => maj(() => sexe = v)),
              const SizedBox(height: 10),
              TextField(controller: contact, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Téléphone')),
              const SizedBox(height: 10),
              TextField(controller: prevenir, decoration: const InputDecoration(labelText: 'Personne à prévenir (hospitalisation, désintox)')),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final op = executer(
                  c,
                  () => Patients.creer(Etat.lire(c).session!,
                      nom: nom.text, prenoms: prenoms.text, sexe: sexe, contact: contact.text, personneAPrevenir: prevenir.text),
                  succes: 'Patient créé.');
              if (op != null) Navigator.pop(c, op.d<String>('id'));
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    ),
  );
}

/// Sélection d'un patient (recherche + création).
Future<String?> choisirPatient(BuildContext context) => showDialog<String>(
      context: context,
      builder: (c) {
        var q = '';
        return StatefulBuilder(builder: (c, maj) {
          final etat = Etat.lire(c);
          final liste = Patients.rechercher(etat.base!, q, limite: 20);
          return AlertDialog(
            title: const Text('Choisir un patient'),
            content: SizedBox(
              width: 460,
              height: 420,
              child: Column(children: [
                TextField(
                    autofocus: true,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Nom ou numéro de dossier'),
                    onChanged: (v) => maj(() => q = v)),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(children: [
                    for (final p in liste)
                      ListTile(
                        title: Text(Patients.libelle(etat.session!, p)),
                        subtitle: Text(p['numero_dossier'] as String),
                        onTap: () => Navigator.pop(c, p['id'] as String),
                      ),
                  ]),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
              FilledButton.icon(
                onPressed: () async {
                  final id = await nouveauPatient(c);
                  if (id != null && c.mounted) Navigator.pop(c, id);
                },
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Nouveau patient'),
              ),
            ],
          );
        });
      },
    );

void ouvrirFichePatient(BuildContext context, String id) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => FichePatient(id: id),
    ));

class FichePatient extends StatelessWidget {
  final String id;
  const FichePatient({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final s = etat.session!;
    final p = Patients.lire(b, id);
    final actes = b.lignes('SELECT * FROM actes WHERE patient=? ORDER BY horodatage DESC LIMIT 100', [id]);
    final dossiers = b.lignes('SELECT * FROM desintox_dossiers WHERE patient=? ORDER BY date_entree DESC', [id]);
    final creance = Actes.creance(b, id);
    return Scaffold(
      appBar: AppBar(title: Text(Patients.libelle(s, p))),
      body: PageContenu(largeurMax: 900, enfants: [
        Carte(
          child: Wrap(spacing: 32, runSpacing: 12, children: [
            _info('Dossier', p['numero_dossier'] as String),
            _info('Sexe', (p['sexe'] as String).isEmpty ? 'Non renseigné' : p['sexe'] as String),
            _info('Contact', (p['contact'] as String).isEmpty ? 'Non renseigné' : p['contact'] as String),
            _info('Personne à prévenir', (p['personne_a_prevenir'] as String).isEmpty ? 'Non renseigné' : p['personne_a_prevenir'] as String),
            _info('Créance', fcfa(creance)),
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (creance > 0 && s.peut('caisse', 'creer'))
            FilledButton.icon(
              onPressed: () => _regler(context, creance),
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Régler la créance'),
            ),
          if (creance > 0 && s.peut('facturation', 'valider'))
            OutlinedButton.icon(
              onPressed: () => formulaire(context, 'Avoir (réduction de la créance)', [
                Champ('montant', 'Montant (FCFA)', nombre: true, aide: 'Créance : ${fcfa(creance)}'),
                Champ('compte', 'Prestation concernée', choix: [
                  for (final c in b.lignes("SELECT numero, libelle FROM comptes WHERE entite='CS' AND actif=1 AND numero LIKE '70%' ORDER BY numero"))
                    (c['numero'] as String, '${c['numero']} ${c['libelle']}')
                ]),
                const Champ('motif', 'Motif (obligatoire)'),
              ], (c, v) => reussir(c, () => Facturation.avoir(s, tiers: id, montant: int.tryParse(v['montant']!) ?? 0, motif: v['motif']!, compteProduit: v['compte']!),
                  succes: 'Avoir enregistré.')),
              icon: const Icon(Icons.remove_circle_outline),
              label: const Text('Établir un avoir'),
            ),
          OutlinedButton.icon(
            onPressed: () => afficherPdf(context, () => Documents.rapport(b, EtatsTiers.releveCompte(b, id, Periode('2000-01-01', dateIso(b.maintenant)))),
                'Relevé de compte'),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Relevé de compte'),
          ),
        ]),
        if (dossiers.isNotEmpty) ...[
          const SizedBox(height: 16),
          const TitreSection('Programmes de désintoxication'),
          const SizedBox(height: 8),
          for (final d in dossiers)
            Card(
              child: ListTile(
                title: Text('${d['numero']} · entrée le ${dateFr(depuisIso(d['date_entree'] as String))}'),
                subtitle: Text(d['date_sortie'] == null ? 'En cours' : 'Sorti le ${dateFr(depuisIso(d['date_sortie'] as String))}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => ouvrirFicheDesintox(context, d['id'] as String),
              ),
            ),
        ],
        const SizedBox(height: 16),
        const TitreSection('Historique des actes'),
        const SizedBox(height: 8),
        if (actes.isEmpty) const EtatVide('Aucun acte.'),
        Card(
          child: Column(children: [
            for (final a in actes)
              ListTile(
                dense: true,
                title: Text('${a['libelle']}${a['annule'] == 1 ? ' (annulé)' : ''}'),
                subtitle: Text('${dateFr(DateTime.parse(a['horodatage'] as String))} · ${a['piece']} · ${Modes.libelles[a['mode']]}'),
                trailing: Text(fcfa(a['montant'] as int)),
                onTap: () => afficherRecu(context, a['uuid_op'] as String),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _info(String l, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(l, style: const TextStyle(fontSize: 12)),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
      ]);

  void _regler(BuildContext context, int du) {
    final m = TextEditingController(text: '$du');
    final ref = TextEditingController();
    String mode = Modes.especes;
    showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, maj) => AlertDialog(
          title: const Text('Règlement de créance'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ChampMontant(controleur: m, aide: 'Créance : ${fcfa(du)}'),
              const SizedBox(height: 12),
              ChoixPastilles<String>(
                options: [for (final x in Modes.encaissables) (x, Modes.libelles[x]!)],
                valeur: mode,
                onChanged: (v) => maj(() => mode = v),
              ),
              if (mode != Modes.especes) ...[
                const SizedBox(height: 12),
                TextField(controller: ref, decoration: const InputDecoration(labelText: 'Référence')),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                final op = executer(
                    c,
                    () => Actes.reglerCreance(Etat.lire(c).session!,
                        tiers: id, montant: lireMontant(m), mode: mode, reference: ref.text.isEmpty ? null : ref.text),
                    succes: 'Règlement enregistré.');
                if (op != null) {
                  Navigator.pop(c);
                  afficherRecu(context, op.uuid);
                }
              },
              child: const Text('Encaisser'),
            ),
          ],
        ),
      ),
    );
  }
}
