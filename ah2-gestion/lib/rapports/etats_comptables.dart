/// États comptables : journaux, grand livre, balances, compte de résultat,
/// bilan, résultat analytique, rapprochement bancaire. Tout est calculé
/// depuis les écritures : les totaux sont toujours justes.
library;

import '../modules/comptabilite/comptabilite.dart';
import '../modules/rapports/rapports.dart';
import '../modules/tresorerie/tresorerie.dart';
import '../noyau/base.dart';
import '../noyau/outils.dart';
import 'modele.dart';

class EtatsComptables {
  static String _nomEntite(Base b, String e) => (b.valeur('SELECT nom FROM entites WHERE code=?', [e]) as String?) ?? e;
  static bool _sycebnl(Base b, String e) => b.valeur('SELECT referentiel FROM entites WHERE code=?', [e]) == 'SYCEBNL';
  static String _ref(Base b, String e) => '${_nomEntite(b, e)} · ${_sycebnl(b, e) ? 'SYCEBNL' : 'SYSCOHADA révisé'}';

  // ------------------------------------------------------------ journaux
  static Rapport journal(Base b, String entite, Periode p, {String? journal}) {
    final ecr = b.lignes(
        'SELECT e.*, l.compte, l.debit, l.credit, c.libelle AS lib_compte FROM ecritures e JOIN lignes_ecriture l ON l.ecriture=e.id '
        'LEFT JOIN comptes c ON c.entite=e.entite AND c.numero=l.compte '
        'WHERE e.entite=? AND e.date BETWEEN ? AND ? ${journal != null ? 'AND e.journal=?' : ''} ORDER BY e.journal, e.date, e.id, l.id',
        [entite, p.du, p.au, ?journal]);
    final journaux = <String, List<List<Object?>>>{};
    for (final l in ecr) {
      journaux.putIfAbsent(l['journal'] as String, () => []).add([
        dateFr(depuisIso(l['date'] as String)),
        l['piece'] ?? '',
        l['compte'],
        l['libelle'],
        l['debit'],
        l['credit'],
      ]);
    }
    final libJ = {for (final j in b.lignes('SELECT code, libelle FROM journaux WHERE entite=?', [entite])) j['code']: j['libelle']};
    return Rapport(
      titre: journal == null ? 'Journaux comptables' : 'Journal ${libJ[journal] ?? journal}',
      entite: entite,
      periode: p.libelle,
      filtres: [_ref(b, entite)],
      paysage: true,
      sections: [
        for (final e in journaux.entries)
          Section(
            titre: '${e.key} : ${libJ[e.key] ?? ''}',
            colonnes: const [
              Colonne('Date', poids: 1),
              Colonne('Pièce', poids: 2),
              Colonne('Compte', poids: 0.8),
              Colonne('Libellé', poids: 4),
              Colonne('Débit', type: TypeColonne.montant, poids: 1.2),
              Colonne('Crédit', type: TypeColonne.montant, poids: 1.2),
            ],
            lignes: e.value,
          ),
      ],
    );
  }

  // ------------------------------------------------------------ grand livre
  static Rapport grandLivre(Base b, String entite, Periode p, {String racine = ''}) {
    final comptes = b.lignes(
        "SELECT DISTINCT l.compte, c.libelle FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture "
        "LEFT JOIN comptes c ON c.entite=e.entite AND c.numero=l.compte WHERE e.entite=? AND l.compte LIKE ? AND e.date<=? ORDER BY l.compte",
        [entite, '$racine%', p.au]);
    final sections = <Section>[];
    for (final c in comptes) {
      final anterieur = b.entier(
          'SELECT COALESCE(SUM(l.debit-l.credit),0) FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture WHERE e.entite=? AND l.compte=? AND e.date<?',
          [entite, c['compte'], p.du]);
      final mvts = b.lignes(
          'SELECT e.date, e.piece, e.journal, e.libelle, l.debit, l.credit FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture '
          'WHERE e.entite=? AND l.compte=? AND e.date BETWEEN ? AND ? ORDER BY e.date, e.id, l.id',
          [entite, c['compte'], p.du, p.au]);
      if (mvts.isEmpty && anterieur == 0) continue;
      var solde = anterieur;
      final lignes = <List<Object?>>[
        ['', '', '', 'Solde au ${dateFr(depuisIso(p.du))}', anterieur > 0 ? anterieur : 0, anterieur < 0 ? -anterieur : 0, anterieur],
      ];
      for (final m in mvts) {
        solde += (m['debit'] as int) - (m['credit'] as int);
        lignes.add([dateFr(depuisIso(m['date'] as String)), m['journal'], m['piece'] ?? '', m['libelle'], m['debit'], m['credit'], solde]);
      }
      sections.add(Section(
        titre: '${c['compte']} ${c['libelle'] ?? ''}',
        colonnes: const [
          Colonne('Date', poids: 1),
          Colonne('Jnl', poids: 0.6),
          Colonne('Pièce', poids: 2),
          Colonne('Libellé', poids: 3.5),
          Colonne('Débit', type: TypeColonne.montant, poids: 1.2),
          Colonne('Crédit', type: TypeColonne.montant, poids: 1.2),
          Colonne('Solde', type: TypeColonne.montant, poids: 1.2),
        ],
        lignes: lignes,
        total: [
          'TOTAL',
          null,
          null,
          null,
          lignes.fold<int>(0, (t, l) => t + (l[4] as int)),
          lignes.fold<int>(0, (t, l) => t + (l[5] as int)),
          solde,
        ],
      ));
    }
    return Rapport(titre: 'Grand livre', entite: entite, periode: p.libelle, filtres: [_ref(b, entite), if (racine.isNotEmpty) 'Comptes $racine…'], paysage: true, sections: sections);
  }

  // ------------------------------------------------------------ balances
  static Rapport balance(Base b, String entite, Periode p) {
    final lignes = b.lignes(
        "SELECT l.compte, c.libelle, "
        "SUM(CASE WHEN e.date < ? THEN l.debit - l.credit ELSE 0 END) AS ouverture, "
        "SUM(CASE WHEN e.date BETWEEN ? AND ? THEN l.debit ELSE 0 END) AS debit, "
        "SUM(CASE WHEN e.date BETWEEN ? AND ? THEN l.credit ELSE 0 END) AS credit "
        "FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture LEFT JOIN comptes c ON c.entite=e.entite AND c.numero=l.compte "
        "WHERE e.entite=? AND e.date <= ? GROUP BY l.compte ORDER BY l.compte",
        [p.du, p.du, p.au, p.du, p.au, entite, p.au]);
    final rows = <List<Object?>>[];
    for (final l in lignes) {
      final o = l['ouverture'] as int, d = l['debit'] as int, c = l['credit'] as int;
      final f = o + d - c;
      if (o == 0 && d == 0 && c == 0) continue;
      rows.add([l['compte'], l['libelle'] ?? '', o > 0 ? o : 0, o < 0 ? -o : 0, d, c, f > 0 ? f : 0, f < 0 ? -f : 0]);
    }
    return Rapport(
      titre: 'Balance générale',
      entite: entite,
      periode: p.libelle,
      filtres: [_ref(b, entite)],
      paysage: true,
      sections: [
        Section(colonnes: const [
          Colonne('Compte', poids: 0.8),
          Colonne('Libellé', poids: 3),
          Colonne('Ouverture débit', type: TypeColonne.montant),
          Colonne('Ouverture crédit', type: TypeColonne.montant),
          Colonne('Mouvements débit', type: TypeColonne.montant),
          Colonne('Mouvements crédit', type: TypeColonne.montant),
          Colonne('Solde débiteur', type: TypeColonne.montant),
          Colonne('Solde créditeur', type: TypeColonne.montant),
        ], lignes: rows),
      ],
    );
  }

  static String _nomTiers(Base b, String id) =>
      (b.valeur("SELECT nom || ' ' || prenoms || ' (' || numero_dossier || ')' FROM patients WHERE id=?", [id]) ??
          b.valeur('SELECT nom FROM fournisseurs WHERE id=?', [id]) ??
          b.valeur('SELECT nom FROM employes WHERE id=?', [id]) ??
          id) as String;

  static Rapport balanceTiers(Base b, String entite, Periode p, {String racine = '411'}) {
    final lignes = b.lignes(
        "SELECT l.compte, l.tiers, SUM(CASE WHEN e.date BETWEEN ? AND ? THEN l.debit ELSE 0 END) AS debit, "
        "SUM(CASE WHEN e.date BETWEEN ? AND ? THEN l.credit ELSE 0 END) AS credit, SUM(l.debit - l.credit) AS solde "
        "FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture WHERE e.entite=? AND l.compte LIKE ? AND e.date<=? AND l.tiers IS NOT NULL "
        "GROUP BY l.compte, l.tiers HAVING debit<>0 OR credit<>0 OR solde<>0 ORDER BY l.compte, solde DESC",
        [p.du, p.au, p.du, p.au, entite, '$racine%', p.au]);
    return Rapport(
      titre: racine.startsWith('40') ? 'Balance des fournisseurs' : 'Balance des tiers (patients et organismes)',
      entite: entite,
      periode: p.libelle,
      filtres: [_ref(b, entite)],
      sections: [
        Section(colonnes: const [
          Colonne('Compte', poids: 0.7),
          Colonne('Tiers', poids: 3),
          Colonne('Débit', type: TypeColonne.montant),
          Colonne('Crédit', type: TypeColonne.montant),
          Colonne('Solde', type: TypeColonne.montant),
        ], lignes: [
          for (final l in lignes) [l['compte'], _nomTiers(b, l['tiers'] as String), l['debit'], l['credit'], l['solde']]
        ]),
      ],
    );
  }

  /// Balance âgée des créances : 0 à 30 jours, 31 à 60, 61 à 90, plus de 90.
  static Rapport balanceAgee(Base b, String entite, String date, {String racine = '411'}) {
    final tiers = b.lignes(
        "SELECT l.tiers, SUM(l.debit-l.credit) AS solde FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture "
        "WHERE e.entite=? AND l.compte LIKE ? AND e.date<=? AND l.tiers IS NOT NULL GROUP BY l.tiers HAVING solde > 0 ORDER BY solde DESC",
        [entite, '$racine%', date]);
    final rows = <List<Object?>>[];
    for (final t in tiers) {
      // Le solde restant est attribué aux débits les plus récents (règlements imputés aux plus anciens).
      var reste = t['solde'] as int;
      final tranches = [0, 0, 0, 0];
      for (final d in b.lignes(
          "SELECT e.date, l.debit FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture "
          "WHERE e.entite=? AND l.compte LIKE ? AND l.tiers=? AND l.debit>0 AND e.date<=? ORDER BY e.date DESC",
          [entite, '$racine%', t['tiers'], date])) {
        if (reste <= 0) break;
        final part = (d['debit'] as int) < reste ? d['debit'] as int : reste;
        final age = joursEntre(d['date'] as String, date);
        tranches[age <= 30 ? 0 : age <= 60 ? 1 : age <= 90 ? 2 : 3] += part;
        reste -= part;
      }
      tranches[3] += reste;
      final contact = b.valeur('SELECT contact FROM patients WHERE id=?', [t['tiers']]) ?? '';
      rows.add([_nomTiers(b, t['tiers'] as String), contact, ...tranches, t['solde']]);
    }
    return Rapport(
      titre: 'Créances : balance âgée',
      entite: entite,
      periode: 'Au ${dateFr(depuisIso(date))}',
      filtres: [_ref(b, entite)],
      paysage: true,
      sections: [
        Section(colonnes: const [
          Colonne('Tiers', poids: 3),
          Colonne('Contact', poids: 1.5),
          Colonne('0 à 30 j', type: TypeColonne.montant),
          Colonne('31 à 60 j', type: TypeColonne.montant),
          Colonne('61 à 90 j', type: TypeColonne.montant),
          Colonne('Plus de 90 j', type: TypeColonne.montant),
          Colonne('Total', type: TypeColonne.montant),
        ], lignes: rows),
      ],
    );
  }

  // ------------------------------------------------------------ compte de résultat
  static const _charges = [
    ('601', 'Achats de marchandises (médicaments, produits)'),
    ('603', 'Variation des stocks'),
    ('604', 'Achats stockés de matières et fournitures'),
    ('605', 'Autres achats (eau, électricité, fournitures)'),
    ('61', 'Transports'),
    ('62', 'Services extérieurs'),
    ('63', 'Autres services extérieurs'),
    ('64', 'Impôts et taxes'),
    ('65', 'Autres charges (dont aides accordées)'),
    ('66', 'Charges de personnel'),
    ('67', 'Frais financiers'),
    ('68', 'Dotations aux amortissements et provisions'),
    ('81', 'Valeurs comptables des cessions'),
    ('83', 'Charges hors activités ordinaires'),
    ('89', 'Impôts sur le résultat'),
  ];
  static const _produits = [
    ('701', 'Ventes de marchandises (pharmacies)'),
    ('706', 'Prestations de services (soins, examens, programmes)'),
    ('707', 'Produits accessoires'),
    ('71', "Subventions d'exploitation"),
    ('73', 'Cotisations des membres'),
    ('75', 'Autres produits (dont dons et libéralités)'),
    ('77', 'Revenus financiers'),
    ('78', 'Transferts de charges'),
    ('79', 'Reprises de provisions'),
    ('82', 'Produits des cessions'),
    ('84', 'Produits hors activités ordinaires'),
    ('86', 'Reprises de subventions'),
  ];

  static int _somme(Base b, String entite, Periode p, String racine, {String? activite}) => b.entier(
      "SELECT COALESCE(SUM(l.debit - l.credit),0) FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture "
      "WHERE e.entite=? AND l.compte LIKE ? AND e.date BETWEEN ? AND ? AND e.journal <> 'CL' ${activite != null ? 'AND l.activite=?' : ''}",
      [entite, '$racine%', p.du, p.au, ?activite]);

  static Rapport compteResultat(Base b, String entite, Periode p) {
    final nonLucratif = _sycebnl(b, entite);
    final ch = [for (final (r, l) in _charges) [r, l, _somme(b, entite, p, r)]].where((x) => x[2] != 0).toList();
    final pr = [for (final (r, l) in _produits) [r, l, -_somme(b, entite, p, r)]].where((x) => x[2] != 0).toList();
    final tc = ch.fold<int>(0, (t, x) => t + (x[2] as int));
    final tp = pr.fold<int>(0, (t, x) => t + (x[2] as int));
    final res = tp - tc;
    final precedent = Periode(p.anneePrecedente.du, p.anneePrecedente.au);
    final resN1 = -_somme(b, entite, precedent, '7') - _somme(b, entite, precedent, '6') - _somme(b, entite, precedent, '8');
    return Rapport(
      titre: nonLucratif ? 'Compte de résultat (ressources et emplois)' : 'Compte de résultat',
      entite: entite,
      periode: p.libelle,
      filtres: [_ref(b, entite)],
      sections: [
        Section(
            titre: nonLucratif ? 'Ressources (produits)' : 'Produits',
            colonnes: const [Colonne('Comptes', poids: 0.7), Colonne('Rubrique', poids: 4), Colonne('Montant', type: TypeColonne.montant, poids: 1.4)],
            lignes: pr,
            libelleTotal: 'TOTAL DES PRODUITS'),
        Section(
            titre: nonLucratif ? 'Emplois (charges)' : 'Charges',
            colonnes: const [Colonne('Comptes', poids: 0.7), Colonne('Rubrique', poids: 4), Colonne('Montant', type: TypeColonne.montant, poids: 1.4)],
            lignes: ch,
            libelleTotal: 'TOTAL DES CHARGES'),
      ],
      synthese: [
        ('Total des produits', fcfa(tp)),
        ('Total des charges', fcfa(tc)),
        ('Même période N-1', fcfa(resN1)),
        (res >= 0 ? (nonLucratif ? 'Excédent' : 'Bénéfice') : (nonLucratif ? 'Déficit' : 'Perte'), fcfa(res)),
      ],
      signatures: const ['Le comptable', 'La direction'],
    );
  }

  /// Résultat par activité, avec répartition des charges communes
  /// (administration) selon la clé paramétrée.
  static Rapport resultatAnalytique(Base b, String entite, Periode p) {
    final acts = b.lignes("SELECT code, libelle FROM activites WHERE entite=? AND code NOT LIKE 'ADM%' ORDER BY code", [entite]);
    final ca = {for (final a in acts) a['code'] as String: -_somme(b, entite, p, '7', activite: a['code'] as String)};
    final directes = {for (final a in acts) a['code'] as String: _somme(b, entite, p, '6', activite: a['code'] as String)};
    final communes = _somme(b, entite, p, '6') - directes.values.fold<int>(0, (t, v) => t + v);
    final cle = b.param('cle_repartition', 'chiffre_affaires');
    final codes = acts.map((a) => a['code'] as String).toList();
    final bases = cle == 'egale' ? [for (final _ in codes) 1] : [for (final c in codes) ca[c]! > 0 ? ca[c]! : 0];
    final totalBase = bases.fold<int>(0, (t, v) => t + v);
    // Répartition exacte au franc près (plus fort reste).
    final parts = <int>[];
    if (totalBase > 0) {
      final bruts = [for (final v in bases) communes * v / totalBase];
      final ent = [for (final x in bruts) x.floor()];
      var reste = communes - ent.fold<int>(0, (t, v) => t + v);
      final ordre = List.generate(codes.length, (i) => i)..sort((a, c) => (bruts[c] - ent[c]).compareTo(bruts[a] - ent[a]));
      for (final i in ordre) {
        if (reste <= 0) break;
        ent[i]++;
        reste--;
      }
      parts.addAll(ent);
    } else {
      parts.addAll(List.filled(codes.length, 0));
    }
    final pct = Rapports.pourcentages([for (final c in codes) ca[c]! > 0 ? ca[c]! : 0]);
    return Rapport(
      titre: 'Résultat par activité (comptabilité analytique)',
      entite: entite,
      periode: p.libelle,
      filtres: [_ref(b, entite), 'Charges communes réparties selon : ${cle == 'egale' ? 'parts égales' : 'chiffre d’affaires'}'],
      paysage: true,
      sections: [
        Section(colonnes: const [
          Colonne('Activité', poids: 2.5),
          Colonne('Recettes', type: TypeColonne.montant),
          Colonne('Part des recettes', type: TypeColonne.pourcentage, poids: 0.8),
          Colonne('Charges directes', type: TypeColonne.montant),
          Colonne('Charges communes', type: TypeColonne.montant),
          Colonne('Résultat', type: TypeColonne.montant),
        ], lignes: [
          for (var i = 0; i < codes.length; i++)
            [acts[i]['libelle'], ca[codes[i]], pct[i], directes[codes[i]], parts[i], ca[codes[i]]! - directes[codes[i]]! - parts[i]]
        ], total: [
          'TOTAL',
          ca.values.fold<int>(0, (t, v) => t + v),
          ca.values.any((v) => v > 0) ? 100 : 0,
          directes.values.fold<int>(0, (t, v) => t + v),
          parts.fold<int>(0, (t, v) => t + v),
          ca.values.fold<int>(0, (t, v) => t + v) - directes.values.fold<int>(0, (t, v) => t + v) - parts.fold<int>(0, (t, v) => t + v),
        ]),
      ],
    );
  }

  // ------------------------------------------------------------ bilan
  static Map<String, int> _soldesBilan(Base b, String entite, String date) {
    final r = <String, int>{};
    for (final l in b.lignes(
        'SELECT l.compte, SUM(l.debit - l.credit) AS solde FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture '
        'WHERE e.entite=? AND e.date<=? GROUP BY l.compte',
        [entite, date])) {
      r[l['compte'] as String] = l['solde'] as int;
    }
    return r;
  }

  static Rapport bilan(Base b, String entite, String date) {
    final nonLucratif = _sycebnl(b, entite);
    final s = _soldesBilan(b, entite, date);
    int somme(bool Function(String c) f, {bool debiteurs = false, bool crediteurs = false}) => s.entries
        .where((e) => f(e.key))
        .map((e) => e.value)
        .where((v) => !debiteurs || v > 0)
        .where((v) => !crediteurs || v < 0)
        .fold<int>(0, (t, v) => t + v);
    final immoBrut = somme((c) => c.startsWith('2') && !c.startsWith('28') && !c.startsWith('29'));
    final amort = -somme((c) => c.startsWith('28') || c.startsWith('29'));
    final stocks = somme((c) => c.startsWith('3'));
    final creances = somme((c) => c.startsWith('4'), debiteurs: true);
    final tresoActif = somme((c) => c.startsWith('5'), debiteurs: true);
    final capitaux = -somme((c) => c.startsWith('10') || c.startsWith('11') || c.startsWith('12') || c.startsWith('13'));
    final resultatEnCours = -somme((c) => c.startsWith('6') || c.startsWith('7') || c.startsWith('8'));
    final subInv = -somme((c) => c.startsWith('14') || c.startsWith('15'));
    final dettesFin = -somme((c) => c.startsWith('16') || c.startsWith('17') || c.startsWith('18') || c.startsWith('19'));
    final dettes = -somme((c) => c.startsWith('4'), crediteurs: true);
    final tresoPassif = -somme((c) => c.startsWith('5'), crediteurs: true);
    const col = [Colonne('Rubrique', poids: 4), Colonne('Brut', type: TypeColonne.montant), Colonne('Amortissements', type: TypeColonne.montant), Colonne('Net', type: TypeColonne.montant)];
    const colP = [Colonne('Rubrique', poids: 4), Colonne('Montant', type: TypeColonne.montant)];
    final actif = [
      ['Actif immobilisé', immoBrut, amort, immoBrut - amort],
      ['Stocks', stocks, 0, stocks],
      ['Créances (patients, organismes, personnel, autres)', creances, 0, creances],
      ['Trésorerie (caisses, banques, mobile money)', tresoActif, 0, tresoActif],
    ];
    final passif = [
      [nonLucratif ? 'Fonds propres et réserves' : 'Capitaux propres et réserves', capitaux],
      [nonLucratif ? "Excédent ou déficit de l'exercice en cours" : "Résultat de l'exercice en cours", resultatEnCours],
      [nonLucratif ? "Subventions et dons d'investissement" : "Subventions d'investissement", subInv],
      ['Dettes financières', dettesFin],
      ['Dettes (fournisseurs, personnel, organismes sociaux, État)', dettes],
      ['Trésorerie passif', tresoPassif],
    ];
    final totalActif = actif.fold<int>(0, (t, l) => t + (l[3] as int));
    final totalPassif = passif.fold<int>(0, (t, l) => t + (l[1] as int));
    return Rapport(
      titre: 'Bilan',
      entite: entite,
      periode: 'Au ${dateFr(depuisIso(date))}',
      filtres: [_ref(b, entite)],
      sections: [
        Section(titre: 'Actif', colonnes: col, lignes: actif, libelleTotal: 'TOTAL ACTIF'),
        Section(titre: nonLucratif ? 'Passif (ressources)' : 'Passif', colonnes: colP, lignes: passif, libelleTotal: 'TOTAL PASSIF'),
      ],
      synthese: [('Total actif', fcfa(totalActif)), ('Total passif', fcfa(totalPassif)), ('Écart', fcfa(totalActif - totalPassif))],
      signatures: const ['Le comptable', 'La direction'],
    );
  }

  // ------------------------------------------------------------ rapprochement
  static Rapport rapprochement(Base b, String tresorerie, String date) {
    final t = Tresorerie.compte(b, tresorerie);
    final releve = b.ligne('SELECT * FROM releves_bancaires WHERE tresorerie=? AND date<=? ORDER BY date DESC LIMIT 1', [tresorerie, date]);
    final soldeComptable = Tresorerie.solde(b, tresorerie, jusquau: date);
    final nonPointes = Comptabilite.mouvementsAvecCle(b, tresorerie, jusquau: date).where((m) => m['pointe'] != true).toList();
    final ecartNonPointe = nonPointes.fold<int>(0, (s, m) => s + (m['montant'] as int));
    final soldeReleve = releve?['solde'] as int?;
    return Rapport(
      titre: 'État de rapprochement bancaire',
      entite: t['entite'] as String,
      periode: 'Au ${dateFr(depuisIso(date))}',
      filtres: ['${t['libelle']} (compte ${t['compte']})'],
      sections: [
        Section(titre: 'Mouvements comptabilisés non encore pointés sur le relevé', colonnes: const [
          Colonne('Date', poids: 1),
          Colonne('Pièce', poids: 2),
          Colonne('Libellé', poids: 4),
          Colonne('Montant', type: TypeColonne.montant, poids: 1.3),
        ], lignes: [
          for (final m in nonPointes) [dateFr(depuisIso(m['date'] as String)), m['piece'] ?? '', m['libelle'], m['montant']]
        ]),
      ],
      synthese: [
        ('Solde comptable', fcfa(soldeComptable)),
        ('Mouvements non pointés', fcfa(ecartNonPointe)),
        ('Solde comptable rapproché', fcfa(soldeComptable - ecartNonPointe)),
        ('Solde du relevé', soldeReleve == null ? 'non saisi' : fcfa(soldeReleve)),
        ('Écart à justifier', soldeReleve == null ? 'non calculé' : fcfa(soldeComptable - ecartNonPointe - soldeReleve)),
      ],
      signatures: const ['Le comptable'],
    );
  }
}
