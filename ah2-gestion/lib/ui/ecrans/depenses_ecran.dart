/// Dépenses et achats : une sortie d'argent en deux gestes (nature, montant),
/// sans choisir de compte ; achat simple ou achat pour le stock ; dépenses
/// répétitives du mois ; liste et total des dépenses.
library;

import 'package:material_ui/material_ui.dart';

import '../../modules/depenses/depenses.dart';
import '../../modules/tresorerie/tresorerie.dart';
import '../../noyau/outils.dart';
import '../etat_app.dart';
import '../theme.dart';
import '../widgets/commun.dart';
import '../widgets/formulaire.dart';
import '../widgets/pdf_ui.dart';
import '../widgets/piece_jointe.dart';
import 'stocks_ecran.dart';

IconData iconeNature(String code) => switch (code) {
      'ELEC' => Icons.bolt_outlined,
      'EAU' => Icons.water_drop_outlined,
      'CARB' => Icons.local_gas_station_outlined,
      'LOYER' => Icons.home_work_outlined,
      'BUREAU' => Icons.edit_note_outlined,
      'ENTRET' => Icons.cleaning_services_outlined,
      'REPAR' => Icons.build_outlined,
      'TRANSP' => Icons.directions_bus_outlined,
      'COMM' => Icons.phone_android_outlined,
      'BANQUE' => Icons.account_balance_outlined,
      'MEDIC' => Icons.medication_outlined,
      'REACTIF' => Icons.science_outlined,
      'AIDE' => Icons.volunteer_activism_outlined,
      _ => Icons.payments_outlined,
    };

class EcranDepenses extends StatefulWidget {
  const EcranDepenses({super.key});
  @override
  State<EcranDepenses> createState() => _EcranDepensesState();
}

class _EcranDepensesState extends State<EcranDepenses> {
  String _entite = 'CS';
  bool _mois = false;

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final s = etat.session!;
    final natures = Depenses.natures(b, _entite);
    final jour = dateIso(b.maintenant);
    final du = _mois ? '${jour.substring(0, 7)}-01' : jour;
    final liste = b.lignes(
        "SELECT d.*, n.libelle AS nature_lib FROM depenses d LEFT JOIN natures_depenses n ON n.code=d.nature AND n.entite=d.entite "
        'WHERE d.entite=? AND d.date BETWEEN ? AND ? AND d.annule=0 ORDER BY d.date DESC, d.piece DESC',
        [_entite, du, jour]);
    final total = liste.where((d) => d['statut'] == 'payee').fold<int>(0, (t, d) => t + (d['montant'] as int));
    final repetitives = Depenses.aPayerCeMois(b).where((m) => m['entite'] == _entite).toList();
    final peutCreer = s.peut('depenses', 'creer');
    final peutParam = s.peut('parametrage', 'creer') && etat.estCentral;
    return PageContenu(enfants: [
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        ChoixPastilles<String>(
          options: const [('CS', 'Centre de santé'), ('ONG', 'ONG')],
          valeur: _entite,
          onChanged: (v) => setState(() => _entite = v),
        ),
        if (peutParam)
          TextButton.icon(onPressed: () => _gererNatures(context), icon: const Icon(Icons.tune), label: const Text('Natures de dépenses')),
      ]),
      const SizedBox(height: 16),
      if (peutCreer) ...[
        const TitreSection("Sortie d'argent", sousTitre: 'Touchez la nature, saisissez le montant : le compte est trouvé automatiquement.'),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final n in natures)
            SizedBox(
              width: 150,
              child: Carte(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                onTap: () => nouvelleDepenseNature(context, entite: _entite, nature: n['code'] as String),
                child: Column(children: [
                  Icon(iconeNature(n['code'] as String), color: Couleurs.primaire),
                  const SizedBox(height: 6),
                  Text(n['libelle'] as String, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 10, runSpacing: 10, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.shopping_bag_outlined),
            label: const Text('Achat simple (fournitures, petit matériel…)'),
            onPressed: () => nouvelleDepenseNature(context, entite: _entite, nature: 'BUREAU'),
          ),
          if (s.peut('stocks', 'creer') && _entite == 'CS')
            OutlinedButton.icon(
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Achat pour le stock (médicaments, remèdes, réactifs)'),
              onPressed: () => _achatStock(context),
            ),
        ]),
        const SizedBox(height: 24),
      ],
      TitreSection('Dépenses répétitives de ce mois',
          sousTitre: repetitives.isEmpty ? 'Loyer, abonnements, salaires fixes…' : '${repetitives.where((r) => r['payee'] == false).length} à payer',
          action: peutParam ? TextButton.icon(onPressed: () => _modele(context), icon: const Icon(Icons.add), label: const Text('Ajouter')) : null),
      const SizedBox(height: 8),
      if (repetitives.isNotEmpty)
        Card(
          child: Column(children: [
            for (final r in repetitives)
              ListTile(
                leading: Icon(r['payee'] == true ? Icons.check_circle : Icons.schedule, color: r['payee'] == true ? Couleurs.hausse : Couleurs.stable),
                title: Text('${r['libelle']} : ${r['beneficiaire']}'),
                subtitle: Text('Le ${dateFr(depuisIso(r['echeance'] as String))} · ${fcfa(r['montant'] as int)}'),
                trailing: Wrap(spacing: 4, children: [
                  if (r['payee'] != true && peutCreer)
                    FilledButton(
                        onPressed: () => nouvelleDepenseNature(context,
                            entite: _entite, nature: r['nature'] as String, beneficiaire: r['beneficiaire'] as String, montant: r['montant'] as int),
                        child: const Text('Payer')),
                  if (peutParam)
                    IconButton(
                        tooltip: 'Retirer',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => executer(context, () => Depenses.retirerModele(s, r['id'] as String), succes: 'Dépense répétitive retirée.')),
                ]),
              ),
          ]),
        ),
      const SizedBox(height: 24),
      TitreSection(_mois ? 'Dépenses du mois' : 'Dépenses du jour', sousTitre: 'Total payé : ${fcfa(total)}',
          action: ChoixPastilles<bool>(options: const [(false, 'Jour'), (true, 'Mois')], valeur: _mois, onChanged: (v) => setState(() => _mois = v))),
      const SizedBox(height: 8),
      if (liste.isEmpty)
        const EtatVide('Aucune dépense.', icone: Icons.receipt_long_outlined)
      else
        Card(
          child: Column(children: [
            for (final d in liste)
              ListTile(
                leading: Icon(iconeNature((d['nature'] as String?) ?? '')),
                title: Text('${d['nature_lib'] ?? d['motif']} : ${d['beneficiaire']}'),
                subtitle: Text('${d['piece']} · ${dateFr(depuisIso(d['date'] as String))}'
                    '${d['statut'] == 'payee' ? '' : ' · ${d['statut'] == 'en_attente' ? 'en attente de validation' : d['statut']}'}'
                    '${(d['motif'] as String).isNotEmpty && d['nature_lib'] != null ? ' · ${d['motif']}' : ''}'),
                trailing: Text(fcfa(d['montant'] as int), style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: () => afficherRecu(context, d['uuid_op'] as String),
              ),
          ]),
        ),
    ]);
  }

  Future<void> _achatStock(BuildContext context) async {
    final stock = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(title: const Text('Quel magasin reçoit l’achat ?'), children: [
        for (final (code, lib) in const [('PHM', 'Pharmacie moderne'), ('PHT', 'Pharmacie traditionnelle (remèdes AE, SE…)'), ('LAB', 'Laboratoire (réactifs)')])
          SimpleDialogOption(onPressed: () => Navigator.pop(c, code), child: Padding(padding: const EdgeInsets.all(6), child: Text(lib))),
      ]),
    );
    if (stock != null && context.mounted) await ouvrirEntreeStock(context, stock: stock);
  }

  void _modele(BuildContext context) {
    final b = Etat.lire(context).base!;
    formulaire(context, 'Nouvelle dépense répétitive', [
      Champ('nature', 'Nature', choix: [for (final n in Depenses.natures(b, _entite)) (n['code'] as String, n['libelle'] as String)]),
      const Champ('beneficiaire', 'Bénéficiaire (ex. ENEO, bailleur)'),
      const Champ('montant', 'Montant habituel (FCFA)', nombre: true),
      const Champ('jour', 'Jour du mois (1 à 28)', nombre: true, initial: '5'),
    ], (c, v) => reussir(
        c,
        () => Depenses.enregistrerModele(Etat.lire(c).session!,
            entite: _entite,
            nature: v['nature']!,
            beneficiaire: v['beneficiaire']!,
            montant: int.tryParse(v['montant']!) ?? 0,
            jour: int.tryParse(v['jour']!) ?? 0),
        succes: 'Dépense répétitive ajoutée.'));
  }

  void _gererNatures(BuildContext context) => showDialog<void>(
        context: context,
        builder: (c) => StatefulBuilder(builder: (c, maj) {
          final etat = Etat.lire(c);
          final b = etat.base!;
          final s = etat.session!;
          final natures = Depenses.natures(b, _entite);
          final comptes = [
            for (final x in b.lignes("SELECT numero, libelle FROM comptes WHERE entite=? AND numero LIKE '6%' AND actif=1 ORDER BY numero", [_entite]))
              (x['numero'] as String, '${x['numero']} ${x['libelle']}')
          ];
          final activites = [
            ('', 'Administration (commune)'),
            for (final a in b.lignes('SELECT code, libelle FROM activites WHERE entite=? AND actif=1 ORDER BY libelle', [_entite]))
              (a['code'] as String, a['libelle'] as String)
          ];
          void editer([Map<String, Object?>? n]) => formulaire(c, n == null ? 'Nouvelle nature' : 'Modifier ${n['libelle']}', [
                Champ('libelle', 'Libellé (ex. Électricité)', initial: (n?['libelle'] as String?) ?? ''),
                Champ('compte', 'Compte de charge (choisi une fois pour toutes)', choix: comptes, initial: (n?['compte'] as String?) ?? ''),
                Champ('activite', 'Activité', choix: activites, initial: (n?['activite'] as String?) ?? ''),
              ], (d, v) {
                final ok = reussir(
                    d,
                    () => Depenses.enregistrerNature(s,
                        entite: _entite,
                        code: (n?['code'] as String?) ??
                            v['libelle']!.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '').padRight(3, 'X').substring(0, 6),
                        libelle: v['libelle']!,
                        compte: v['compte']!,
                        activite: v['activite']!.isEmpty ? null : v['activite']),
                    succes: 'Nature enregistrée.');
                if (ok) maj(() {});
                return ok;
              });
          return AlertDialog(
            title: const Text('Natures de dépenses'),
            content: SizedBox(
              width: 520,
              height: 460,
              child: ListView(children: [
                for (final n in natures)
                  ListTile(
                    dense: true,
                    leading: Icon(iconeNature(n['code'] as String)),
                    title: Text(n['libelle'] as String),
                    subtitle: Text('Compte ${n['compte']}'),
                    onTap: () => editer(n),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        reussir(c, () => Depenses.retirerNature(s, _entite, n['code'] as String), succes: 'Nature retirée.');
                        maj(() {});
                      },
                    ),
                  ),
              ]),
            ),
            actions: [
              TextButton.icon(onPressed: () => editer(), icon: const Icon(Icons.add), label: const Text('Ajouter')),
              FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Fermer')),
            ],
          );
        }),
      );
}

/// Dépense en deux gestes : la nature est déjà choisie, il reste le montant.
void nouvelleDepenseNature(BuildContext context,
    {required String entite, required String nature, String beneficiaire = '', int? montant}) {
  final etat = Etat.lire(context);
  final b = etat.base!;
  final n = b.ligne('SELECT * FROM natures_depenses WHERE code=? AND entite=?', [nature, entite]);
  final benef = TextEditingController(text: beneficiaire), motif = TextEditingController(), m = TextEditingController(text: montant == null ? '' : '$montant');
  final ref = TextEditingController();
  final tresos = b.lignes('SELECT * FROM tresoreries WHERE entite=? AND actif=1 ORDER BY centrale DESC, type, id', [entite]);
  String? treso = () {
    try {
      return Tresorerie.caisseDe(b, entite);
    } on RegleMetier {
      return tresos.isEmpty ? null : tresos.first['id'] as String;
    }
  }();
  Map<String, Object?>? fichier;
  showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, maj) {
      final type = treso == null ? null : tresos.firstWhere((t) => t['id'] == treso, orElse: () => tresos.first)['type'];
      return AlertDialog(
        title: Text(n == null ? 'Dépense' : n['libelle'] as String),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ChampMontant(controleur: m),
              const SizedBox(height: 10),
              TextField(controller: benef, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Payé à (bénéficiaire)')),
              const SizedBox(height: 10),
              TextField(controller: motif, decoration: const InputDecoration(labelText: 'Précision (facultatif)', hintText: 'ex. facture de mars')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: treso,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Payé par'),
                items: [for (final t in tresos) DropdownMenuItem(value: t['id'] as String, child: Text(t['libelle'] as String, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => maj(() => treso = v),
              ),
              if (type == 'momo' || type == 'banque') ...[
                const SizedBox(height: 10),
                TextField(controller: ref, decoration: const InputDecoration(labelText: 'Référence (transaction, chèque)')),
              ],
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: BoutonPieceJointe(fichier: fichier, onChanged: (f) => maj(() => fichier = f))),
              Text('Pièce obligatoire au-delà de ${fcfa(b.paramInt('seuil_piece_jointe'))} ; validation de la direction au-delà de '
                  '${fcfa(b.paramInt('seuil_validation_depense'))}.', style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(
            onPressed: treso == null
                ? null
                : () {
                    if (executer(
                            c,
                            () => Tresorerie.depense(Etat.lire(c).session!,
                                entite: entite,
                                beneficiaire: benef.text.trim().isEmpty ? (n?['libelle'] as String? ?? 'Divers') : benef.text,
                                motif: motif.text,
                                nature: nature,
                                montant: lireMontant(m),
                                tresorerie: treso!,
                                reference: ref.text.trim().isEmpty ? null : ref.text.trim(),
                                fichier: fichier),
                            succes: 'Dépense enregistrée.') !=
                        null) {
                      Navigator.pop(c);
                    }
                  },
            child: const Text('Enregistrer'),
          ),
        ],
      );
    }),
  );
}
