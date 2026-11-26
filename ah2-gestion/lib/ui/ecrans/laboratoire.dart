/// Laboratoire : nouvel examen (patient ou client divers), examens du jour
/// avec leur suivi (demandé, réalisé, résultat remis), liste des examens et
/// de leurs prix modifiable sur place, réactifs.
library;

import 'package:material_ui/material_ui.dart';

import '../../modules/actes/actes.dart';
import '../../modules/parametrage/parametrage.dart';
import '../../modules/patients/patients.dart';
import '../../modules/stocks/stocks.dart';
import '../../modules/tresorerie/tresorerie.dart';
import '../../noyau/outils.dart';
import '../etat_app.dart';
import '../theme.dart';
import '../widgets/commun.dart';
import '../widgets/formulaire.dart';
import '../widgets/pdf_ui.dart';
import 'patients.dart';
import 'stocks_ecran.dart';

class EcranLaboratoire extends StatelessWidget {
  const EcranLaboratoire({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Etat.de(context).session!;
    final onglets = [
      if (s.peut('actes', 'creer')) (const Tab(text: 'Nouvel examen'), const _NouvelExamen()),
      (const Tab(text: 'Examens du jour'), const _ExamensDuJour()),
      (const Tab(text: 'Liste et prix des examens'), const _Catalogue()),
      if (s.peut('stocks', 'voir')) (const Tab(text: 'Réactifs'), const _Reactifs()),
    ];
    return DefaultTabController(
      length: onglets.length,
      child: Column(children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final o in onglets) o.$1]),
        ),
        Expanded(child: TabBarView(children: [for (final o in onglets) o.$2])),
      ]),
    );
  }
}

// ------------------------------------------------------------ nouvel examen
class _NouvelExamen extends StatefulWidget {
  const _NouvelExamen();
  @override
  State<_NouvelExamen> createState() => _NouvelExamenState();
}

class _NouvelExamenState extends State<_NouvelExamen> {
  String? _patient;
  final _client = TextEditingController();
  final Set<String> _examens = {};
  String _mode = Modes.especes;
  String _statut = 'demande';
  String? _motifGratuite;
  final _reference = TextEditingController();
  String _filtre = '';

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final s = etat.session!;
    final jour = dateIso(b.maintenant);
    final catalogue = b.lignes("SELECT * FROM actes_catalogue WHERE activite='LAB' AND actif=1 ORDER BY libelle");
    int prix(String code) {
      try {
        return Parametrage.tarif(b, code, jour);
      } on RegleMetier {
        return 0;
      }
    }

    final visibles = catalogue.where((c) => (c['libelle'] as String).toLowerCase().contains(_filtre.toLowerCase())).toList();
    final total = _mode == Modes.gratuit ? 0 : _examens.fold<int>(0, (t, c) => t + prix(c));
    final patient = _patient == null ? null : b.ligne('SELECT * FROM patients WHERE id=?', [_patient]);
    return Column(children: [
      Expanded(
        child: PageContenu(largeurMax: 760, enfants: [
          Etape('1', 'Client',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ChoixPastilles<bool>(
                  options: const [(false, 'Client divers (de passage)'), (true, 'Patient enregistré')],
                  valeur: _patient != null,
                  onChanged: (v) async {
                    if (v) {
                      final id = await choisirPatient(context);
                      if (id != null) setState(() => _patient = id);
                    } else {
                      setState(() => _patient = null);
                    }
                  },
                ),
                const SizedBox(height: 10),
                if (patient != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline),
                    title: Text(Patients.libelle(s, patient), style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(patient['numero_dossier'] as String),
                  )
                else
                  TextField(
                    controller: _client,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Nom du client (facultatif)', hintText: 'Laisser vide : « Client divers »'),
                  ),
              ])),
          Etape('2', 'Examens',
              child: Column(children: [
                if (catalogue.length > 8)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher un examen', isDense: true),
                      onChanged: (v) => setState(() => _filtre = v),
                    ),
                  ),
                for (final c in visibles)
                  CheckboxListTile(
                    dense: true,
                    value: _examens.contains(c['code']),
                    onChanged: (v) => setState(() => v! ? _examens.add(c['code'] as String) : _examens.remove(c['code'])),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(c['libelle'] as String),
                    secondary: Text(fcfa(prix(c['code'] as String)), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                if (catalogue.isEmpty) const EtatVide("Aucun examen. Ajoutez-les dans l'onglet « Liste et prix des examens »."),
              ])),
          Etape('3', 'Paiement et suivi',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ChoixPastilles<String>(
                  options: [
                    for (final m in [Modes.especes, Modes.orange, Modes.mtn, Modes.gratuit, if (_patient != null) Modes.credit]) (m, Modes.libelles[m]!)
                  ],
                  valeur: _mode,
                  onChanged: (v) => setState(() => _mode = v),
                ),
                if (Modes.estMomo(_mode)) ...[
                  const SizedBox(height: 10),
                  TextField(controller: _reference, decoration: const InputDecoration(labelText: 'Référence de la transaction')),
                ],
                if (_mode == Modes.gratuit) ...[
                  const SizedBox(height: 10),
                  ChoixPastilles<String>(
                    options: [for (final m in Actes.motifsGratuite) (m, m)],
                    valeur: _motifGratuite,
                    onChanged: (v) => setState(() => _motifGratuite = v),
                  ),
                ],
                const SizedBox(height: 12),
                ChoixPastilles<String>(
                  options: const [('demande', 'À réaliser'), ('realise', 'Déjà réalisé')],
                  valeur: _statut,
                  onChanged: (v) => setState(() => _statut = v),
                ),
              ])),
        ]),
      ),
      _BarreTotal(
        total: total,
        libelle: _mode == Modes.credit ? 'Enregistrer (à crédit)' : 'Encaisser et émettre le reçu',
        actif: _examens.isNotEmpty,
        onPressed: () {
          final op = executer(
              context,
              () => Actes.enregistrer(s,
                  activite: 'LAB',
                  actes: [for (final c in _examens) DemandeActe(c)],
                  mode: _mode,
                  patient: _patient,
                  client: _patient == null ? (_client.text.trim().isEmpty ? null : _client.text.trim()) : null,
                  reference: _reference.text.trim().isEmpty ? null : _reference.text.trim(),
                  motifGratuite: _motifGratuite,
                  statut: _statut),
              succes: 'Examen enregistré.');
          if (op != null) {
            setState(() {
              _examens.clear();
              _client.clear();
              _reference.clear();
              _patient = null;
            });
            afficherRecu(context, op.uuid);
          }
        },
      ),
    ]);
  }
}

class _BarreTotal extends StatelessWidget {
  final int total;
  final String libelle;
  final bool actif;
  final VoidCallback onPressed;
  const _BarreTotal({required this.total, required this.libelle, required this.actif, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final etroit = MediaQuery.sizeOf(context).width < 600;
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Flex(
            direction: etroit ? Axis.vertical : Axis.horizontal,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: etroit ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
            children: [
              Flexible(
                fit: FlexFit.loose,
                child: Text('Total : ${fcfa(total)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12, height: 8),
              FilledButton.icon(onPressed: actif ? onPressed : null, icon: const Icon(Icons.check), label: Text(libelle)),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ examens du jour
class _ExamensDuJour extends StatefulWidget {
  const _ExamensDuJour();
  @override
  State<_ExamensDuJour> createState() => _ExamensDuJourState();
}

class _ExamensDuJourState extends State<_ExamensDuJour> {
  DateTime? _jour;
  String? _statut;

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final s = etat.session!;
    final jour = _jour ?? b.maintenant;
    final lignes = b.lignes(
        "SELECT a.uuid_op, a.piece, a.statut, a.client, a.mode, a.horodatage, GROUP_CONCAT(a.libelle, ', ') AS examens, SUM(a.montant) AS montant, "
        "p.nom, p.prenoms FROM actes a LEFT JOIN patients p ON p.id=a.patient WHERE a.activite='LAB' AND a.date=? AND a.annule=0 "
        "GROUP BY a.uuid_op ORDER BY a.horodatage DESC",
        [dateIso(jour)]);
    final compte = {for (final k in Actes.statuts.keys) k: lignes.where((l) => l['statut'] == k).length};
    final visibles = _statut == null ? lignes : lignes.where((l) => l['statut'] == _statut).toList();
    return PageContenu(enfants: [
      Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.event),
          label: Text(dateFr(jour)),
          onPressed: () async {
            final d = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: b.maintenant, initialDate: jour);
            if (d != null) setState(() => _jour = d);
          },
        ),
        ChoixPastilles<String?>(
          options: [
            (null, 'Tous (${lignes.length})'),
            for (final e in Actes.statuts.entries) (e.key, '${e.value} (${compte[e.key]})'),
          ],
          valeur: _statut,
          onChanged: (v) => setState(() => _statut = v),
        ),
      ]),
      const SizedBox(height: 12),
      if (visibles.isEmpty)
        const EtatVide('Aucun examen ce jour.', icone: Icons.biotech_outlined)
      else
        Card(
          child: Column(children: [
            for (final l in visibles)
              ListTile(
                title: Text(l['nom'] != null ? '${l['nom']} ${l['prenoms']}' : (l['client'] as String? ?? 'Client divers'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${l['examens']}\n${l['piece']} · ${heureFr(DateTime.parse(l['horodatage'] as String))} · ${fcfa(l['montant'] as int)}'),
                isThreeLine: true,
                onTap: () => afficherRecu(context, l['uuid_op'] as String),
                trailing: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Pastille(Actes.statuts[l['statut']] ?? '${l['statut']}',
                      couleur: switch (l['statut']) { 'demande' => Couleurs.stable, 'realise' => Couleurs.primaire, _ => Couleurs.hausse }),
                  if (s.peut('actes', 'creer') && l['statut'] != 'remis')
                    IconButton(
                      tooltip: l['statut'] == 'demande' ? 'Marquer réalisé' : 'Résultat remis',
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: () => executer(context, () => Actes.changerStatut(s, l['uuid_op'] as String, l['statut'] == 'demande' ? 'realise' : 'remis'),
                          succes: l['statut'] == 'demande' ? 'Examen réalisé.' : 'Résultat remis.'),
                    ),
                ]),
              ),
          ]),
        ),
    ]);
  }
}

// ------------------------------------------------------------ liste et prix des examens
class _Catalogue extends StatelessWidget {
  const _Catalogue();

  static String _code(String libelle, Set<String> existants) {
    final base = libelle
        .toUpperCase()
        .replaceAll(RegExp('[ÀÂÄ]'), 'A')
        .replaceAll(RegExp('[ÉÈÊË]'), 'E')
        .replaceAll(RegExp('[ÎÏ]'), 'I')
        .replaceAll(RegExp('[ÔÖ]'), 'O')
        .replaceAll(RegExp('[ÙÛÜ]'), 'U')
        .replaceAll('Ç', 'C')
        .replaceAll(RegExp('[^A-Z0-9]+'), '');
    final racine = 'LAB-${base.isEmpty ? 'EX' : base.substring(0, base.length < 12 ? base.length : 12)}';
    var c = racine;
    for (var i = 2; existants.contains(c); i++) {
      c = '$racine$i';
    }
    return c;
  }

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final s = etat.session!;
    final modifiable = s.peut('parametrage', 'creer') && etat.estCentral;
    final jour = dateIso(b.maintenant);
    final liste = b.lignes("SELECT * FROM actes_catalogue WHERE activite='LAB' ORDER BY actif DESC, libelle");
    int? prix(String code) {
      try {
        return Parametrage.tarif(b, code, jour);
      } on RegleMetier {
        return null;
      }
    }

    return PageContenu(largeurMax: 820, enfants: [
      TitreSection('Examens proposés', sousTitre: '${liste.where((l) => l['actif'] == 1).length} examen(s) actif(s)',
          action: modifiable
              ? FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter un examen'),
                  onPressed: () => formulaire(context, 'Nouvel examen', const [
                    Champ('libelle', "Nom de l'examen"),
                    Champ('prix', 'Prix (FCFA)', nombre: true),
                  ], (c, v) => reussir(
                      c,
                      () => Parametrage.ajouterActe(s,
                          code: _code(v['libelle']!, {for (final l in b.lignes('SELECT code FROM actes_catalogue')) l['code'] as String}),
                          libelle: v['libelle']!,
                          activite: 'LAB',
                          compteProduit: (b.valeur("SELECT compte_produit FROM actes_catalogue WHERE activite='LAB' LIMIT 1") as String?) ?? '7062',
                          prix: int.tryParse(v['prix']!) ?? 0),
                      succes: 'Examen ajouté.')),
                )
              : null),
      if (!modifiable)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('La liste et les prix se modifient sur le PC central, par le comptable.', style: TextStyle(fontSize: 13)),
        ),
      const SizedBox(height: 12),
      Card(
        child: Column(children: [
          for (final l in liste)
            ListTile(
              enabled: l['actif'] == 1,
              title: Text(l['libelle'] as String),
              subtitle: l['actif'] == 1 ? null : const Text('Retiré'),
              trailing: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(prix(l['code'] as String) == null ? '' : fcfa(prix(l['code'] as String)!), style: const TextStyle(fontWeight: FontWeight.w700)),
                if (modifiable && l['actif'] == 1) ...[
                  IconButton(
                    tooltip: 'Modifier le nom ou le prix',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => formulaire(context, 'Modifier ${l['libelle']}', [
                      Champ('libelle', "Nom de l'examen", initial: l['libelle'] as String),
                      Champ('prix', 'Nouveau prix (FCFA)', nombre: true, initial: '${prix(l['code'] as String) ?? ''}',
                          aide: "Appliqué à partir d'aujourd'hui ; les reçus passés ne changent pas."),
                    ], (c, v) => reussir(c, () {
                      if (v['libelle'] != l['libelle']) {
                        Parametrage.modifierActe(s, l['code'] as String, libelle: v['libelle']!, compteProduit: l['compte_produit'] as String);
                      }
                      final p = int.tryParse(v['prix']!);
                      if (p != null && p != prix(l['code'] as String)) Parametrage.definirTarif(s, l['code'] as String, p);
                    }, succes: 'Examen modifié.')),
                  ),
                  IconButton(
                    tooltip: 'Retirer',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () async {
                      if (await confirmer(context, 'Retirer « ${l['libelle']} » de la liste ?') && context.mounted) {
                        executer(context, () => Parametrage.retirerActe(s, l['code'] as String), succes: 'Examen retiré.');
                      }
                    },
                  ),
                ],
                if (modifiable && l['actif'] != 1)
                  TextButton(
                      onPressed: () => executer(context, () => Parametrage.reactiverActe(s, l['code'] as String), succes: 'Examen remis dans la liste.'),
                      child: const Text('Remettre')),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

// ------------------------------------------------------------ réactifs
class _Reactifs extends StatelessWidget {
  const _Reactifs();

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final s = etat.session!;
    final produits = b.lignes("SELECT * FROM produits WHERE stock='LAB' AND actif=1 ORDER BY designation");
    return PageContenu(largeurMax: 820, enfants: [
      Wrap(spacing: 10, runSpacing: 10, children: [
        if (s.peut('stocks', 'creer'))
          FilledButton.icon(
              onPressed: () => ouvrirSortieStock(context, stock: 'LAB', type: 'consommation'),
              icon: const Icon(Icons.science_outlined),
              label: const Text('Réactifs utilisés')),
        if (s.peut('stocks', 'creer'))
          OutlinedButton.icon(onPressed: () => ouvrirEntreeStock(context, stock: 'LAB'), icon: const Icon(Icons.input), label: const Text('Réception de réactifs')),
      ]),
      const SizedBox(height: 12),
      if (produits.isEmpty)
        const EtatVide('Aucun réactif. Ajoutez-les dans Pharmacies et stocks, magasin Laboratoire.', icone: Icons.science_outlined)
      else
        Card(
          child: Column(children: [
            for (final p in produits)
              () {
                final q = Stocks.quantite(b, p['code'] as String);
                final bas = q <= (p['stock_minimum'] as int);
                return ListTile(
                  title: Text(p['designation'] as String),
                  subtitle: Text('${p['unite']} · seuil ${p['stock_minimum']}'),
                  trailing: Text('$q', style: TextStyle(fontWeight: FontWeight.w700, color: bas ? Couleurs.baisse : null)),
                );
              }(),
          ]),
        ),
    ]);
  }
}
