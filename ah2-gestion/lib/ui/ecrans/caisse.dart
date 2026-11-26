/// Caisse et trésorerie : soldes, brouillard, dépenses, mouvements internes,
/// arrêté de caisse avec billetage, validation des dépenses.
library;

import 'package:material_ui/material_ui.dart';

import '../../modules/rapports/rapports.dart';
import '../../modules/tresorerie/tresorerie.dart';
import '../../noyau/outils.dart';
import '../../pdf/documents.dart';
import '../etat_app.dart';
import '../theme.dart';
import '../widgets/commun.dart';
import '../widgets/pdf_ui.dart';
import '../widgets/piece_jointe.dart';

class EcranCaisse extends StatefulWidget {
  const EcranCaisse({super.key});
  @override
  State<EcranCaisse> createState() => _EcranCaisseState();
}

class _EcranCaisseState extends State<EcranCaisse> {
  String _entite = 'CS';
  String? _selection;

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final s = etat.session!;
    final tresos = b.lignes('SELECT * FROM tresoreries WHERE entite=? AND actif=1 ORDER BY centrale DESC, type, id', [_entite]);
    _selection ??= () {
      try {
        return Tresorerie.caisseDe(b, _entite);
      } on RegleMetier {
        return tresos.isEmpty ? null : tresos.first['id'] as String;
      }
    }();
    if (!tresos.any((t) => t['id'] == _selection)) _selection = tresos.isEmpty ? null : tresos.first['id'] as String;
    final aujourdhui = dateIso(b.maintenant);
    final br = _selection == null ? null : Rapports.brouillard(b, _selection!, aujourdhui);
    final attente = b.lignes("SELECT * FROM depenses WHERE statut='en_attente' AND annule=0 AND entite=? ORDER BY date", [_entite]);
    return PageContenu(enfants: [
      Row(children: [
        Expanded(child: ChoixPastilles<String>(
          options: const [('CS', 'Centre de santé'), ('ONG', 'ONG')],
          valeur: _entite,
          onChanged: (v) => setState(() {
            _entite = v;
            _selection = null;
          }),
        )),
      ]),
      const SizedBox(height: 16),
      Wrap(spacing: 12, runSpacing: 12, children: [
        for (final t in tresos)
          SizedBox(
            width: 250,
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: t['id'] == _selection ? Couleurs.primaire : Colors.transparent, width: 2),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => setState(() => _selection = t['id'] as String),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t['libelle'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('Compte ${t['compte']}', style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 8),
                    Text(fcfa(Tresorerie.solde(b, t['id'] as String)), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 16),
      Wrap(spacing: 12, runSpacing: 12, children: [
        if (s.peut('depenses', 'creer'))
          FilledButton.icon(onPressed: () => nouvelleDepense(context, entite: _entite), icon: const Icon(Icons.receipt_long), label: const Text('Nouvelle dépense')),
        if (s.peut('caisse', 'creer'))
          OutlinedButton.icon(onPressed: () => _virement(context), icon: const Icon(Icons.swap_horiz), label: const Text('Mouvement interne')),
        if (s.peut('caisse', 'creer') && _selection != null && Tresorerie.compte(b, _selection!)['type'] == 'caisse')
          OutlinedButton.icon(onPressed: () => _arrete(context, _selection!), icon: const Icon(Icons.calculate_outlined), label: const Text('Arrêté de caisse')),
      ]),
      if (attente.isNotEmpty) ...[
        const SizedBox(height: 20),
        TitreSection('Dépenses en attente de validation', sousTitre: '${attente.length}'),
        const SizedBox(height: 8),
        Card(
          child: Column(children: [
            for (final d in attente)
              ListTile(
                title: Text('${d['motif']} – ${d['beneficiaire']}'),
                subtitle: Text('${d['piece']} · ${dateFr(depuisIso(d['date'] as String))}'),
                trailing: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(fcfa(d['montant'] as int), style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (s.peut('depenses', 'valider')) ...[
                    IconButton(
                      tooltip: 'Valider',
                      icon: const Icon(Icons.check_circle_outline, color: Couleurs.hausse),
                      onPressed: () => executer(context, () => Tresorerie.validerDepense(s, d['uuid_op'] as String), succes: 'Dépense validée et payée.'),
                    ),
                    IconButton(
                      tooltip: 'Rejeter',
                      icon: const Icon(Icons.cancel_outlined, color: Couleurs.baisse),
                      onPressed: () => executer(context,
                          () => Tresorerie.validerDepense(s, d['uuid_op'] as String, accepter: false, motif: 'Rejetée par la direction'),
                          succes: 'Dépense rejetée.'),
                    ),
                  ],
                ]),
              ),
          ]),
        ),
      ],
      if (br != null) ...[
        const SizedBox(height: 20),
        TitreSection('Brouillard du jour', sousTitre: '${(br['caisse'] as Map)['libelle']} · ${dateFr(b.maintenant)}'),
        const SizedBox(height: 8),
        Card(
          child: Column(children: [
            ListTile(dense: true, title: const Text('Solde d’ouverture'), trailing: Text(fcfa(br['ouverture'] as int))),
            for (final m in (br['mouvements'] as List).cast<Map>())
              ListTile(
                dense: true,
                title: Text(m['libelle'] as String),
                subtitle: Text('${heureFr(DateTime.parse(m['horodatage'] as String))} · ${m['piece'] ?? ''}'),
                trailing: Text(fcfa(m['montant'] as int),
                    style: TextStyle(fontWeight: FontWeight.w700, color: (m['montant'] as int) < 0 ? Couleurs.baisse : Couleurs.hausse)),
              ),
            ListTile(
              title: const Text('Solde', style: TextStyle(fontWeight: FontWeight.w700)),
              trailing: Text(fcfa(br['cloture'] as int), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      ],
    ]);
  }

  void _virement(BuildContext context) {
    final b = Etat.lire(context).base!;
    final tresos = b.lignes('SELECT * FROM tresoreries WHERE entite=? AND actif=1 ORDER BY centrale DESC, type, id', [_entite]);
    String? source = _selection, destination;
    final m = TextEditingController(), ref = TextEditingController(), remis = TextEditingController(), recu = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, maj) {
        final caisses = source != null &&
            destination != null &&
            Tresorerie.compte(b, source!)['type'] == 'caisse' &&
            Tresorerie.compte(b, destination!)['type'] == 'caisse';
        DropdownMenuItem<String> item(Map t) => DropdownMenuItem(value: t['id'] as String, child: Text(t['libelle'] as String));
        return AlertDialog(
          title: const Text('Mouvement interne'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                    initialValue: source, items: [for (final t in tresos) item(t)], onChanged: (v) => maj(() => source = v),
                    decoration: const InputDecoration(labelText: 'De')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                    initialValue: destination, items: [for (final t in tresos) item(t)], onChanged: (v) => maj(() => destination = v),
                    decoration: const InputDecoration(labelText: 'Vers')),
                const SizedBox(height: 10),
                ChampMontant(controleur: m),
                const SizedBox(height: 10),
                if (caisses) ...[
                  TextField(controller: remis, decoration: const InputDecoration(labelText: 'Remis par')),
                  const SizedBox(height: 10),
                  TextField(controller: recu, decoration: const InputDecoration(labelText: 'Reçu par')),
                ] else
                  TextField(controller: ref, decoration: const InputDecoration(labelText: 'Référence (bordereau, transaction)')),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                if (source == null || destination == null) return;
                if (executer(
                        c,
                        () => Tresorerie.virement(Etat.lire(c).session!,
                            source: source!,
                            destination: destination!,
                            montant: lireMontant(m),
                            reference: ref.text.isEmpty ? null : ref.text,
                            remisPar: remis.text.isEmpty ? null : remis.text,
                            recuPar: recu.text.isEmpty ? null : recu.text),
                        succes: 'Mouvement enregistré (pièce à signer par les deux parties).') !=
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

  void _arrete(BuildContext context, String caisse) {
    final b = Etat.lire(context).base!;
    final coupures = Tresorerie.coupures(b);
    final champs = {for (final c in coupures) c: TextEditingController()};
    final motif = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, maj) {
        final total = champs.entries.fold<int>(0, (t, e) => t + e.key * (int.tryParse(e.value.text) ?? 0));
        final theorique = Tresorerie.solde(b, caisse);
        final ecart = total - theorique;
        return AlertDialog(
          title: const Text('Arrêté de caisse · billetage'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final e in champs.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      SizedBox(width: 110, child: Text(fcfa(e.key), style: const TextStyle(fontWeight: FontWeight.w600))),
                      Expanded(
                        child: TextField(
                          controller: e.value,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Nombre', isDense: true),
                          onChanged: (_) => maj(() {}),
                        ),
                      ),
                    ]),
                  ),
                const Divider(),
                ListTile(dense: true, title: const Text('Total compté'), trailing: Text(fcfa(total))),
                ListTile(dense: true, title: const Text('Solde théorique'), trailing: Text(fcfa(theorique))),
                ListTile(
                  dense: true,
                  title: Text(ecart < 0 ? 'Manquant' : (ecart > 0 ? 'Excédent' : 'Écart')),
                  trailing: Text(fcfa(ecart), style: TextStyle(fontWeight: FontWeight.w800, color: ecart == 0 ? Couleurs.hausse : Couleurs.baisse)),
                ),
                if (ecart != 0) TextField(controller: motif, decoration: const InputDecoration(labelText: "Motif de l'écart (obligatoire)")),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                final op = executer(
                    c,
                    () => Tresorerie.arreterCaisse(Etat.lire(c).session!,
                        caisse: caisse,
                        billetage: {for (final e in champs.entries) e.key: int.tryParse(e.value.text) ?? 0},
                        motifEcart: motif.text.isEmpty ? null : motif.text),
                    succes: 'Arrêté enregistré.');
                if (op != null) {
                  Navigator.pop(c);
                  afficherPdf(context, () => Documents.arreteCaisse(b, op.uuid), op.piece ?? 'Arrêté');
                }
              },
              child: const Text('Valider l’arrêté'),
            ),
          ],
        );
      }),
    );
  }
}

/// Décaissement : bénéficiaire, motif, imputation, pièce jointe.
void nouvelleDepense(BuildContext context, {String entite = 'CS'}) {
  final etat = Etat.lire(context);
  final b = etat.base!;
  final beneficiaire = TextEditingController(), motif = TextEditingController(), m = TextEditingController();
  Map<String, Object?>? fichier;
  String ent = entite;
  String? compte;
  String? activite;
  showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, maj) {
      final comptes = b.lignes("SELECT numero, libelle FROM comptes WHERE entite=? AND numero LIKE '6%' AND actif=1 ORDER BY numero", [ent]);
      final activites = b.lignes('SELECT code, libelle FROM activites WHERE entite=? ORDER BY code', [ent]);
      compte ??= comptes.isEmpty ? null : comptes.first['numero'] as String;
      activite ??= activites.last['code'] as String;
      return AlertDialog(
        title: const Text('Nouvelle dépense'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ChoixPastilles<String>(
                options: const [('CS', 'Centre de santé'), ('ONG', 'ONG')],
                valeur: ent,
                onChanged: (v) => maj(() {
                  ent = v;
                  compte = null;
                  activite = null;
                }),
              ),
              const SizedBox(height: 10),
              TextField(controller: beneficiaire, decoration: const InputDecoration(labelText: 'Bénéficiaire')),
              const SizedBox(height: 10),
              TextField(controller: motif, decoration: const InputDecoration(labelText: 'Motif')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: compte,
                isExpanded: true,
                items: [for (final x in comptes) DropdownMenuItem(value: x['numero'] as String, child: Text('${x['numero']} · ${x['libelle']}'))],
                onChanged: (v) => maj(() => compte = v),
                decoration: const InputDecoration(labelText: 'Imputation (compte de charge)'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: activite,
                isExpanded: true,
                items: [for (final x in activites) DropdownMenuItem(value: x['code'] as String, child: Text(x['libelle'] as String))],
                onChanged: (v) => maj(() => activite = v),
                decoration: const InputDecoration(labelText: 'Activité'),
              ),
              const SizedBox(height: 10),
              ChampMontant(controleur: m, aide: 'Validation de la direction au-delà de ${fcfa(b.paramInt('seuil_validation_depense'))}'),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: BoutonPieceJointe(fichier: fichier, onChanged: (f) => maj(() => fichier = f)),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Obligatoire au-delà de ${fcfa(b.paramInt('seuil_piece_jointe'))}', style: const TextStyle(fontSize: 12)),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (compte == null || activite == null) return;
              if (executer(
                      c,
                      () => Tresorerie.depense(Etat.lire(c).session!,
                          entite: ent,
                          beneficiaire: beneficiaire.text,
                          motif: motif.text,
                          compteCharge: compte!,
                          activite: activite!,
                          montant: lireMontant(m),
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
