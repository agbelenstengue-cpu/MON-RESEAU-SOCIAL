/// États de la phase 3 : paie, immobilisations, notes annexes, prévisions,
/// tendances sur 12 mois, export vers Sage.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../modules/desintox/desintox.dart';
import '../modules/immobilisations/immobilisations.dart';
import '../modules/paie/paie.dart';
import '../modules/stocks/stocks.dart';
import '../modules/tresorerie/tresorerie.dart';
import '../noyau/base.dart';
import '../noyau/outils.dart';
import 'modele.dart';

class EtatsPaie {
  static Rapport bulletin(Base b, String employe, String periode) {
    final bu = b.ligne('SELECT * FROM bulletins WHERE employe=? AND periode=? AND annule=0', [employe, periode]) ??
        (throw RegleMetier('Aucun bulletin pour $periode.'));
    final e = b.ligne('SELECT * FROM employes WHERE id=?', [employe])!;
    final d = jsonDecode(bu['detail'] as String) as Map;
    final lignes = (d['lignes'] as List).cast<Map>();
    return Rapport(
      titre: 'Bulletin de paie',
      entite: e['entite'] as String,
      periode: 'Période : ${periode.substring(5)}/${periode.substring(0, 4)}',
      filtres: [
        '${e['nom']} · matricule ${e['matricule']} · ${e['poste']}',
        '${e['statut'] == 'salarie' ? 'Salarié' : 'Bénévole indemnisé'}${(e['cnps'] as String).isNotEmpty ? ' · n° CNPS ${e['cnps']}' : ''}',
      ],
      sections: [
        Section(titre: 'Rémunération', colonnes: const [Colonne('Élément', poids: 4), Colonne('Montant', type: TypeColonne.montant)], lignes: [
          ['Salaire de base', d['base']],
          if ((d['primes'] as int) > 0) ['Primes et indemnités', d['primes']],
        ], libelleTotal: 'SALAIRE BRUT'),
        Section(titre: 'Retenues salariales', colonnes: const [
          Colonne('Rubrique', poids: 3),
          Colonne('Base', type: TypeColonne.montant),
          Colonne('Taux', poids: 0.8),
          Colonne('Montant', type: TypeColonne.montant),
        ], lignes: [
          for (final l in lignes.where((l) => l['nature'] == 'retenue_salariale'))
            [l['libelle'], l['base'], '${((l['taux'] as int) / 100).toStringAsFixed(2).replaceAll('.', ',')} %', l['montant']],
          if ((d['retenues_diverses'] as int) > 0) ['Retenues diverses', null, '', d['retenues_diverses']],
          if ((d['avances'] as int) > 0) ['Avances sur salaire déduites', null, '', d['avances']],
        ], total: ['TOTAL DES RETENUES', null, null, (d['retenues'] as int) + (d['avances'] as int)]),
        Section(titre: 'Charges patronales (pour information)', colonnes: const [
          Colonne('Rubrique', poids: 3),
          Colonne('Base', type: TypeColonne.montant),
          Colonne('Taux', poids: 0.8),
          Colonne('Montant', type: TypeColonne.montant),
        ], lignes: [
          for (final l in lignes.where((l) => l['nature'] == 'charge_patronale'))
            [l['libelle'], l['base'], '${((l['taux'] as int) / 100).toStringAsFixed(2).replaceAll('.', ',')} %', l['montant']],
        ], total: ['TOTAL', null, null, d['patronales']]),
      ],
      synthese: [('Salaire brut', fcfa(d['brut'] as int)), ('Retenues', fcfa((d['retenues'] as int) + (d['avances'] as int))), ('NET À PAYER', fcfa(d['net'] as int))],
      signatures: const ["L'employeur", "L'employé"],
    );
  }

  static Rapport livre(Base b, String entite, Periode p) {
    final l = b.lignes(
        'SELECT b.*, e.nom, e.matricule FROM bulletins b JOIN employes e ON e.id=b.employe WHERE e.entite=? AND b.annule=0 AND b.periode BETWEEN ? AND ? '
        'ORDER BY b.periode, e.nom',
        [entite, p.du.substring(0, 7), p.au.substring(0, 7)]);
    return Rapport(
      titre: 'Livre de paie',
      entite: entite,
      periode: p.libelle,
      paysage: true,
      sections: [
        Section(colonnes: const [
          Colonne('Période', poids: 0.8),
          Colonne('Matricule', poids: 1.4),
          Colonne('Employé', poids: 2.4),
          Colonne('Brut', type: TypeColonne.montant),
          Colonne('Retenues', type: TypeColonne.montant),
          Colonne('Avances', type: TypeColonne.montant),
          Colonne('Net', type: TypeColonne.montant),
          Colonne('Charges patronales', type: TypeColonne.montant),
          Colonne('Coût total', type: TypeColonne.montant),
        ], lignes: [
          for (final x in l)
            [x['periode'], x['matricule'], x['nom'], x['brut'], x['retenues'], x['avances'], x['net'], x['patronales'], (x['brut'] as int) + (x['patronales'] as int)]
        ]),
      ],
    );
  }

  /// États de déclaration : cotisations CNPS et retenues fiscales par employé.
  static Rapport declaration(Base b, String entite, String periode, {required String organisme}) {
    final rows = <List<Object?>>[];
    for (final x in b.lignes(
        'SELECT b.detail, e.nom, e.matricule, e.cnps FROM bulletins b JOIN employes e ON e.id=b.employe WHERE e.entite=? AND b.periode=? AND b.annule=0 ORDER BY e.nom',
        [entite, periode])) {
      final d = jsonDecode(x['detail'] as String) as Map;
      final lignes = (d['lignes'] as List).cast<Map>().where((l) => l['organisme'] == organisme);
      final sal = lignes.where((l) => l['nature'] == 'retenue_salariale').fold<int>(0, (t, l) => t + (l['montant'] as int));
      final pat = lignes.where((l) => l['nature'] == 'charge_patronale').fold<int>(0, (t, l) => t + (l['montant'] as int));
      rows.add([x['nom'], organisme == 'CNPS' ? x['cnps'] : x['matricule'], d['brut'], sal, pat, sal + pat]);
    }
    return Rapport(
      titre: organisme == 'CNPS' ? 'Déclaration des cotisations sociales (CNPS)' : 'État des retenues et taxes fiscales',
      entite: entite,
      periode: 'Période : ${periode.substring(5)}/${periode.substring(0, 4)}',
      sections: [
        Section(colonnes: const [
          Colonne('Employé', poids: 2.5),
          Colonne('N° CNPS ou matricule', poids: 1.5),
          Colonne('Salaire brut', type: TypeColonne.montant),
          Colonne('Part salariale', type: TypeColonne.montant),
          Colonne('Part patronale', type: TypeColonne.montant),
          Colonne('Total à verser', type: TypeColonne.montant),
        ], lignes: rows),
      ],
      signatures: const ["L'employeur"],
    );
  }
}

class EtatsImmobilisations {
  static Rapport registre(Base b, String entite, String date) {
    final periode = date.substring(0, 7);
    return Rapport(
      titre: 'Registre des immobilisations',
      entite: entite,
      periode: 'Au ${dateFr(depuisIso(date))}',
      paysage: true,
      sections: [
        Section(colonnes: const [
          Colonne('N° inventaire', poids: 1.6),
          Colonne('Désignation', poids: 2.6),
          Colonne('Catégorie', poids: 1.4),
          Colonne('Acquisition', poids: 1),
          Colonne('Origine', poids: 0.7),
          Colonne('Localisation', poids: 1.2),
          Colonne('Valeur', type: TypeColonne.montant),
          Colonne('Amortissements', type: TypeColonne.montant),
          Colonne('Valeur nette', type: TypeColonne.montant),
          Colonne('Statut', poids: 0.9),
        ], lignes: [
          for (final i in b.lignes(
              'SELECT i.*, c.libelle AS cat FROM immobilisations i JOIN categories_immobilisations c ON c.code=i.categorie WHERE i.entite=? AND i.date_acquisition<=? ORDER BY i.numero',
              [entite, date]))
            () {
              final amorti = i['date_sortie'] != null ? i['amorti'] as int : Immobilisations.cumulTheorique(i, periode).clamp(0, i['amorti'] as int);
              return [
                i['numero'], i['designation'], i['cat'], dateFr(depuisIso(i['date_acquisition'] as String)), i['origine'], i['localisation'],
                i['valeur'], amorti, (i['valeur'] as int) - amorti, i['date_sortie'] == null ? 'En service' : 'Sorti (${i['motif_sortie']})',
              ];
            }(),
        ]),
      ],
    );
  }

  static Rapport tableauAmortissements(Base b, String entite, int annee) {
    final rows = <List<Object?>>[];
    for (final i in b.lignes('SELECT * FROM immobilisations WHERE entite=? AND date_acquisition<=? ORDER BY numero', [entite, '$annee-12-31'])) {
      final debut = Immobilisations.cumulTheorique(i, '${annee - 1}-12');
      final fin = i['date_sortie'] != null && (i['date_sortie'] as String).compareTo('$annee-12-31') <= 0
          ? i['amorti'] as int
          : Immobilisations.cumulTheorique(i, '$annee-12');
      rows.add([i['numero'], i['designation'], i['valeur'], '${i['duree_mois']} mois', debut, fin - debut, fin, (i['valeur'] as int) - fin]);
    }
    return Rapport(
      titre: 'Tableau des amortissements',
      entite: entite,
      periode: 'Exercice $annee',
      paysage: true,
      sections: [
        Section(colonnes: const [
          Colonne('N° inventaire', poids: 1.6),
          Colonne('Désignation', poids: 2.6),
          Colonne('Valeur', type: TypeColonne.montant),
          Colonne('Durée', poids: 0.8),
          Colonne('Cumul au début', type: TypeColonne.montant),
          Colonne("Dotation de l'exercice", type: TypeColonne.montant),
          Colonne('Cumul à la fin', type: TypeColonne.montant),
          Colonne('Valeur nette', type: TypeColonne.montant),
        ], lignes: rows),
      ],
    );
  }

  static Rapport ficheInventaire(Base b, String entite) => Rapport(
        titre: 'Inventaire physique des immobilisations',
        entite: entite,
        periode: 'Au ${dateFr(b.maintenant)}',
        sections: [
          Section(colonnes: const [
            Colonne('N° inventaire', poids: 1.6),
            Colonne('Désignation', poids: 3),
            Colonne('Localisation prévue', poids: 1.5),
            Colonne('Constaté (présent, absent, état)', poids: 2),
          ], lignes: [
            for (final i in b.lignes('SELECT * FROM immobilisations WHERE entite=? AND date_sortie IS NULL ORDER BY localisation, numero', [entite]))
              [i['numero'], i['designation'], i['localisation'], '']
          ], totaliser: false),
        ],
        signatures: const ['Inventorié par', 'Le comptable'],
      );
}

class EtatsFinanciersAnnexes {
  /// Notes annexes simplifiées (SYSCOHADA / SYCEBNL).
  static Rapport notes(Base b, String entite, int annee) {
    final ref = b.valeur('SELECT referentiel FROM entites WHERE code=?', [entite]) as String;
    final fin = '$annee-12-31';
    final immos = b.lignes(
        'SELECT c.libelle, SUM(CASE WHEN i.date_acquisition < ? THEN i.valeur ELSE 0 END) AS debut, '
        'SUM(CASE WHEN i.date_acquisition BETWEEN ? AND ? THEN i.valeur ELSE 0 END) AS acquisitions, '
        "SUM(CASE WHEN i.date_sortie BETWEEN ? AND ? THEN i.valeur ELSE 0 END) AS sorties "
        'FROM immobilisations i JOIN categories_immobilisations c ON c.code=i.categorie WHERE i.entite=? GROUP BY c.code',
        ['$annee-01-01', '$annee-01-01', fin, '$annee-01-01', fin, entite]);
    int solde(String racine, {bool debiteurs = false, bool crediteurs = false}) {
      final r = b.lignes(
          'SELECT l.compte, SUM(l.debit-l.credit) AS s FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture WHERE e.entite=? AND e.date<=? AND l.compte LIKE ? GROUP BY l.compte',
          [entite, fin, '$racine%']);
      return r.map((x) => x['s'] as int).where((v) => !debiteurs || v > 0).where((v) => !crediteurs || v < 0).fold<int>(0, (t, v) => t + v);
    }

    return Rapport(
      titre: 'Notes annexes aux états financiers',
      entite: entite,
      periode: 'Exercice $annee',
      note: 'Règles et méthodes comptables : comptabilité tenue selon le référentiel ${ref == 'SYCEBNL' ? 'SYCEBNL (entités à but non lucratif, OHADA)' : 'SYSCOHADA révisé'}. '
          'Stocks valorisés au coût unitaire moyen pondéré. Immobilisations amorties en linéaire selon les durées paramétrées par catégorie. '
          'Montants en francs CFA (XAF), sans décimales.',
      sections: [
        Section(titre: 'Note 1 : immobilisations brutes', colonnes: const [
          Colonne('Catégorie', poids: 3),
          Colonne('Début', type: TypeColonne.montant),
          Colonne('Acquisitions', type: TypeColonne.montant),
          Colonne('Sorties', type: TypeColonne.montant),
          Colonne('Fin', type: TypeColonne.montant),
        ], lignes: [
          for (final i in immos) [i['libelle'], i['debut'], i['acquisitions'], i['sorties'], (i['debut'] as int) + (i['acquisitions'] as int) - (i['sorties'] as int)]
        ]),
        Section(titre: 'Note 2 : stocks', colonnes: const [Colonne('Stock', poids: 3), Colonne('Valeur comptable', type: TypeColonne.montant)], lignes: [
          for (final c in ['311', '312', '331'])
            if (solde(c) != 0) [b.valeur('SELECT libelle FROM comptes WHERE entite=? AND numero LIKE ?', [entite, '$c%']) ?? c, solde(c)]
        ]),
        Section(titre: 'Note 3 : créances et dettes (échéance à moins d’un an)', colonnes: const [Colonne('Nature', poids: 3), Colonne('Montant', type: TypeColonne.montant)], lignes: [
          ['Créances patients et organismes', solde('41', debiteurs: true)],
          ['Avances au personnel', solde('421', debiteurs: true)],
          ['Dettes fournisseurs', -solde('40', crediteurs: true)],
          ['Dettes sociales et fiscales', -solde('43', crediteurs: true) - solde('44', crediteurs: true)],
          ['Rémunérations dues', -solde('422', crediteurs: true)],
        ], totaliser: false),
        if (ref == 'SYCEBNL')
          Section(titre: 'Note 4 : dons, legs et subventions reçus', colonnes: const [Colonne('Nature', poids: 3), Colonne('Montant', type: TypeColonne.montant)], lignes: [
            ['Dons en numéraire', -b.entier("SELECT COALESCE(SUM(l.debit-l.credit),0) FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture WHERE e.entite=? AND l.compte LIKE '7581%' AND e.date BETWEEN ? AND ? AND e.journal<>'CL'", [entite, '$annee-01-01', fin])],
            ['Dons en nature', -b.entier("SELECT COALESCE(SUM(l.debit-l.credit),0) FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture WHERE e.entite=? AND l.compte LIKE '7582%' AND e.date BETWEEN ? AND ? AND e.journal<>'CL'", [entite, '$annee-01-01', fin])],
            ["Subventions d'exploitation", -b.entier("SELECT COALESCE(SUM(l.debit-l.credit),0) FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture WHERE e.entite=? AND l.compte LIKE '718%' AND e.date BETWEEN ? AND ? AND e.journal<>'CL'", [entite, '$annee-01-01', fin])],
          ]),
      ],
      signatures: const ['Le comptable', 'La direction'],
    );
  }
}

class Previsions {
  /// Recettes et charges mois par mois sur 12 mois (courbes du tableau de bord).
  static List<Map<String, Object>> douzeMois(Base b, {String? entite}) {
    final aujourdhui = dateIso(b.maintenant);
    final r = <Map<String, Object>>[];
    for (var i = 11; i >= 0; i--) {
      final d = DateTime.utc(int.parse(aujourdhui.substring(0, 4)), int.parse(aujourdhui.substring(5, 7)) - i, 1);
      final p = Periode.mois(dateIso(d));
      int s(String racine) => b.entier(
          "SELECT COALESCE(SUM(l.debit-l.credit),0) FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture "
          "WHERE e.date BETWEEN ? AND ? AND e.journal<>'CL' AND l.compte LIKE ? ${entite != null ? 'AND e.entite=?' : ''}",
          [p.du, p.au, '$racine%', ?entite]);
      r.add({'mois': p.du.substring(0, 7), 'recettes': -s('7'), 'charges': s('6')});
    }
    return r;
  }

  /// Prévision de trésorerie : solde actuel + flux moyens des 90 derniers
  /// jours + échéances connues (salaires, échéanciers de désintoxication,
  /// tranches de subventions attendues, dettes fournisseurs).
  static Map<String, Object> tresorerie(Base b, String entite, int horizon) {
    final aujourdhui = dateIso(b.maintenant);
    final fin = ajouterJours(aujourdhui, horizon);
    final debut90 = ajouterJours(aujourdhui, -90);
    final solde = b.lignes('SELECT id FROM tresoreries WHERE entite=? AND actif=1', [entite]).fold<int>(0, (t, x) => t + Tresorerie.solde(b, x['id'] as String));
    final flux = b.lignes(
        "SELECT m.montant, m.uuid_op FROM mouvements_tresorerie m JOIN tresoreries t ON t.id=m.tresorerie JOIN operations o ON o.uuid=m.uuid_op "
        "WHERE t.entite=? AND m.date BETWEEN ? AND ? AND o.type NOT IN ('virement_interne','paiement_salaires','desintox_versement','subvention_tranche','reglement_fournisseur')",
        [entite, debut90, aujourdhui]);
    final net90 = flux.fold<int>(0, (t, m) => t + (m['montant'] as int));
    final courant = (net90 * horizon / 90).round();
    // Salaires : dernière masse nette mensuelle × nombre de fins de mois dans l'horizon.
    final masse = b.entier(
        "SELECT COALESCE(SUM(b.net),0) FROM bulletins b JOIN employes e ON e.id=b.employe WHERE e.entite=? AND b.annule=0 AND b.periode=(SELECT MAX(periode) FROM bulletins)",
        [entite]);
    var finsDeMois = 0;
    for (var d = 1; d <= horizon; d++) {
      final j = depuisIso(ajouterJours(aujourdhui, d));
      if (j.add(const Duration(days: 1)).day == 1) finsDeMois++;
    }
    final salaires = masse * finsDeMois;
    var desintox = 0;
    if (entite == 'CS') {
      for (final dd in b.lignes('SELECT id, echeancier FROM desintox_dossiers WHERE date_sortie IS NULL')) {
        final sit = Desintox.situation(b, dd['id'] as String);
        var cumul = 0;
        for (final e in (jsonDecode(dd['echeancier'] as String) as List).cast<Map>()) {
          cumul += e['montant'] as int;
          final date = e['date'] as String;
          if (date.compareTo(aujourdhui) > 0 && date.compareTo(fin) <= 0 && cumul > sit.verse) {
            desintox += (cumul - sit.verse).clamp(0, e['montant'] as int);
          }
        }
      }
    }
    var subventions = 0;
    if (entite == 'ONG') {
      for (final s in b.lignes('SELECT id, tranches FROM subventions')) {
        final recu = b.entier('SELECT COALESCE(SUM(montant),0) FROM subventions_tranches_recues WHERE subvention=? AND annule=0', [s['id']]);
        var cumul = 0;
        for (final t in (jsonDecode(s['tranches'] as String) as List).cast<Map>()) {
          cumul += t['montant'] as int;
          final date = t['date'] as String;
          if (date.compareTo(aujourdhui) > 0 && date.compareTo(fin) <= 0 && cumul > recu) subventions += (cumul - recu).clamp(0, t['montant'] as int);
        }
      }
    }
    final fournisseurs = -b.entier(
        "SELECT COALESCE(SUM(l.debit-l.credit),0) FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture WHERE e.entite=? AND l.compte LIKE '401%'", [entite]);
    final dettes = horizon >= 30 ? fournisseurs : 0;
    final previsionnel = solde + courant - salaires + desintox + subventions - dettes;
    return {
      'solde_actuel': solde,
      'flux_courants': courant,
      'salaires': -salaires,
      'echeances_desintox': desintox,
      'tranches_subventions': subventions,
      'dettes_fournisseurs': -dettes,
      'solde_previsionnel': previsionnel,
    };
  }

  /// Résultat projeté de fin d'exercice (prorata des jours écoulés).
  static Map<String, int> resultatProjete(Base b, String entite) {
    final aujourdhui = dateIso(b.maintenant);
    final debut = '${aujourdhui.substring(0, 4)}-01-01';
    int s(String r) => b.entier(
        "SELECT COALESCE(SUM(l.debit-l.credit),0) FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture WHERE e.entite=? AND e.date BETWEEN ? AND ? AND e.journal<>'CL' AND l.compte LIKE ?",
        [entite, debut, aujourdhui, '$r%']);
    final actuel = -s('7') - s('6') - s('8');
    final ecoules = joursEntre(debut, aujourdhui) + 1;
    final total = joursEntre(debut, '${aujourdhui.substring(0, 4)}-12-31') + 1;
    return {'actuel': actuel, 'projete': (actuel * total / ecoules).round()};
  }

  static Rapport rapport(Base b, String entite) {
    final p30 = tresorerie(b, entite, 30), p90 = tresorerie(b, entite, 90);
    final r = resultatProjete(b, entite);
    const libelles = {
      'solde_actuel': 'Solde actuel des caisses, banques et mobile money',
      'flux_courants': 'Flux courants (moyenne des 90 derniers jours)',
      'salaires': 'Salaires à payer',
      'echeances_desintox': 'Échéances de désintoxication attendues',
      'tranches_subventions': 'Tranches de subventions attendues',
      'dettes_fournisseurs': 'Dettes fournisseurs à régler',
      'solde_previsionnel': 'SOLDE PRÉVISIONNEL',
    };
    return Rapport(
      titre: 'Prévisions de trésorerie et de résultat',
      entite: entite,
      periode: 'Établies le ${dateFr(b.maintenant)}',
      note: 'Résultat de l’exercice à ce jour : ${fcfa(r['actuel']!)} ; résultat projeté à la fin de l’exercice : ${fcfa(r['projete']!)}.',
      sections: [
        Section(colonnes: const [
          Colonne('Élément', poids: 4),
          Colonne('À 30 jours', type: TypeColonne.montant),
          Colonne('À 90 jours', type: TypeColonne.montant),
        ], lignes: [
          for (final e in libelles.entries) [e.value, p30[e.key], p90[e.key]]
        ], totaliser: false),
      ],
    );
  }
}

/// Export des écritures au format texte importable dans Sage (§2.3, option
/// de transition) : une ligne par mouvement, séparateur point-virgule,
/// date JJMMAA, montants sans séparateur de milliers.
class ExportSage {
  static Uint8List generer(Base b, String entite, Periode p) {
    final l = b.lignes(
        'SELECT e.journal, e.date, e.piece, e.libelle, l.compte, l.tiers, l.debit, l.credit FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture '
        'WHERE e.entite=? AND e.date BETWEEN ? AND ? ORDER BY e.date, e.id, l.id',
        [entite, p.du, p.au]);
    String nettoyer(Object? v) => '${v ?? ''}'.replaceAll(';', ',').replaceAll('\n', ' ');
    final buf = StringBuffer('Journal;Date;Compte;Tiers;Piece;Libelle;Debit;Credit\r\n');
    for (final x in l) {
      final d = x['date'] as String;
      buf.write('${x['journal']};${d.substring(8, 10)}${d.substring(5, 7)}${d.substring(2, 4)};${x['compte']};'
          '${nettoyer(x['tiers'] == null ? '' : _codeTiers(b, x['tiers'] as String))};${nettoyer(x['piece'])};${nettoyer(x['libelle'])};${x['debit']};${x['credit']}\r\n');
    }
    // Encodage Windows-1252 (accents) attendu par Sage : approximation Latin-1.
    return Uint8List.fromList(latin1.encode(buf.toString().replaceAll(RegExp(r'[^\x00-\xFF]'), '?')));
  }

  static String _codeTiers(Base b, String id) =>
      (b.valeur('SELECT numero_dossier FROM patients WHERE id=?', [id]) ?? b.valeur('SELECT matricule FROM employes WHERE id=?', [id]) ??
          b.valeur('SELECT nom FROM fournisseurs WHERE id=?', [id]) ?? id) as String;
}

/// Valeur totale des stocks (tableau de bord).
int valeurStocks(Base b) => b.lignes('SELECT code FROM produits').fold<int>(0, (t, p) => t + Stocks.valeur(b, p['code'] as String));

/// Pour l'écran : bulletin disponible ?
bool bulletinExiste(Base b, String employe, String periode) =>
    b.valeur('SELECT 1 FROM bulletins WHERE employe=? AND periode=? AND annule=0', [employe, periode]) != null;

/// Récapitulatif d'un calcul de paie (écran).
Map<String, int> totauxPaie(Base b, String entite, String periode) {
  final l = b.lignes('SELECT b.* FROM bulletins b JOIN employes e ON e.id=b.employe WHERE e.entite=? AND b.periode=? AND b.annule=0', [entite, periode]);
  return {
    'brut': l.fold<int>(0, (t, x) => t + (x['brut'] as int)),
    'net': l.fold<int>(0, (t, x) => t + (x['net'] as int)),
    'patronales': l.fold<int>(0, (t, x) => t + (x['patronales'] as int)),
    'reste_a_payer': l.fold<int>(0, (t, x) => t + Paie.netAPayer(b, entite, x['employe'] as String)),
  };
}
