/// Données de paramétrage livrées par défaut, À VALIDER PAR LE COMPTABLE.
///
/// Deux comptabilités distinctes :
///  * CS : Centre de santé : plan SYSCOHADA révisé ;
///  * ONG : A Hand to Humanity : plan SYCEBNL (dons, subventions, programmes).
/// Les numéros sont indicatifs (§6.15, §15) : tout est modifiable dans le
/// paramétrage, rien n'est codé en dur dans les modules.
library;

class CompteDefaut {
  final String numero;
  final String libelle;
  const CompteDefaut(this.numero, this.libelle);
}

const entitesDefaut = [
  {'code': 'CS', 'nom': 'Centre de santé A Hand to Humanity', 'sigle': 'CS-AH2', 'referentiel': 'SYSCOHADA'},
  {'code': 'ONG', 'nom': 'A Hand to Humanity', 'sigle': 'AH2', 'referentiel': 'SYCEBNL'},
];

/// Comptes communs aux deux entités (numérotation OHADA).
const _communs = [
  CompteDefaut('1011', 'Capital ou fonds associatifs'),
  CompteDefaut('1211', 'Report à nouveau créditeur'),
  CompteDefaut('1291', 'Report à nouveau débiteur'),
  CompteDefaut('1311', "Résultat net de l'exercice : bénéfice ou excédent"),
  CompteDefaut('1391', "Résultat net de l'exercice : perte ou déficit"),
  CompteDefaut('2311', 'Bâtiments'),
  CompteDefaut('2411', 'Matériel médical et technique'),
  CompteDefaut('2442', 'Matériel informatique'),
  CompteDefaut('2444', 'Mobilier de bureau'),
  CompteDefaut('2451', 'Matériel de transport'),
  CompteDefaut('2831', 'Amortissements des bâtiments'),
  CompteDefaut('2841', 'Amortissements du matériel médical et technique'),
  CompteDefaut('2844', 'Amortissements du matériel et mobilier de bureau'),
  CompteDefaut('2845', 'Amortissements du matériel de transport'),
  CompteDefaut('4211', 'Personnel, avances et acomptes'),
  CompteDefaut('6813', 'Dotations aux amortissements des immobilisations corporelles'),
  CompteDefaut('8121', 'Valeur comptable des cessions d’immobilisations'),
  CompteDefaut('8221', 'Produits des cessions d’immobilisations'),
  CompteDefaut('4011', 'Fournisseurs'),
  CompteDefaut('4221', 'Personnel, rémunérations dues'),
  CompteDefaut('4311', 'Sécurité sociale (CNPS)'),
  CompteDefaut('4471', 'État, impôts retenus à la source'),
  CompteDefaut('5211', 'Banque, compte courant'),
  CompteDefaut('5521', 'Monnaie électronique MTN Mobile Money'),
  CompteDefaut('5522', 'Monnaie électronique Orange Money'),
  CompteDefaut('5711', 'Caisse centrale'),
  CompteDefaut('5851', 'Virements de fonds internes'),
  CompteDefaut('6051', 'Eau'),
  CompteDefaut('6052', 'Électricité'),
  CompteDefaut('6053', 'Carburant et autres énergies'),
  CompteDefaut('6054', "Fournitures d'entretien"),
  CompteDefaut('6055', 'Fournitures de bureau'),
  CompteDefaut('6181', 'Voyages et déplacements'),
  CompteDefaut('6221', 'Locations de bâtiments'),
  CompteDefaut('6241', 'Entretien, réparations et maintenance'),
  CompteDefaut('6281', 'Frais de télécommunications'),
  CompteDefaut('6311', 'Frais bancaires'),
  CompteDefaut('6588', 'Charges diverses (dont manquants de caisse)'),
  CompteDefaut('6611', 'Appointements, salaires et indemnités'),
  CompteDefaut('6641', 'Charges sociales (CNPS)'),
  CompteDefaut('7588', 'Produits divers (dont excédents de caisse)'),
];

/// Centre de santé, SYSCOHADA révisé.
const comptesCS = [
  ..._communs,
  CompteDefaut('4111', 'Clients patients'),
  CompteDefaut('4112', 'Clients organismes de prise en charge'),
  CompteDefaut('4191', 'Clients, avances et cautions reçues'),
  CompteDefaut('4671', 'Compte de liaison ONG AH2'),
  CompteDefaut('4770', "Produits constatés d'avance"),
  CompteDefaut('6011', 'Achats de médicaments'),
  CompteDefaut('6031', 'Variation des stocks de marchandises'),
  CompteDefaut('6041', 'Achats de réactifs et consommables de laboratoire'),
  CompteDefaut('6012', 'Achats de produits de la pharmacie traditionnelle'),
  CompteDefaut('6033', 'Variation des stocks de réactifs et consommables'),
  CompteDefaut('3111', 'Stock de médicaments (pharmacie moderne)'),
  CompteDefaut('3112', 'Stock de produits de la pharmacie traditionnelle'),
  CompteDefaut('3311', 'Stock de réactifs et consommables de laboratoire'),
  CompteDefaut('7011', 'Ventes de la pharmacie moderne'),
  CompteDefaut('7012', 'Ventes de la pharmacie traditionnelle'),
  CompteDefaut('7061', 'Prestations de consultations'),
  CompteDefaut('7062', 'Prestations de laboratoire'),
  CompteDefaut('7063', "Prestations d'hospitalisation"),
  CompteDefaut('7064', 'Prestations de désintoxication'),
  CompteDefaut('7065', 'Prestations de massages et soins'),
];

/// ONG, SYCEBNL. Les comptes de dons et subventions sont à confirmer par
/// le comptable avec la nomenclature SYCEBNL en vigueur.
const comptesONG = [
  ..._communs,
  CompteDefaut('3111', 'Stocks reçus en don (médicaments, fournitures)'),
  CompteDefaut('1411', "Dons et subventions d'investissement reçus"),
  CompteDefaut('4671', 'Compte de liaison Centre de santé'),
  CompteDefaut('6581', 'Aides et secours accordés (programmes sociaux)'),
  CompteDefaut('7181', "Subventions d'exploitation des bailleurs"),
  CompteDefaut('7581', 'Dons manuels en numéraire'),
  CompteDefaut('7582', 'Dons en nature'),
];

const journauxDefaut = [
  ['CA1', 'Caisse centrale', 'caisse'],
  ['BQ1', 'Banque', 'banque'],
  ['MTN', 'MTN Mobile Money', 'momo'],
  ['ORA', 'Orange Money', 'momo'],
  ['VT', 'Ventes et prestations', 'ventes'],
  ['AC', 'Achats', 'achats'],
  ['PA', 'Paie', 'paie'],
  ['OD', 'Opérations diverses', 'od'],
  ['AN', 'À-nouveaux', 'an'],
  ['CL', "Clôture de l'exercice", 'od'],
];

/// [code, libellé, entité, service (relevé), type de relevé]
const activitesDefaut = [
  ['CONS', 'Consultations', 'CS', 1, 'actes'],
  ['LAB', 'Laboratoire', 'CS', 1, 'actes'],
  ['HOSP', 'Hospitalisation', 'CS', 1, 'actes'],
  ['DESINTOX', 'Désintoxication', 'CS', 1, 'actes'],
  ['MASS', 'Massages et soins', 'CS', 1, 'actes'],
  ['PHM', 'Pharmacie moderne', 'CS', 1, 'sorties'],
  ['PHT', 'Pharmacie traditionnelle', 'CS', 1, 'sorties'],
  ['ADM_CS', 'Administration générale (centre)', 'CS', 0, 'actes'],
  ['PROG', 'Programmes sociaux', 'ONG', 0, 'actes'],
  ['ADM_ONG', 'Administration générale (ONG)', 'ONG', 0, 'actes'],
];

/// Catalogue de démonstration, tarifs FICTIFS à remplacer (§15).
/// [code, libellé, activité, compte de produit, prix]
const actesDefaut = [
  ['CONS-GEN', 'Consultation générale', 'CONS', '7061', 2000],
  ['CONS-SPE', 'Consultation spécialisée', 'CONS', '7061', 5000],
  ['CONS-CTRL', 'Consultation de contrôle', 'CONS', '7061', 1000],
  ['LAB-GLY', 'Glycémie à jeun', 'LAB', '7062', 1500],
  ['LAB-NFS', 'NFS (numération)', 'LAB', '7062', 3500],
  ['LAB-GE', 'Goutte épaisse (paludisme)', 'LAB', '7062', 1000],
  ['LAB-WID', 'Sérodiagnostic de Widal', 'LAB', '7062', 3000],
  ['LAB-ECBU', 'ECBU', 'LAB', '7062', 4000],
  ['MASS-30', 'Massage 30 minutes', 'MASS', '7065', 5000],
  ['MASS-60', 'Massage 60 minutes', 'MASS', '7065', 9000],
];

/// Programmes de désintoxication FICTIFS : [code, libellé, type, durée, mode, montant]
const programmesDefaut = [
  ['RES-90', 'Résidentiel 90 jours', 'residentiel', 90, 'forfait', 450000],
  ['RES-30', 'Résidentiel 30 jours', 'residentiel', 30, 'forfait', 180000],
  ['AMB-60', 'Ambulatoire 60 jours', 'ambulatoire', 60, 'journalier', 2500],
];

/// Schémas d'écritures : [type, ordre, sens, compte, montant, répétition, journal, libellé]
const _schemasCommuns = [
  ['depense', 1, 'D', '{charge}', 'total', 'unique', '{journal_tresorerie}', 'Dépense'],
  ['depense', 2, 'C', '{tresorerie}', 'total', 'unique', '{journal_tresorerie}', 'Dépense'],
  ['virement_sortie', 1, 'D', '5851', 'total', 'unique', '{journal_source}', 'Virement interne'],
  ['virement_sortie', 2, 'C', '{source}', 'total', 'unique', '{journal_source}', 'Virement interne'],
  ['virement_entree', 1, 'D', '{destination}', 'total', 'unique', '{journal_destination}', 'Virement interne'],
  ['virement_entree', 2, 'C', '5851', 'total', 'unique', '{journal_destination}', 'Virement interne'],
  ['ecart_caisse_manquant', 1, 'D', '6588', 'total', 'unique', '{journal_tresorerie}', 'Manquant de caisse'],
  ['ecart_caisse_manquant', 2, 'C', '{tresorerie}', 'total', 'unique', '{journal_tresorerie}', 'Manquant de caisse'],
  ['ecart_caisse_excedent', 1, 'D', '{tresorerie}', 'total', 'unique', '{journal_tresorerie}', 'Excédent de caisse'],
  ['ecart_caisse_excedent', 2, 'C', '7588', 'total', 'unique', '{journal_tresorerie}', 'Excédent de caisse'],
];

/// Schémas des phases 2 et 3 (communs aux deux entités).
const _schemasGestion = [
  ['achat_fournisseur', 1, 'D', '{compte_achat}', 'total', 'unique', 'AC', 'Achat fournisseur'],
  ['achat_fournisseur', 2, 'C', '4011', 'total', 'unique', 'AC', 'Achat fournisseur'],
  ['entree_stock', 1, 'D', '{compte_stock}', 'total', 'unique', 'OD', 'Entrée en stock'],
  ['entree_stock', 2, 'C', '{compte_variation}', 'total', 'unique', 'OD', 'Entrée en stock'],
  ['sortie_stock', 1, 'D', '{compte_variation}', 'total', 'unique', 'OD', 'Sortie de stock'],
  ['sortie_stock', 2, 'C', '{compte_stock}', 'total', 'unique', 'OD', 'Sortie de stock'],
  ['entree_stock_liaison', 1, 'D', '{compte_stock}', 'total', 'unique', 'OD', 'Don en nature reçu par l’ONG'],
  ['entree_stock_liaison', 2, 'C', '4671', 'total', 'unique', 'OD', 'Don en nature reçu par l’ONG'],
  ['reglement_fournisseur', 1, 'D', '4011', 'total', 'unique', '{journal_tresorerie}', 'Règlement fournisseur'],
  ['reglement_fournisseur', 2, 'C', '{tresorerie}', 'total', 'unique', '{journal_tresorerie}', 'Règlement fournisseur'],
  ['avance_salaire', 1, 'D', '4211', 'total', 'unique', '{journal_tresorerie}', 'Avance sur salaire'],
  ['avance_salaire', 2, 'C', '{tresorerie}', 'total', 'unique', '{journal_tresorerie}', 'Avance sur salaire'],
  ['paie_brut', 1, 'D', '6611', 'total', 'unique', 'PA', 'Salaires bruts'],
  ['paie_brut', 2, 'C', '4221', 'total', 'unique', 'PA', 'Salaires bruts'],
  ['paie_retenues_cnps', 1, 'D', '4221', 'total', 'unique', 'PA', 'Cotisations sociales salariales'],
  ['paie_retenues_cnps', 2, 'C', '4311', 'total', 'unique', 'PA', 'Cotisations sociales salariales'],
  ['paie_retenues_etat', 1, 'D', '4221', 'total', 'unique', 'PA', 'Retenues fiscales'],
  ['paie_retenues_etat', 2, 'C', '4471', 'total', 'unique', 'PA', 'Retenues fiscales'],
  ['paie_patronales_cnps', 1, 'D', '6641', 'total', 'unique', 'PA', 'Charges patronales CNPS'],
  ['paie_patronales_cnps', 2, 'C', '4311', 'total', 'unique', 'PA', 'Charges patronales CNPS'],
  ['paie_patronales_etat', 1, 'D', '6641', 'total', 'unique', 'PA', 'Charges patronales fiscales'],
  ['paie_patronales_etat', 2, 'C', '4471', 'total', 'unique', 'PA', 'Charges patronales fiscales'],
  ['paie_avances', 1, 'D', '4221', 'total', 'unique', 'PA', 'Avances déduites'],
  ['paie_avances', 2, 'C', '4211', 'total', 'unique', 'PA', 'Avances déduites'],
  ['paiement_salaire', 1, 'D', '4221', 'total', 'unique', '{journal_tresorerie}', 'Paiement des salaires'],
  ['paiement_salaire', 2, 'C', '{tresorerie}', 'total', 'unique', '{journal_tresorerie}', 'Paiement des salaires'],
  ['immo_acquisition', 1, 'D', '{compte_immobilisation}', 'total', 'unique', 'OD', 'Acquisition d’immobilisation'],
  ['immo_acquisition', 2, 'C', '{contrepartie}', 'total', 'unique', 'OD', 'Acquisition d’immobilisation'],
  ['dotation_amortissement', 1, 'D', '6813', 'total', 'unique', 'OD', 'Dotation aux amortissements'],
  ['dotation_amortissement', 2, 'C', '{compte_amortissement}', 'total', 'unique', 'OD', 'Dotation aux amortissements'],
  ['sortie_immo_amortissement', 1, 'D', '{compte_amortissement}', 'total', 'unique', 'OD', 'Sortie d’immobilisation'],
  ['sortie_immo_amortissement', 2, 'C', '{compte_immobilisation}', 'total', 'unique', 'OD', 'Sortie d’immobilisation'],
  ['sortie_immo_vnc', 1, 'D', '8121', 'total', 'unique', 'OD', 'Valeur comptable de la sortie'],
  ['sortie_immo_vnc', 2, 'C', '{compte_immobilisation}', 'total', 'unique', 'OD', 'Valeur comptable de la sortie'],
  ['cession_immo', 1, 'D', '{tresorerie}', 'total', 'unique', '{journal_tresorerie}', 'Produit de cession'],
  ['cession_immo', 2, 'C', '8221', 'total', 'unique', '{journal_tresorerie}', 'Produit de cession'],
];

const schemasCS = [
  ..._schemasGestion,
  ['caution_hospitalisation', 1, 'D', '{tresorerie}', 'total', 'unique', '{journal_tresorerie}', 'Caution d’hospitalisation'],
  ['caution_hospitalisation', 2, 'C', '4191', 'total', 'unique', '{journal_tresorerie}', 'Caution d’hospitalisation'],
  ['imputation_caution', 1, 'D', '4191', 'total', 'unique', 'OD', 'Caution déduite de la facture'],
  ['imputation_caution', 2, 'C', '4111', 'total', 'unique', 'OD', 'Caution déduite de la facture'],
  ['remboursement_caution', 1, 'D', '4191', 'total', 'unique', '{journal_tresorerie}', 'Remboursement de caution'],
  ['remboursement_caution', 2, 'C', '{tresorerie}', 'total', 'unique', '{journal_tresorerie}', 'Remboursement de caution'],
  ['avoir', 1, 'D', '{produit}', 'total', 'unique', 'VT', 'Avoir'],
  ['avoir', 2, 'C', '{compte_tiers}', 'total', 'unique', 'VT', 'Avoir'],
  ..._schemasCommuns,
  ['prestation_payee', 1, 'D', '{tresorerie}', 'total', 'unique', '{journal_tresorerie}', 'Prestation payée'],
  ['prestation_payee', 2, 'C', '{produit}', 'ligne', 'par_ligne', '{journal_tresorerie}', 'Prestation payée'],
  ['prestation_credit', 1, 'D', '4111', 'total', 'unique', 'VT', 'Prestation à crédit'],
  ['prestation_credit', 2, 'C', '{produit}', 'ligne', 'par_ligne', 'VT', 'Prestation à crédit'],
  ['prestation_pec', 1, 'D', '4112', 'total', 'unique', 'VT', 'Prestation prise en charge'],
  ['prestation_pec', 2, 'C', '{produit}', 'ligne', 'par_ligne', 'VT', 'Prestation prise en charge'],
  ['reglement_creance', 1, 'D', '{tresorerie}', 'total', 'unique', '{journal_tresorerie}', 'Règlement de créance'],
  ['reglement_creance', 2, 'C', '{compte_tiers}', 'total', 'unique', '{journal_tresorerie}', 'Règlement de créance'],
  ['desintox_inscription', 1, 'D', '4111', 'total', 'unique', 'VT', 'Inscription en désintoxication'],
  ['desintox_inscription', 2, 'C', '7064', 'total', 'unique', 'VT', 'Inscription en désintoxication'],
  ['desintox_inscription_etalee', 1, 'D', '4111', 'total', 'unique', 'VT', 'Inscription en désintoxication'],
  ['desintox_inscription_etalee', 2, 'C', '4770', 'total', 'unique', 'VT', 'Inscription en désintoxication'],
  ['desintox_constatation', 1, 'D', '4770', 'total', 'unique', 'OD', 'Produit de désintoxication de la période'],
  ['desintox_constatation', 2, 'C', '7064', 'total', 'unique', 'OD', 'Produit de désintoxication de la période'],
  ['desintox_hausse', 1, 'D', '4111', 'total', 'unique', 'VT', 'Ajustement du montant (hausse)'],
  ['desintox_hausse', 2, 'C', '{compte_produit}', 'total', 'unique', 'VT', 'Ajustement du montant (hausse)'],
  ['desintox_baisse', 1, 'D', '{compte_produit}', 'total', 'unique', 'VT', 'Ajustement du montant (baisse)'],
  ['desintox_baisse', 2, 'C', '4111', 'total', 'unique', 'VT', 'Ajustement du montant (baisse)'],
  ['desintox_versement', 1, 'D', '{tresorerie}', 'total', 'unique', '{journal_tresorerie}', 'Versement désintoxication'],
  ['desintox_versement', 2, 'C', '4111', 'total', 'unique', '{journal_tresorerie}', 'Versement désintoxication'],
];

const schemasONG = [
  ..._schemasCommuns,
  ..._schemasGestion,
  ['don_nature_transfert', 1, 'D', '4671', 'total', 'unique', 'OD', 'Don en nature transféré au centre de santé'],
  ['don_nature_transfert', 2, 'C', '7582', 'total', 'unique', 'OD', 'Don en nature transféré au centre de santé'],
  ['don_numeraire', 1, 'D', '{tresorerie}', 'total', 'unique', '{journal_tresorerie}', 'Don reçu'],
  ['don_numeraire', 2, 'C', '7581', 'total', 'unique', '{journal_tresorerie}', 'Don reçu'],
  ['don_nature', 1, 'D', '{compte_actif}', 'total', 'unique', 'OD', 'Don en nature'],
  ['don_nature', 2, 'C', '7582', 'total', 'unique', 'OD', 'Don en nature'],
  ['subvention_tranche', 1, 'D', '{tresorerie}', 'total', 'unique', '{journal_tresorerie}', 'Tranche de subvention'],
  ['subvention_tranche', 2, 'C', '7181', 'total', 'unique', '{journal_tresorerie}', 'Tranche de subvention'],
];

const rolesDefaut = {
  'admin': 'Administrateur',
  'comptable': 'Comptable',
  'caissier': 'Caissier',
  'agent': 'Agent de service',
  'pharmacien': 'Pharmacien',
  'responsable': 'Responsable de service',
  'direction': 'Direction / président / trésorier',
  'auditeur': 'Auditeur',
};

/// Modules de saisie (l'administrateur n'y saisit rien).
const modulesSaisie = [
  'patients', 'caisse', 'actes', 'desintox', 'depenses', 'dons', 'releves',
  'stocks', 'achats', 'hospitalisation', 'facturation', 'paie', 'immobilisations',
];
const tousModules = [
  ...modulesSaisie,
  'parametrage', 'utilisateurs', 'appareils', 'sauvegardes', 'comptabilite',
  'rapports', 'cloture', 'audit', 'anomalies', 'patients_noms', 'remises', 'tresorerie',
];

/// Droits par défaut : rôle -> module -> actions.
Map<String, Map<String, List<String>>> droitsDefaut() {
  const tout = ['voir', 'creer', 'valider', 'annuler'];
  final lecture = {for (final m in tousModules) m: ['voir']};
  return {
    'admin': {
      'parametrage': ['voir', 'creer', 'valider'],
      'utilisateurs': ['voir', 'creer', 'valider'],
      'appareils': ['voir', 'creer', 'valider'],
      'sauvegardes': ['voir', 'creer', 'valider'],
      'audit': ['voir'],
    },
    'comptable': {
      for (final m in tousModules) m: tout,
      // Le comptable gère aussi le personnel qui utilise le logiciel.
      'utilisateurs': ['voir', 'creer'],
      'appareils': ['voir'],
      'sauvegardes': ['voir', 'creer'],
      'audit': ['voir'],
    },
    'caissier': {
      'hospitalisation': ['voir', 'creer'],
      'facturation': ['voir'],
      'stocks': ['voir'],
      'patients': ['voir', 'creer'],
      'patients_noms': ['voir'],
      'caisse': ['voir', 'creer'],
      'actes': ['voir', 'creer'],
      'desintox': ['voir', 'creer'],
      'depenses': ['voir', 'creer'],
      'dons': ['voir', 'creer'],
      'tresorerie': ['voir'],
      'rapports': ['voir'],
    },
    'agent': {
      'hospitalisation': ['voir', 'creer'],
      'stocks': ['voir', 'creer'],
      'patients': ['voir', 'creer'],
      'patients_noms': ['voir'],
      'actes': ['voir', 'creer'],
      'desintox': ['voir', 'creer'],
      'caisse': ['voir', 'creer'],
      'releves': ['voir'],
    },
    'pharmacien': {
      'stocks': ['voir', 'creer'],
      'achats': ['voir', 'creer'],
      'patients': ['voir'],
      'actes': ['voir', 'creer'],
      'caisse': ['voir', 'creer'],
      'releves': ['voir'],
    },
    'responsable': {
      'actes': ['voir'],
      'releves': ['voir', 'valider'],
      'rapports': ['voir'],
    },
    'direction': {
      ...lecture,
      'depenses': ['voir', 'valider'],
      'cloture': ['voir', 'valider'],
      'desintox': ['voir', 'valider'],
      'remises': ['voir', 'creer'],
    },
    'auditeur': lecture,
  };
}

/// Seuils et délais par défaut (§5), modifiables dans le paramétrage.
const parametresDefaut = {
  'plafond_encaisse': '500000',
  'seuil_validation_depense': '100000',
  'seuil_piece_jointe': '25000',
  'stock_minimum_defaut': '10',
  'peremption_alerte_jours': '60',
  'baisse_activite_pourcent': '20',
  'desintox_archivage_jours': '30',
  'desintox_reconnaissance': 'inscription',
  'sync_jours_max': '3',
  'sync_alerte_heures': '24',
  'remise_plafond_pourcent': '20',
  'connexion_echecs_max': '5',
  'connexion_verrou_minutes': '15',
  'inactivite_minutes': '10',
  'releve_section_ecarts': '1',
  'seuil_don_liste': '500000',
  'sauvegarde_conservation_jours': '30',
  'sauvegarde_dossier': '',
  'version_parametrage': '1',
  'tresorerie_minimum': '0',
  'alerte_deficit': '1',
  'cle_repartition': 'chiffre_affaires',
  'sortie_stock_minimum_jours': '0',
  // Billets et pièces FCFA (billetage).
  'coupures': '10000,5000,2000,1000,500,100,50,25,10,5,1',
};

/// Taux de paie à VALIDER avec la législation en vigueur (§6.12) : ils sont
/// datés et modifiables ; aucun n'est codé dans les calculs.
/// [code, libellé, nature, organisme, taux pour dix mille, plafond]
const rubriquesPaieDefaut = [
  ['CNPS_PV_SAL', 'CNPS pension vieillesse (part salariale)', 'retenue_salariale', 'CNPS', 420, 750000],
  ['CFC_SAL', 'Crédit foncier (part salariale)', 'retenue_salariale', 'ETAT', 100, 0],
  ['IRPP', 'IRPP (à paramétrer selon le barème)', 'retenue_salariale', 'ETAT', 0, 0],
  ['CNPS_PV_PAT', 'CNPS pension vieillesse (part patronale)', 'charge_patronale', 'CNPS', 420, 750000],
  ['CNPS_PF', 'CNPS prestations familiales', 'charge_patronale', 'CNPS', 700, 750000],
  ['CNPS_AT', 'CNPS accidents du travail', 'charge_patronale', 'CNPS', 175, 750000],
  ['CFC_PAT', 'Crédit foncier (part patronale)', 'charge_patronale', 'ETAT', 150, 0],
  ['FNE', 'Fonds national de l’emploi', 'charge_patronale', 'ETAT', 100, 0],
];

/// [code, libellé, compte d'immobilisation, compte d'amortissement, durée en mois]
const categoriesImmobilisationsDefaut = [
  ['BAT', 'Bâtiments', '2311', '2831', 240],
  ['MED', 'Matériel médical et technique', '2411', '2841', 60],
  ['INFO', 'Matériel informatique', '2442', '2844', 36],
  ['MOB', 'Mobilier de bureau', '2444', '2844', 120],
  ['TRANS', 'Matériel de transport', '2451', '2845', 48],
];

/// Stocks : comptes par magasin. [stock, libellé, compte de stock, variation, achat, vente, activité]
const magasinsDefaut = {
  'PHM': ['Pharmacie moderne', '3111', '6031', '6011', '7011', 'PHM'],
  'PHT': ['Pharmacie traditionnelle', '3112', '6031', '6012', '7012', 'PHT'],
  'LAB': ['Réactifs du laboratoire', '3311', '6033', '6041', '', 'LAB'],
};
