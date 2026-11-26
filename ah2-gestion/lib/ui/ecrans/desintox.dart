/// Désintoxication : liste de travail, inscription, fiche patient (maquette),
/// versements progressifs, sortie, rapport de sortie, archives, réadmission.
library;

import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../modules/desintox/desintox.dart';
import '../../modules/patients/patients.dart';
import '../../modules/tresorerie/tresorerie.dart';
import '../../noyau/outils.dart';
import '../../pdf/documents.dart';
import '../etat_app.dart';
import '../theme.dart';
import '../widgets/commun.dart';
import '../widgets/pdf_ui.dart';
import 'patients.dart';

class EcranDesintox extends StatefulWidget {
  const EcranDesintox({super.key});
  @override
  State<EcranDesintox> createState() => _EcranDesintoxState();
}

class _EcranDesintoxState extends State<EcranDesintox> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final s = etat.session!;
    Widget liste(String onglet) {
      final l = Desintox.listeTravail(b, onglet: onglet, recherche: _q);
      if (l.isEmpty) return const EtatVide('Aucun patient dans cette liste.');
      return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
        for (final sit in l) _CarteDossier(sit),
      ]);
    }

    return DefaultTabController(
      length: 3,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Nom ou numéro de dossier'),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            const SizedBox(width: 12),
            if (s.peut('desintox', 'creer'))
              MediaQuery.sizeOf(context).width < 600
                  ? IconButton.filled(tooltip: 'Inscrire', onPressed: () => _inscrire(context), icon: const Icon(Icons.add))
                  : FilledButton.icon(onPressed: () => _inscrire(context), icon: const Icon(Icons.add), label: const Text('Inscrire')),
          ]),
        ),
        const TabBar(isScrollable: true, tabs: [Tab(text: 'En cours'), Tab(text: 'Sortis avec solde dû'), Tab(text: 'Archives')]),
        Expanded(child: TabBarView(children: [liste('en_cours'), liste('solde_du'), liste('archives')])),
      ]),
    );
  }

  Future<void> _inscrire(BuildContext context) async {
    final patient = await choisirPatient(context);
    if (patient == null || !context.mounted) return;
    final b = Etat.lire(context).base!;
    final programmes = b.lignes('SELECT * FROM programmes_desintox ORDER BY code');
    String programme = programmes.first['code'] as String;
    final responsables = <Responsable>[];
    final nom = TextEditingController(), lien = TextEditingController(), tel = TextEditingController();
    final montant = TextEditingController();
    final motif = TextEditingController();
    final duree = TextEditingController(text: '${programmes.first['duree_jours']}');
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, maj) {
        final d = int.tryParse(duree.text) ?? 0;
        final calcule = d > 0 ? Desintox.montantProgramme(b, programme, d) : 0;
        return AlertDialog(
          title: const Text('Inscription en désintoxication'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('Patient : ${Patients.libelle(Etat.lire(c).session!, Patients.lire(b, patient))}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                const Text('Programme'),
                const SizedBox(height: 6),
                ChoixPastilles<String>(
                  options: [for (final p in programmes) (p['code'] as String, p['libelle'] as String)],
                  valeur: programme,
                  onChanged: (v) => maj(() {
                    programme = v;
                    duree.text = '${programmes.firstWhere((p) => p['code'] == v)['duree_jours']}';
                  }),
                ),
                const SizedBox(height: 12),
                TextField(controller: duree, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Durée prévue (jours)'),
                    onChanged: (_) => maj(() {})),
                const SizedBox(height: 8),
                Text('Montant du programme : ${fcfa(calcule)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ChampMontant(controleur: montant, libelle: 'Autre montant (rôle autorisé, facultatif)'),
                if (montant.text.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  TextField(controller: motif, decoration: const InputDecoration(labelText: 'Motif de la modification du montant')),
                ],
                const SizedBox(height: 16),
                const Text('Responsables du paiement', style: TextStyle(fontWeight: FontWeight.w700)),
                for (final r in responsables) ListTile(dense: true, title: Text('${r.nom} · ${r.lien}'), subtitle: Text(r.telephone)),
                Row(children: [
                  Expanded(child: TextField(controller: nom, decoration: const InputDecoration(labelText: 'Nom'))),
                  const SizedBox(width: 8),
                  SizedBox(width: 100, child: TextField(controller: lien, decoration: const InputDecoration(labelText: 'Lien'))),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: tel, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Téléphone'))),
                  IconButton(
                    tooltip: 'Ajouter ce responsable',
                    icon: const Icon(Icons.person_add_alt),
                    onPressed: () => maj(() {
                      if (nom.text.trim().isEmpty) return;
                      responsables.add(Responsable(nom.text.trim(), lien.text.trim(), tel.text.trim()));
                      nom.clear();
                      lien.clear();
                      tel.clear();
                    }),
                  ),
                ]),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                if (nom.text.trim().isNotEmpty) responsables.add(Responsable(nom.text.trim(), lien.text.trim(), tel.text.trim()));
                final op = executer(
                    c,
                    () => Desintox.inscrire(Etat.lire(c).session!,
                        patient: patient,
                        programme: programme,
                        duree: int.tryParse(duree.text),
                        montantTotal: montant.text.isEmpty ? null : lireMontant(montant),
                        motifMontant: motif.text,
                        responsables: responsables),
                    succes: 'Inscription enregistrée.');
                if (op != null) {
                  Navigator.pop(c);
                  ouvrirFicheDesintox(context, op.d<String>('id'));
                }
              },
              child: const Text('Inscrire'),
            ),
          ],
        );
      }),
    );
  }
}

class _CarteDossier extends StatelessWidget {
  final SituationDesintox sit;
  const _CarteDossier(this.sit);

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final p = Patients.lire(etat.base!, sit.dossier['patient'] as String);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Carte(
        padding: const EdgeInsets.all(16),
        onTap: () => ouvrirFicheDesintox(context, sit.dossier['id'] as String),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(Patients.libelle(etat.session!, p), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            _badge(sit),
          ]),
          const SizedBox(height: 4),
          Text('${sit.dossier['numero']} · entrée le ${dateFr(depuisIso(sit.dossier['date_entree'] as String))}',
              style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: sit.pourcentage / 100, minHeight: 8),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 16, children: [
            Text('Total ${fcfa(sit.total)}'),
            Text('Versé ${fcfa(sit.verse)}', style: const TextStyle(color: Couleurs.hausse, fontWeight: FontWeight.w600)),
            Text(sit.reste == 0 ? 'Soldé' : 'Reste ${fcfa(sit.reste)}',
                style: TextStyle(color: sit.reste == 0 ? Couleurs.hausse : Couleurs.baisse, fontWeight: FontWeight.w700)),
          ]),
        ]),
      ),
    );
  }
}

Widget _badge(SituationDesintox s) => switch (s.statut) {
      'en_cours' => const Pastille('En cours', couleur: Couleurs.primaire),
      'sorti_solde_du' => const Pastille('Sorti · solde dû', couleur: Couleurs.baisse),
      'sorti_solde' => Pastille('Sorti · soldé (archivage le ${dateFr(depuisIso(s.dateArchivage!))})', couleur: Couleurs.hausse),
      _ => const Pastille('Archivé', couleur: Color(0xFF5B6B66)),
    };

void ouvrirFicheDesintox(BuildContext context, String id) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FicheDesintox(id: id)));

/// Fiche patient en désintoxication (maquette).
class FicheDesintox extends StatelessWidget {
  final String id;
  const FicheDesintox({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final s = etat.session!;
    final sit = Desintox.situation(b, id);
    final d = sit.dossier;
    final p = Patients.lire(b, d['patient'] as String);
    final prog = b.ligne('SELECT * FROM programmes_desintox WHERE code=?', [d['programme']])!;
    final resp = (jsonDecode(d['responsables'] as String) as List).cast<Map>();
    final echeances = Desintox.echeancesImpayees(b).where((e) => e['dossier'] == id).toList();
    final enCours = d['date_sortie'] == null;
    return Scaffold(
      appBar: AppBar(title: Text(Patients.libelle(s, p))),
      bottomNavigationBar: sit.reste > 0 && s.peut('desintox', 'creer')
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                    onPressed: () => _verser(context, sit, resp), icon: const Icon(Icons.add), label: const Text('Nouveau versement')),
              ),
            )
          : null,
      body: PageContenu(largeurMax: 760, enfants: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Couleurs.barreLaterale, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text('Dossier ${d['numero']} · ${prog['libelle']}', style: const TextStyle(color: Color(0xFFA9C2BA))),
              ),
              _badge(sit),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Text('Payé : ${sit.pourcentage} %', style: const TextStyle(color: Colors.white)),
              const Spacer(),
              Text('Entrée le ${dateFr(depuisIso(d['date_entree'] as String))}', style: const TextStyle(color: Color(0xFFD3E2DC))),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: sit.pourcentage / 100,
                minHeight: 12,
                color: const Color(0xFF4ADE80),
                backgroundColor: const Color(0xFF1E4A40),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: CarteIndicateur(libelle: 'Montant total', valeur: fcfa(sit.total))),
          const SizedBox(width: 8),
          Expanded(child: CarteIndicateur(libelle: 'Total versé', valeur: fcfa(sit.verse), couleurDetail: Couleurs.hausse)),
          const SizedBox(width: 8),
          Expanded(child: CarteIndicateur(libelle: 'Reste à payer', valeur: sit.reste == 0 ? 'Soldé' : fcfa(sit.reste))),
        ]),
        for (final e in echeances)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Couleurs.alerteOrangeFond, border: Border.all(color: Couleurs.alerteOrangeBord), borderRadius: BorderRadius.circular(14)),
            child: Text('Échéance non reçue : ${fcfa(e['manquant'] as int)} prévus le ${dateFr(depuisIso(e['date'] as String))}',
                style: const TextStyle(fontWeight: FontWeight.w600, color: Couleurs.encre)),
          ),
        const SizedBox(height: 12),
        Carte(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const TitreSection('Responsables du paiement'),
            for (final r in resp)
              ListTile(contentPadding: EdgeInsets.zero, dense: true, title: Text('${r['nom']} · ${r['lien']}'), trailing: Text('${r['telephone']}')),
          ]),
        ),
        const SizedBox(height: 12),
        Carte(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const TitreSection('Versements'),
            if (sit.versements.isEmpty) const EtatVide('Aucun versement.'),
            for (final v in sit.versements.reversed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(fcfa(v['montant'] as int), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${v['piece']} · ${v['payeur']} · ${Modes.libelles[v['mode']]}'),
                trailing: Text(dateFr(depuisIso(v['date'] as String))),
                onTap: () => afficherRecu(context, v['uuid_op'] as String),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, children: [
          OutlinedButton.icon(
            onPressed: () => afficherPdf(context, () => Documents.rapportSortie(b, id), 'Rapport de sortie ${d['numero']}'),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Rapport de sortie du patient (PDF)'),
          ),
          if (enCours && s.peut('desintox', 'creer'))
            OutlinedButton.icon(onPressed: () => _sortie(context), icon: const Icon(Icons.logout), label: const Text('Enregistrer la sortie')),
          if (s.peut('desintox', 'valider'))
            OutlinedButton.icon(onPressed: () => _montant(context, sit), icon: const Icon(Icons.edit_outlined), label: const Text('Modifier le montant')),
        ]),
      ]),
    );
  }

  void _verser(BuildContext context, SituationDesintox sit, List<Map> resp) {
    final m = TextEditingController();
    final ref = TextEditingController();
    final autre = TextEditingController();
    String? payeur = resp.isEmpty ? null : resp.first['nom'] as String;
    String mode = Modes.especes;
    showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, maj) => AlertDialog(
          title: const Text('Nouveau versement'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                ChampMontant(controleur: m, aide: 'Reste à payer : ${fcfa(sit.reste)}'),
                const SizedBox(height: 12),
                const Text('Payé par'),
                const SizedBox(height: 6),
                ChoixPastilles<String?>(
                  options: [for (final r in resp) (r['nom'] as String, r['nom'] as String), (null, 'Autre personne')],
                  valeur: payeur,
                  onChanged: (v) => maj(() => payeur = v),
                ),
                if (payeur == null) ...[
                  const SizedBox(height: 8),
                  TextField(controller: autre, decoration: const InputDecoration(labelText: 'Nom de la personne qui paie')),
                ],
                const SizedBox(height: 12),
                ChoixPastilles<String>(
                  options: [for (final x in Modes.encaissables) (x, Modes.libelles[x]!)],
                  valeur: mode,
                  onChanged: (v) => maj(() => mode = v),
                ),
                if (mode != Modes.especes) ...[
                  const SizedBox(height: 8),
                  TextField(controller: ref, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Référence de transaction')),
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
                    () => Desintox.verser(Etat.lire(c).session!,
                        dossierId: id,
                        montant: lireMontant(m),
                        payeur: payeur ?? autre.text,
                        mode: mode,
                        reference: ref.text.isEmpty ? null : ref.text),
                    succes: 'Versement enregistré.');
                if (op != null) {
                  Navigator.pop(c);
                  afficherRecu(context, op.uuid);
                }
              },
              child: const Text('Encaisser et émettre le reçu'),
            ),
          ],
        ),
      ),
    );
  }

  void _sortie(BuildContext context) {
    String motif = Desintox.motifsSortie.first;
    showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, maj) => AlertDialog(
          title: const Text('Sortie du programme'),
          content: ChoixPastilles<String>(
            options: [for (final m in Desintox.motifsSortie) (m, Desintox.libellesMotifs[m]!)],
            valeur: motif,
            onChanged: (v) => maj(() => motif = v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                if (executer(c, () => Desintox.sortir(Etat.lire(c).session!, id, motif: motif), succes: 'Sortie enregistrée.') != null) {
                  Navigator.pop(c);
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  void _montant(BuildContext context, SituationDesintox sit) {
    final m = TextEditingController(text: '${sit.total}');
    final motif = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Modifier le montant total'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ChampMontant(controleur: m, aide: 'Déjà versé : ${fcfa(sit.verse)}'),
            const SizedBox(height: 12),
            TextField(controller: motif, decoration: const InputDecoration(labelText: 'Motif (obligatoire, tracé)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (executer(c, () => Desintox.modifierMontant(Etat.lire(c).session!, id, lireMontant(m), motif.text),
                      succes: 'Montant modifié.') !=
                  null) {
                Navigator.pop(c);
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}
