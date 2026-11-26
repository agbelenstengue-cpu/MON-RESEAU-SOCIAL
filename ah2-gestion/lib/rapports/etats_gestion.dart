/// États de gestion (§8) : filtrables par période, service, utilisateur,
/// appareil et subvention ; comparaison avec la période précédente et la
/// même période de l'année précédente.
library;

import 'dart:convert';

import '../modules/desintox/desintox.dart';
import '../modules/dons/dons.dart';
import '../modules/rapports/rapports.dart';
import '../modules/releves/releves.dart';
import '../modules/tresorerie/tresorerie.dart';
import '../noyau/base.dart';
import '../noyau/outils.dart';
import 'modele.dart';

class EtatsGestion {
  static String _lib(Base b, String table, String col, String? v, String nom) =>
      v == null ? '' : '$nom : ${b.valeur('SELECT $col FROM $table WHERE ${table == 'utilisateurs' ? 'id' : 'code'}=?', [v]) ?? v}';

  static List<String> _filtres(Base b, Filtres f) => [
        if (f.entite != null) f.entite == 'CS' ? 'Centre de santé' : 'ONG',
        if (f.activite != null) _lib(b, 'activites', 'libelle', f.activite, 'Service'),
        if (f.utilisateur != null) _lib(b, 'utilisateurs', 'nom', f.utilisateur, 'Utilisateur'),
        if (f.appareil != null) 'Appareil : ${f.appareil}',
        if (f.subvention != null) 'Subvention : ${b.valeur('SELECT reference FROM subventions WHERE id=?', [f.subvention]) ?? f.subvention}',
      ];

  /// Conditions SQL communes sur les écritures (e) et leurs lignes (l).
  static (String, List<Object?>) _condEcritures(Filtres f, Periode p) {
    final w = <String>['e.date BETWEEN ? AND ?', "e.journal <> 'CL'"];
    final a = <Object?>[p.du, p.au];
    if (f.entite != null) {
      w.add('e.entite=?');
      a.add(f.entite);
    }
    if (f.activite != null) {
      w.add('l.activite=?');
      a.add(f.activite);
    }
    if (f.utilisateur != null) {
      w.add('e.utilisateur=?');
      a.add(f.utilisateur);
    }
    if (f.appareil != null) {
      w.add('e.appareil=?');
      a.add(f.appareil);
    }
    if (f.subvention != null) {
      w.add("(l.subvention=? OR l.subvention LIKE ?)");
      a.addAll([f.subvention, '${f.subvention}#%']);
    }
    return (w.join(' AND '), a);
  }

  static int _total(Base b, Filtres f, Periode p, String racine) {
    final (w, a) = _condEcritures(f, p);
    return b.entier('SELECT COALESCE(SUM(l.debit-l.credit),0) FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture WHERE $w AND l.compte LIKE ?',
        [...a, '$racine%']);
  }

  static String _evolution(int actuel, int reference) {
    if (reference == 0) return actuel == 0 ? 'stable' : 'nouveau';
    final e = ((actuel - reference) * 100 / reference.abs()).round();
    return e == 0 ? 'stable' : '${e > 0 ? '+' : ''}$e %';
  }

  // ------------------------------------------------------------ rapport financier
  static Rapport financier(Base b, Filtres f) {
    final p = f.periode;
    final (w, a) = _condEcritures(f, p);
    final parAct = b.lignes(
        "SELECT COALESCE(l.activite,'?') AS activite, SUM(l.credit - l.debit) AS montant FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture "
        "WHERE $w AND l.compte LIKE '7%' GROUP BY l.activite ORDER BY montant DESC",
        a);
    final libelles = {for (final x in b.lignes('SELECT code, libelle FROM activites')) x['code']: x['libelle']};
    final pct = Rapports.pourcentages([for (final x in parAct) (x['montant'] as int) > 0 ? x['montant'] as int : 0]);
    int recettes(Periode q) => -_total(b, f, q, '7');
    int charges(Periode q) => _total(b, f, q, '6');
    final rec = recettes(p), ch = charges(p);
    final prec = p.precedente, n1 = p.anneePrecedente;
    final moyenne = p.jours == 1 ? null : rec ~/ p.jours;
    final lignes = [for (final l in parAct) l];
    final note = StringBuffer('Recettes ${fcfa(rec)}');
    if (lignes.isNotEmpty && rec > 0) note.write(', dont ${pct.first} % ${(libelles[lignes.first['activite']] ?? '').toString().toLowerCase()}');
    note.write('. Charges ${fcfa(ch)}, résultat ${fcfa(rec - ch)}');
    final rp = recettes(prec);
    if (rp != 0) note.write('. Recettes ${_evolution(rec, rp)} par rapport à la période précédente');
    note.write('.');
    return Rapport(
      titre: 'Rapport financier',
      entite: f.entite ?? 'CS',
      periode: p.libelle,
      filtres: _filtres(b, f),
      note: note.toString(),
      sections: [
        Section(titre: 'Recettes par activité', colonnes: const [
          Colonne('Activité', poids: 3),
          Colonne('Recettes', type: TypeColonne.montant),
          Colonne('Part', type: TypeColonne.pourcentage, poids: 0.7),
        ], lignes: [
          for (var i = 0; i < lignes.length; i++) [libelles[lignes[i]['activite']] ?? lignes[i]['activite'], lignes[i]['montant'], pct[i]]
        ], total: ['TOTAL', rec, rec > 0 ? 100 : 0]),
        Section(titre: 'Comparaisons', colonnes: const [
          Colonne('Période', poids: 3),
          Colonne('Recettes', type: TypeColonne.montant),
          Colonne('Charges', type: TypeColonne.montant),
          Colonne('Résultat', type: TypeColonne.montant),
          Colonne('Évolution des recettes', poids: 1.2),
        ], lignes: [
          [p.libelle, rec, ch, rec - ch, ''],
          ['Période précédente : ${prec.libelle}', rp, charges(prec), rp - charges(prec), _evolution(rec, rp)],
          ['Année précédente : ${n1.libelle}', recettes(n1), charges(n1), recettes(n1) - charges(n1), _evolution(rec, recettes(n1))],
        ], totaliser: false),
      ],
      synthese: [
        ('Recettes', fcfa(rec)),
        ('Charges', fcfa(ch)),
        ('Encaissements', fcfa(Rapports.encaissements(b, du: p.du, au: p.au, entite: f.entite))),
        if (moyenne != null) ('Recette moyenne par jour', fcfa(moyenne)),
        ('Résultat', fcfa(rec - ch)),
      ],
    );
  }

  // ------------------------------------------------------------ activité d'un service
  static (String, List<Object?>) _condActes(Filtres f) {
    final w = <String>['a.date BETWEEN ? AND ?', 'a.annule=0'];
    final a = <Object?>[f.periode.du, f.periode.au];
    if (f.activite != null) {
      w.add('a.activite=?');
      a.add(f.activite);
    }
    if (f.utilisateur != null) {
      w.add('a.utilisateur=?');
      a.add(f.utilisateur);
    }
    if (f.appareil != null) {
      w.add('a.appareil=?');
      a.add(f.appareil);
    }
    if (f.entite != null) {
      w.add('a.activite IN (SELECT code FROM activites WHERE entite=?)');
      a.add(f.entite);
    }
    return (w.join(' AND '), a);
  }

  static Rapport activite(Base b, Filtres f) {
    final (w, a) = _condActes(f);
    final parActe = b.lignes(
        "SELECT a.libelle, COUNT(*) AS n, SUM(a.quantite) AS q, SUM(CASE WHEN a.mode='gratuit' THEN 1 ELSE 0 END) AS gratuits, SUM(a.montant) AS m "
        "FROM actes a WHERE $w GROUP BY a.code_acte ORDER BY m DESC",
        a);
    final parUtilisateur = b.lignes(
        "SELECT COALESCE(u.nom, a.utilisateur) AS nom, COUNT(*) AS n, SUM(a.montant) AS m FROM actes a LEFT JOIN utilisateurs u ON u.id=a.utilisateur "
        "WHERE $w GROUP BY a.utilisateur ORDER BY m DESC",
        a);
    final parPraticien = b.lignes(
        "SELECT COALESCE(NULLIF(a.praticien,''), 'Non précisé') AS p, COUNT(*) AS n, SUM(a.montant) AS m FROM actes a WHERE $w GROUP BY 1 ORDER BY m DESC",
        a);
    final parMode = b.lignes("SELECT a.mode, COUNT(*) AS n, SUM(a.montant) AS m FROM actes a WHERE $w GROUP BY a.mode ORDER BY m DESC", a);
    final prec = Filtres(f.periode.precedente, activite: f.activite, utilisateur: f.utilisateur, appareil: f.appareil, entite: f.entite);
    final (w2, a2) = _condActes(prec);
    final totalPrec = b.entier('SELECT COALESCE(SUM(a.montant),0) FROM actes a WHERE $w2', a2);
    final nbPrec = b.entier('SELECT COUNT(*) FROM actes a WHERE $w2', a2);
    final total = parActe.fold<int>(0, (t, l) => t + (l['m'] as int));
    final nb = parActe.fold<int>(0, (t, l) => t + (l['n'] as int));
    return Rapport(
      titre: "Activité ${f.activite != null ? 'du service' : 'des services'}",
      entite: f.entite ?? 'CS',
      periode: f.periode.libelle,
      filtres: _filtres(b, f),
      note: '$nb actes pour ${fcfa(total)} ; période précédente : $nbPrec actes pour ${fcfa(totalPrec)} (${_evolution(total, totalPrec)}).',
      sections: [
        Section(titre: "Par type d'acte", colonnes: const [
          Colonne('Acte', poids: 3),
          Colonne('Nombre', type: TypeColonne.nombre),
          Colonne('Quantité', type: TypeColonne.nombre),
          Colonne('Gratuités', type: TypeColonne.nombre),
          Colonne('Montant', type: TypeColonne.montant),
        ], lignes: [
          for (final l in parActe) [l['libelle'], l['n'], l['q'], l['gratuits'], l['m']]
        ]),
        Section(titre: 'Par praticien ou prestataire', colonnes: const [
          Colonne('Praticien', poids: 3),
          Colonne('Actes', type: TypeColonne.nombre),
          Colonne('Montant', type: TypeColonne.montant),
        ], lignes: [
          for (final l in parPraticien) [l['p'], l['n'], l['m']]
        ]),
        Section(titre: 'Par utilisateur ayant saisi', colonnes: const [
          Colonne('Utilisateur', poids: 3),
          Colonne('Actes', type: TypeColonne.nombre),
          Colonne('Montant', type: TypeColonne.montant),
        ], lignes: [
          for (final l in parUtilisateur) [l['nom'], l['n'], l['m']]
        ]),
        Section(titre: 'Par mode de paiement', colonnes: const [
          Colonne('Mode', poids: 3),
          Colonne('Actes', type: TypeColonne.nombre),
          Colonne('Montant', type: TypeColonne.montant),
        ], lignes: [
          for (final l in parMode) [Modes.libelles[l['mode']] ?? l['mode'], l['n'], l['m']]
        ]),
      ],
    );
  }

  /// Liste détaillée des actes (contrôle sur place) avec case « Constaté ».
  static Rapport listeActes(Base b, Filtres f) {
    final (w, a) = _condActes(f);
    final l = b.lignes(
        'SELECT a.*, p.numero_dossier, u.nom AS saisi_par FROM actes a LEFT JOIN patients p ON p.id=a.patient '
        'LEFT JOIN utilisateurs u ON u.id=a.utilisateur WHERE $w ORDER BY a.horodatage, a.id',
        a);
    return Rapport(
      titre: 'Liste détaillée des actes à contrôler',
      entite: f.entite ?? 'CS',
      periode: f.periode.libelle,
      filtres: _filtres(b, f),
      paysage: true,
      sections: [
        Section(colonnes: const [
          Colonne('Date et heure', poids: 1.5),
          Colonne('Reçu', poids: 2),
          Colonne('Dossier', poids: 1.4),
          Colonne('Acte', poids: 2.6),
          Colonne('Montant', type: TypeColonne.montant),
          Colonne('Mode', poids: 1.1),
          Colonne('Saisi par', poids: 1.6),
          Colonne('Appareil', poids: 0.7),
          Colonne('Constaté', poids: 0.8),
        ], lignes: [
          for (final x in l)
            [
              '${dateFr(DateTime.parse(x['horodatage'] as String))} ${heureFr(DateTime.parse(x['horodatage'] as String))}',
              x['piece'],
              x['numero_dossier'] ?? '',
              (x['quantite'] as int) > 1 ? '${x['libelle']} x${x['quantite']}' : x['libelle'],
              x['montant'],
              Modes.libelles[x['mode']] ?? x['mode'],
              x['saisi_par'] ?? '',
              x['appareil'],
              '[  ]',
            ]
        ]),
      ],
      signatures: const ['Responsable du service', 'Contrôleur'],
    );
  }

  // ------------------------------------------------------------ trésorerie
  static Rapport brouillard(Base b, String tresorerie, Periode p) {
    final t = Tresorerie.compte(b, tresorerie);
    final ouverture = Tresorerie.solde(b, tresorerie, jusquau: ajouterJours(p.du, -1));
    final mvts = b.lignes('SELECT * FROM mouvements_tresorerie WHERE tresorerie=? AND date BETWEEN ? AND ? ORDER BY horodatage, id',
        [tresorerie, p.du, p.au]);
    var solde = ouverture;
    final lignes = <List<Object?>>[
      [dateFr(depuisIso(p.du)), '', "Solde d'ouverture", 0, 0, ouverture]
    ];
    for (final m in mvts) {
      final v = m['montant'] as int;
      solde += v;
      lignes.add([dateFr(depuisIso(m['date'] as String)), m['piece'] ?? '', m['libelle'], v > 0 ? v : 0, v < 0 ? -v : 0, solde]);
    }
    return Rapport(
      titre: 'Brouillard de caisse',
      entite: t['entite'] as String,
      periode: p.libelle,
      filtres: ['${t['libelle']} (compte ${t['compte']})'],
      sections: [
        Section(colonnes: const [
          Colonne('Date', poids: 1),
          Colonne('Pièce', poids: 2),
          Colonne('Libellé', poids: 4),
          Colonne('Entrées', type: TypeColonne.montant),
          Colonne('Sorties', type: TypeColonne.montant),
          Colonne('Solde', type: TypeColonne.montant),
        ], lignes: lignes, total: [
          'TOTAL',
          null,
          null,
          lignes.fold<int>(0, (s, l) => s + (l[3] as int)),
          lignes.fold<int>(0, (s, l) => s + (l[4] as int)),
          solde
        ]),
      ],
      signatures: const ['Le caissier', 'Le comptable'],
    );
  }

  static Rapport recus(Base b, Filtres f) {
    final w = <String>['o.date_op BETWEEN ? AND ?', 'o.piece IS NOT NULL'];
    final a = <Object?>[f.periode.du, f.periode.au];
    if (f.utilisateur != null) {
      w.add('o.utilisateur=?');
      a.add(f.utilisateur);
    }
    if (f.appareil != null) {
      w.add('o.appareil=?');
      a.add(f.appareil);
    }
    if (f.entite != null) {
      w.add('o.entite=?');
      a.add(f.entite);
    }
    final l = b.lignes(
        "SELECT o.*, an.motif AS motif_annulation, u.nom FROM operations o LEFT JOIN annulations an ON an.uuid_annule=o.uuid "
        "LEFT JOIN utilisateurs u ON u.id=o.utilisateur WHERE ${w.join(' AND ')} ORDER BY o.horodatage",
        a);
    int montant(Map<String, Object?> o) {
      final d = jsonDecode(o['donnees'] as String) as Map;
      return ((d['total'] ?? d['montant']) as int?) ?? 0;
    }

    return Rapport(
      titre: 'Reçus et pièces émis et annulés',
      entite: f.entite ?? 'CS',
      periode: f.periode.libelle,
      filtres: _filtres(b, f),
      paysage: true,
      sections: [
        Section(colonnes: const [
          Colonne('Date et heure', poids: 1.5),
          Colonne('Pièce', poids: 2.2),
          Colonne('Nature', poids: 1.6),
          Colonne('Montant', type: TypeColonne.montant),
          Colonne('Saisi par', poids: 1.6),
          Colonne('Appareil', poids: 0.7),
          Colonne('Statut', poids: 2.2),
        ], lignes: [
          for (final o in l)
            [
              '${dateFr(DateTime.parse(o['horodatage'] as String))} ${heureFr(DateTime.parse(o['horodatage'] as String))}',
              o['piece'],
              o['type'],
              montant(o),
              o['nom'] ?? '',
              o['appareil'],
              o['motif_annulation'] == null ? 'Valide' : 'Annulé : ${o['motif_annulation']}',
            ]
        ], totaliser: false),
      ],
    );
  }

  // ------------------------------------------------------------ désintoxication
  static Rapport versementsDesintox(Base b, Periode p) => Rapport(
        titre: 'Versements reçus en désintoxication',
        periode: p.libelle,
        sections: [
          Section(colonnes: const [
            Colonne('Date', poids: 1),
            Colonne('Reçu', poids: 2),
            Colonne('Dossier', poids: 1.4),
            Colonne('Payé par', poids: 2),
            Colonne('Mode', poids: 1),
            Colonne('Montant', type: TypeColonne.montant),
          ], lignes: [
            for (final v in b.lignes(
                'SELECT v.*, d.numero FROM desintox_versements v JOIN desintox_dossiers d ON d.id=v.dossier WHERE v.date BETWEEN ? AND ? AND v.annule=0 ORDER BY v.horodatage',
                [p.du, p.au]))
              [dateFr(depuisIso(v['date'] as String)), v['piece'], v['numero'], v['payeur'], Modes.libelles[v['mode']] ?? v['mode'], v['montant']]
          ]),
        ],
      );

  /// État des patients en désintoxication (en cours, ou sortis avec solde dû).
  static Rapport desintoxEnCours(Base b, String date, {bool avecSoldeDu = true}) {
    final sits = [
      ...Desintox.listeTravail(b).where((s) => s.statut == 'en_cours'),
      if (avecSoldeDu) ...Desintox.listeTravail(b, onglet: 'solde_du'),
    ];
    final retards = {for (final e in Desintox.echeancesImpayees(b)) e['dossier']: e};
    return Rapport(
      titre: 'État des patients en désintoxication',
      periode: 'Situation au ${dateFr(depuisIso(date))}',
      paysage: true,
      sections: [
        Section(colonnes: const [
          Colonne('Patient', poids: 2.4),
          Colonne('Dossier', poids: 1.6),
          Colonne('Programme', poids: 1.8),
          Colonne('Entrée', poids: 1),
          Colonne('Jours', type: TypeColonne.nombre, poids: 0.6),
          Colonne('Statut', poids: 1.2),
          Colonne('Montant total', type: TypeColonne.montant),
          Colonne('Médicaments facturés', type: TypeColonne.montant),
          Colonne('Versé', type: TypeColonne.montant),
          Colonne('Reste', type: TypeColonne.montant),
          Colonne('Échéance en retard', type: TypeColonne.montant),
        ], lignes: [
          for (final s in sits)
            () {
              final p = b.ligne('SELECT * FROM patients WHERE id=?', [s.dossier['patient']])!;
              final prog = b.valeur('SELECT libelle FROM programmes_desintox WHERE code=?', [s.dossier['programme']]) ?? s.dossier['programme'];
              final fin = (s.dossier['date_sortie'] as String?) ?? date;
              return [
                '${p['nom']} ${p['prenoms']}',
                s.dossier['numero'],
                prog,
                dateFr(depuisIso(s.dossier['date_entree'] as String)),
                joursEntre(s.dossier['date_entree'] as String, fin),
                s.statut == 'en_cours' ? 'En cours' : 'Sorti, solde dû',
                s.dossier['montant_total'],
                s.dossier['medicaments_factures'] ?? 0,
                s.verse,
                s.reste,
                (retards[s.dossier['id']]?['manquant'] as int?) ?? 0,
              ];
            }(),
        ]),
      ],
      signatures: const ['Le comptable', 'Responsable du programme'],
    );
  }

  // ------------------------------------------------------------ dons et subventions
  static Rapport dons(Base b, Filtres f) {
    final p = f.periode;
    final l = b.lignes(
        'SELECT d.*, o.nom, o.type AS type_donateur, o.pays FROM dons d JOIN donateurs o ON o.id=d.donateur '
        'WHERE d.date BETWEEN ? AND ? AND d.annule=0 ${f.subvention != null ? 'AND d.subvention=?' : ''} ORDER BY d.date',
        [p.du, p.au, ?f.subvention]);
    final seuil = b.paramInt('seuil_don_liste');
    final parDonateur = <String, int>{};
    final parNature = <String, int>{};
    for (final d in l) {
      parDonateur[d['nom'] as String] = (parDonateur[d['nom']] ?? 0) + (d['montant'] as int);
      parNature[d['nature'] as String] = (parNature[d['nature']] ?? 0) + (d['montant'] as int);
    }
    return Rapport(
      titre: 'État des dons',
      entite: 'ONG',
      periode: p.libelle,
      filtres: _filtres(b, f),
      sections: [
        Section(titre: 'Dons reçus', colonnes: const [
          Colonne('Date', poids: 1),
          Colonne('Reçu', poids: 2),
          Colonne('Donateur', poids: 2.5),
          Colonne('Nature', poids: 1),
          Colonne('Montant', type: TypeColonne.montant),
        ], lignes: [
          for (final d in l) [dateFr(depuisIso(d['date'] as String)), d['piece'], d['nom'], d['nature'], d['montant']]
        ]),
        Section(titre: 'Par donateur', colonnes: const [Colonne('Donateur', poids: 3), Colonne('Montant', type: TypeColonne.montant)], lignes: [
          for (final e in parDonateur.entries) [e.key, e.value]
        ]),
        Section(titre: 'Par nature', colonnes: const [Colonne('Nature', poids: 3), Colonne('Montant', type: TypeColonne.montant)], lignes: [
          for (final e in parNature.entries) [e.key, e.value]
        ]),
        Section(titre: 'Dons supérieurs à ${fcfa(seuil)}', colonnes: const [
          Colonne('Date', poids: 1),
          Colonne('Donateur', poids: 3),
          Colonne('Pays', poids: 1),
          Colonne('Montant', type: TypeColonne.montant),
        ], lignes: [
          for (final d in l.where((d) => (d['montant'] as int) > seuil)) [dateFr(depuisIso(d['date'] as String)), d['nom'], d['pays'], d['montant']]
        ]),
      ],
    );
  }

  static Rapport subventions(Base b) {
    final sections = <Section>[];
    for (final s in b.lignes('SELECT s.*, d.nom FROM subventions s JOIN donateurs d ON d.id=s.bailleur ORDER BY s.debut')) {
      final recu = b.entier('SELECT COALESCE(SUM(montant),0) FROM subventions_tranches_recues WHERE subvention=? AND annule=0', [s['id']]);
      sections.add(Section(
        titre: '${s['reference']} · ${s['nom']} · accordé ${fcfa(s['montant_accorde'] as int)}, reçu ${fcfa(recu)}',
        colonnes: const [
          Colonne('Ligne budgétaire', poids: 3),
          Colonne('Budget', type: TypeColonne.montant),
          Colonne('Réalisé', type: TypeColonne.montant),
          Colonne('Solde', type: TypeColonne.montant),
        ],
        lignes: [
          for (final l in Dons.suiviSubvention(b, s['id'] as String)) [l['libelle'], l['budget'], l['realise'], l['solde']]
        ],
      ));
    }
    return Rapport(titre: 'Suivi des subventions', entite: 'ONG', periode: 'Au ${dateFr(b.maintenant)}', sections: sections);
  }

  // ------------------------------------------------------------ contrôle
  static Rapport suiviReleves(Base b, Periode p) => Rapport(
        titre: 'Suivi des relevés journaliers et des écarts',
        periode: p.libelle,
        sections: [
          Section(colonnes: const [
            Colonne('Relevé', poids: 2),
            Colonne('Date des actes', poids: 1.2),
            Colonne('Statut', poids: 1.4),
            Colonne('Retard (jours)', type: TypeColonne.nombre),
            Colonne('Écarts', type: TypeColonne.nombre),
            Colonne('Écarts ouverts', type: TypeColonne.nombre),
          ], lignes: [
            for (final r in Releves.suivi(b).where((r) => (r['date_actes'] as String).compareTo(p.du) >= 0 && (r['date_actes'] as String).compareTo(p.au) <= 0))
              [r['numero'], dateFr(depuisIso(r['date_actes'] as String)), r['statut'] == 'genere' ? 'En attente' : 'Retourné signé', r['retard_jours'], r['ecarts'], r['ecarts_ouverts']]
          ]),
        ],
      );

  static Rapport anomalies(Base b, Periode p) => Rapport(
        titre: 'Anomalies de synchronisation',
        periode: p.libelle,
        sections: [
          Section(colonnes: const [
            Colonne('Date', poids: 1.2),
            Colonne('Type', poids: 1.5),
            Colonne('Détail', poids: 5),
            Colonne('Statut', poids: 1),
          ], lignes: [
            for (final a in b.lignes('SELECT * FROM anomalies_sync WHERE substr(horodatage,1,10) BETWEEN ? AND ? ORDER BY id', [p.du, p.au]))
              [dateFr(DateTime.parse(a['horodatage'] as String)), a['type'], a['detail'], a['statut'] == 'a_traiter' ? 'À traiter' : 'Traitée']
          ]),
        ],
      );
}
