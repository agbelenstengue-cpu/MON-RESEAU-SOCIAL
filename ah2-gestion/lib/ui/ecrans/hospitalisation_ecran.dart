/// Hospitalisation : occupation des lits, admission, fiche de séjour
/// (actes, produits, facture), sortie ; paramétrage des lits.
library;

import 'package:material_ui/material_ui.dart';

import '../../modules/actes/actes.dart';
import '../../modules/hospitalisation/hospitalisation.dart';
import '../../modules/patients/patients.dart';
import '../../modules/tresorerie/tresorerie.dart';
import '../../noyau/outils.dart';
import '../../pdf/documents.dart';
import '../../rapports/etats_stocks_hospitalisation.dart';
import '../etat_app.dart';
import '../theme.dart';
import '../widgets/commun.dart';
import '../widgets/formulaire.dart';
import '../widgets/pdf_ui.dart';
import 'patients.dart';
import 'stocks_ecran.dart';

class EcranHospitalisation extends StatelessWidget {
  const EcranHospitalisation({super.key});

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final s = etat.session!;
    final lits = Hospitalisation.occupation(b);
    final occupes = lits.where((l) => l['sejour'] != null).length;
    return PageContenu(enfants: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('$occupes lit(s) occupé(s) sur ${lits.length}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: () => afficherPdf(context, () => Documents.rapport(b, EtatsHospitalisation.occupation(b, dateIso(b.maintenant))), 'Occupation des lits'),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('État des hospitalisés'),
        ),
        if (etat.estCentral && s.peut('parametrage', 'creer'))
          OutlinedButton.icon(onPressed: () => _lit(context, null), icon: const Icon(Icons.bed_outlined), label: const Text('Ajouter un lit')),
      ]),
      const SizedBox(height: 16),
      if (lits.isEmpty) const EtatVide('Aucun lit : ajoutez les lits (PC central).'),
      Wrap(spacing: 12, runSpacing: 12, children: [
        for (final l in lits)
          SizedBox(
            width: 260,
            child: Carte(
              onTap: l['sejour'] != null
                  ? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FicheSejour(id: l['sejour'] as String)))
                  : (s.peut('hospitalisation', 'creer') ? () => _admettre(context, l['code'] as String) : null),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('${l['chambre']} · lit ${l['code']}', style: const TextStyle(fontWeight: FontWeight.bold))),
                  Pastille(l['sejour'] == null ? 'Libre' : 'Occupé', couleur: l['sejour'] == null ? Couleurs.hausse : Couleurs.stable),
                ]),
                Text('${l['categorie']} · ${fcfa(l['tarif_journalier'] as int)} par jour', style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                Text(l['sejour'] == null ? 'Appuyez pour admettre un patient' : '${l['nom']} ${l['prenoms']}',
                    style: TextStyle(fontWeight: l['sejour'] == null ? FontWeight.normal : FontWeight.bold)),
                if (l['sejour'] != null) Text('Entré le ${dateFr(depuisIso(l['date_entree'] as String))}', style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ),
      ]),
    ]);
  }

  void _lit(BuildContext context, Map<String, Object?>? l) => formulaire(context, 'Lit', [
        Champ('code', 'Code du lit (ex. C1-L1)', initial: (l?['code'] ?? '') as String, modifiable: l == null),
        Champ('chambre', 'Chambre', initial: (l?['chambre'] ?? '') as String),
        Champ('categorie', 'Catégorie', initial: (l?['categorie'] ?? 'Standard') as String),
        Champ('tarif', 'Tarif journalier (FCFA)', initial: '${l?['tarif_journalier'] ?? ''}', nombre: true),
      ], (c, v) => reussir(c, () => Hospitalisation.enregistrerLit(Etat.lire(c).session!,
          code: v['code']!, chambre: v['chambre']!, categorie: v['categorie']!, tarif: int.tryParse(v['tarif']!) ?? -1), succes: 'Lit enregistré.'));

  Future<void> _admettre(BuildContext context, String lit) async {
    final patient = await choisirPatient(context);
    if (patient == null || !context.mounted) return;
    await formulaire(context, 'Admission au lit $lit', [
      const Champ('caution', 'Caution encaissée (FCFA)', nombre: true, initial: '0'),
      Champ('mode', 'Mode de paiement de la caution', choix: [for (final m in Modes.encaissables) (m, Modes.libelles[m]!)]),
      const Champ('reference', 'Référence (mobile money)'),
    ], (c, v) {
      final op = executer(
          c,
          () => Hospitalisation.admettre(Etat.lire(c).session!,
              patient: patient, lit: lit, caution: int.tryParse(v['caution']!) ?? 0, mode: v['mode']!, reference: v['reference']!.isEmpty ? null : v['reference']),
          succes: 'Patient admis.');
      if (op != null && op.piece != null) Future.microtask(() => context.mounted ? afficherRecu(context, op.uuid) : null);
      return op != null;
    }, bouton: 'Admettre');
  }
}

class FicheSejour extends StatelessWidget {
  final String id;
  const FicheSejour({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final s = etat.session!;
    final sit = Hospitalisation.situation(b, id);
    final se = sit['sejour'] as Map;
    final p = Patients.lire(b, se['patient'] as String);
    final enCours = se['date_sortie'] == null;
    return Scaffold(
      appBar: AppBar(title: Text('${Patients.libelle(s, p)} · séjour ${se['numero']}')),
      body: PageContenu(largeurMax: 900, enfants: [
        Wrap(spacing: 12, runSpacing: 12, children: [
          SizedBox(width: 200, child: CarteIndicateur(libelle: 'Journées', valeur: '${sit['journees']}', detail: fcfa(sit['montant_journees'] as int))),
          SizedBox(width: 200, child: CarteIndicateur(libelle: 'Actes', valeur: fcfa(sit['total_actes'] as int))),
          SizedBox(width: 200, child: CarteIndicateur(libelle: 'Produits', valeur: fcfa(sit['total_produits'] as int))),
          SizedBox(width: 200, child: CarteIndicateur(libelle: 'Caution', valeur: fcfa(se['caution'] as int))),
          SizedBox(
              width: 200,
              child: CarteIndicateur(
                  libelle: (sit['reste'] as int) >= 0 ? 'Reste à payer' : 'À rembourser', valeur: fcfa((sit['reste'] as int).abs()))),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (enCours && s.peut('actes', 'creer')) FilledButton.icon(onPressed: () => _acte(context), icon: const Icon(Icons.add), label: const Text('Ajouter un acte')),
          if (enCours && s.peut('stocks', 'creer'))
            OutlinedButton.icon(
                onPressed: () => ouvrirSortieStock(context, stock: 'PHM', type: 'delivrance_sejour', sejour: id),
                icon: const Icon(Icons.medication_outlined),
                label: const Text('Délivrer un médicament')),
          OutlinedButton.icon(
            onPressed: () => afficherPdf(context, () => Documents.rapport(b, EtatsHospitalisation.facture(b, id)), 'Facture ${se['numero']}'),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Facture récapitulative'),
          ),
          if (enCours && s.peut('hospitalisation', 'creer'))
            OutlinedButton.icon(
              onPressed: () async {
                if (await confirmer(context, 'Enregistrer la sortie ? La facture est établie, la caution déduite et l’éventuel excédent remboursé.') &&
                    context.mounted) {
                  reussir(context, () => Hospitalisation.sortir(s, id), succes: 'Sortie enregistrée.');
                }
              },
              icon: const Icon(Icons.logout),
              label: const Text('Sortie du patient'),
            ),
        ]),
        const SizedBox(height: 16),
        const TitreSection('Actes du séjour'),
        Card(
          child: Column(children: [
            for (final a in (sit['actes'] as List).cast<Map>())
              ListTile(dense: true, title: Text('${a['libelle']}'), subtitle: Text(dateFr(depuisIso(a['date'] as String))), trailing: Text(fcfa(a['montant'] as int))),
          ]),
        ),
        const SizedBox(height: 12),
        const TitreSection('Produits délivrés'),
        Card(
          child: Column(children: [
            for (final m in (sit['produits'] as List).cast<Map>())
              ListTile(dense: true, title: Text('${m['designation']} × ${-(m['quantite'] as int)}'), subtitle: Text('lot ${m['lot']} · ${dateFr(depuisIso(m['date'] as String))}')),
          ]),
        ),
      ]),
    );
  }

  void _acte(BuildContext context) {
    final b = Etat.lire(context).base!;
    final actes = [
      for (final a in b.lignes('SELECT c.code, c.libelle, t.libelle AS service FROM actes_catalogue c JOIN activites t ON t.code=c.activite WHERE c.actif=1 AND t.actif=1 ORDER BY t.libelle, c.libelle'))
        (a['code'] as String, '${a['service']} : ${a['libelle']}')
    ];
    formulaire(context, 'Acte pendant le séjour', [
      Champ('acte', 'Acte', choix: actes),
      const Champ('quantite', 'Quantité', nombre: true, initial: '1'),
      const Champ('praticien', 'Praticien'),
    ], (c, v) {
      final activite = b.valeur('SELECT activite FROM actes_catalogue WHERE code=?', [v['acte']]) as String;
      return reussir(
          c,
          () => Actes.enregistrer(Etat.lire(c).session!,
              activite: activite,
              actes: [DemandeActe(v['acte']!, quantite: int.tryParse(v['quantite']!) ?? 1)],
              mode: Modes.credit,
              sejour: id,
              praticien: v['praticien']!.isEmpty ? null : v['praticien']),
          succes: 'Acte ajouté au séjour.');
    });
  }
}
