/// Fiche de suivi du patient interné, compte rendu du soir aux dirigeants,
/// états d'audit.
library;

import 'dart:convert';

import '../modules/depenses/depenses.dart';
import '../modules/desintox/desintox.dart';
import '../modules/hospitalisation/hospitalisation.dart';
import '../modules/rapports/rapports.dart';
import '../modules/tresorerie/tresorerie.dart';
import '../noyau/base.dart';
import '../noyau/outils.dart';
import 'modele.dart';

class EtatsSuivi {
  static List<List<Object?>> _consommations(Base b, String colonne, String id) => [
        for (final c in b.lignes('SELECT * FROM consommations WHERE $colonne=? AND annule=0 ORDER BY date, id', [id]))
          [
            dateFr(depuisIso(c['date'] as String)),
            c['designation'],
            '${c['quantite']} ${c['unite']}',
            c['facture'] == 1 ? 'Facturé en plus' : 'Compris',
            c['cout'],
            c['montant'],
          ]
      ];

  static const _colConso = [
    Colonne('Date', poids: 1),
    Colonne('Produit ou remède', poids: 2.6),
    Colonne('Quantité', poids: 1),
    Colonne('Prise en charge', poids: 1.2),
    Colonne('Coût', type: TypeColonne.montant),
    Colonne('Facturé', type: TypeColonne.montant),
  ];

  /// Fiche de suivi d'un patient en désintoxication : tout ce qui lui a été
  /// donné, versé et ce qu'il doit ; coût réel comparé à l'abonnement.
  static Rapport desintox(Base b, String dossierId) {
    final sit = Desintox.situation(b, dossierId);
    final d = sit.dossier;
    final p = b.ligne('SELECT * FROM patients WHERE id=?', [d['patient']])!;
    final prog = b.valeur('SELECT libelle FROM programmes_desintox WHERE code=?', [d['programme']]) ?? d['programme'];
    final resp = (jsonDecode(d['responsables'] as String) as List).cast<Map>();
    final fin = (d['date_sortie'] as String?) ?? dateIso(b.maintenant);
    final conso = _consommations(b, 'dossier', dossierId);
    final coutReel = conso.fold<int>(0, (t, l) => t + (l[4] as int));
    final coutCompris = conso.where((l) => l[3] == 'Compris').fold<int>(0, (t, l) => t + (l[4] as int));
    final remedes = b.lignes(
        'SELECT designation, unite, SUM(quantite) AS q, SUM(cout) AS c FROM consommations WHERE dossier=? AND annule=0 GROUP BY produit ORDER BY designation',
        [dossierId]);
    return Rapport(
      titre: 'Fiche de suivi du patient',
      periode: 'Situation au ${dateFr(b.maintenant)}',
      filtres: [
        '${p['nom']} ${p['prenoms']} · dossier ${p['numero_dossier']} · programme ${d['numero']} ($prog)',
        'Entrée le ${dateFr(depuisIso(d['date_entree'] as String))}${d['date_sortie'] != null ? ', sorti le ${dateFr(depuisIso(d['date_sortie'] as String))}' : ', en cours'} · '
            '${joursEntre(d['date_entree'] as String, fin)} jour(s)',
        'Responsables : ${resp.map((r) => '${r['nom']} (${r['lien']}, ${r['telephone']})').join(' ; ')}',
      ],
      sections: [
        Section(titre: 'Ce qui a été donné au patient', colonnes: _colConso, lignes: conso),
        Section(titre: 'Récapitulatif par produit', colonnes: const [
          Colonne('Produit ou remède', poids: 3),
          Colonne('Quantité totale', poids: 1.2),
          Colonne('Coût', type: TypeColonne.montant),
        ], lignes: [
          for (final r in remedes) [r['designation'], '${r['q']} ${r['unite']}', r['c']]
        ]),
        Section(titre: 'Versements', colonnes: const [
          Colonne('Date', poids: 1),
          Colonne('Reçu', poids: 2),
          Colonne('Payé par', poids: 2),
          Colonne('Mode', poids: 1),
          Colonne('Montant', type: TypeColonne.montant),
        ], lignes: [
          for (final v in sit.versements)
            [dateFr(depuisIso(v['date'] as String)), v['piece'], v['payeur'], Modes.libelles[v['mode']] ?? v['mode'], v['montant']]
        ]),
      ],
      synthese: [
        ('Abonnement (programme)', fcfa(d['montant_total'] as int)),
        ('Médicaments facturés en plus', fcfa((d['medicaments_factures'] as int?) ?? 0)),
        ('Total dû', fcfa(sit.total)),
        ('Total versé', fcfa(sit.verse)),
        ('Reste à payer', sit.reste == 0 ? 'Soldé' : fcfa(sit.reste)),
        ('Coût réel des produits donnés', fcfa(coutReel)),
        ('Coût des produits compris dans l\'abonnement', fcfa(coutCompris)),
        ('Abonnement moins coût des produits compris', fcfa((d['montant_total'] as int) - coutCompris)),
      ],
      signatures: const ['Le comptable', 'Responsable du programme'],
    );
  }

  /// Fiche de suivi d'un patient hospitalisé.
  static Rapport sejour(Base b, String sejourId) {
    final s = Hospitalisation.situation(b, sejourId);
    final se = s['sejour'] as Map;
    final p = b.ligne('SELECT * FROM patients WHERE id=?', [se['patient']])!;
    final conso = _consommations(b, 'sejour', sejourId);
    return Rapport(
      titre: 'Fiche de suivi du patient hospitalisé',
      periode: 'Situation au ${dateFr(b.maintenant)}',
      filtres: [
        '${p['nom']} ${p['prenoms']} · dossier ${p['numero_dossier']} · séjour ${se['numero']} · lit ${se['lit']}',
        'Entrée le ${dateFr(depuisIso(se['date_entree'] as String))} · ${s['journees']} journée(s)',
      ],
      sections: [
        Section(titre: 'Produits donnés', colonnes: _colConso, lignes: conso),
        Section(titre: 'Actes et examens', colonnes: const [
          Colonne('Date', poids: 1),
          Colonne('Acte', poids: 3),
          Colonne('Statut', poids: 1),
          Colonne('Montant', type: TypeColonne.montant),
        ], lignes: [
          for (final a in (s['actes'] as List).cast<Map>()) [dateFr(depuisIso(a['date'] as String)), a['libelle'], a['statut'], a['montant']]
        ]),
      ],
      synthese: [
        ('Journées', fcfa(s['montant_journees'] as int)),
        ('Actes', fcfa(s['total_actes'] as int)),
        ('Produits', fcfa(s['total_produits'] as int)),
        ('Total du séjour', fcfa(s['total'] as int)),
        ('Caution versée', fcfa(se['caution'] as int)),
        ((s['reste'] as int) >= 0 ? 'Reste à payer' : 'À rembourser', fcfa((s['reste'] as int).abs())),
      ],
      signatures: const ['Le comptable', 'Le médecin'],
    );
  }

  // ------------------------------------------------------------ compte rendu du soir
  static Rapport compteRendu(Base b, String date) {
    final r = Rapports.financierDuJour(b, date);
    final actes = b.lignes(
        "SELECT a.activite, t.libelle, COUNT(*) AS n, SUM(a.montant) AS m, SUM(CASE WHEN a.mode='gratuit' THEN 1 ELSE 0 END) AS g "
        'FROM actes a JOIN activites t ON t.code=a.activite WHERE a.date=? AND a.annule=0 GROUP BY a.activite ORDER BY m DESC',
        [date]);
    final ventes = b.lignes(
        "SELECT o.donnees FROM operations o WHERE o.type='stock_sortie' AND o.date_op=? AND o.uuid NOT IN (SELECT uuid_annule FROM annulations)", [date]);
    final depenses = b.lignes(
        "SELECT d.*, n.libelle AS nature_lib FROM depenses d LEFT JOIN natures_depenses n ON n.code=d.nature AND n.entite=d.entite "
        "WHERE d.date=? AND d.annule=0 AND d.statut='payee' ORDER BY d.piece",
        [date]);
    final modes = b.lignes(
        "SELECT t.id, t.libelle, t.entite, SUM(CASE WHEN m.montant>0 THEN m.montant ELSE 0 END) AS e, SUM(CASE WHEN m.montant<0 THEN -m.montant ELSE 0 END) AS s "
        "FROM mouvements_tresorerie m JOIN tresoreries t ON t.id=m.tresorerie WHERE m.date=? GROUP BY t.id ORDER BY t.entite, t.id",
        [date]);
    final versements = b.entier('SELECT COALESCE(SUM(montant),0) FROM desintox_versements WHERE date=? AND annule=0', [date]);
    final enCours = Desintox.listeTravail(b).where((s) => s.statut == 'en_cours').toList();
    final consoJour = b.lignes(
        'SELECT designation, unite, SUM(quantite) AS q FROM consommations WHERE date=? AND annule=0 GROUP BY produit', [date]);
    final alertes = Rapports.alertes(b).take(12).toList();
    final occupes = Hospitalisation.occupation(b).where((l) => l['sejour'] != null).length;
    final obs = Depenses.observations(b, date);
    final totalDepenses = depenses.fold<int>(0, (t, d) => t + (d['montant'] as int));
    return Rapport(
      titre: 'Compte rendu de la journée',
      periode: 'Journée du ${dateFr(depuisIso(date))}',
      note: r['note'] as String,
      sections: [
        Section(titre: 'Activité par service', colonnes: const [
          Colonne('Service', poids: 3),
          Colonne('Actes', type: TypeColonne.nombre),
          Colonne('Gratuités', type: TypeColonne.nombre),
          Colonne('Montant', type: TypeColonne.montant),
        ], lignes: [
          for (final a in actes) [a['libelle'], a['n'], a['g'], a['m']],
          if (ventes.isNotEmpty)
            ['Pharmacies (ventes et délivrances)', ventes.length, 0, ventes.fold<int>(0, (t, v) => t + ((jsonDecode(v['donnees'] as String)['total'] as int?) ?? 0))],
        ]),
        Section(titre: 'Dépenses de la journée', colonnes: const [
          Colonne('Pièce', poids: 1.8),
          Colonne('Nature', poids: 1.8),
          Colonne('Bénéficiaire et motif', poids: 3),
          Colonne('Montant', type: TypeColonne.montant),
        ], lignes: [
          for (final d in depenses) [d['piece'], d['nature_lib'] ?? d['compte'], '${d['beneficiaire']} : ${d['motif']}', d['montant']]
        ]),
        Section(titre: 'Encaissements et sorties par caisse, banque et mobile money', colonnes: const [
          Colonne('Compte', poids: 3),
          Colonne('Entrées', type: TypeColonne.montant),
          Colonne('Sorties', type: TypeColonne.montant),
          Colonne('Solde du soir', type: TypeColonne.montant),
        ], lignes: [
          for (final m in modes)
            [
              '${m['libelle']} (${m['entite']})',
              m['e'],
              m['s'],
              Tresorerie.solde(b, m['id'] as String, jusquau: date)
            ]
        ]),
        Section(titre: 'Désintoxication et hospitalisation', colonnes: const [Colonne('Indicateur', poids: 3), Colonne('Valeur', poids: 1.5)], lignes: [
          ['Patients en désintoxication', '${enCours.length}'],
          ['Versements reçus ce jour', fcfa(versements)],
          ['Reste à encaisser (désintoxication)', fcfa(Desintox.resteTotal(b))],
          ['Lits occupés', '$occupes'],
          for (final c in consoJour) ['${c['designation']} servi', '${c['q']} ${c['unite']}'],
        ], totaliser: false),
        if (alertes.isNotEmpty)
          Section(titre: 'Points d’attention', colonnes: const [Colonne('Alerte', poids: 2), Colonne('Détail', poids: 4)], lignes: [
            for (final a in alertes) [a['titre'], a['detail']]
          ], totaliser: false),
        Section(titre: 'Observations du comptable', colonnes: const [Colonne('Observations', poids: 6)], lignes: [
          [obs.isEmpty ? 'Aucune observation.' : obs]
        ], totaliser: false),
      ],
      synthese: [
        ('Recettes du jour', fcfa(r['recettes'] as int)),
        ('Dépenses du jour', fcfa(totalDepenses)),
        ('Encaissements', fcfa(r['encaissements'] as int)),
        ('Résultat du jour', fcfa(r['resultat'] as int)),
      ],
      signatures: const ['Le comptable'],
    );
  }
}

class EtatsAudit {
  static Rapport annulations(Base b, Periode p) => Rapport(
        titre: 'Annulations et motifs',
        periode: p.libelle,
        sections: [
          Section(colonnes: const [
            Colonne('Date', poids: 1),
            Colonne('Pièce annulée', poids: 2),
            Colonne('Nature', poids: 1.4),
            Colonne('Motif', poids: 3),
            Colonne('Annulé par', poids: 1.6),
          ], lignes: [
            for (final a in b.lignes(
                'SELECT o.piece, o.type, an.motif, x.horodatage, u.nom FROM annulations an JOIN operations o ON o.uuid=an.uuid_annule '
                'JOIN operations x ON x.uuid=an.uuid_op LEFT JOIN utilisateurs u ON u.id=x.utilisateur WHERE x.date_op BETWEEN ? AND ? ORDER BY x.horodatage',
                [p.du, p.au]))
              [dateFr(DateTime.parse(a['horodatage'] as String)), a['piece'] ?? '', a['type'], a['motif'], a['nom'] ?? '']
          ], totaliser: false),
        ],
      );

  static Rapport gratuitesRemises(Base b, Periode p) => Rapport(
        titre: 'Gratuités et remises accordées',
        periode: p.libelle,
        sections: [
          Section(colonnes: const [
            Colonne('Date', poids: 1),
            Colonne('Reçu', poids: 2),
            Colonne('Acte', poids: 2.5),
            Colonne('Nature', poids: 1),
            Colonne('Motif', poids: 1.6),
            Colonne('Valeur accordée', type: TypeColonne.montant),
          ], lignes: [
            for (final a in b.lignes(
                "SELECT a.*, json_extract(o.donnees, '\$.motif_remise') AS motif_remise FROM actes a JOIN operations o ON o.uuid=a.uuid_op "
                "WHERE a.date BETWEEN ? AND ? AND a.annule=0 AND (a.mode='gratuit' OR a.remise>0) ORDER BY a.horodatage",
                [p.du, p.au]))
              [
                dateFr(depuisIso(a['date'] as String)),
                a['piece'],
                a['libelle'],
                a['mode'] == 'gratuit' ? 'Gratuité' : 'Remise',
                a['mode'] == 'gratuit' ? a['motif_gratuite'] : a['motif_remise'],
                a['mode'] == 'gratuit' ? (a['prix_unitaire'] as int) * (a['quantite'] as int) : a['remise'],
              ]
          ]),
        ],
      );

  static Rapport ecartsCaisse(Base b, Periode p) => Rapport(
        titre: 'Écarts de caisse',
        periode: p.libelle,
        sections: [
          Section(colonnes: const [
            Colonne('Date', poids: 1),
            Colonne('Caisse', poids: 2),
            Colonne('Compté', type: TypeColonne.montant),
            Colonne('Théorique', type: TypeColonne.montant),
            Colonne('Écart', type: TypeColonne.montant),
            Colonne('Motif', poids: 2.5),
          ], lignes: [
            for (final a in b.lignes(
                'SELECT a.*, t.libelle FROM arretes_caisse a JOIN tresoreries t ON t.id=a.tresorerie WHERE a.date BETWEEN ? AND ? AND a.ecart<>0 ORDER BY a.date',
                [p.du, p.au]))
              [dateFr(depuisIso(a['date'] as String)), a['libelle'], a['compte'], a['theorique'], a['ecart'], a['motif_ecart'] ?? '']
          ]),
        ],
      );

  static Rapport modifications(Base b, Periode p) => Rapport(
        titre: 'Modifications du paramétrage (prix, montants, comptes)',
        periode: p.libelle,
        paysage: true,
        sections: [
          Section(colonnes: const [
            Colonne('Date et heure', poids: 1.5),
            Colonne('Objet', poids: 2.4),
            Colonne('Avant', poids: 2.4),
            Colonne('Après', poids: 2.4),
            Colonne('Par', poids: 1.4),
          ], lignes: [
            for (final a in b.lignes(
                "SELECT a.*, u.nom FROM audit a LEFT JOIN utilisateurs u ON u.id=a.utilisateur WHERE a.action IN ('modification','validation') "
                'AND substr(a.horodatage,1,10) BETWEEN ? AND ? ORDER BY a.id',
                [p.du, p.au]))
              [
                '${dateFr(DateTime.parse(a['horodatage'] as String))} ${heureFr(DateTime.parse(a['horodatage'] as String))}',
                a['objet'],
                _court(a['ancienne_valeur']),
                _court(a['nouvelle_valeur']),
                a['nom'] ?? a['utilisateur'],
              ]
          ], totaliser: false),
          Section(titre: 'Modifications du montant des abonnements de désintoxication', colonnes: const [
            Colonne('Date', poids: 1),
            Colonne('Dossier', poids: 1.6),
            Colonne('Ancien', type: TypeColonne.montant),
            Colonne('Nouveau', type: TypeColonne.montant),
            Colonne('Motif', poids: 3),
          ], lignes: [
            for (final o in b.lignes("SELECT * FROM operations WHERE type='desintox_montant' AND date_op BETWEEN ? AND ? ORDER BY seq", [p.du, p.au]))
              () {
                final d = jsonDecode(o['donnees'] as String) as Map;
                return [
                  dateFr(depuisIso(o['date_op'] as String)),
                  b.valeur('SELECT numero FROM desintox_dossiers WHERE id=?', [d['dossier']]) ?? '',
                  d['ancien'],
                  d['nouveau'],
                  d['motif'],
                ];
              }(),
          ], totaliser: false),
        ],
      );

  static String _court(Object? v) {
    final s = '${v ?? ''}';
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }

  /// Opérations saisies à une date passée (reprise de l'historique).
  static Rapport saisiesRetroactives(Base b, Periode p) => Rapport(
        titre: 'Saisies à une date passée',
        periode: 'Opérations datées ${p.libelle.toLowerCase()}',
        paysage: true,
        sections: [
          Section(colonnes: const [
            Colonne("Date de l'opération", poids: 1.2),
            Colonne('Saisie réelle le', poids: 1.5),
            Colonne('Pièce', poids: 2),
            Colonne('Nature', poids: 1.6),
            Colonne('Par', poids: 1.5),
          ], lignes: [
            for (final o in b.lignes(
                "SELECT o.*, u.nom FROM operations o LEFT JOIN utilisateurs u ON u.id=o.utilisateur WHERE o.date_op BETWEEN ? AND ? "
                "AND json_extract(o.donnees, '\$._saisi_le') IS NOT NULL ORDER BY o.date_op, o.seq",
                [p.du, p.au]))
              [
                dateFr(depuisIso(o['date_op'] as String)),
                () {
                  final r = DateTime.parse((jsonDecode(o['donnees'] as String) as Map)['_saisi_le'] as String);
                  return '${dateFr(r)} ${heureFr(r)}';
                }(),
                o['piece'] ?? '',
                o['type'],
                o['nom'] ?? '',
              ]
          ], totaliser: false),
        ],
      );

  /// Journal d'audit filtré (période, appareil, action).
  static Rapport journal(Base b, Periode p, {String? appareil, String? utilisateur}) => Rapport(
        titre: "Journal d'audit",
        periode: p.libelle,
        filtres: [if (appareil != null) 'Appareil : $appareil'],
        paysage: true,
        sections: [
          Section(colonnes: const [
            Colonne('Date et heure', poids: 1.5),
            Colonne('Action', poids: 1.2),
            Colonne('Objet', poids: 4),
            Colonne('Utilisateur', poids: 1.5),
            Colonne('Appareil', poids: 0.8),
          ], lignes: [
            for (final a in b.lignes(
                "SELECT a.*, u.nom FROM audit a LEFT JOIN utilisateurs u ON u.id=a.utilisateur WHERE substr(a.horodatage,1,10) BETWEEN ? AND ? "
                "${appareil != null ? 'AND a.appareil=?' : ''} ${utilisateur != null ? 'AND a.utilisateur=?' : ''} ORDER BY a.id",
                [p.du, p.au, ?appareil, ?utilisateur]))
              [
                '${dateFr(DateTime.parse(a['horodatage'] as String))} ${heureFr(DateTime.parse(a['horodatage'] as String))}',
                a['action'],
                a['objet'],
                a['nom'] ?? a['utilisateur'],
                a['appareil'],
              ]
          ], totaliser: false),
        ],
      );
}
