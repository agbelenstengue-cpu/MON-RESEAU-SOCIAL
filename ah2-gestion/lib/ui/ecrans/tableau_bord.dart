/// Page d'accueil = tableau de bord (§9, maquette « Accueil »).
library;

import 'package:material_ui/material_ui.dart';

import '../../modules/rapports/rapports.dart';
import '../../noyau/outils.dart';
import '../etat_app.dart';
import '../theme.dart';
import '../widgets/commun.dart';
import '../../rapports/etats_phase3.dart';
import '../../modules/depenses/depenses.dart';
import '../../modules/stocks/stocks.dart';
import 'assistants.dart';
import 'coquille.dart';
import 'depenses_ecran.dart';
import 'desintox.dart';

class EcranTableauBord extends StatelessWidget {
  const EcranTableauBord({super.key});

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final tb = Rapports.tableauDeBord(b);
    final jour = dateIso(b.maintenant);
    final rapport = Rapports.financierDuJour(b, jour);
    final sante = (tb['sante'] as List).cast<Map<String, Object?>>();
    final maxJour = sante.fold<int>(1, (m, s) => (s['jour'] as int) > m ? s['jour'] as int : m);
    final alertes = (tb['alertes'] as List).cast<Map<String, String>>();
    final treso = (tb['tresoreries'] as List).cast<Map<String, Object?>>();
    final t = Theme.of(context).textTheme;
    final larg = MediaQuery.sizeOf(context).width;
    return PageContenu(enfants: [
      Text('Situation au ${dateFr(b.maintenant)}',
          style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(rapport['note'] as String, style: t.bodyMedium?.copyWith(color: Theme.of(context).hintColor)),
      const SizedBox(height: 16),
      const CarteMiseEnRoute(),
      const _ActionsDuJour(),
      const SizedBox(height: 16),
      GridView.count(
        crossAxisCount: larg >= 1100 ? 4 : (larg >= 600 ? 2 : 2),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: larg >= 600 ? 1.9 : 1.25,
        children: [
          CarteIndicateur(
            libelle: 'Recettes du jour',
            valeur: fcfa(tb['recettes_jour'] as int),
            detail: 'Mois : ${fcfa(tb['recettes_mois'] as int)}',
          ),
          CarteIndicateur(
            libelle: 'Charges du jour',
            valeur: fcfa(tb['charges_jour'] as int),
            detail: 'Mois : ${fcfa(tb['charges_mois'] as int)}',
          ),
          CarteIndicateur(
            libelle: 'Créances patients',
            valeur: fcfa(tb['creances'] as int),
            detail: 'Comptes 411, désintox comprise',
          ),
          CarteIndicateur(
            libelle: 'Reste à encaisser (désintox)',
            valeur: fcfa(tb['desintox_reste'] as int),
            detail: '${tb['desintox_en_cours']} patient(s) en cours',
          ),
        ],
      ),
      const SizedBox(height: 16),
      Wrap(spacing: 16, runSpacing: 16, children: [
        SizedBox(
          width: larg >= 1100 ? 640 : double.infinity,
          child: Carte(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const TitreSection('Santé des activités', sousTitre: 'aujourd’hui vs moyenne des 4 dernières semaines'),
              const SizedBox(height: 12),
              for (final s in sante)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    SizedBox(width: larg < 600 ? 110 : 170, child: Text(s['libelle'] as String, overflow: TextOverflow.ellipsis)),
                    if (larg < 600) const Spacer() else Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: LinearProgressIndicator(
                          minHeight: 10,
                          value: (s['jour'] as int) / maxJour,
                          backgroundColor: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(width: 96, child: Text(fcfa(s['jour'] as int), textAlign: TextAlign.right)),
                    const SizedBox(width: 8),
                    Pastille(libelleTendance(s['tendance'] as String), couleur: couleurTendance(s['tendance'] as String)),
                  ]),
                ),
            ]),
          ),
        ),
        SizedBox(
          width: larg >= 1100 ? 440 : double.infinity,
          child: Carte(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const TitreSection('Trésorerie'),
              const SizedBox(height: 8),
              for (final c in treso.where((c) => (c['solde'] as int) != 0 || c['centrale'] == 1 || c['type'] != 'caisse'))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('${c['libelle']}'),
                  subtitle: Text(c['entite'] == 'CS' ? 'Centre de santé' : 'ONG'),
                  trailing: Text(fcfa(c['solde'] as int), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      Wrap(spacing: 16, runSpacing: 16, children: [
        SizedBox(
          width: larg >= 1100 ? 640 : double.infinity,
          child: Carte(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const TitreSection('Tendance sur 12 mois', sousTitre: 'recettes (vert) et charges (gris)'),
              const SizedBox(height: 12),
              Courbes12Mois(donnees: Previsions.douzeMois(b)),
            ]),
          ),
        ),
        SizedBox(
          width: larg >= 1100 ? 440 : double.infinity,
          child: Carte(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const TitreSection('Perspectives'),
              const SizedBox(height: 8),
              for (final ent in ['CS', 'ONG'])
                () {
                  final p30 = Previsions.tresorerie(b, ent, 30), p90 = Previsions.tresorerie(b, ent, 90);
                  final r = Previsions.resultatProjete(b, ent);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(ent == 'CS' ? 'Centre de santé' : 'ONG', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('Trésorerie prévue : ${fcfa(p30['solde_previsionnel'] as int)} à 30 jours, ${fcfa(p90['solde_previsionnel'] as int)} à 90 jours'),
                      Text('Résultat projeté fin d’exercice : ${fcfa(r['projete']!)}'),
                    ]),
                  );
                }(),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      Carte(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TitreSection('Alertes à traiter', sousTitre: alertes.isEmpty ? 'aucune' : '${alertes.length}'),
          const SizedBox(height: 12),
          if (alertes.isEmpty) const EtatVide('Tout est en ordre.', icone: Icons.check_circle_outline),
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final a in alertes)
              Container(
                width: larg < 600 ? double.infinity : 320,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: a['niveau'] == 'rouge' ? Couleurs.alerteRougeFond : Couleurs.alerteOrangeFond,
                  border: Border.all(color: a['niveau'] == 'rouge' ? Couleurs.alerteRougeBord : Couleurs.alerteOrangeBord),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a['titre']!, style: const TextStyle(fontWeight: FontWeight.w700, color: Couleurs.encre)),
                  const SizedBox(height: 4),
                  Text(a['detail']!, style: const TextStyle(color: Color(0xFF3D4A46))),
                ]),
              ),
          ]),
        ]),
      ),
    ]);
  }
}


/// Histogramme sobre recettes / charges sur 12 mois.
class Courbes12Mois extends StatelessWidget {
  final List<Map<String, Object>> donnees;
  const Courbes12Mois({super.key, required this.donnees});

  static const _mois = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

  @override
  Widget build(BuildContext context) {
    final max = donnees.fold<int>(1, (m, d) => [m, d['recettes'] as int, d['charges'] as int].reduce((a, b) => a > b ? a : b));
    final primaire = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 180,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final d in donnees)
          Expanded(
            child: Tooltip(
              message: '${d['mois']} : recettes ${fcfa(d['recettes'] as int)}, charges ${fcfa(d['charges'] as int)}',
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(width: 8, height: 140 * ((d['recettes'] as int).clamp(0, max)) / max, color: primaire),
                  const SizedBox(width: 2),
                  Container(width: 8, height: 140 * ((d['charges'] as int).clamp(0, max)) / max, color: const Color(0xFFB0B0B0)),
                ]),
                const SizedBox(height: 4),
                Text(_mois[int.parse((d['mois'] as String).substring(5)) - 1], style: const TextStyle(fontSize: 10)),
              ]),
            ),
          ),
      ]),
    );
  }
}


/// Les gestes du quotidien, à un toucher de l'accueil.
class _ActionsDuJour extends StatelessWidget {
  const _ActionsDuJour();
  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final s = etat.session!;
    final nav = Navigation.de(context);
    final aPayer = s.peut('depenses', 'creer') ? Depenses.aPayerCeMois(b).where((m) => m['payee'] != true).toList() : const <Map<String, Object?>>[];
    Widget action(IconData i, String t, VoidCallback f) => SizedBox(
          width: 168,
          child: Carte(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            onTap: f,
            child: Row(children: [
              Icon(i, color: Couleurs.primaire),
              const SizedBox(width: 10),
              Expanded(child: Text(t, style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 10, runSpacing: 10, children: [
        if (s.peut('actes', 'creer')) action(Icons.point_of_sale_outlined, 'Encaisser', () => nav.ouvrir('encaissement')),
        if (s.peut('actes', 'creer')) action(Icons.biotech_outlined, 'Examen de laboratoire', () => nav.ouvrir('laboratoire')),
        if (s.peut('depenses', 'creer')) action(Icons.receipt_long_outlined, 'Dépense ou achat', () => nav.ouvrir('depenses')),
        if (s.peut('desintox', 'creer')) action(Icons.healing_outlined, 'Désintoxication', () => nav.ouvrir('desintox')),
        if (s.peut('stocks', 'creer') && Stocks.remedes(b).isNotEmpty)
          action(Icons.local_drink_outlined, 'Servir les remèdes', () => servirRemedes(context)),
        if (s.peut('rapports', 'voir')) action(Icons.summarize_outlined, 'Compte rendu du soir', () => ouvrirCompteRendu(context)),
        if (s.peut('rapports', 'voir')) action(Icons.show_chart, 'Statistiques', () => nav.ouvrir('statistiques')),
      ]),
      if (aPayer.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Couleurs.alerteOrangeFond, border: Border.all(color: Couleurs.alerteOrangeBord), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Dépenses répétitives à payer ce mois', style: TextStyle(fontWeight: FontWeight.w700, color: Couleurs.encre)),
            for (final m in aPayer)
              Row(children: [
                Expanded(
                  child: Text('${m['libelle']} : ${m['beneficiaire']} · ${fcfa(m['montant'] as int)} · le ${dateFr(depuisIso(m['echeance'] as String))}',
                      style: const TextStyle(color: Couleurs.encre)),
                ),
                TextButton(
                    onPressed: () => nouvelleDepenseNature(context,
                        entite: m['entite'] as String, nature: m['nature'] as String, beneficiaire: m['beneficiaire'] as String, montant: m['montant'] as int),
                    child: const Text('Payer')),
              ]),
          ]),
        ),
      ],
    ]);
  }
}
