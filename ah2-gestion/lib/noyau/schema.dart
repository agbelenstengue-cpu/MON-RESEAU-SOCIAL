/// Schéma de la base locale SQLite (identique sur le PC central et sur chaque appareil).
///
/// Trois familles de tables :
///  * PARAMÉTRAGE : fait autorité sur le PC central, diffusé aux appareils ;
///  * REGISTRES IMMUABLES : `operations`, `audit`, `ecritures`, `lignes_ecriture` , 
///    des déclencheurs SQL interdisent toute modification ou suppression ;
///  * VUES MÉTIER DÉRIVÉES : calculées en appliquant les opérations (actes,
///    versements, mouvements de trésorerie…). Elles se reconstruisent à
///    l'identique sur chaque appareil à partir des opérations.
library;

/// Version du schéma. Une mise à jour du logiciel n'efface jamais rien :
/// chaque nouvelle version ajoute des tables ou des colonnes (voir [migrations]).
const int versionSchema = 2;

const String schemaSql = r'''
-- ============================== PARAMÉTRAGE ==============================
CREATE TABLE parametres (
  cle TEXT PRIMARY KEY,
  valeur TEXT NOT NULL
) STRICT;

CREATE TABLE entites (
  code TEXT PRIMARY KEY,            -- CS (centre de santé) ou ONG
  nom TEXT NOT NULL,
  sigle TEXT NOT NULL,
  referentiel TEXT NOT NULL CHECK (referentiel IN ('SYSCOHADA','SYCEBNL')),
  adresse TEXT NOT NULL DEFAULT '',
  contacts TEXT NOT NULL DEFAULT '',
  numeros_administratifs TEXT NOT NULL DEFAULT '',
  logo BLOB,                        -- PNG ou JPEG
  entete BLOB,                      -- entête complète importée (image), remplace l'entête générée
  filigrane INTEGER NOT NULL DEFAULT 1  -- logo en filigrane sur les documents et l'écran
) STRICT;

CREATE TABLE comptes (
  entite TEXT NOT NULL REFERENCES entites(code),
  numero TEXT NOT NULL,
  libelle TEXT NOT NULL,
  origine TEXT NOT NULL,            -- SYSCOHADA ou SYCEBNL
  a_valider INTEGER NOT NULL DEFAULT 1,
  actif INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY (entite, numero)
) STRICT;

CREATE TABLE journaux (
  entite TEXT NOT NULL REFERENCES entites(code),
  code TEXT NOT NULL,
  libelle TEXT NOT NULL,
  type TEXT NOT NULL,               -- caisse, banque, momo, ventes, achats, paie, od, an
  PRIMARY KEY (entite, code)
) STRICT;

CREATE TABLE activites (
  code TEXT PRIMARY KEY,
  libelle TEXT NOT NULL,
  entite TEXT NOT NULL REFERENCES entites(code),
  service INTEGER NOT NULL DEFAULT 0,   -- 1 = enregistre des actes (relevé journalier)
  type_releve TEXT NOT NULL DEFAULT 'actes',  -- actes ou sorties (pharmacies)
  actif INTEGER NOT NULL DEFAULT 1
) STRICT;

CREATE TABLE tresoreries (
  id TEXT PRIMARY KEY,
  entite TEXT NOT NULL REFERENCES entites(code),
  type TEXT NOT NULL CHECK (type IN ('caisse','banque','momo')),
  libelle TEXT NOT NULL,
  compte TEXT NOT NULL,
  journal TEXT NOT NULL,
  appareil TEXT,                    -- caisse mobile : appareil rattaché
  operateur TEXT,                   -- momo : MTN ou ORANGE
  centrale INTEGER NOT NULL DEFAULT 0,
  actif INTEGER NOT NULL DEFAULT 1
) STRICT;

CREATE TABLE actes_catalogue (
  code TEXT PRIMARY KEY,
  libelle TEXT NOT NULL,
  activite TEXT NOT NULL REFERENCES activites(code),
  compte_produit TEXT NOT NULL,
  actif INTEGER NOT NULL DEFAULT 1
) STRICT;

-- Historique des tarifs : un tarif modifié ne change jamais le passé.
CREATE TABLE tarifs (
  code_acte TEXT NOT NULL REFERENCES actes_catalogue(code),
  depuis TEXT NOT NULL,             -- date ISO d'entrée en vigueur
  prix INTEGER NOT NULL CHECK (prix >= 0),
  PRIMARY KEY (code_acte, depuis)
) STRICT;

CREATE TABLE programmes_desintox (
  code TEXT PRIMARY KEY,
  libelle TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('ambulatoire','residentiel')),
  duree_jours INTEGER NOT NULL,
  phases TEXT NOT NULL DEFAULT '',
  mode_calcul TEXT NOT NULL CHECK (mode_calcul IN ('forfait','journalier')),
  montant INTEGER NOT NULL,         -- forfait total, ou prix par jour
  actif INTEGER NOT NULL DEFAULT 1
) STRICT;

-- Schémas d'écritures automatiques, modifiables par le comptable.
-- compte : numéro de compte, ou variable entre accolades ({tresorerie}, {produit}…)
-- montant : 'total' (montant de l'opération) ou 'ligne' (montant de chaque ligne)
-- repetition : 'unique' ou 'par_ligne'
CREATE TABLE schemas_ecritures (
  entite TEXT NOT NULL REFERENCES entites(code),
  type_ecriture TEXT NOT NULL,
  ordre INTEGER NOT NULL,
  sens TEXT NOT NULL CHECK (sens IN ('D','C')),
  compte TEXT NOT NULL,
  montant TEXT NOT NULL CHECK (montant IN ('total','ligne')),
  repetition TEXT NOT NULL CHECK (repetition IN ('unique','par_ligne')),
  journal TEXT NOT NULL,            -- code journal ou {journal_tresorerie}
  libelle TEXT NOT NULL,
  PRIMARY KEY (entite, type_ecriture, ordre)
) STRICT;

CREATE TABLE roles (
  code TEXT PRIMARY KEY,
  libelle TEXT NOT NULL
) STRICT;

-- Droits fins : par rôle, module et action (voir, creer, valider, annuler).
CREATE TABLE droits (
  role TEXT NOT NULL REFERENCES roles(code),
  module TEXT NOT NULL,
  action TEXT NOT NULL,
  PRIMARY KEY (role, module, action)
) STRICT;

CREATE TABLE utilisateurs (
  id TEXT PRIMARY KEY,
  identifiant TEXT NOT NULL UNIQUE,
  nom TEXT NOT NULL,
  role TEXT NOT NULL REFERENCES roles(code),
  activite TEXT,                    -- service rattaché (agents, responsables)
  sel TEXT NOT NULL,
  empreinte TEXT NOT NULL,          -- PBKDF2-HMAC-SHA256 du mot de passe
  sel_code TEXT,
  empreinte_code TEXT,              -- code court pour le téléphone
  actif INTEGER NOT NULL DEFAULT 1
) STRICT;

CREATE TABLE appareils (
  code TEXT PRIMARY KEY,            -- PC1, T01, T02…
  nom TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('pc','telephone')),
  central INTEGER NOT NULL DEFAULT 0,
  utilisateur_principal TEXT,
  cle_sync TEXT NOT NULL,           -- secret partagé (base64), sert au chiffrement
  statut TEXT NOT NULL DEFAULT 'autorise' CHECK (statut IN ('autorise','revoque','inactif')),
  derniere_sync TEXT                -- horodatage de la dernière synchronisation complète
) STRICT;

-- ============================== REGISTRES IMMUABLES ==============================
CREATE TABLE operations (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,   -- ordre d'arrivée dans CETTE base
  uuid TEXT NOT NULL UNIQUE,
  type TEXT NOT NULL,
  entite TEXT NOT NULL,
  appareil TEXT NOT NULL,
  utilisateur TEXT NOT NULL,
  horodatage TEXT NOT NULL,                -- ISO 8601, heure de l'appareil
  date_op TEXT NOT NULL,                   -- date ISO de rattachement
  piece TEXT,                              -- numéro de pièce attribué sur l'appareil
  donnees TEXT NOT NULL,                   -- JSON
  origine TEXT NOT NULL CHECK (origine IN ('locale','synchronisee')),
  recu_le TEXT NOT NULL
) STRICT;
CREATE INDEX operations_date ON operations(date_op, type);
CREATE UNIQUE INDEX operations_piece ON operations(piece) WHERE piece IS NOT NULL;

CREATE TRIGGER operations_pas_de_modif BEFORE UPDATE ON operations
BEGIN SELECT RAISE(ABORT, 'Une opération enregistrée ne peut pas être modifiée.'); END;
CREATE TRIGGER operations_pas_de_suppr BEFORE DELETE ON operations
BEGIN SELECT RAISE(ABORT, 'Une opération enregistrée ne peut pas être supprimée.'); END;

-- Compteurs de pièces : une série par appareil, entité, type de pièce et exercice.
CREATE TABLE compteurs (
  appareil TEXT NOT NULL,
  entite TEXT NOT NULL,
  type_piece TEXT NOT NULL,
  exercice INTEGER NOT NULL,
  dernier INTEGER NOT NULL,
  PRIMARY KEY (appareil, entite, type_piece, exercice)
) STRICT;
CREATE TRIGGER compteurs_croissants BEFORE UPDATE ON compteurs
WHEN NEW.dernier <> OLD.dernier + 1
BEGIN SELECT RAISE(ABORT, 'Un compteur de pièces ne peut qu''avancer de 1.'); END;
CREATE TRIGGER compteurs_pas_de_suppr BEFORE DELETE ON compteurs
BEGIN SELECT RAISE(ABORT, 'Un compteur de pièces ne peut pas être supprimé.'); END;

-- Journal d'audit chaîné : chaque ligne contient l'empreinte de la précédente.
CREATE TABLE audit (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  horodatage TEXT NOT NULL,
  utilisateur TEXT NOT NULL,
  appareil TEXT NOT NULL,
  action TEXT NOT NULL,            -- creation, modification, annulation, connexion, synchronisation…
  objet TEXT NOT NULL,
  ancienne_valeur TEXT,
  nouvelle_valeur TEXT,
  empreinte_prec TEXT NOT NULL,
  empreinte TEXT NOT NULL
) STRICT;
CREATE TRIGGER audit_pas_de_modif BEFORE UPDATE ON audit
BEGIN SELECT RAISE(ABORT, 'Le journal d''audit ne peut pas être modifié.'); END;
CREATE TRIGGER audit_pas_de_suppr BEFORE DELETE ON audit
BEGIN SELECT RAISE(ABORT, 'Le journal d''audit ne peut pas être supprimé.'); END;

CREATE TABLE ecritures (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid_op TEXT NOT NULL,
  entite TEXT NOT NULL,
  journal TEXT NOT NULL,
  date TEXT NOT NULL,
  libelle TEXT NOT NULL,
  piece TEXT,
  utilisateur TEXT NOT NULL,
  appareil TEXT NOT NULL,
  contre_passation INTEGER NOT NULL DEFAULT 0
) STRICT;
CREATE INDEX ecritures_op ON ecritures(uuid_op);
CREATE INDEX ecritures_date ON ecritures(entite, date);

CREATE TABLE lignes_ecriture (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ecriture INTEGER NOT NULL REFERENCES ecritures(id),
  compte TEXT NOT NULL,
  debit INTEGER NOT NULL DEFAULT 0 CHECK (debit >= 0),
  credit INTEGER NOT NULL DEFAULT 0 CHECK (credit >= 0),
  activite TEXT,
  subvention TEXT,
  tiers TEXT
) STRICT;
CREATE INDEX lignes_compte ON lignes_ecriture(compte);
CREATE INDEX lignes_tiers ON lignes_ecriture(tiers);

CREATE TRIGGER ecritures_pas_de_modif BEFORE UPDATE ON ecritures
BEGIN SELECT RAISE(ABORT, 'Une écriture comptable ne peut pas être modifiée.'); END;
CREATE TRIGGER ecritures_pas_de_suppr BEFORE DELETE ON ecritures
BEGIN SELECT RAISE(ABORT, 'Une écriture comptable ne peut pas être supprimée.'); END;
CREATE TRIGGER lignes_pas_de_modif BEFORE UPDATE ON lignes_ecriture
BEGIN SELECT RAISE(ABORT, 'Une écriture comptable ne peut pas être modifiée.'); END;
CREATE TRIGGER lignes_pas_de_suppr BEFORE DELETE ON lignes_ecriture
BEGIN SELECT RAISE(ABORT, 'Une écriture comptable ne peut pas être supprimée.'); END;

-- ============================== VUES MÉTIER DÉRIVÉES ==============================
CREATE TABLE annulations (
  uuid_annule TEXT PRIMARY KEY,
  uuid_op TEXT NOT NULL,           -- opération d'annulation
  motif TEXT NOT NULL
) STRICT;

CREATE TABLE mouvements_tresorerie (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid_op TEXT NOT NULL,
  tresorerie TEXT NOT NULL REFERENCES tresoreries(id),
  date TEXT NOT NULL,
  horodatage TEXT NOT NULL,
  montant INTEGER NOT NULL,        -- positif = entrée, négatif = sortie
  libelle TEXT NOT NULL,
  piece TEXT,
  reference TEXT
) STRICT;
CREATE INDEX mouvements_treso ON mouvements_tresorerie(tresorerie, date);

CREATE TABLE patients (
  id TEXT PRIMARY KEY,
  numero_dossier TEXT NOT NULL UNIQUE,
  nom TEXT NOT NULL,
  prenoms TEXT NOT NULL DEFAULT '',
  sexe TEXT NOT NULL DEFAULT '',
  naissance TEXT,
  contact TEXT NOT NULL DEFAULT '',
  personne_a_prevenir TEXT NOT NULL DEFAULT '',
  version_op TEXT NOT NULL,        -- opération qui a produit la version affichée
  horodatage_version TEXT NOT NULL
) STRICT;

CREATE TABLE patients_historique (
  uuid_op TEXT PRIMARY KEY,
  patient TEXT NOT NULL,
  horodatage TEXT NOT NULL,
  donnees TEXT NOT NULL
) STRICT;

CREATE TABLE actes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid_op TEXT NOT NULL,
  piece TEXT NOT NULL,
  patient TEXT,
  activite TEXT NOT NULL,
  code_acte TEXT NOT NULL,
  libelle TEXT NOT NULL,
  quantite INTEGER NOT NULL,
  prix_unitaire INTEGER NOT NULL,
  remise INTEGER NOT NULL DEFAULT 0,
  montant INTEGER NOT NULL,
  mode TEXT NOT NULL,
  motif_gratuite TEXT,
  praticien TEXT,
  date TEXT NOT NULL,
  horodatage TEXT NOT NULL,
  appareil TEXT NOT NULL,
  utilisateur TEXT NOT NULL,
  statut TEXT NOT NULL DEFAULT 'realise',   -- labo : demande / realise
  annule INTEGER NOT NULL DEFAULT 0
) STRICT;
CREATE INDEX actes_jour ON actes(activite, date);

CREATE TABLE desintox_dossiers (
  id TEXT PRIMARY KEY,
  numero TEXT NOT NULL UNIQUE,
  patient TEXT NOT NULL REFERENCES patients(id),
  programme TEXT NOT NULL,
  date_entree TEXT NOT NULL,
  duree_prevue INTEGER NOT NULL,
  montant_total INTEGER NOT NULL,
  responsables TEXT NOT NULL,      -- JSON [{nom, lien, telephone}]
  echeancier TEXT NOT NULL,        -- JSON [{date, montant}]
  reconnaissance TEXT NOT NULL,    -- inscription ou etalee
  produit_constate INTEGER NOT NULL DEFAULT 0,
  date_sortie TEXT,
  motif_sortie TEXT,
  uuid_op TEXT NOT NULL
) STRICT;

CREATE TABLE desintox_versements (
  uuid_op TEXT PRIMARY KEY,
  dossier TEXT NOT NULL REFERENCES desintox_dossiers(id),
  date TEXT NOT NULL,
  horodatage TEXT NOT NULL,
  montant INTEGER NOT NULL CHECK (montant > 0),
  payeur TEXT NOT NULL,
  mode TEXT NOT NULL,
  reference TEXT,
  piece TEXT NOT NULL,
  annule INTEGER NOT NULL DEFAULT 0
) STRICT;

CREATE TABLE depenses (
  uuid_op TEXT PRIMARY KEY,
  entite TEXT NOT NULL,
  piece TEXT NOT NULL,
  date TEXT NOT NULL,
  beneficiaire TEXT NOT NULL,
  motif TEXT NOT NULL,
  compte TEXT NOT NULL,
  activite TEXT NOT NULL,
  subvention TEXT,
  tresorerie TEXT NOT NULL,
  montant INTEGER NOT NULL CHECK (montant > 0),
  piece_jointe TEXT,
  statut TEXT NOT NULL CHECK (statut IN ('en_attente','validee','rejetee','payee')),
  valide_par TEXT,
  annule INTEGER NOT NULL DEFAULT 0
) STRICT;

CREATE TABLE arretes_caisse (
  uuid_op TEXT PRIMARY KEY,
  tresorerie TEXT NOT NULL,
  date TEXT NOT NULL,
  billetage TEXT NOT NULL,         -- JSON {coupure: nombre}
  compte INTEGER NOT NULL,
  theorique INTEGER NOT NULL,
  ecart INTEGER NOT NULL,
  motif_ecart TEXT,
  piece TEXT NOT NULL
) STRICT;

CREATE TABLE clotures (
  entite TEXT NOT NULL,
  date TEXT NOT NULL,
  cloture INTEGER NOT NULL,        -- 1 = clôturée, 0 = rouverte
  uuid_op TEXT NOT NULL,
  PRIMARY KEY (entite, date)
) STRICT;

CREATE TABLE periodes_verrouillees (
  entite TEXT NOT NULL,
  periode TEXT NOT NULL,           -- AAAA-MM ou AAAA
  uuid_op TEXT NOT NULL,
  PRIMARY KEY (entite, periode)
) STRICT;

CREATE TABLE releves (
  numero TEXT PRIMARY KEY,
  activite TEXT NOT NULL,
  date_actes TEXT NOT NULL,
  genere_le TEXT NOT NULL,
  genere_par TEXT NOT NULL,
  contenu TEXT NOT NULL,           -- JSON figé : lignes + synthèse
  statut TEXT NOT NULL DEFAULT 'genere' CHECK (statut IN ('genere','retourne_signe')),
  scan TEXT,
  uuid_op TEXT NOT NULL
) STRICT;

CREATE TABLE ecarts_releve (
  numero TEXT PRIMARY KEY,
  releve TEXT NOT NULL REFERENCES releves(numero),
  ligne TEXT NOT NULL,
  nature TEXT NOT NULL,
  observation TEXT NOT NULL DEFAULT '',
  statut TEXT NOT NULL DEFAULT 'ouvert' CHECK (statut IN ('ouvert','justifie','regularise')),
  regularisation TEXT,
  uuid_op TEXT NOT NULL
) STRICT;

CREATE TABLE donateurs (
  id TEXT PRIMARY KEY,
  nom TEXT NOT NULL,
  responsable TEXT NOT NULL DEFAULT '',
  adresse TEXT NOT NULL DEFAULT '',
  telephone TEXT NOT NULL DEFAULT '',
  pays TEXT NOT NULL DEFAULT '',
  type TEXT NOT NULL,
  uuid_op TEXT NOT NULL
) STRICT;

CREATE TABLE dons (
  uuid_op TEXT PRIMARY KEY,
  piece TEXT NOT NULL,
  donateur TEXT NOT NULL REFERENCES donateurs(id),
  date TEXT NOT NULL,
  montant INTEGER NOT NULL CHECK (montant > 0),
  nature TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  affectation TEXT,                -- activité ou programme
  subvention TEXT,
  annule INTEGER NOT NULL DEFAULT 0
) STRICT;

CREATE TABLE subventions (
  id TEXT PRIMARY KEY,
  reference TEXT NOT NULL UNIQUE,
  bailleur TEXT NOT NULL REFERENCES donateurs(id),
  montant_accorde INTEGER NOT NULL,
  debut TEXT NOT NULL,
  fin TEXT NOT NULL,
  programme TEXT,
  conditions TEXT NOT NULL DEFAULT '',
  budget TEXT NOT NULL,            -- JSON [{ligne, libelle, montant}]
  tranches TEXT NOT NULL,          -- JSON [{date, montant}] attendues
  uuid_op TEXT NOT NULL
) STRICT;

CREATE TABLE subventions_tranches_recues (
  uuid_op TEXT PRIMARY KEY,
  subvention TEXT NOT NULL REFERENCES subventions(id),
  date TEXT NOT NULL,
  montant INTEGER NOT NULL,
  piece TEXT NOT NULL,
  annule INTEGER NOT NULL DEFAULT 0
) STRICT;

-- Pièces jointes (photos, scans) : synchronisées avec l'opération qui les porte.
CREATE TABLE pieces_jointes (
  sha256 TEXT PRIMARY KEY,
  uuid_op TEXT NOT NULL,
  nom TEXT NOT NULL,
  contenu BLOB NOT NULL,
  ajoute_le TEXT NOT NULL
) STRICT;

CREATE TABLE anomalies_sync (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  horodatage TEXT NOT NULL,
  type TEXT NOT NULL,
  uuid_op TEXT,
  detail TEXT NOT NULL,
  statut TEXT NOT NULL DEFAULT 'a_traiter' CHECK (statut IN ('a_traiter','traitee')),
  traitee_par TEXT
) STRICT;

-- État de synchronisation côté appareil (curseurs).
CREATE TABLE etat_sync (
  cle TEXT PRIMARY KEY,
  valeur TEXT NOT NULL
) STRICT;
''';

/// Migrations successives, appliquées dans l'ordre et dans une transaction.
/// Règle : uniquement des ajouts (CREATE TABLE, ALTER TABLE ADD COLUMN),
/// jamais de suppression de données.
const Map<int, String> migrations = {
  2: r"""
-- ---------- Comptabilité : rapprochement bancaire, lettrage, analytique
CREATE TABLE releves_bancaires (
  uuid_op TEXT PRIMARY KEY,
  tresorerie TEXT NOT NULL,
  date TEXT NOT NULL,
  solde INTEGER NOT NULL,
  reference TEXT NOT NULL DEFAULT ''
) STRICT;
CREATE TABLE pointages (
  mouvement TEXT PRIMARY KEY,       -- uuid de l'opération + ':' + rang du mouvement
  uuid_op TEXT NOT NULL,
  releve TEXT
) STRICT;
CREATE TABLE lettrages (
  ligne TEXT PRIMARY KEY,           -- uuid de l'opération + ':' + rang de la ligne
  code TEXT NOT NULL,
  uuid_op TEXT NOT NULL
) STRICT;

-- ---------- Stocks (pharmacies moderne et traditionnelle, réactifs du laboratoire)
CREATE TABLE produits (
  code TEXT PRIMARY KEY,
  designation TEXT NOT NULL,
  stock TEXT NOT NULL,              -- PHM, PHT ou LAB
  forme TEXT NOT NULL DEFAULT '',
  dosage TEXT NOT NULL DEFAULT '',
  unite TEXT NOT NULL DEFAULT 'unité',
  prix_vente INTEGER NOT NULL DEFAULT 0,
  stock_minimum INTEGER NOT NULL DEFAULT 0,
  producteur TEXT NOT NULL DEFAULT '',
  origine TEXT NOT NULL DEFAULT '',
  preparation TEXT NOT NULL DEFAULT '',
  actif INTEGER NOT NULL DEFAULT 1
) STRICT;
CREATE TABLE mouvements_stock (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid_op TEXT NOT NULL,
  rang INTEGER NOT NULL,
  produit TEXT NOT NULL,
  lot TEXT NOT NULL,
  peremption TEXT,
  date TEXT NOT NULL,
  horodatage TEXT NOT NULL,
  quantite INTEGER NOT NULL,        -- positive = entrée, négative = sortie
  cout_unitaire INTEGER NOT NULL,   -- CUMP (sorties) ou coût d'achat (entrées)
  type TEXT NOT NULL,
  reference TEXT,
  annule INTEGER NOT NULL DEFAULT 0
) STRICT;
CREATE INDEX mouvements_stock_produit ON mouvements_stock(produit, lot);
CREATE TABLE inventaires (
  uuid_op TEXT PRIMARY KEY,
  stock TEXT NOT NULL,
  date TEXT NOT NULL,
  lignes TEXT NOT NULL
) STRICT;

-- ---------- Fournisseurs et achats
CREATE TABLE fournisseurs (
  id TEXT PRIMARY KEY,
  nom TEXT NOT NULL,
  contact TEXT NOT NULL DEFAULT '',
  adresse TEXT NOT NULL DEFAULT '',
  uuid_op TEXT NOT NULL
) STRICT;
CREATE TABLE commandes (
  uuid_op TEXT PRIMARY KEY,
  piece TEXT NOT NULL,
  fournisseur TEXT NOT NULL,
  date TEXT NOT NULL,
  lignes TEXT NOT NULL,
  statut TEXT NOT NULL DEFAULT 'envoyee'
) STRICT;

-- ---------- Hospitalisation
CREATE TABLE lits (
  code TEXT PRIMARY KEY,
  chambre TEXT NOT NULL,
  categorie TEXT NOT NULL,
  tarif_journalier INTEGER NOT NULL,
  actif INTEGER NOT NULL DEFAULT 1
) STRICT;
CREATE TABLE sejours (
  id TEXT PRIMARY KEY,
  numero TEXT NOT NULL UNIQUE,
  patient TEXT NOT NULL,
  lit TEXT NOT NULL,
  date_entree TEXT NOT NULL,
  tarif_journalier INTEGER NOT NULL,
  caution INTEGER NOT NULL DEFAULT 0,
  date_sortie TEXT,
  journees INTEGER,
  uuid_op TEXT NOT NULL
) STRICT;

-- ---------- Massages : carnets de séances
CREATE TABLE carnets (
  id TEXT PRIMARY KEY,
  patient TEXT,
  acte TEXT NOT NULL,
  seances INTEGER NOT NULL,
  consommees INTEGER NOT NULL DEFAULT 0,
  montant INTEGER NOT NULL,
  date TEXT NOT NULL,
  uuid_op TEXT NOT NULL
) STRICT;

-- ---------- Personnel et paie
CREATE TABLE employes (
  id TEXT PRIMARY KEY,
  matricule TEXT NOT NULL UNIQUE,
  nom TEXT NOT NULL,
  poste TEXT NOT NULL DEFAULT '',
  activite TEXT,
  entite TEXT NOT NULL,
  embauche TEXT,
  contrat TEXT NOT NULL DEFAULT '',
  statut TEXT NOT NULL DEFAULT 'salarie',     -- salarie ou benevole
  salaire_base INTEGER NOT NULL DEFAULT 0,
  primes INTEGER NOT NULL DEFAULT 0,
  cnps TEXT NOT NULL DEFAULT '',
  paiement TEXT NOT NULL DEFAULT '',
  actif INTEGER NOT NULL DEFAULT 1,
  uuid_op TEXT NOT NULL
) STRICT;
-- Rubriques de paie paramétrables et datées (aucun taux codé en dur).
CREATE TABLE rubriques_paie (
  code TEXT NOT NULL,
  depuis TEXT NOT NULL,
  libelle TEXT NOT NULL,
  nature TEXT NOT NULL CHECK (nature IN ('retenue_salariale','charge_patronale')),
  organisme TEXT NOT NULL CHECK (organisme IN ('CNPS','ETAT')),
  taux INTEGER NOT NULL,            -- taux en pour dix mille (420 = 4,20 %)
  plafond INTEGER NOT NULL DEFAULT 0, -- base plafonnée (0 = pas de plafond)
  actif INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY (code, depuis)
) STRICT;
CREATE TABLE bulletins (
  id TEXT PRIMARY KEY,              -- employé + période
  uuid_op TEXT NOT NULL,
  employe TEXT NOT NULL,
  periode TEXT NOT NULL,
  brut INTEGER NOT NULL,
  retenues INTEGER NOT NULL,
  avances INTEGER NOT NULL,
  net INTEGER NOT NULL,
  patronales INTEGER NOT NULL,
  detail TEXT NOT NULL,
  annule INTEGER NOT NULL DEFAULT 0
) STRICT;
CREATE TABLE conges (
  uuid_op TEXT PRIMARY KEY,
  employe TEXT NOT NULL,
  debut TEXT NOT NULL,
  fin TEXT NOT NULL,
  motif TEXT NOT NULL DEFAULT ''
) STRICT;

-- ---------- Immobilisations
CREATE TABLE categories_immobilisations (
  code TEXT PRIMARY KEY,
  libelle TEXT NOT NULL,
  compte_immobilisation TEXT NOT NULL,
  compte_amortissement TEXT NOT NULL,
  duree_mois INTEGER NOT NULL
) STRICT;
CREATE TABLE immobilisations (
  id TEXT PRIMARY KEY,
  numero TEXT NOT NULL UNIQUE,
  designation TEXT NOT NULL,
  categorie TEXT NOT NULL,
  entite TEXT NOT NULL,
  date_acquisition TEXT NOT NULL,
  valeur INTEGER NOT NULL,
  origine TEXT NOT NULL,            -- achat ou don
  localisation TEXT NOT NULL DEFAULT '',
  activite TEXT,
  duree_mois INTEGER NOT NULL,
  amorti INTEGER NOT NULL DEFAULT 0,
  date_sortie TEXT,
  motif_sortie TEXT,
  uuid_op TEXT NOT NULL
) STRICT;

-- ---------- Désintoxication : médicaments facturés en plus du forfait
ALTER TABLE desintox_dossiers ADD COLUMN medicaments_factures INTEGER NOT NULL DEFAULT 0;
ALTER TABLE desintox_dossiers ADD COLUMN medicaments_compris INTEGER NOT NULL DEFAULT 0;
""",
};
