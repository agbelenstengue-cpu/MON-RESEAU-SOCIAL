/// Page d'accueil = tableau de bord (§9, maquette « Accueil »).
library;

import 'package:material_ui/material_ui.dart';

import '../../modules/rapports/rapports.dart';
import '../../noyau/outils.dart';
import '../etat_app.dart';
import '../theme.dart';
import '../widgets/commun.dart';

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
      const SizedBox(height: 20),
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
