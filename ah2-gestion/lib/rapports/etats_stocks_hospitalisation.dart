/// États des stocks, de l'hospitalisation et des comptes de tiers.
library;

import 'dart:convert';

import '../modules/hospitalisation/hospitalisation.dart';
import '../modules/stocks/stocks.dart';
import '../modules/tresorerie/tresorerie.dart';
import '../noyau/base.dart';
import '../noyau/outils.dart';
import 'modele.dart';

class EtatsStocks {
  static String _nomStock(String? s) => s == null ? 'Tous les stocks' : Stocks.magasin(s)[0];

  /// État des stocks et valorisation au CUMP, par lot.
  static Rapport etat(Base b, String? stock, String date) {
    final produits = b.lignes('SELECT * FROM produits ${stock != null ? 'WHERE stock=?' : ''} ORDER BY stock, designation', [?stock]);
    final lignes = <List<Object?>>[];
    for (final p in produits) {
      final q = Stocks.quantite(b, p['code'] as String);
      if (q == 0 && p['actif'] == 0) continue;
      final c = Stocks.cump(b, p['code'] as String);
      final lots = Stocks.lots(b, p['code'] as String);
      lignes.add([
        p['designation'],
        '${p['forme']} ${p['dosage']}'.trim(),
        lots.map((l) => '${l['lot']}${l['peremption'] != null ? ' (${dateFr(depuisIso(l['peremption'] as String))})' : ''} : ${l['quantite']}').join(' ; '),
        q,
        p['stock_minimum'],
        c,
        q * c,
        q <= (p['stock_minimum'] as int) && (p['stock_minimum'] as int) > 0 ? 'Stock bas' : '',
      ]);
    }
    return Rapport(
      titre: 'État des stocks et valorisation',
      periode: 'Au ${dateFr(depuisIso(date))}',
      filtres: [_nomStock(stock), 'Valorisation au coût unitaire moyen pondéré (CUMP)'],
      paysage: true,
      sections: [
        Section(colonnes: const [
          Colonne('Produit', poids: 2.4),
          Colonne('Forme, dosage', poids: 1.2),
          Colonne('Lots (péremption) : quantité', poids: 3),
          Colonne('Quantité', type: TypeColonne.nombre, poids: 0.8),
          Colonne('Minimum', type: TypeColonne.nombre, poids: 0.7),
          Colonne('CUMP', type: TypeColonne.montant, poids: 0.8),
          Colonne('Valeur', type: TypeColonne.montant),
          Colonne('Alerte', poids: 0.8),
        ], lignes: lignes, total: [
          'TOTAL',
          null,
          null,
          lignes.fold<int>(0, (t, l) => t + (l[3] as int)),
          null,
          null,
          lignes.fold<int>(0, (t, l) => t + (l[6] as int)),
          null
        ]),
      ],
    );
  }

  static Rapport mouvements(Base b, String? stock, Periode p, {List<String>? types}) {
    final l = b.lignes(
        'SELECT m.*, pr.designation, pr.stock FROM mouvements_stock m JOIN produits pr ON pr.code=m.produit '
        'WHERE m.date BETWEEN ? AND ? AND m.annule=0 ${stock != null ? 'AND pr.stock=?' : ''} '
        '${types != null ? 'AND m.type IN (${List.filled(types.length, '?').join(',')})' : ''} ORDER BY m.horodatage, m.id',
        [p.du, p.au, ?stock, ...?types]);
    return Rapport(
      titre: types == null ? 'Mouvements de stock' : 'Consommations, pertes et péremptions',
      periode: p.libelle,
      filtres: [_nomStock(stock)],
      paysage: true,
      sections: [
        Section(colonnes: const [
          Colonne('Date', poids: 1),
          Colonne('Pièce', poids: 2),
          Colonne('Produit', poids: 2.5),
          Colonne('Lot', poids: 1),
          Colonne('Nature', poids: 1.4),
          Colonne('Entrées', type: TypeColonne.nombre, poids: 0.8),
          Colonne('Sorties', type: TypeColonne.nombre, poids: 0.8),
          Colonne('Coût unitaire', type: TypeColonne.montant),
          Colonne('Valeur', type: TypeColonne.montant),
        ], lignes: [
          for (final m in l)
            [
              dateFr(depuisIso(m['date'] as String)),
              m['reference'] ?? '',
              m['designation'],
              m['lot'],
              Stocks.typesSortie[m['type']] ?? (m['type'] == 'achat' ? 'Achat' : m['type'] == 'don' ? 'Don' : m['type']),
              (m['quantite'] as int) > 0 ? m['quantite'] : 0,
              (m['quantite'] as int) < 0 ? -(m['quantite'] as int) : 0,
              m['cout_unitaire'],
              (m['quantite'] as int).abs() * (m['cout_unitaire'] as int),
            ]
        ]),
      ],
    );
  }

  static Rapport inventaire(Base b, String stock) {
    final inv = b.ligne('SELECT * FROM inventaires WHERE stock=? ORDER BY date DESC LIMIT 1', [stock]);
    final lignes = inv == null ? <Map>[] : (jsonDecode(inv['lignes'] as String) as List).cast<Map>();
    return Rapport(
      titre: 'Inventaire physique : écarts',
      periode: inv == null ? 'Aucun inventaire' : 'Inventaire du ${dateFr(depuisIso(inv['date'] as String))}',
      filtres: [_nomStock(stock)],
      sections: [
        Section(colonnes: const [
          Colonne('Produit', poids: 2.5),
          Colonne('Lot', poids: 1),
          Colonne('Théorique', type: TypeColonne.nombre),
          Colonne('Compté', type: TypeColonne.nombre),
          Colonne('Écart', type: TypeColonne.nombre),
          Colonne('Valeur de l’écart', type: TypeColonne.montant),
        ], lignes: [
          for (final l in lignes)
            [b.valeur('SELECT designation FROM produits WHERE code=?', [l['produit']]) ?? l['produit'], l['lot'], l['theorique'], l['compte'], l['ecart'],
              (l['ecart'] as int) * (l['cout'] as int)]
        ]),
      ],
      signatures: const ['Le pharmacien', 'Le comptable'],
    );
  }

  /// Fiche de comptage vierge pour l'inventaire physique.
  static Rapport ficheComptage(Base b, String stock, String date) => Rapport(
        titre: "Fiche de comptage d'inventaire",
        periode: 'Au ${dateFr(depuisIso(date))}',
        filtres: [_nomStock(stock)],
        sections: [
          Section(colonnes: const [
            Colonne('Produit', poids: 3),
            Colonne('Lot', poids: 1.2),
            Colonne('Péremption', poids: 1),
            Colonne('Quantité théorique', type: TypeColonne.nombre),
            Colonne('Quantité comptée', poids: 1.2),
          ], lignes: [
            for (final p in b.lignes('SELECT * FROM produits WHERE stock=? AND actif=1 ORDER BY designation', [stock]))
              for (final l in Stocks.lots(b, p['code'] as String))
                [p['designation'], l['lot'], l['peremption'] == null ? '' : dateFr(depuisIso(l['peremption'] as String)), l['quantite'], '']
          ], totaliser: false),
        ],
        signatures: const ['Compté par', 'Vérifié par'],
      );
}

class EtatsHospitalisation {
  static Rapport occupation(Base b, String date) {
    final o = Hospitalisation.occupation(b);
    final occupes = o.where((l) => l['sejour'] != null).length;
    return Rapport(
      titre: 'Occupation des lits',
      periode: 'Situation au ${dateFr(depuisIso(date))}',
      note: '$occupes lit(s) occupé(s) sur ${o.length}, soit ${o.isEmpty ? 0 : (occupes * 100 / o.length).round()} %.',
      sections: [
        Section(colonnes: const [
          Colonne('Chambre', poids: 1),
          Colonne('Lit', poids: 0.8),
          Colonne('Catégorie', poids: 1.2),
          Colonne('Tarif par jour', type: TypeColonne.montant),
          Colonne('Patient', poids: 2.5),
          Colonne('Entrée', poids: 1),
          Colonne('Journées', type: TypeColonne.nombre, poids: 0.7),
          Colonne('Montant cumulé', type: TypeColonne.montant),
          Colonne('Caution', type: TypeColonne.montant),
        ], lignes: [
          for (final l in o)
            () {
              if (l['sejour'] == null) return [l['chambre'], l['code'], l['categorie'], l['tarif_journalier'], 'Libre', '', 0, 0, 0];
              final s = Hospitalisation.situation(b, l['sejour'] as String);
              return [
                l['chambre'], l['code'], l['categorie'], l['tarif_journalier'], '${l['nom']} ${l['prenoms']} (${l['numero_dossier']})',
                dateFr(depuisIso(l['date_entree'] as String)), s['journees'], s['total'], (s['sejour'] as Map)['caution'],
              ];
            }(),
        ]),
      ],
    );
  }

  /// Facture récapitulative d'un séjour (§6.5).
  static Rapport facture(Base b, String sejour) {
    final s = Hospitalisation.situation(b, sejour);
    final se = s['sejour'] as Map;
    final p = b.ligne('SELECT * FROM patients WHERE id=?', [se['patient']])!;
    final lignes = <List<Object?>>[
      ['Hospitalisation, lit ${se['lit']}', s['journees'], se['tarif_journalier'], s['montant_journees']],
      for (final a in (s['actes'] as List).cast<Map>()) ['${a['libelle']} (${dateFr(depuisIso(a['date'] as String))})', a['quantite'], a['prix_unitaire'], a['montant']],
    ];
    for (final o in b.lignes("SELECT donnees, date_op FROM operations WHERE type='stock_sortie' AND donnees LIKE ? AND uuid NOT IN (SELECT uuid_annule FROM annulations)",
        ['%"sejour":"$sejour"%'])) {
      for (final l in (jsonDecode(o['donnees'] as String)['lignes'] as List).cast<Map>()) {
        lignes.add(['${l['designation']} (${dateFr(depuisIso(o['date_op'] as String))})', l['quantite'], l['prix'], (l['prix'] as int) * (l['quantite'] as int)]);
      }
    }
    final reste = s['reste'] as int;
    return Rapport(
      titre: 'Facture récapitulative de séjour',
      periode: 'Séjour ${se['numero']} du ${dateFr(depuisIso(se['date_entree'] as String))}${se['date_sortie'] != null ? ' au ${dateFr(depuisIso(se['date_sortie'] as String))}' : ' (en cours)'}',
      filtres: ['Patient : ${p['nom']} ${p['prenoms']} · dossier ${p['numero_dossier']}'],
      sections: [
        Section(colonnes: const [
          Colonne('Désignation', poids: 4),
          Colonne('Quantité', type: TypeColonne.nombre, poids: 0.8),
          Colonne('Prix unitaire', type: TypeColonne.montant),
          Colonne('Montant', type: TypeColonne.montant),
        ], lignes: lignes, total: ['TOTAL', null, null, s['total']]),
      ],
      synthese: [
        ('Total du séjour', fcfa(s['total'] as int)),
        ('Caution versée', fcfa(se['caution'] as int)),
        (reste >= 0 ? 'Reste à payer' : 'À rembourser au patient', fcfa(reste.abs())),
      ],
      signatures: const ['Le caissier', 'Le patient ou son représentant'],
    );
  }
}

class EtatsTiers {
  /// Relevé de compte d'un patient (actes, paiements, solde) (§8).
  static Rapport releveCompte(Base b, String patient, Periode p) {
    final pa = b.ligne('SELECT * FROM patients WHERE id=?', [patient]);
    final lignes = b.lignes(
        "SELECT e.date, e.piece, e.libelle, l.debit, l.credit FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture "
        "WHERE l.tiers=? AND l.compte LIKE '41%' AND e.date BETWEEN ? AND ? ORDER BY e.date, e.id",
        [patient, p.du, p.au]);
    final anterieur = b.entier(
        "SELECT COALESCE(SUM(l.debit-l.credit),0) FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture WHERE l.tiers=? AND l.compte LIKE '411%' AND e.date<?",
        [patient, p.du]);
    final actesPayes = b.lignes("SELECT date, piece, libelle, montant, mode FROM actes WHERE patient=? AND date BETWEEN ? AND ? AND annule=0 AND mode NOT IN ('credit','pec') ORDER BY date",
        [patient, p.du, p.au]);
    var solde = anterieur;
    return Rapport(
      titre: 'Relevé de compte patient',
      periode: p.libelle,
      filtres: [if (pa != null) '${pa['nom']} ${pa['prenoms']} · dossier ${pa['numero_dossier']}'],
      sections: [
        Section(titre: 'Compte (actes à crédit, versements, règlements)', colonnes: const [
          Colonne('Date', poids: 1),
          Colonne('Pièce', poids: 2),
          Colonne('Libellé', poids: 4),
          Colonne('Facturé', type: TypeColonne.montant),
          Colonne('Payé', type: TypeColonne.montant),
          Colonne('Solde', type: TypeColonne.montant),
        ], lignes: [
          ['', '', 'Solde antérieur', 0, 0, anterieur],
          for (final l in lignes)
            () {
              solde += (l['debit'] as int) - (l['credit'] as int);
              return [dateFr(depuisIso(l['date'] as String)), l['piece'] ?? '', l['libelle'], l['debit'], l['credit'], solde];
            }(),
        ], total: null, totaliser: false),
        Section(titre: 'Actes payés comptant', colonnes: const [
          Colonne('Date', poids: 1),
          Colonne('Reçu', poids: 2),
          Colonne('Acte', poids: 4),
          Colonne('Mode', poids: 1),
          Colonne('Montant', type: TypeColonne.montant),
        ], lignes: [
          for (final a in actesPayes) [dateFr(depuisIso(a['date'] as String)), a['piece'], a['libelle'], Modes.libelles[a['mode']] ?? a['mode'], a['montant']]
        ]),
      ],
      synthese: [('Solde dû au ${dateFr(depuisIso(p.au))}', fcfa(solde))],
    );
  }

  /// Liste de relance : créances anciennes avec contact.
  static Rapport relances(Base b, String date, {int joursMin = 30}) {
    final tiers = b.lignes(
        "SELECT l.tiers, SUM(l.debit-l.credit) AS solde, MIN(CASE WHEN l.debit>0 THEN e.date END) AS plus_ancienne "
        "FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture WHERE l.compte LIKE '411%' AND l.tiers IS NOT NULL "
        "GROUP BY l.tiers HAVING solde > 0 ORDER BY plus_ancienne",
        []);
    return Rapport(
      titre: 'Créances à relancer',
      periode: 'Au ${dateFr(depuisIso(date))}, créances de plus de $joursMin jours',
      sections: [
        Section(colonnes: const [
          Colonne('Patient ou organisme', poids: 3),
          Colonne('Contact', poids: 1.6),
          Colonne('Personne à prévenir', poids: 2),
          Colonne('Depuis le', poids: 1),
          Colonne('Montant dû', type: TypeColonne.montant),
        ], lignes: [
          for (final t in tiers.where((t) => t['plus_ancienne'] != null && joursEntre(t['plus_ancienne'] as String, date) >= joursMin))
            () {
              final p = b.ligne('SELECT * FROM patients WHERE id=?', [t['tiers']]);
              return [
                p == null ? t['tiers'] : '${p['nom']} ${p['prenoms']} (${p['numero_dossier']})',
                p?['contact'] ?? '',
                p?['personne_a_prevenir'] ?? '',
                dateFr(depuisIso(t['plus_ancienne'] as String)),
                t['solde'],
              ];
            }(),
        ]),
      ],
    );
  }
}
