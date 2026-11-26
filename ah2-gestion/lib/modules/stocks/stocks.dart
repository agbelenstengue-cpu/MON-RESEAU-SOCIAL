/// Stocks (§6.8, §6.9, §6.4) : pharmacie moderne, pharmacie traditionnelle,
/// réactifs du laboratoire. Gestion par lots, sortie FEFO (premier périmé,
/// premier sorti), valorisation au coût unitaire moyen pondéré (CUMP),
/// inventaire physique, alertes, fournisseurs et achats.
///
/// Le stock n'est jamais stocké : il est TOUJOURS calculé (entrées moins
/// sorties). Le CUMP est recalculé dans l'ordre chronologique des mouvements,
/// donc identique sur tous les appareils.
library;

import 'dart:convert';

import '../../noyau/base.dart';
import '../../noyau/operations.dart';
import '../../noyau/outils.dart';
import '../../noyau/session.dart';
import '../comptabilite/moteur.dart';
import '../parametrage/parametrage.dart';
import '../parametrage/referentiels.dart';
import '../tresorerie/tresorerie.dart';

class LigneStock {
  final String produit;
  final int quantite;
  final String? lot;
  final String? peremption; // ISO
  final int coutUnitaire; // entrées
  final int? prix; // prix de vente unitaire (sorties facturées)
  const LigneStock(this.produit, this.quantite, {this.lot, this.peremption, this.coutUnitaire = 0, this.prix});
}

class Stocks {
  static const typesSortie = {
    'vente': 'Vente',
    'delivrance_sejour': 'Délivrance pendant une hospitalisation',
    'delivrance_desintox': 'Délivrance en désintoxication',
    'distribution': 'Distribution gratuite (programme)',
    'consommation': 'Consommation du service (réactifs)',
    'peremption': 'Produit périmé',
    'casse': 'Casse',
    'perte': 'Perte',
  };

  static List<String> magasin(String stock) => List<String>.from(magasinsDefaut[stock] ?? (throw RegleMetier('Stock inconnu : $stock')));

  // ------------------------------------------------------------ produits (paramétrage)
  static void enregistrerProduit(Session s,
          {required String code,
          required String designation,
          required String stock,
          String forme = '',
          String dosage = '',
          String unite = 'unité',
          int prixVente = 0,
          int stockMinimum = 0,
          String producteur = '',
          String origine = '',
          String preparation = ''}) =>
      Parametrage.modifier(s, 'stocks', 'produit:$code', () {
        final c = code.trim().toUpperCase();
        if (!RegExp(r'^[A-Z0-9][A-Z0-9_-]{1,19}$').hasMatch(c)) throw const RegleMetier('Code produit invalide (ex. AMOX500).');
        if (designation.trim().isEmpty) throw const RegleMetier('La désignation est obligatoire.');
        magasin(stock);
        if (prixVente < 0 || stockMinimum < 0) throw const RegleMetier('Valeurs négatives interdites.');
        s.base.exec(
            'INSERT INTO produits(code, designation, stock, forme, dosage, unite, prix_vente, stock_minimum, producteur, origine, preparation) '
            'VALUES (?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(code) DO UPDATE SET designation=excluded.designation, forme=excluded.forme, '
            'dosage=excluded.dosage, unite=excluded.unite, prix_vente=excluded.prix_vente, stock_minimum=excluded.stock_minimum, '
            'producteur=excluded.producteur, origine=excluded.origine, preparation=excluded.preparation, actif=1',
            [c, designation.trim(), stock, forme, dosage, unite, prixVente, stockMinimum, producteur, origine, preparation]);
      }, nouveau: {'designation': designation, 'prix': prixVente});

  static String retirerProduit(Session s, String code) => Parametrage.modifier(s, 'stocks', 'produit:$code', () {
        final b = s.base;
        if (b.valeur('SELECT 1 FROM mouvements_stock WHERE produit=? LIMIT 1', [code]) != null) {
          if (quantite(b, code) != 0) throw const RegleMetier('Le produit a encore du stock : sortez-le ou faites un inventaire avant de le retirer.');
          b.exec('UPDATE produits SET actif=0 WHERE code=?', [code]);
          return 'désactivé';
        }
        b.exec('DELETE FROM produits WHERE code=?', [code]);
        return 'supprimé';
      }, nouveau: 'retiré');

  static Ligne produit(Base b, String code) =>
      b.ligne('SELECT * FROM produits WHERE code=?', [code]) ?? (throw RegleMetier('Produit inconnu : $code'));

  // ------------------------------------------------------------ calculs
  static int quantite(Base b, String produit, {String? lot}) => b.entier(
      'SELECT COALESCE(SUM(quantite),0) FROM mouvements_stock WHERE produit=? AND annule=0 ${lot != null ? 'AND lot=?' : ''}', [produit, ?lot]);

  /// Lots disponibles, du premier périmé au dernier (FEFO).
  static List<Ligne> lots(Base b, String produit) => b.lignes(
      'SELECT lot, MIN(peremption) AS peremption, SUM(quantite) AS quantite FROM mouvements_stock WHERE produit=? AND annule=0 '
      "GROUP BY lot HAVING SUM(quantite) > 0 ORDER BY COALESCE(MIN(peremption), '9999-12-31'), lot",
      [produit]);

  /// CUMP recalculé chronologiquement (horodatage, opération, rang).
  static int cump(Base b, String produit, {String? jusqua}) {
    var q = 0, v = 0;
    for (final m in b.lignes(
        'SELECT quantite, cout_unitaire FROM mouvements_stock WHERE produit=? AND annule=0 ${jusqua != null ? 'AND horodatage<=?' : ''} '
        'ORDER BY horodatage, uuid_op, rang',
        [produit, ?jusqua])) {
      final mq = m['quantite'] as int;
      if (mq > 0) {
        v += mq * (m['cout_unitaire'] as int);
        q += mq;
      } else if (q > 0) {
        final c = v ~/ q;
        v += mq * c;
        q += mq;
        if (q <= 0) {
          q = 0;
          v = 0;
        }
      }
    }
    return q > 0 ? (v / q).round() : 0;
  }

  static int valeur(Base b, String produit) => quantite(b, produit) * cump(b, produit);

  /// Répartit une quantité sur les lots en commençant par le premier périmé.
  static List<(String, int)> repartirFefo(Base b, String produit, int qte, {String? lot}) {
    if (lot != null) {
      final dispo = quantite(b, produit, lot: lot);
      if (qte > dispo) throw RegleMetier('Stock insuffisant pour le lot $lot : $dispo disponible(s).');
      return [(lot, qte)];
    }
    final r = <(String, int)>[];
    var reste = qte;
    for (final l in lots(b, produit)) {
      if (reste == 0) break;
      final pris = (l['quantite'] as int) < reste ? l['quantite'] as int : reste;
      r.add((l['lot'] as String, pris));
      reste -= pris;
    }
    if (reste > 0) {
      throw RegleMetier('Stock insuffisant pour $produit : ${quantite(b, produit)} disponible(s), $qte demandé(s).');
    }
    return r;
  }

  static Map<String, String> _variables(String stock) {
    final m = magasin(stock);
    return {'compte_stock': m[1], 'compte_variation': m[2], 'compte_achat': m[3], 'produit': m[4]};
  }

  // ------------------------------------------------------------ fournisseurs
  static Operation creerFournisseur(Session s, {required String nom, String contact = '', String adresse = ''}) {
    if (nom.trim().isEmpty) throw const RegleMetier('Le nom du fournisseur est obligatoire.');
    return Operations.enregistrer(s,
        type: 'fournisseur', entite: 'CS', donnees: {'id': s.base.nouvelUuid(), 'nom': nom.trim(), 'contact': contact, 'adresse': adresse});
  }

  static Operation commander(Session s, {required String fournisseur, required List<LigneStock> lignes}) {
    if (lignes.isEmpty) throw const RegleMetier('La commande est vide.');
    for (final l in lignes) {
      produit(s.base, l.produit);
      if (l.quantite <= 0) throw const RegleMetier('Quantité invalide.');
    }
    return Operations.enregistrer(s, type: 'commande', entite: 'CS', typePiece: 'BC', donnees: {
      'fournisseur': fournisseur,
      'lignes': [for (final l in lignes) {'produit': l.produit, 'quantite': l.quantite, 'cout': l.coutUnitaire}],
    });
  }

  /// Entrée en stock : réception d'achat (crée la dette fournisseur), don en
  /// nature (reçu par l'ONG, transféré au centre) ou retour.
  static Operation entrer(Session s,
      {required String stock,
      required String origine, // achat, don, retour
      required List<LigneStock> lignes,
      String? fournisseur,
      String? donateur,
      String? commande,
      String? facture}) {
    final b = s.base;
    return b.transaction(() {
      magasin(stock);
      if (!['achat', 'don', 'retour'].contains(origine)) throw const RegleMetier('Origine : achat, don ou retour.');
      if (origine == 'achat' && fournisseur == null) throw const RegleMetier('Choisissez le fournisseur.');
      if (origine == 'don' && donateur == null) throw const RegleMetier('Choisissez le donateur.');
      if (lignes.isEmpty) throw const RegleMetier('Aucun produit.');
      for (final l in lignes) {
        final p = produit(b, l.produit);
        if (p['stock'] != stock) throw RegleMetier('${p['designation']} n’appartient pas à ce stock.');
        if (l.quantite <= 0 || l.coutUnitaire < 0) throw const RegleMetier('Quantité ou coût invalide.');
        if ((l.lot ?? '').trim().isEmpty) throw RegleMetier('Numéro de lot obligatoire pour ${p['designation']}.');
        if (stock != 'LAB' && l.peremption == null) throw RegleMetier('Date de péremption obligatoire pour ${p['designation']}.');
      }
      return Operations.enregistrer(s, type: 'stock_entree', entite: 'CS', typePiece: 'ENT', donnees: {
        'stock': stock,
        'origine': origine,
        'fournisseur': fournisseur,
        'donateur': donateur,
        'commande': commande,
        'facture': facture,
        'lignes': [
          for (final l in lignes) {'produit': l.produit, 'quantite': l.quantite, 'lot': l.lot!.trim(), 'peremption': l.peremption, 'cout': l.coutUnitaire}
        ],
      });
    });
  }

  /// Sortie de stock (FEFO) : vente, délivrance (séjour, désintoxication),
  /// distribution gratuite, consommation, péremption, casse, perte.
  static Operation sortir(Session s,
      {required String stock,
      required String type,
      required List<LigneStock> lignes,
      String? patient,
      String? sejour,
      String? dossierDesintox,
      bool facturer = true,
      String mode = Modes.especes,
      String? reference,
      String? motif,
      String? beneficiaires}) {
    final b = s.base;
    return b.transaction(() {
      final m = magasin(stock);
      if (!typesSortie.containsKey(type)) throw RegleMetier('Type de sortie inconnu : $type');
      if (lignes.isEmpty) throw const RegleMetier('Aucun produit.');
      if (['peremption', 'casse', 'perte'].contains(type)) {
        s.exiger('stocks', 'valider');
        if (motif == null || motif.trim().isEmpty) throw const RegleMetier('Le motif est obligatoire.');
      }
      if (type == 'distribution' && (beneficiaires == null || beneficiaires.trim().isEmpty)) {
        throw const RegleMetier('Indiquez la liste des bénéficiaires.');
      }
      if (type == 'delivrance_sejour' && sejour == null) throw const RegleMetier('Choisissez le séjour.');
      if (type == 'delivrance_desintox' && dossierDesintox == null) throw const RegleMetier('Choisissez le dossier de désintoxication.');
      final factureVente = type == 'vente' || ((type == 'delivrance_sejour' || type == 'delivrance_desintox') && facturer);
      if (factureVente && m[4].isEmpty) throw const RegleMetier('Ce stock ne se vend pas.');
      if (type == 'vente') {
        if (mode == Modes.credit && patient == null) throw const RegleMetier('Une vente à crédit doit être rattachée à un patient.');
        if (!Modes.encaissables.contains(mode) && mode != Modes.credit) throw const RegleMetier('Mode de paiement invalide.');
        Tresorerie.verifierReference(mode, reference);
      }
      if (sejour != null) patient = b.valeur('SELECT patient FROM sejours WHERE id=? AND date_sortie IS NULL', [sejour]) as String? ?? (throw const RegleMetier('Séjour introuvable ou terminé.'));
      if (dossierDesintox != null) {
        patient = b.valeur('SELECT patient FROM desintox_dossiers WHERE id=?', [dossierDesintox]) as String? ?? (throw const RegleMetier('Dossier introuvable.'));
      }
      final details = <Map<String, Object?>>[];
      for (final l in lignes) {
        final p = produit(b, l.produit);
        if (p['stock'] != stock) throw RegleMetier('${p['designation']} n’appartient pas à ce stock.');
        if (l.quantite <= 0) throw const RegleMetier('Quantité invalide.');
        final cout = cump(b, l.produit);
        final prix = l.prix ?? p['prix_vente'] as int;
        for (final (lot, q) in repartirFefo(b, l.produit, l.quantite, lot: l.lot)) {
          details.add({
            'produit': l.produit,
            'designation': p['designation'],
            'lot': lot,
            'quantite': q,
            'cout': cout,
            'prix': factureVente ? prix : 0,
          });
        }
      }
      final total = details.fold<int>(0, (t, d) => t + (d['prix'] as int) * (d['quantite'] as int));
      final typePiece = type == 'vente' ? (mode == Modes.credit ? 'FAC' : 'REC') : (factureVente ? 'FAC' : 'SOR');
      return Operations.enregistrer(s, type: 'stock_sortie', entite: 'CS', typePiece: typePiece, donnees: {
        'stock': stock,
        'type': type,
        'patient': patient,
        'sejour': sejour,
        'dossier': dossierDesintox,
        'facturer': factureVente,
        'mode': type == 'vente' ? mode : (factureVente ? Modes.credit : null),
        'reference': reference,
        'tresorerie': type == 'vente' && Modes.encaissables.contains(mode) ? Tresorerie.pourMode(b, 'CS', mode) : null,
        'motif': motif,
        'beneficiaires': beneficiaires,
        'lignes': details,
        'total': total,
      });
    });
  }

  /// Inventaire physique : quantités comptées par lot ; les écarts sont
  /// enregistrés (avec leur écriture d'ajustement au CUMP).
  static Operation inventorier(Session s, {required String stock, required Map<(String, String), int> comptes, String? observation}) {
    final b = s.base;
    return b.transaction(() {
      magasin(stock);
      final lignes = <Map<String, Object?>>[];
      for (final e in comptes.entries) {
        final (prod, lot) = e.key;
        if (e.value < 0) throw const RegleMetier('Quantité comptée négative.');
        final theorique = quantite(b, prod, lot: lot);
        lignes.add({
          'produit': prod,
          'lot': lot,
          'theorique': theorique,
          'compte': e.value,
          'ecart': e.value - theorique,
          'cout': cump(b, prod),
          'peremption': b.valeur('SELECT MIN(peremption) FROM mouvements_stock WHERE produit=? AND lot=?', [prod, lot]),
        });
      }
      return Operations.enregistrer(s,
          type: 'inventaire_stock', entite: 'CS', typePiece: 'INV', donnees: {'stock': stock, 'lignes': lignes, 'observation': observation});
    });
  }

  static Operation reglerFournisseur(Session s, {required String fournisseur, required int montant, required String mode, String? reference}) {
    final b = s.base;
    return b.transaction(() {
      final du = -Moteur.solde(b, 'CS', '4011', tiers: fournisseur);
      if (montant <= 0 || montant > du) throw RegleMetier('Montant invalide : dette envers ce fournisseur ${fcfa(du)}.');
      Tresorerie.verifierReference(mode, reference);
      final treso = Tresorerie.pourMode(b, 'CS', mode);
      Tresorerie.verifierDisponible(b, treso, montant);
      return Operations.enregistrer(s, type: 'reglement_fournisseur', entite: 'CS', typePiece: 'DEC', donnees: {
        'fournisseur': fournisseur,
        'montant': montant,
        'mode': mode,
        'reference': reference,
        'tresorerie': treso,
      });
    });
  }

  // ------------------------------------------------------------ alertes
  static List<Map<String, String>> alertes(Base b) {
    final r = <Map<String, String>>[];
    final aujourdhui = dateIso(b.maintenant);
    final limite = ajouterJours(aujourdhui, b.paramInt('peremption_alerte_jours', 60));
    for (final p in b.lignes('SELECT * FROM produits WHERE actif=1')) {
      final q = quantite(b, p['code'] as String);
      if (q <= (p['stock_minimum'] as int) && (p['stock_minimum'] as int) > 0) {
        r.add({'niveau': 'orange', 'titre': 'Stock bas', 'detail': '${p['designation']} : $q restant(s), minimum ${p['stock_minimum']}'});
      }
      for (final l in lots(b, p['code'] as String)) {
        final per = l['peremption'] as String?;
        if (per == null) continue;
        if (per.compareTo(aujourdhui) < 0) {
          r.add({'niveau': 'rouge', 'titre': 'Produit périmé en stock', 'detail': '${p['designation']} · lot ${l['lot']} · ${l['quantite']} unité(s)'});
        } else if (per.compareTo(limite) <= 0) {
          r.add({'niveau': 'orange', 'titre': 'Péremption proche', 'detail': '${p['designation']} · lot ${l['lot']} · ${joursEntre(aujourdhui, per)} jours'});
        }
      }
    }
    return r;
  }

  static void declarer() {
    Operations.declarer(_Fournisseur());
    Operations.declarer(_Commande());
    Operations.declarer(_Entree());
    Operations.declarer(_Sortie());
    Operations.declarer(_Inventaire());
    Operations.declarer(_ReglementFournisseur());
  }
}

void _mouvement(Base b, Operation op, int rang, Map l, int quantite, String type, {String? reference}) => b.exec(
    'INSERT INTO mouvements_stock(uuid_op, rang, produit, lot, peremption, date, horodatage, quantite, cout_unitaire, type, reference) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
    [op.uuid, rang, l['produit'], l['lot'], l['peremption'], op.dateOp, op.horodatage, quantite, l['cout'], type, reference ?? op.piece]);

class _Fournisseur extends TypeOperation {
  @override
  String get type => 'fournisseur';
  @override
  String get module => 'achats';
  @override
  String get libelle => 'Fiche fournisseur';
  @override
  bool get annulable => false;
  @override
  void appliquer(Base base, Operation op) => base.exec('INSERT INTO fournisseurs(id, nom, contact, adresse, uuid_op) VALUES (?,?,?,?,?)',
      [op.d('id'), op.d('nom'), op.d('contact'), op.d('adresse'), op.uuid]);
}

class _Commande extends TypeOperation {
  @override
  String get type => 'commande';
  @override
  String get module => 'achats';
  @override
  String get libelle => 'Bon de commande';
  @override
  void appliquer(Base base, Operation op) => base.exec('INSERT INTO commandes(uuid_op, piece, fournisseur, date, lignes) VALUES (?,?,?,?,?)',
      [op.uuid, op.piece, op.d('fournisseur'), op.dateOp, jsonEncode(op.d('lignes'))]);
  @override
  void annuler(Base base, Operation cible, Operation annulation) =>
      base.exec("UPDATE commandes SET statut='annulee' WHERE uuid_op=?", [cible.uuid]);
}

class _Entree extends TypeOperation {
  @override
  String get type => 'stock_entree';
  @override
  String get module => 'stocks';
  @override
  String get libelle => 'Entrée en stock';

  @override
  void appliquer(Base base, Operation op) {
    final stock = op.d<String>('stock');
    final lignes = op.d<List>('lignes').cast<Map>();
    var rang = 0;
    var total = 0;
    for (final l in lignes) {
      _mouvement(base, op, ++rang, l, l['quantite'] as int, op.d('origine'));
      total += (l['quantite'] as int) * (l['cout'] as int);
    }
    if (op.d('commande') != null) base.exec("UPDATE commandes SET statut='recue' WHERE uuid_op=?", [op.d('commande')]);
    if (total == 0) return;
    final vars = Stocks._variables(stock);
    final lib = '${Stocks.magasin(stock)[0]} : entrée ${op.piece}';
    switch (op.d<String>('origine')) {
      case 'achat':
        Moteur.generer(base, op, 'achat_fournisseur', total: total, variables: vars, tiers: op.d('fournisseur'), activite: Stocks.magasin(stock)[5], libelle: lib);
        Moteur.generer(base, op, 'entree_stock', total: total, variables: vars, activite: Stocks.magasin(stock)[5], libelle: lib);
      case 'don':
        // Don reçu par l'ONG (SYCEBNL) puis transféré au centre de santé.
        final nom = base.valeur('SELECT nom FROM donateurs WHERE id=?', [op.d('donateur')]) ?? '';
        base.exec(
            "INSERT INTO dons(uuid_op, piece, donateur, date, montant, nature, description, affectation) VALUES (?,?,?,?,?,'nature',?,?)",
            [op.uuid, op.piece, op.d('donateur'), op.dateOp, total, 'Produits pour ${Stocks.magasin(stock)[0]}', Stocks.magasin(stock)[5]]);
        Moteur.generer(base, op, 'don_nature_transfert', total: total, entite: 'ONG', activite: 'PROG', libelle: 'Don en nature de $nom transféré au centre');
        Moteur.generer(base, op, 'entree_stock_liaison', total: total, variables: vars, activite: Stocks.magasin(stock)[5], libelle: 'Don en nature de $nom');
      default:
        Moteur.generer(base, op, 'entree_stock', total: total, variables: vars, activite: Stocks.magasin(stock)[5], libelle: lib);
    }
  }

  @override
  void annuler(Base base, Operation cible, Operation annulation) {
    base.exec('UPDATE mouvements_stock SET annule=1 WHERE uuid_op=?', [cible.uuid]);
    base.exec('UPDATE dons SET annule=1 WHERE uuid_op=?', [cible.uuid]);
  }
}

class _Sortie extends TypeOperation {
  @override
  String get type => 'stock_sortie';
  @override
  String get module => 'stocks';
  @override
  String get libelle => 'Sortie de stock';

  @override
  void appliquer(Base base, Operation op) {
    final stock = op.d<String>('stock');
    final m = Stocks.magasin(stock);
    final lignes = op.d<List>('lignes').cast<Map>();
    var rang = 0;
    var cout = 0;
    for (final l in lignes) {
      _mouvement(base, op, ++rang, l, -(l['quantite'] as int), op.d('type'),
          reference: op.d<String?>('sejour') ?? op.d<String?>('dossier') ?? op.piece);
      cout += (l['quantite'] as int) * (l['cout'] as int);
      // Conflit hors ligne : deux appareils ont vendu le même stock (§2.2).
      if (Stocks.quantite(base, l['produit'] as String, lot: l['lot'] as String) < 0) {
        Operations.signalerAnomalie(base, 'conflit_stock', op.uuid,
            'Stock négatif pour ${l['designation']} (lot ${l['lot']}) après ${op.piece} de ${op.appareil} : vente hors ligne au-delà du stock réel.');
      }
    }
    final vars = Stocks._variables(stock);
    final type = op.d<String>('type');
    if (cout > 0) {
      Moteur.generer(base, op, 'sortie_stock', total: cout, variables: vars, activite: m[5], libelle: '${Stocks.typesSortie[type]} ${op.piece}');
    }
    final total = op.d<int>('total');
    if (op.d<bool>('facturer') && total > 0) {
      final detail = [
        for (final l in lignes) LigneMontant((l['prix'] as int) * (l['quantite'] as int), variables: {'produit': m[4]}, activite: m[5])
      ];
      final lib = '${m[0]} : ${lignes.map((l) => l['designation']).toSet().join(', ')} ${op.piece}';
      if (op.d('mode') == Modes.credit) {
        Moteur.generer(base, op, 'prestation_credit', total: total, lignes: detail, tiers: op.d('patient'), activite: m[5], libelle: lib);
      } else {
        final treso = op.d<String>('tresorerie');
        Moteur.generer(base, op, 'prestation_payee', total: total, lignes: detail, variables: Tresorerie.variables(base, treso), activite: m[5], libelle: lib);
        Tresorerie.mouvement(base, op, treso, total, lib, reference: op.d('reference'));
      }
    }
    final dossier = op.d<String?>('dossier');
    if (dossier != null) {
      if (op.d<bool>('facturer')) {
        base.exec('UPDATE desintox_dossiers SET medicaments_factures = medicaments_factures + ? WHERE id=?', [total, dossier]);
      } else {
        base.exec('UPDATE desintox_dossiers SET medicaments_compris = medicaments_compris + ? WHERE id=?', [cout, dossier]);
      }
    }
  }

  @override
  void annuler(Base base, Operation cible, Operation annulation) {
    base.exec('UPDATE mouvements_stock SET annule=1 WHERE uuid_op=?', [cible.uuid]);
    final dossier = cible.d<String?>('dossier');
    if (dossier != null) {
      final cout = cible.d<List>('lignes').cast<Map>().fold<int>(0, (t, l) => t + (l['quantite'] as int) * (l['cout'] as int));
      if (cible.d<bool>('facturer')) {
        base.exec('UPDATE desintox_dossiers SET medicaments_factures = medicaments_factures - ? WHERE id=?', [cible.d<int>('total'), dossier]);
      } else {
        base.exec('UPDATE desintox_dossiers SET medicaments_compris = medicaments_compris - ? WHERE id=?', [cout, dossier]);
      }
    }
  }
}

class _Inventaire extends TypeOperation {
  @override
  String get type => 'inventaire_stock';
  @override
  String get module => 'stocks';
  @override
  String get libelle => 'Inventaire physique';
  @override
  bool get annulable => false;

  @override
  void appliquer(Base base, Operation op) {
    final stock = op.d<String>('stock');
    base.exec('INSERT INTO inventaires(uuid_op, stock, date, lignes) VALUES (?,?,?,?)', [op.uuid, stock, op.dateOp, jsonEncode(op.d('lignes'))]);
    var rang = 0;
    var plus = 0, moins = 0;
    for (final l in op.d<List>('lignes').cast<Map>()) {
      final e = l['ecart'] as int;
      if (e == 0) continue;
      _mouvement(base, op, ++rang, l, e, 'inventaire');
      if (e > 0) plus += e * (l['cout'] as int);
      if (e < 0) moins += -e * (l['cout'] as int);
    }
    final vars = Stocks._variables(stock);
    final act = Stocks.magasin(stock)[5];
    if (plus > 0) Moteur.generer(base, op, 'entree_stock', total: plus, variables: vars, activite: act, libelle: 'Inventaire : excédents ${op.piece}');
    if (moins > 0) Moteur.generer(base, op, 'sortie_stock', total: moins, variables: vars, activite: act, libelle: 'Inventaire : manquants ${op.piece}');
  }
}

class _ReglementFournisseur extends TypeOperation {
  @override
  String get type => 'reglement_fournisseur';
  @override
  String get module => 'achats';
  @override
  String get libelle => 'Règlement fournisseur';

  @override
  void appliquer(Base base, Operation op) {
    final treso = op.d<String>('tresorerie');
    final m = op.d<int>('montant');
    final nom = base.valeur('SELECT nom FROM fournisseurs WHERE id=?', [op.d('fournisseur')]) ?? '';
    Moteur.generer(base, op, 'reglement_fournisseur',
        total: m, variables: Tresorerie.variables(base, treso), tiers: op.d('fournisseur'), libelle: 'Règlement $nom ${op.piece}');
    Tresorerie.mouvement(base, op, treso, -m, 'Règlement fournisseur $nom', reference: op.d('reference'));
  }
}
