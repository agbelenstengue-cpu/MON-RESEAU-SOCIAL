/// Pharmacies et stocks : état du stock, ventes et sorties, entrées
/// (achats, dons), inventaire, produits, fournisseurs et commandes.
library;

import 'package:material_ui/material_ui.dart';

import '../../modules/comptabilite/moteur.dart';
import '../../modules/stocks/stocks.dart';
import '../../modules/tresorerie/tresorerie.dart';
import '../../noyau/outils.dart';
import '../../noyau/session.dart';
import '../../pdf/documents.dart';
import '../../rapports/etats_stocks_hospitalisation.dart';
import '../etat_app.dart';
import '../theme.dart';
import '../widgets/commun.dart';
import '../widgets/formulaire.dart';
import '../widgets/pdf_ui.dart';

const _stocks = [('PHM', 'Pharmacie moderne'), ('PHT', 'Pharmacie traditionnelle'), ('LAB', 'Réactifs du laboratoire')];

class EcranStocks extends StatefulWidget {
  const EcranStocks({super.key});
  @override
  State<EcranStocks> createState() => _EcranStocksState();
}

class _EcranStocksState extends State<EcranStocks> {
  String _stock = 'PHM';

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ChoixPastilles<String>(options: _stocks, valeur: _stock, onChanged: (v) => setState(() => _stock = v)),
          ),
        ),
        const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
          Tab(text: 'Stock'),
          Tab(text: 'Produits'),
          Tab(text: 'Fournisseurs et commandes'),
          Tab(text: 'Inventaire'),
        ]),
        Expanded(
          child: TabBarView(children: [
            _Etat(stock: _stock),
            _Produits(stock: _stock),
            const _Fournisseurs(),
            _Inventaire(key: ValueKey(_stock), stock: _stock),
          ]),
        ),
      ]),
    );
  }
}

class _Etat extends StatelessWidget {
  final String stock;
  const _Etat({required this.stock});

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final s = etat.session!;
    final produits = b.lignes('SELECT * FROM produits WHERE stock=? AND actif=1 ORDER BY designation', [stock]);
    final valeur = produits.fold<int>(0, (t, p) => t + Stocks.valeur(b, p['code'] as String));
    final alertes = Stocks.alertes(b);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('Valeur du stock : ${fcfa(valeur)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(width: 12),
        if (s.peut('stocks', 'creer')) ...[
          if (stock != 'LAB')
            FilledButton.icon(onPressed: () => ouvrirSortieStock(context, stock: stock, type: 'vente'), icon: const Icon(Icons.point_of_sale), label: const Text('Vente')),
          OutlinedButton.icon(onPressed: () => ouvrirSortieStock(context, stock: stock), icon: const Icon(Icons.output), label: const Text('Autre sortie')),
          OutlinedButton.icon(onPressed: () => ouvrirEntreeStock(context, stock: stock), icon: const Icon(Icons.input), label: const Text('Entrée (achat, don)')),
        ],
        OutlinedButton.icon(
          onPressed: () => afficherPdf(context, () => Documents.rapport(b, EtatsStocks.etat(b, stock, dateIso(b.maintenant))), 'État des stocks'),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('État des stocks'),
        ),
      ]),
      if (alertes.isNotEmpty) ...[
        const SizedBox(height: 12),
        for (final a in alertes.take(8))
          Text('${a['titre']} : ${a['detail']}', style: TextStyle(color: a['niveau'] == 'rouge' ? Couleurs.baisse : Couleurs.stable)),
      ],
      const SizedBox(height: 12),
      if (produits.isEmpty) const EtatVide('Aucun produit : ajoutez-les dans l’onglet Produits.'),
      Card(
        child: Column(children: [
          for (final p in produits)
            () {
              final q = Stocks.quantite(b, p['code'] as String);
              final lots = Stocks.lots(b, p['code'] as String);
              return ListTile(
                title: Text('${p['designation']} ${p['dosage']}'.trim()),
                subtitle: Text(lots.isEmpty
                    ? 'Aucun lot en stock'
                    : lots.map((l) => 'lot ${l['lot']}${l['peremption'] != null ? ' (${dateFr(depuisIso(l['peremption'] as String))})' : ''} : ${l['quantite']}').join(' · ')),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('$q ${p['unite']}', style: TextStyle(fontWeight: FontWeight.bold, color: q <= (p['stock_minimum'] as int) && (p['stock_minimum'] as int) > 0 ? Couleurs.baisse : null)),
                  Text('CUMP ${fcfa(Stocks.cump(b, p['code'] as String))}', style: const TextStyle(fontSize: 12)),
                ]),
              );
            }(),
        ]),
      ),
    ]);
  }
}

class _Produits extends StatelessWidget {
  final String stock;
  const _Produits({required this.stock});

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final ok = etat.session!.peut('stocks', 'creer') && etat.estCentral;
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (ok)
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(onPressed: () => _produit(context, null), icon: const Icon(Icons.add), label: const Text('Ajouter un produit')),
        ),
      if (!etat.estCentral) const Text('Les produits se créent sur le PC central.'),
      const SizedBox(height: 8),
      Card(
        child: Column(children: [
          for (final p in b.lignes('SELECT * FROM produits WHERE stock=? ORDER BY actif DESC, designation', [stock]))
            ListTile(
              title: Text('${p['designation']}${p['actif'] == 0 ? ' (désactivé)' : ''}'),
              subtitle: Text('${p['code']} · ${p['forme']} ${p['dosage']} · prix ${fcfa(p['prix_vente'] as int)} · minimum ${p['stock_minimum']}'),
              trailing: !ok
                  ? null
                  : Wrap(children: [
                      IconButton(tooltip: 'Modifier', icon: const Icon(Icons.edit_outlined), onPressed: () => _produit(context, p)),
                      IconButton(
                        tooltip: 'Retirer',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (await confirmer(context, 'Retirer ${p['designation']} ?') && context.mounted) {
                            executer(context, () => Stocks.retirerProduit(etat.session!, p['code'] as String), succes: 'Produit retiré.');
                          }
                        },
                      ),
                    ]),
            ),
        ]),
      ),
    ]);
  }

  void _produit(BuildContext context, Map<String, Object?>? p) => formulaire(context, p == null ? 'Ajouter un produit' : 'Modifier le produit', [
        Champ('code', 'Code (ex. AMOX500)', initial: (p?['code'] ?? '') as String, modifiable: p == null),
        Champ('designation', 'Désignation', initial: (p?['designation'] ?? '') as String),
        Champ('forme', 'Forme (comprimé, sirop…)', initial: (p?['forme'] ?? '') as String),
        Champ('dosage', 'Dosage', initial: (p?['dosage'] ?? '') as String),
        Champ('unite', 'Unité', initial: (p?['unite'] ?? 'unité') as String),
        Champ('prix', 'Prix de vente (FCFA)', initial: '${p?['prix_vente'] ?? 0}', nombre: true),
        Champ('minimum', 'Stock minimum (alerte)', initial: '${p?['stock_minimum'] ?? 0}', nombre: true),
        if (stock == 'PHT') ...[
          Champ('producteur', 'Producteur ou fournisseur', initial: (p?['producteur'] ?? '') as String),
          Champ('origine', 'Origine', initial: (p?['origine'] ?? '') as String),
          Champ('preparation', 'Mode de préparation ou conditionnement', initial: (p?['preparation'] ?? '') as String),
        ],
      ], (c, v) => reussir(c, () => Stocks.enregistrerProduit(Etat.lire(c).session!,
          code: v['code']!, designation: v['designation']!, stock: stock, forme: v['forme']!, dosage: v['dosage']!, unite: v['unite']!,
          prixVente: int.tryParse(v['prix']!) ?? 0, stockMinimum: int.tryParse(v['minimum']!) ?? 0,
          producteur: v['producteur'] ?? '', origine: v['origine'] ?? '', preparation: v['preparation'] ?? ''), succes: 'Produit enregistré.'));
}

class _Fournisseurs extends StatelessWidget {
  const _Fournisseurs();

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final s = etat.session!;
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (s.peut('achats', 'creer'))
        Wrap(spacing: 8, children: [
          FilledButton.icon(
            onPressed: () => formulaire(context, 'Nouveau fournisseur', const [
              Champ('nom', 'Nom'),
              Champ('contact', 'Téléphone, e-mail'),
              Champ('adresse', 'Adresse'),
            ], (c, v) => reussir(c, () => Stocks.creerFournisseur(s, nom: v['nom']!, contact: v['contact']!, adresse: v['adresse']!), succes: 'Fournisseur créé.')),
            icon: const Icon(Icons.add_business_outlined),
            label: const Text('Nouveau fournisseur'),
          ),
          OutlinedButton.icon(onPressed: () => _commande(context), icon: const Icon(Icons.description_outlined), label: const Text('Bon de commande')),
        ]),
      const SizedBox(height: 12),
      const TitreSection('Fournisseurs et dettes'),
      Card(
        child: Column(children: [
          for (final f in b.lignes('SELECT * FROM fournisseurs ORDER BY nom'))
            () {
              final du = -Moteur.solde(b, 'CS', '4011', tiers: f['id'] as String);
              return ListTile(
                title: Text(f['nom'] as String),
                subtitle: Text(f['contact'] as String),
                trailing: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                  Text('Dette ${fcfa(du)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (du > 0 && s.peut('achats', 'creer'))
                    TextButton(
                      onPressed: () => formulaire(context, 'Règlement de ${f['nom']}', [
                        Champ('montant', 'Montant (FCFA)', initial: '$du', nombre: true),
                        Champ('mode', 'Mode', choix: [for (final m in Modes.encaissables) (m, Modes.libelles[m]!)]),
                        const Champ('reference', 'Référence (chèque, virement, transaction)'),
                      ], (c, v) => reussir(c, () => Stocks.reglerFournisseur(s, fournisseur: f['id'] as String, montant: int.tryParse(v['montant']!) ?? 0,
                          mode: v['mode']!, reference: v['reference']!.isEmpty ? null : v['reference']), succes: 'Règlement enregistré.')),
                      child: const Text('Régler'),
                    ),
                ]),
              );
            }(),
        ]),
      ),
      const SizedBox(height: 12),
      const TitreSection('Commandes'),
      Card(
        child: Column(children: [
          for (final c in b.lignes('SELECT c.*, f.nom FROM commandes c JOIN fournisseurs f ON f.id=c.fournisseur ORDER BY c.date DESC LIMIT 50'))
            ListTile(
              title: Text('${c['piece']} · ${c['nom']}'),
              subtitle: Text('${dateFr(depuisIso(c['date'] as String))} · ${c['statut'] == 'recue' ? 'reçue' : c['statut'] == 'annulee' ? 'annulée' : 'envoyée'}'),
            ),
        ]),
      ),
    ]);
  }

  void _commande(BuildContext context) {
    final b = Etat.lire(context).base!;
    final fournisseurs = [for (final f in b.lignes('SELECT id, nom FROM fournisseurs ORDER BY nom')) (f['id'] as String, f['nom'] as String)];
    final produits = [for (final p in b.lignes('SELECT code, designation FROM produits WHERE actif=1 ORDER BY designation')) (p['code'] as String, p['designation'] as String)];
    if (fournisseurs.isEmpty || produits.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Créez d’abord un fournisseur et des produits.')));
      return;
    }
    formulaire(context, 'Bon de commande', [
      Champ('fournisseur', 'Fournisseur', choix: fournisseurs),
      Champ('produit', 'Produit', choix: produits),
      const Champ('quantite', 'Quantité', nombre: true),
      const Champ('prix', 'Prix unitaire prévu (FCFA)', nombre: true),
    ], (c, v) => reussir(c, () => Stocks.commander(Etat.lire(c).session!, fournisseur: v['fournisseur']!, lignes: [
          LigneStock(v['produit']!, int.tryParse(v['quantite']!) ?? 0, coutUnitaire: int.tryParse(v['prix']!) ?? 0)
        ]), succes: 'Bon de commande enregistré.'));
  }
}

class _Inventaire extends StatefulWidget {
  final String stock;
  const _Inventaire({super.key, required this.stock});
  @override
  State<_Inventaire> createState() => _InventaireState();
}

class _InventaireState extends State<_Inventaire> {
  final Map<(String, String), TextEditingController> _comptes = {};

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final lignes = [
      for (final p in b.lignes('SELECT * FROM produits WHERE stock=? AND actif=1 ORDER BY designation', [widget.stock]))
        for (final l in Stocks.lots(b, p['code'] as String)) (p, l)
    ];
    for (final (p, l) in lignes) {
      _comptes.putIfAbsent((p['code'] as String, l['lot'] as String), () => TextEditingController(text: '${l['quantite']}'));
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 8, children: [
        OutlinedButton.icon(
          onPressed: () => afficherPdf(context, () => Documents.rapport(b, EtatsStocks.ficheComptage(b, widget.stock, dateIso(b.maintenant))), 'Fiche de comptage'),
          icon: const Icon(Icons.print_outlined),
          label: const Text('Imprimer la fiche de comptage'),
        ),
        OutlinedButton.icon(
          onPressed: () => afficherPdf(context, () => Documents.rapport(b, EtatsStocks.inventaire(b, widget.stock)), 'Écarts d’inventaire'),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Écarts du dernier inventaire'),
        ),
      ]),
      const SizedBox(height: 12),
      const Text('Saisissez les quantités comptées (préremplies avec la quantité théorique).'),
      Card(
        child: Column(children: [
          for (final (p, l) in lignes)
            ListTile(
              dense: true,
              title: Text('${p['designation']} · lot ${l['lot']}'),
              subtitle: Text('Théorique : ${l['quantite']}'),
              trailing: SizedBox(
                width: 110,
                child: TextField(
                  controller: _comptes[(p['code'] as String, l['lot'] as String)],
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Compté', isDense: true),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 8),
      if (etat.session!.peut('stocks', 'creer'))
        FilledButton(
          onPressed: lignes.isEmpty
              ? null
              : () => reussir(context, () => Stocks.inventorier(etat.session!, stock: widget.stock, comptes: {
                    for (final (p, l) in lignes)
                      (p['code'] as String, l['lot'] as String): int.tryParse(_comptes[(p['code'] as String, l['lot'] as String)]!.text) ?? 0
                  }), succes: 'Inventaire enregistré ; les écarts sont comptabilisés.'),
          child: const Text('Valider l’inventaire'),
        ),
    ]);
  }
}

/// Sortie de stock : vente, délivrance (séjour ou désintoxication), distribution, perte…
Future<void> ouvrirSortieStock(BuildContext context, {required String stock, String? type, String? sejour, String? dossier}) {
  final b = Etat.lire(context).base!;
  final produits = [
    for (final p in b.lignes('SELECT code, designation, prix_vente FROM produits WHERE stock=? AND actif=1 ORDER BY designation', [stock]))
      if (Stocks.quantite(b, p['code'] as String) > 0) (p['code'] as String, '${p['designation']} (${Stocks.quantite(b, p['code'] as String)} en stock, ${fcfa(p['prix_vente'] as int)})')
  ];
  if (produits.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucun produit en stock.')));
    return Future.value();
  }
  final types = type != null
      ? [(type, Stocks.typesSortie[type]!)]
      : [for (final e in Stocks.typesSortie.entries) if (!e.key.startsWith('delivrance') && (stock != 'LAB' || e.key != 'vente')) (e.key, e.value)];
  return formulaire(context, type == null ? 'Sortie de stock' : Stocks.typesSortie[type]!, [
    Champ('type', 'Nature de la sortie', choix: types, modifiable: type == null),
    Champ('produit', 'Produit', choix: produits),
    const Champ('quantite', 'Quantité', nombre: true),
    if (type == 'vente' || type == null) Champ('mode', 'Mode de paiement (vente)', choix: [for (final m in [...Modes.encaissables, Modes.credit]) (m, Modes.libelles[m]!)]),
    if (type == 'vente' || type == null) const Champ('reference', 'Référence mobile money (si MoMo)'),
    if (dossier != null || sejour != null)
      const Champ('facturer', 'Prise en charge', choix: [('oui', 'Facturé au patient'), ('non', 'Compris dans le forfait (non facturé)')]),
    if (type == null) const Champ('motif', 'Motif (pertes, casse, péremption)'),
    if (type == null) const Champ('beneficiaires', 'Bénéficiaires (distribution gratuite)'),
  ], (c, v) {
    final op = executer(
        c,
        () => Stocks.sortir(Etat.lire(c).session!,
            stock: stock,
            type: v['type']!,
            lignes: [LigneStock(v['produit']!, int.tryParse(v['quantite']!) ?? 0)],
            mode: v['mode'] ?? Modes.especes,
            reference: (v['reference'] ?? '').isEmpty ? null : v['reference'],
            sejour: sejour,
            dossierDesintox: dossier,
            facturer: v['facturer'] != 'non',
            motif: (v['motif'] ?? '').isEmpty ? null : v['motif'],
            beneficiaires: (v['beneficiaires'] ?? '').isEmpty ? null : v['beneficiaires']),
        succes: 'Sortie enregistrée.');
    if (op != null && (op.d<int>('total') > 0) && v['type'] == 'vente') {
      Future.microtask(() => context.mounted ? afficherRecu(context, op.uuid) : null);
    }
    return op != null;
  });
}

/// Entrée en stock : réception d'achat (lot, péremption, coût) ou don.
Future<void> ouvrirEntreeStock(BuildContext context, {required String stock}) {
  final b = Etat.lire(context).base!;
  final produits = [for (final p in b.lignes('SELECT code, designation FROM produits WHERE stock=? AND actif=1 ORDER BY designation', [stock])) (p['code'] as String, p['designation'] as String)];
  if (produits.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ajoutez d’abord des produits.')));
    return Future.value();
  }
  final fournisseurs = [for (final f in b.lignes('SELECT id, nom FROM fournisseurs ORDER BY nom')) (f['id'] as String, f['nom'] as String)];
  final donateurs = [for (final d in b.lignes('SELECT id, nom FROM donateurs ORDER BY nom')) (d['id'] as String, d['nom'] as String)];
  final commandes = [for (final c in b.lignes("SELECT uuid_op, piece FROM commandes WHERE statut='envoyee' ORDER BY date DESC")) (c['uuid_op'] as String, c['piece'] as String)];
  return formulaire(context, 'Entrée en stock', [
    const Champ('origine', 'Origine', choix: [('achat', 'Achat (réception fournisseur)'), ('don', 'Don en nature'), ('retour', 'Retour')]),
    Champ('fournisseur', 'Fournisseur (achat)', choix: [('', 'Aucun'), ...fournisseurs]),
    Champ('donateur', 'Donateur (don)', choix: [('', 'Aucun'), ...donateurs]),
    Champ('commande', 'Bon de commande reçu', choix: [('', 'Aucun'), ...commandes]),
    Champ('produit', 'Produit', choix: produits),
    const Champ('quantite', 'Quantité', nombre: true),
    const Champ('lot', 'Numéro de lot'),
    const Champ('peremption', 'Date de péremption (JJ/MM/AAAA)'),
    const Champ('cout', "Coût unitaire d'achat ou valeur estimée (FCFA)", nombre: true),
    const Champ('facture', 'N° de facture fournisseur'),
  ], (c, v) => reussir(
      c,
      () => Stocks.entrer(Etat.lire(c).session!,
          stock: stock,
          origine: v['origine']!,
          fournisseur: v['fournisseur']!.isEmpty ? null : v['fournisseur'],
          donateur: v['donateur']!.isEmpty ? null : v['donateur'],
          commande: v['commande']!.isEmpty ? null : v['commande'],
          facture: v['facture'],
          lignes: [
            LigneStock(v['produit']!, int.tryParse(v['quantite']!) ?? 0,
                lot: v['lot'], peremption: v['peremption']!.isEmpty ? null : _iso(v['peremption']!), coutUnitaire: int.tryParse(v['cout']!) ?? 0)
          ]),
      succes: 'Entrée enregistrée.'));
}

String _iso(String fr) {
  if (!RegExp(r'^\d{1,2}/\d{1,2}/\d{4}$').hasMatch(fr)) throw const RegleMetier('Date de péremption : format JJ/MM/AAAA.');
  return isoDepuisFr(fr);
}

/// Pour l'écran d'accueil : la session a-t-elle accès aux stocks ?
bool accesStocks(Session s) => s.peut('stocks', 'voir');
