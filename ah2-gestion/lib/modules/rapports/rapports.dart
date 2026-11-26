/// Rapports journaliers et tableau de bord (§8, §9).
///
/// Tous les chiffres sont CALCULÉS depuis les écritures et les mouvements :
/// les totaux sont toujours égaux à la somme des lignes, et les pourcentages
/// totalisent exactement 100 % (méthode du plus fort reste).
library;

import '../../noyau/base.dart';
import '../../noyau/outils.dart';
import '../desintox/desintox.dart';
import '../tresorerie/tresorerie.dart';

class Rapports {
  /// Répartit 100 % entre des montants (plus fort reste) : la somme fait toujours 100.
  static List<int> pourcentages(List<int> montants) {
    final total = montants.fold<int>(0, (a, b) => a + b);
    if (total == 0) return List.filled(montants.length, 0);
    final bruts = [for (final m in montants) m * 100 / total];
    final ent = [for (final b in bruts) b.floor()];
    var reste = 100 - ent.fold<int>(0, (a, b) => a + b);
    final ordre = List.generate(montants.length, (i) => i)
      ..sort((a, b) => (bruts[b] - ent[b]).compareTo(bruts[a] - ent[a]));
    for (final i in ordre) {
      if (reste == 0) break;
      if (montants[i] > 0) {
        ent[i]++;
        reste--;
      }
    }
    return ent;
  }

  /// Recettes (produits de classe 7, nets des contre-passations) par activité.
  static Map<String, int> recettesParActivite(Base base, {required String du, required String au, String? entite}) {
    final r = base.lignes(
        "SELECT COALESCE(l.activite,'?') AS activite, SUM(l.credit - l.debit) AS montant "
        "FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture "
        "WHERE l.compte LIKE '7%' AND e.date BETWEEN ? AND ? ${entite != null ? 'AND e.entite=?' : ''} "
        "GROUP BY l.activite",
        [du, au, ?entite]);
    return {for (final l in r) l['activite'] as String: l['montant'] as int};
  }

  static int charges(Base base, {required String du, required String au, String? entite}) => base.entier(
      "SELECT COALESCE(SUM(l.debit - l.credit),0) FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture "
      "WHERE l.compte LIKE '6%' AND e.date BETWEEN ? AND ? ${entite != null ? 'AND e.entite=?' : ''}",
      [du, au, ?entite]);

  static int encaissements(Base base, {required String du, required String au, String? entite}) => base.entier(
      "SELECT COALESCE(SUM(m.montant),0) FROM mouvements_tresorerie m JOIN tresoreries t ON t.id=m.tresorerie "
      "WHERE m.montant > 0 AND m.date BETWEEN ? AND ? AND m.libelle NOT LIKE 'Virement%' "
      "${entite != null ? 'AND t.entite=?' : ''}",
      [du, au, ?entite]);

  /// Rapport financier du jour, avec note de synthèse rédigée.
  static Map<String, Object?> financierDuJour(Base base, String date, {String? entite}) {
    final parAct = recettesParActivite(base, du: date, au: date, entite: entite);
    final libelles = {
      for (final a in base.lignes('SELECT code, libelle FROM activites')) a['code'] as String: a['libelle'] as String
    };
    final codes = parAct.keys.toList()..sort((a, b) => parAct[b]!.compareTo(parAct[a]!));
    final montants = [for (final c in codes) parAct[c]!];
    final pct = pourcentages(montants);
    final total = montants.fold<int>(0, (a, b) => a + b);
    // Moyenne des 28 jours précédents.
    final debut = ajouterJours(date, -28);
    final veille = ajouterJours(date, -1);
    final total28 = recettesParActivite(base, du: debut, au: veille, entite: entite).values.fold<int>(0, (a, b) => a + b);
    final moyenne = total28 ~/ 28;
    final ch = charges(base, du: date, au: date, entite: entite);
    final lignes = [
      for (var i = 0; i < codes.length; i++)
        {'activite': codes[i], 'libelle': libelles[codes[i]] ?? codes[i], 'montant': montants[i], 'pourcentage': pct[i]}
    ];
    return {
      'date': date,
      'recettes': total,
      'charges': ch,
      'resultat': total - ch,
      'encaissements': encaissements(base, du: date, au: date, entite: entite),
      'lignes': lignes,
      'moyenne_28j': moyenne,
      'note': noteSynthese(total, lignes, moyenne),
    };
  }

  /// Note en phrases simples : « Recettes 185 000 FCFA, dont 40 % du laboratoire… »
  static String noteSynthese(int total, List<Map<String, Object?>> lignes, int moyenne) {
    if (total == 0) return 'Aucune recette enregistrée ce jour.';
    final b = StringBuffer('Recettes ${fcfa(total)}');
    if (lignes.isNotEmpty) {
      final p = lignes.first;
      b.write(', dont ${p['pourcentage']} % ${_du(p['activite'] as String, p['libelle'] as String)}');
    }
    if (moyenne > 0) {
      final ecart = ((total - moyenne) * 100 / moyenne).round();
      if (ecart.abs() < 5) {
        b.write(', stables par rapport à la moyenne des 4 dernières semaines');
      } else {
        b.write(', en ${ecart > 0 ? 'hausse' : 'baisse'} de ${ecart.abs()} % par rapport à la moyenne des 4 dernières semaines');
      }
    }
    b.write('.');
    return b.toString();
  }

  static const _articles = {
    'CONS': 'des consultations',
    'LAB': 'du laboratoire',
    'HOSP': "de l'hospitalisation",
    'DESINTOX': 'de la désintoxication',
    'MASS': 'des massages et soins',
    'PHM': 'de la pharmacie moderne',
    'PHT': 'de la pharmacie traditionnelle',
    'PROG': 'des programmes sociaux',
  };

  static String _du(String code, String libelle) => _articles[code] ?? 'de « $libelle »';

  /// Brouillard de caisse : solde d'ouverture, mouvements, solde de clôture.
  static Map<String, Object?> brouillard(Base base, String caisse, String date) {
    final ouverture = Tresorerie.solde(base, caisse, jusquau: ajouterJours(date, -1));
    final mvts = base.lignes('SELECT * FROM mouvements_tresorerie WHERE tresorerie=? AND date=? ORDER BY horodatage, id', [caisse, date]);
    final entrees = mvts.where((m) => (m['montant'] as int) > 0).fold<int>(0, (t, m) => t + (m['montant'] as int));
    final sorties = mvts.where((m) => (m['montant'] as int) < 0).fold<int>(0, (t, m) => t - (m['montant'] as int));
    return {
      'caisse': Tresorerie.compte(base, caisse),
      'date': date,
      'ouverture': ouverture,
      'mouvements': mvts,
      'entrees': entrees,
      'sorties': sorties,
      'cloture': ouverture + entrees - sorties,
    };
  }

  /// Reçus émis et annulés d'une journée.
  static List<Ligne> recus(Base base, String date) => base.lignes(
      "SELECT o.piece, o.type, o.appareil, o.horodatage, o.uuid, a.motif AS motif_annulation "
      "FROM operations o LEFT JOIN annulations a ON a.uuid_annule=o.uuid "
      "WHERE o.date_op=? AND o.piece IS NOT NULL ORDER BY o.horodatage",
      [date]);

  static List<Ligne> versementsDesintox(Base base, String date) => base.lignes(
      'SELECT v.*, d.numero, p.numero_dossier FROM desintox_versements v JOIN desintox_dossiers d ON d.id=v.dossier '
      'JOIN patients p ON p.id=d.patient WHERE v.date=? ORDER BY v.horodatage',
      [date]);

  /// Santé d'une activité : jour vs moyenne journalière des 4 dernières semaines.
  static List<Map<String, Object?>> santeActivites(Base base, String date) {
    final jour = recettesParActivite(base, du: date, au: date);
    final avant = recettesParActivite(base, du: ajouterJours(date, -28), au: ajouterJours(date, -1));
    final seuil = base.paramInt('baisse_activite_pourcent');
    return [
      for (final a in base.lignes("SELECT code, libelle FROM activites WHERE code NOT LIKE 'ADM%' AND actif=1 ORDER BY code"))
        () {
          final j = jour[a['code']] ?? 0;
          final moy = (avant[a['code']] ?? 0) / 28;
          String tendance;
          if (moy == 0) {
            tendance = j > 0 ? 'en_hausse' : 'stable';
          } else {
            final ecart = (j - moy) * 100 / moy;
            tendance = ecart <= -seuil ? 'en_baisse' : (ecart >= 10 ? 'en_hausse' : 'stable');
          }
          return {'activite': a['code'], 'libelle': a['libelle'], 'jour': j, 'moyenne': moy.round(), 'tendance': tendance};
        }(),
    ];
  }

  /// Alertes du tableau de bord (§9).
  static List<Map<String, String>> alertes(Base base) {
    final r = <Map<String, String>>[];
    final aujourdhui = dateIso(base.maintenant);
    final plafond = base.paramInt('plafond_encaisse');
    for (final c in base.lignes("SELECT * FROM tresoreries WHERE type='caisse' AND actif=1")) {
      final s = Tresorerie.solde(base, c['id'] as String);
      if (s > plafond) {
        r.add({'niveau': 'orange', 'titre': 'Plafond de caisse dépassé', 'detail': '${c['libelle']} (${c['entite']}) : ${fcfa(s)} : proposer un versement en banque'});
      }
      final hier = ajouterJours(aujourdhui, -1);
      final aTravaille = base.valeur('SELECT 1 FROM mouvements_tresorerie WHERE tresorerie=? AND date=?', [c['id'], hier]) != null;
      final arrete = base.valeur(
          'SELECT 1 FROM arretes_caisse WHERE tresorerie=? AND date=? AND uuid_op NOT IN (SELECT uuid_annule FROM annulations)',
          [c['id'], hier]) != null;
      if (aTravaille && !arrete) {
        r.add({'niveau': 'orange', 'titre': 'Arrêté de caisse non fait', 'detail': '${c['libelle']} (${c['entite']}) · ${dateFr(depuisIso(hier))}'});
      }
    }
    for (final rel in base.lignes("SELECT numero, genere_le FROM releves WHERE statut='genere'")) {
      final j = joursEntre((rel['genere_le'] as String).substring(0, 10), aujourdhui);
      if (j >= 1) r.add({'niveau': 'orange', 'titre': 'Relevé non retourné signé', 'detail': '${rel['numero']} · $j j de retard'});
    }
    for (final e in Desintox.echeancesImpayees(base)) {
      r.add({'niveau': 'rouge', 'titre': 'Échéance désintox impayée', 'detail': '${e['numero']} · ${fcfa(e['manquant'] as int)} prévu le ${dateFr(depuisIso(e['date'] as String))}'});
    }
    final enAttente = base.entier("SELECT COUNT(*) FROM depenses WHERE statut='en_attente' AND annule=0");
    if (enAttente > 0) r.add({'niveau': 'orange', 'titre': 'Dépenses en attente de validation', 'detail': '$enAttente dépense(s)'});
    final anomalies = base.entier("SELECT COUNT(*) FROM anomalies_sync WHERE statut='a_traiter'");
    if (anomalies > 0) r.add({'niveau': 'rouge', 'titre': 'Anomalies de synchronisation', 'detail': '$anomalies à traiter'});
    final heures = base.paramInt('sync_alerte_heures');
    for (final a in base.lignes("SELECT code, derniere_sync FROM appareils WHERE central=0 AND statut='autorise'")) {
      final d = a['derniere_sync'] as String?;
      if (d == null || base.maintenant.difference(DateTime.parse(d)).inHours > heures) {
        r.add({'niveau': 'orange', 'titre': 'Appareil non synchronisé', 'detail': '${a['code']} · ${d == null ? 'jamais' : 'depuis ${dateFr(DateTime.parse(d))} ${heureFr(DateTime.parse(d))}'}'});
      }
    }
    // Déficits : résultat du mois, activités déficitaires, trésorerie sous le minimum.
    if (base.param('alerte_deficit', '1') == '1') {
      final debutMois = '${aujourdhui.substring(0, 7)}-01';
      for (final ent in ['CS', 'ONG']) {
        final nom = ent == 'CS' ? 'Centre de santé' : 'ONG';
        int somme(String racine, [String? activite]) => base.entier(
            "SELECT COALESCE(SUM(l.debit-l.credit),0) FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture "
            "WHERE e.entite=? AND e.date BETWEEN ? AND ? AND e.journal <> 'CL' AND l.compte LIKE ? ${activite != null ? 'AND l.activite=?' : ''}",
            [ent, debutMois, aujourdhui, '$racine%', ?activite]);
        final resultat = -somme('7') - somme('6');
        if (resultat < 0) {
          r.add({'niveau': 'rouge', 'titre': 'Déficit du mois : $nom', 'detail': 'Charges supérieures aux recettes de ${fcfa(-resultat)} depuis le 1er du mois'});
        }
        for (final a in base.lignes("SELECT code, libelle FROM activites WHERE entite=? AND actif=1 AND code NOT LIKE 'ADM%'", [ent])) {
          final ra = -somme('7', a['code'] as String) - somme('6', a['code'] as String);
          if (ra < 0) {
            r.add({'niveau': 'orange', 'titre': 'Activité déficitaire ce mois', 'detail': '${a['libelle']} : ${fcfa(ra)} (charges directes supérieures aux recettes)'});
          }
        }
        final minimum = base.paramInt('tresorerie_minimum', 0);
        if (minimum > 0) {
          final total = base.lignes('SELECT id FROM tresoreries WHERE entite=? AND actif=1', [ent]).fold<int>(0, (t, x) => t + Tresorerie.solde(base, x['id'] as String));
          if (total < minimum) {
            r.add({'niveau': 'rouge', 'titre': 'Trésorerie insuffisante : $nom', 'detail': 'Disponible ${fcfa(total)} pour un minimum fixé à ${fcfa(minimum)}'});
          }
        }
      }
    }
    final sauvegarde = base.valeur("SELECT valeur FROM etat_sync WHERE cle='derniere_sauvegarde'") as String?;
    final estCentral = base.valeur('SELECT central FROM appareils WHERE code=?', [base.appareil]) == 1;
    if (estCentral && (sauvegarde == null || sauvegarde.isEmpty || base.maintenant.difference(DateTime.parse(sauvegarde)).inHours > 24)) {
      r.add({'niveau': 'rouge', 'titre': 'Sauvegarde non effectuée', 'detail': 'Aucune sauvegarde réussie depuis plus de 24 heures'});
    }
    return r;
  }

  /// Indicateurs clés du tableau de bord.
  static Map<String, Object?> tableauDeBord(Base base, {String? date}) {
    final j = date ?? dateIso(base.maintenant);
    final mois = '${j.substring(0, 7)}-01';
    final annee = '${j.substring(0, 4)}-01-01';
    int rec(String du) => recettesParActivite(base, du: du, au: j).values.fold<int>(0, (a, b) => a + b);
    return {
      'recettes_jour': rec(j),
      'recettes_mois': rec(mois),
      'recettes_annee': rec(annee),
      'charges_jour': charges(base, du: j, au: j),
      'charges_mois': charges(base, du: mois, au: j),
      'tresoreries': [
        for (final t in base.lignes('SELECT * FROM tresoreries WHERE actif=1 ORDER BY entite, centrale DESC, type, id'))
          {...t, 'solde': Tresorerie.solde(base, t['id'] as String)}
      ],
      'desintox_en_cours': Desintox.listeTravail(base).where((s) => s.statut == 'en_cours').length,
      'desintox_reste': Desintox.resteTotal(base),
      'creances': base.entier(
          "SELECT COALESCE(SUM(l.debit-l.credit),0) FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture WHERE l.compte LIKE '411%'"),
      'sante': santeActivites(base, j),
      'alertes': alertes(base),
    };
  }
}
