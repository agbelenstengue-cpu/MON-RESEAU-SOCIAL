/// Paramétrage : installation, utilisateurs, appareils, tarifs, seuils.
///
/// Le PC central fait autorité : le paramétrage ne se modifie que sur lui,
/// puis il est diffusé à tous les appareils à chaque synchronisation.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../noyau/audit.dart';
import '../../noyau/base.dart';
import '../../noyau/outils.dart';
import '../../noyau/securite.dart';
import '../../noyau/session.dart';
import 'referentiels.dart';

class Parametrage {
  /// Tables diffusées par le PC central (ordre d'insertion).
  static const tablesDiffusees = [
    'parametres', 'entites', 'roles', 'droits', 'comptes', 'journaux', 'activites',
    'tresoreries', 'actes_catalogue', 'tarifs', 'programmes_desintox',
    'schemas_ecritures', 'utilisateurs', 'appareils',
    'produits', 'lits', 'rubriques_paie', 'categories_immobilisations',
  ];

  static String _cleAleatoire() {
    final r = Random.secure();
    return base64Encode(List<int>.generate(32, (_) => r.nextInt(256)));
  }

  /// Installe la base de référence sur le PC central.
  static void installerPcCentral(
    Base base, {
    required String motDePasseAdmin,
    String identifiantAdmin = 'admin',
    String nomAdmin = 'Administrateur',
    String nomAppareil = 'PC central',
    Uint8List? logo,
  }) {
    if (base.entier('SELECT COUNT(*) FROM entites') > 0) {
      throw const RegleMetier('La base est déjà installée.');
    }
    base.transaction(() {
      parametresDefaut.forEach(base.definirParam);
      base.definirParam('exercice_courant', '${base.maintenant.year}');
      for (final e in entitesDefaut) {
        base.exec('INSERT INTO entites(code, nom, sigle, referentiel) VALUES (?,?,?,?)',
            [e['code'], e['nom'], e['sigle'], e['referentiel']]);
      }
      void comptes(String ent, List<CompteDefaut> liste, String origine) {
        for (final c in liste) {
          base.exec('INSERT INTO comptes(entite, numero, libelle, origine) VALUES (?,?,?,?)',
              [ent, c.numero, c.libelle, origine]);
        }
      }

      comptes('CS', comptesCS, 'SYSCOHADA');
      comptes('ONG', comptesONG, 'SYCEBNL');
      for (final ent in ['CS', 'ONG']) {
        for (final j in journauxDefaut) {
          base.exec('INSERT INTO journaux(entite, code, libelle, type) VALUES (?,?,?,?)', [ent, j[0], j[1], j[2]]);
        }
        base.exec(
            "INSERT INTO tresoreries(id, entite, type, libelle, compte, journal, appareil, centrale) VALUES (?,?,'caisse',?,?,?,?,1)",
            ['$ent-CAISSE', ent, 'Caisse centrale', '5711', 'CA1', base.appareil]);
        base.exec("INSERT INTO tresoreries(id, entite, type, libelle, compte, journal) VALUES (?,?,'banque',?,?,?)",
            ['$ent-BQ', ent, 'Banque, compte courant', '5211', 'BQ1']);
        base.exec(
            "INSERT INTO tresoreries(id, entite, type, libelle, compte, journal, operateur) VALUES (?,?,'momo',?,?,?,?)",
            ['$ent-MTN', ent, 'MTN Mobile Money', '5521', 'MTN', 'MTN']);
        base.exec(
            "INSERT INTO tresoreries(id, entite, type, libelle, compte, journal, operateur) VALUES (?,?,'momo',?,?,?,?)",
            ['$ent-ORA', ent, 'Orange Money', '5522', 'ORA', 'ORANGE']);
      }
      for (final a in activitesDefaut) {
        base.exec('INSERT INTO activites(code, libelle, entite, service, type_releve) VALUES (?,?,?,?,?)', a);
      }
      for (final a in actesDefaut) {
        base.exec('INSERT INTO actes_catalogue(code, libelle, activite, compte_produit) VALUES (?,?,?,?)',
            [a[0], a[1], a[2], a[3]]);
        // Tarif initial : en vigueur depuis l'origine.
        base.exec('INSERT INTO tarifs(code_acte, depuis, prix) VALUES (?,?,?)', [a[0], '2000-01-01', a[4]]);
      }
      for (final p in programmesDefaut) {
        base.exec(
            'INSERT INTO programmes_desintox(code, libelle, type, duree_jours, mode_calcul, montant) VALUES (?,?,?,?,?,?)', p);
      }
      void schemas(String ent, List<List<Object>> liste) {
        for (final s in liste) {
          base.exec(
              'INSERT INTO schemas_ecritures(entite, type_ecriture, ordre, sens, compte, montant, repetition, journal, libelle) '
              'VALUES (?,?,?,?,?,?,?,?,?)',
              [ent, ...s]);
        }
      }

      schemas('CS', schemasCS);
      schemas('ONG', schemasONG);
      rolesDefaut.forEach((code, lib) => base.exec('INSERT INTO roles(code, libelle) VALUES (?,?)', [code, lib]));
      droitsDefaut().forEach((role, modules) => modules.forEach((module, actions) {
            for (final a in actions) {
              base.exec('INSERT OR IGNORE INTO droits(role, module, action) VALUES (?,?,?)', [role, module, a]);
            }
          }));
      if (logo != null) {
        verifierImage(logo);
        base.exec('UPDATE entites SET logo=?', [logo]);
      }
      base.exec("INSERT INTO appareils(code, nom, type, central, cle_sync) VALUES (?,?,'pc',1,?)",
          [base.appareil, nomAppareil, _cleAleatoire()]);
      _insererUtilisateur(base, identifiantAdmin, nomAdmin, 'admin', motDePasseAdmin, null, null);
      base.exec("INSERT INTO etat_sync(cle, valeur) VALUES ('installe_le', ?)", [base.maintenant.toIso8601String()]);
      completerReferentiels(base);
      Audit.tracer(base, utilisateur: 'installation', action: 'installation', objet: 'PC central ${base.appareil}');
    });
  }

  /// Ajoute, sans rien écraser, les éléments de paramétrage apportés par une
  /// nouvelle version du logiciel (comptes, journaux, schémas, droits,
  /// paramètres, taux de paie, catégories d'immobilisations). Appelé à
  /// l'installation et à chaque démarrage du PC central : une mise à jour
  /// complète le paramétrage sans toucher à ce que le comptable a modifié.
  static void completerReferentiels(Base base) {
    if (base.entier('SELECT COUNT(*) FROM entites') == 0) return;
    base.transaction(() {
      final avant = base.entier('SELECT total_changes()');
      void comptes(String ent, List<CompteDefaut> liste) {
        final ref = base.valeur('SELECT referentiel FROM entites WHERE code=?', [ent]);
        for (final c in liste) {
          base.exec('INSERT OR IGNORE INTO comptes(entite, numero, libelle, origine) VALUES (?,?,?,?)', [ent, c.numero, c.libelle, ref]);
        }
      }

      comptes('CS', comptesCS);
      comptes('ONG', comptesONG);
      for (final ent in ['CS', 'ONG']) {
        for (final j in journauxDefaut) {
          base.exec('INSERT OR IGNORE INTO journaux(entite, code, libelle, type) VALUES (?,?,?,?)', [ent, j[0], j[1], j[2]]);
        }
        for (final sc in ent == 'CS' ? schemasCS : schemasONG) {
          base.exec(
              'INSERT OR IGNORE INTO schemas_ecritures(entite, type_ecriture, ordre, sens, compte, montant, repetition, journal, libelle) '
              'VALUES (?,?,?,?,?,?,?,?,?)',
              [ent, ...sc]);
        }
      }
      rolesDefaut.forEach((code, lib) => base.exec('INSERT OR IGNORE INTO roles(code, libelle) VALUES (?,?)', [code, lib]));
      droitsDefaut().forEach((role, modules) => modules.forEach((module, actions) {
            for (final a in actions) {
              base.exec('INSERT OR IGNORE INTO droits(role, module, action) VALUES (?,?,?)', [role, module, a]);
            }
          }));
      parametresDefaut.forEach((k, v) => base.exec('INSERT OR IGNORE INTO parametres(cle, valeur) VALUES (?,?)', [k, v]));
      for (final r in rubriquesPaieDefaut) {
        base.exec(
            "INSERT OR IGNORE INTO rubriques_paie(code, depuis, libelle, nature, organisme, taux, plafond) VALUES (?,'2000-01-01',?,?,?,?,?)", r);
      }
      for (final c in categoriesImmobilisationsDefaut) {
        base.exec(
            'INSERT OR IGNORE INTO categories_immobilisations(code, libelle, compte_immobilisation, compte_amortissement, duree_mois) VALUES (?,?,?,?,?)',
            c);
      }
      if (base.entier('SELECT total_changes()') != avant && base.valeur('SELECT 1 FROM parametres WHERE cle=?', ['version_parametrage']) != null) {
        _versionSuivante(base);
      }
    });
  }

  static bool estCentral(Base base) =>
      base.valeur('SELECT central FROM appareils WHERE code=?', [base.appareil]) == 1;

  static void _exigerCentral(Base base) {
    if (!estCentral(base)) {
      throw const RegleMetier('Le paramétrage se modifie uniquement sur le PC central.');
    }
  }

  static void _versionSuivante(Base base) =>
      base.definirParam('version_parametrage', '${base.paramInt('version_parametrage', 0) + 1}');

  static String _insererUtilisateur(
      Base base, String identifiant, String nom, String role, String mdp, String? activite, String? code) {
    if (mdp.length < 6) throw const RegleMetier('Le mot de passe doit contenir au moins 6 caractères.');
    final id = base.nouvelUuid();
    final sel = Securite.nouveauSel();
    String? selCode, empCode;
    if (code != null) {
      if (code.length < 4) throw const RegleMetier('Le code doit contenir au moins 4 chiffres.');
      selCode = Securite.nouveauSel();
      empCode = Securite.hacher(code, selCode);
    }
    base.exec(
        'INSERT INTO utilisateurs(id, identifiant, nom, role, activite, sel, empreinte, sel_code, empreinte_code) VALUES (?,?,?,?,?,?,?,?,?)',
        [id, identifiant, nom, role, activite, sel, Securite.hacher(mdp, sel), selCode, empCode]);
    return id;
  }

  /// Crée un utilisateur (identifiant personnel, aucun compte partagé).
  static String ajouterUtilisateur(Session s,
      {required String identifiant,
      required String nom,
      required String role,
      required String motDePasse,
      String? activite,
      String? code}) {
    final base = s.base;
    return base.transaction(() {
      _exigerCentral(base);
      s.exiger('utilisateurs', 'creer');
      if (base.valeur('SELECT 1 FROM utilisateurs WHERE identifiant=?', [identifiant]) != null) {
        throw RegleMetier('L’identifiant « $identifiant » existe déjà.');
      }
      final id = _insererUtilisateur(base, identifiant, nom, role, motDePasse, activite, code);
      _versionSuivante(base);
      Audit.tracer(base,
          utilisateur: s.utilisateur,
          action: 'creation',
          objet: 'utilisateur:$identifiant',
          nouveau: {'nom': nom, 'role': role, 'activite': activite});
      return id;
    });
  }

  /// Enregistre et autorise un appareil. Crée ses caisses mobiles (une par
  /// entité) et renvoie la clé de synchronisation à saisir sur l'appareil.
  static String ajouterAppareil(Session s,
      {required String code, required String nom, required String type, String? utilisateurPrincipal}) {
    final base = s.base;
    return base.transaction(() {
      _exigerCentral(base);
      s.exiger('appareils', 'creer');
      if (!RegExp(r'^[A-Z][A-Z0-9]{1,5}$').hasMatch(code)) {
        throw const RegleMetier('Code appareil invalide (exemples : PC2, T01).');
      }
      if (base.valeur('SELECT 1 FROM appareils WHERE code=?', [code]) != null) {
        throw RegleMetier("L'appareil $code existe déjà.");
      }
      final cle = _cleAleatoire();
      base.exec('INSERT INTO appareils(code, nom, type, utilisateur_principal, cle_sync) VALUES (?,?,?,?,?)',
          [code, nom, type, utilisateurPrincipal, cle]);
      final rang = base.entier("SELECT COUNT(*) FROM appareils WHERE central=0");
      for (final ent in ['CS', 'ONG']) {
        final compte = '5712${rang.toString().padLeft(2, '0')}';
        final journal = 'C$code';
        base.exec('INSERT INTO comptes(entite, numero, libelle, origine) VALUES (?,?,?,?)',
            [ent, compte, 'Caisse mobile $code', ent == 'CS' ? 'SYSCOHADA' : 'SYCEBNL']);
        base.exec("INSERT INTO journaux(entite, code, libelle, type) VALUES (?,?,?,'caisse')",
            [ent, journal, 'Caisse mobile $code']);
        base.exec(
            "INSERT INTO tresoreries(id, entite, type, libelle, compte, journal, appareil) VALUES (?,?,'caisse',?,?,?,?)",
            ['$ent-CAISSE-$code', ent, 'Caisse mobile $code', compte, journal, code]);
      }
      _versionSuivante(base);
      Audit.tracer(base, utilisateur: s.utilisateur, action: 'creation', objet: 'appareil:$code', nouveau: {'nom': nom, 'type': type});
      return cle;
    });
  }

  /// Révoque un appareil perdu : il est bloqué à sa prochaine connexion,
  /// puis ses données locales sont effacées.
  static void revoquerAppareil(Session s, String code, String motif) {
    final base = s.base;
    base.transaction(() {
      _exigerCentral(base);
      s.exiger('appareils', 'valider');
      if (code == base.appareil) throw const RegleMetier('Le PC central ne peut pas être révoqué.');
      final avant = base.valeur('SELECT statut FROM appareils WHERE code=?', [code]);
      if (avant == null) throw RegleMetier('Appareil inconnu : $code');
      base.exec("UPDATE appareils SET statut='revoque' WHERE code=?", [code]);
      _versionSuivante(base);
      Audit.tracer(base,
          utilisateur: s.utilisateur, action: 'modification', objet: 'appareil:$code', ancien: avant, nouveau: 'revoque ($motif)');
    });
  }

  /// Déclare un appareil inactif (ne bloque plus les clôtures) ou le réactive.
  static void changerStatutAppareil(Session s, String code, String statut) {
    final base = s.base;
    base.transaction(() {
      _exigerCentral(base);
      s.exiger('appareils', 'valider');
      final avant = base.valeur('SELECT statut FROM appareils WHERE code=?', [code]);
      if (avant == 'revoque') throw const RegleMetier('Un appareil révoqué ne peut pas être réactivé.');
      base.exec('UPDATE appareils SET statut=? WHERE code=?', [statut, code]);
      _versionSuivante(base);
      Audit.tracer(base, utilisateur: s.utilisateur, action: 'modification', objet: 'appareil:$code', ancien: avant, nouveau: statut);
    });
  }

  /// Charte des documents : identité de l'entité (en-tête commune).
  static void modifierEntite(Session s, String code,
      {required String nom, required String sigle, required String adresse, required String contacts, required String numeros}) {
    final base = s.base;
    base.transaction(() {
      _exigerCentral(base);
      s.exiger('parametrage', 'creer');
      final avant = base.ligne('SELECT * FROM entites WHERE code=?', [code]);
      base.exec('UPDATE entites SET nom=?, sigle=?, adresse=?, contacts=?, numeros_administratifs=? WHERE code=?',
          [nom, sigle, adresse, contacts, numeros, code]);
      _versionSuivante(base);
      Audit.tracer(base, utilisateur: s.utilisateur, action: 'modification', objet: 'entite:$code', ancien: avant,
          nouveau: {'nom': nom, 'sigle': sigle, 'adresse': adresse, 'contacts': contacts, 'numeros': numeros});
    });
  }

  /// Modifie un seuil ou un délai.
  static void modifierParametre(Session s, String cle, String valeur) {
    final base = s.base;
    base.transaction(() {
      _exigerCentral(base);
      s.exiger('parametrage', 'creer');
      final avant = base.param(cle, '');
      base.definirParam(cle, valeur);
      _versionSuivante(base);
      Audit.tracer(base, utilisateur: s.utilisateur, action: 'modification', objet: 'parametre:$cle', ancien: avant, nouveau: valeur);
    });
  }

  /// Nouveau tarif à partir d'une date : le passé n'est jamais modifié.
  static void definirTarif(Session s, String codeActe, int prix, {String? depuis}) {
    final base = s.base;
    base.transaction(() {
      _exigerCentral(base);
      s.exiger('parametrage', 'creer');
      final d = depuis ?? dateIso(base.maintenant);
      if (d.compareTo(dateIso(base.maintenant)) < 0) {
        throw const RegleMetier("Un tarif ne peut pas prendre effet dans le passé.");
      }
      final avant = tarif(base, codeActe, d);
      base.exec(
          'INSERT INTO tarifs(code_acte, depuis, prix) VALUES (?,?,?) ON CONFLICT(code_acte, depuis) DO UPDATE SET prix=excluded.prix',
          [codeActe, d, prix]);
      _versionSuivante(base);
      Audit.tracer(base, utilisateur: s.utilisateur, action: 'modification', objet: 'tarif:$codeActe', ancien: avant, nouveau: '$prix depuis $d');
    });
  }

  /// Tarif en vigueur à une date donnée.
  static int tarif(Base base, String codeActe, String date) {
    final p = base.valeur(
        'SELECT prix FROM tarifs WHERE code_acte=? AND depuis<=? ORDER BY depuis DESC LIMIT 1', [codeActe, date]);
    if (p == null) throw RegleMetier("Aucun tarif en vigueur pour l'acte $codeActe.");
    return p as int;
  }

  /// Valide un compte du plan comptable (livré « à valider »).
  static void validerCompte(Session s, String entite, String numero) {
    final base = s.base;
    base.transaction(() {
      _exigerCentral(base);
      s.exiger('comptabilite', 'valider');
      base.exec('UPDATE comptes SET a_valider=0 WHERE entite=? AND numero=?', [entite, numero]);
      _versionSuivante(base);
      Audit.tracer(base, utilisateur: s.utilisateur, action: 'validation', objet: 'compte:$entite:$numero');
    });
  }


  // ======================================================================
  // Modifications du paramétrage par le comptable (ou l'administrateur).
  // « Retirer » supprime ce qui n'a jamais servi ; ce qui a déjà servi est
  // désactivé (l'historique et la comptabilité restent intacts).
  // ======================================================================

  static T modifier<T>(Session s, String module, String objet, T Function() action, {Object? ancien, Object? nouveau}) {
    final base = s.base;
    return base.transaction(() {
      _exigerCentral(base);
      s.exiger(module, 'creer');
      final r = action();
      _versionSuivante(base);
      Audit.tracer(base, utilisateur: s.utilisateur, action: 'modification', objet: objet, ancien: ancien, nouveau: nouveau);
      return r;
    });
  }

  static void _texte(String v, String quoi) {
    if (v.trim().isEmpty) throw RegleMetier('$quoi est obligatoire.');
  }

  /// Contrôle qu'une image est bien un PNG ou un JPEG de taille raisonnable.
  static void verifierImage(Uint8List o) {
    final png = o.length > 8 && o[0] == 0x89 && o[1] == 0x50 && o[2] == 0x4E && o[3] == 0x47;
    final jpg = o.length > 3 && o[0] == 0xFF && o[1] == 0xD8;
    if (!png && !jpg) throw const RegleMetier('Image non reconnue : utilisez un fichier PNG ou JPEG.');
    if (o.length > 2 * 1024 * 1024) throw const RegleMetier('Image trop lourde (2 Mo maximum).');
  }

  /// Logo de l'entité (null pour le retirer). Utilisé dans l'entête et en filigrane.
  static void definirLogo(Session s, String entite, Uint8List? image) => modifier(s, 'parametrage', 'logo:$entite', () {
        if (image != null) verifierImage(image);
        s.base.exec('UPDATE entites SET logo=? WHERE code=?', [image, entite]);
      }, nouveau: image == null ? 'retiré' : '${image.length} octets');

  /// Entête complète importée (image d'un papier à en-tête). Elle remplace
  /// l'entête générée sur tous les documents A4. null pour la retirer.
  static void definirEntete(Session s, String entite, Uint8List? image) => modifier(s, 'parametrage', 'entete:$entite', () {
        if (image != null) verifierImage(image);
        s.base.exec('UPDATE entites SET entete=? WHERE code=?', [image, entite]);
      }, nouveau: image == null ? 'retirée' : '${image.length} octets');

  static void definirFiligrane(Session s, String entite, bool actif) => modifier(s, 'parametrage', 'filigrane:$entite',
      () => s.base.exec('UPDATE entites SET filigrane=? WHERE code=?', [actif ? 1 : 0, entite]), nouveau: actif);

  // ------------------------------------------------------------ services
  static void ajouterActivite(Session s,
          {required String code, required String libelle, required String entite, bool service = true, String typeReleve = 'actes'}) =>
      modifier(s, 'parametrage', 'activite:$code', () {
        final c = code.trim().toUpperCase();
        if (!RegExp(r'^[A-Z][A-Z0-9_]{1,11}$').hasMatch(c)) throw const RegleMetier('Code de service invalide (ex. ECHO, DENT).');
        _texte(libelle, 'Le libellé');
        if (s.base.valeur('SELECT 1 FROM activites WHERE code=?', [c]) != null) throw RegleMetier('Le service $c existe déjà.');
        s.base.exec('INSERT INTO activites(code, libelle, entite, service, type_releve) VALUES (?,?,?,?,?)',
            [c, libelle.trim(), entite, service ? 1 : 0, typeReleve]);
      }, nouveau: {'libelle': libelle, 'entite': entite});

  static void modifierActivite(Session s, String code, {required String libelle}) => modifier(s, 'parametrage', 'activite:$code', () {
        _texte(libelle, 'Le libellé');
        s.base.exec('UPDATE activites SET libelle=? WHERE code=?', [libelle.trim(), code]);
      }, nouveau: libelle);

  static String retirerActivite(Session s, String code) => modifier(s, 'parametrage', 'activite:$code', () {
        final b = s.base;
        final utilise = b.valeur('SELECT 1 FROM actes WHERE activite=? LIMIT 1', [code]) != null ||
            b.valeur('SELECT 1 FROM lignes_ecriture WHERE activite=? LIMIT 1', [code]) != null ||
            b.valeur('SELECT 1 FROM actes_catalogue WHERE activite=? LIMIT 1', [code]) != null;
        if (utilise) {
          b.exec('UPDATE activites SET actif=0 WHERE code=?', [code]);
          b.exec('UPDATE actes_catalogue SET actif=0 WHERE activite=?', [code]);
          return 'désactivé';
        }
        b.exec('DELETE FROM activites WHERE code=?', [code]);
        return 'supprimé';
      }, nouveau: 'retiré');

  static void reactiverActivite(Session s, String code) =>
      modifier(s, 'parametrage', 'activite:$code', () => s.base.exec('UPDATE activites SET actif=1 WHERE code=?', [code]), nouveau: 'réactivé');

  // ------------------------------------------------------------ actes et prix
  static void ajouterActe(Session s,
          {required String code, required String libelle, required String activite, required String compteProduit, required int prix}) =>
      modifier(s, 'parametrage', 'acte:$code', () {
        final b = s.base;
        final c = code.trim().toUpperCase();
        if (!RegExp(r'^[A-Z0-9][A-Z0-9_-]{1,19}$').hasMatch(c)) throw const RegleMetier("Code d'acte invalide (ex. LAB-HB).");
        _texte(libelle, 'Le libellé');
        if (prix < 0) throw const RegleMetier('Le prix ne peut pas être négatif.');
        if (b.valeur('SELECT 1 FROM actes_catalogue WHERE code=?', [c]) != null) throw RegleMetier("L'acte $c existe déjà.");
        final ent = b.valeur('SELECT entite FROM activites WHERE code=?', [activite]) ?? (throw const RegleMetier('Service inconnu.'));
        if (b.valeur('SELECT 1 FROM comptes WHERE entite=? AND numero=? AND actif=1', [ent, compteProduit]) == null) {
          throw RegleMetier("Le compte $compteProduit n'existe pas dans le plan comptable.");
        }
        b.exec('INSERT INTO actes_catalogue(code, libelle, activite, compte_produit) VALUES (?,?,?,?)', [c, libelle.trim(), activite, compteProduit]);
        b.exec('INSERT INTO tarifs(code_acte, depuis, prix) VALUES (?,?,?)', [c, '2000-01-01', prix]);
      }, nouveau: {'libelle': libelle, 'activite': activite, 'compte': compteProduit, 'prix': prix});

  static void modifierActe(Session s, String code, {required String libelle, required String compteProduit}) =>
      modifier(s, 'parametrage', 'acte:$code', () {
        _texte(libelle, 'Le libellé');
        s.base.exec('UPDATE actes_catalogue SET libelle=?, compte_produit=? WHERE code=?', [libelle.trim(), compteProduit, code]);
      }, nouveau: {'libelle': libelle, 'compte': compteProduit});

  static String retirerActe(Session s, String code) => modifier(s, 'parametrage', 'acte:$code', () {
        final b = s.base;
        if (b.valeur('SELECT 1 FROM actes WHERE code_acte=? LIMIT 1', [code]) != null) {
          b.exec('UPDATE actes_catalogue SET actif=0 WHERE code=?', [code]);
          return 'désactivé';
        }
        b.exec('DELETE FROM tarifs WHERE code_acte=?', [code]);
        b.exec('DELETE FROM actes_catalogue WHERE code=?', [code]);
        return 'supprimé';
      }, nouveau: 'retiré');

  static void reactiverActe(Session s, String code) =>
      modifier(s, 'parametrage', 'acte:$code', () => s.base.exec('UPDATE actes_catalogue SET actif=1 WHERE code=?', [code]), nouveau: 'réactivé');

  // ------------------------------------------------------------ programmes de désintoxication
  static void enregistrerProgramme(Session s,
          {required String code,
          required String libelle,
          required String type,
          required int duree,
          required String modeCalcul,
          required int montant,
          String phases = ''}) =>
      modifier(s, 'parametrage', 'programme:$code', () {
        final c = code.trim().toUpperCase();
        if (!RegExp(r'^[A-Z0-9][A-Z0-9_-]{1,11}$').hasMatch(c)) throw const RegleMetier('Code de programme invalide (ex. RES-60).');
        _texte(libelle, 'Le libellé');
        if (!['ambulatoire', 'residentiel'].contains(type)) throw const RegleMetier('Type : ambulatoire ou residentiel.');
        if (!['forfait', 'journalier'].contains(modeCalcul)) throw const RegleMetier('Calcul : forfait ou journalier.');
        if (duree <= 0 || montant <= 0) throw const RegleMetier('Durée et montant doivent être positifs.');
        s.base.exec(
            'INSERT INTO programmes_desintox(code, libelle, type, duree_jours, phases, mode_calcul, montant) VALUES (?,?,?,?,?,?,?) '
            'ON CONFLICT(code) DO UPDATE SET libelle=excluded.libelle, type=excluded.type, duree_jours=excluded.duree_jours, '
            'phases=excluded.phases, mode_calcul=excluded.mode_calcul, montant=excluded.montant, actif=1',
            [c, libelle.trim(), type, duree, phases, modeCalcul, montant]);
      }, nouveau: {'libelle': libelle, 'type': type, 'duree': duree, 'calcul': modeCalcul, 'montant': montant});

  static String retirerProgramme(Session s, String code) => modifier(s, 'parametrage', 'programme:$code', () {
        final b = s.base;
        if (b.valeur('SELECT 1 FROM desintox_dossiers WHERE programme=? LIMIT 1', [code]) != null) {
          b.exec('UPDATE programmes_desintox SET actif=0 WHERE code=?', [code]);
          return 'désactivé';
        }
        b.exec('DELETE FROM programmes_desintox WHERE code=?', [code]);
        return 'supprimé';
      }, nouveau: 'retiré');

  // ------------------------------------------------------------ plan comptable
  static void ajouterCompte(Session s, {required String entite, required String numero, required String libelle}) =>
      modifier(s, 'comptabilite', 'compte:$entite:$numero', () {
        final b = s.base;
        if (!RegExp(r'^[1-9][0-9]{1,9}$').hasMatch(numero)) throw const RegleMetier('Numéro de compte invalide (chiffres uniquement).');
        _texte(libelle, 'Le libellé');
        if (b.valeur('SELECT 1 FROM comptes WHERE entite=? AND numero=?', [entite, numero]) != null) {
          throw RegleMetier('Le compte $numero existe déjà.');
        }
        final ref = b.valeur('SELECT referentiel FROM entites WHERE code=?', [entite]);
        b.exec('INSERT INTO comptes(entite, numero, libelle, origine, a_valider) VALUES (?,?,?,?,0)', [entite, numero, libelle.trim(), ref]);
      }, nouveau: libelle);

  static void modifierCompte(Session s, {required String entite, required String numero, required String libelle}) =>
      modifier(s, 'comptabilite', 'compte:$entite:$numero', () {
        _texte(libelle, 'Le libellé');
        s.base.exec('UPDATE comptes SET libelle=? WHERE entite=? AND numero=?', [libelle.trim(), entite, numero]);
      }, nouveau: libelle);

  static String retirerCompte(Session s, {required String entite, required String numero}) =>
      modifier(s, 'comptabilite', 'compte:$entite:$numero', () {
        final b = s.base;
        if (b.valeur("SELECT 1 FROM schemas_ecritures WHERE entite=? AND compte=?", [entite, numero]) != null ||
            b.valeur('SELECT 1 FROM tresoreries WHERE entite=? AND compte=? AND actif=1', [entite, numero]) != null ||
            b.valeur('SELECT 1 FROM actes_catalogue c JOIN activites a ON a.code=c.activite WHERE a.entite=? AND c.compte_produit=? AND c.actif=1',
                    [entite, numero]) !=
                null) {
          throw RegleMetier('Le compte $numero est utilisé par le paramétrage (schéma, trésorerie ou acte) : modifiez d’abord ce paramétrage.');
        }
        final mouvemente = b.valeur(
                'SELECT 1 FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture WHERE e.entite=? AND l.compte=? LIMIT 1', [entite, numero]) !=
            null;
        if (mouvemente) {
          b.exec('UPDATE comptes SET actif=0 WHERE entite=? AND numero=?', [entite, numero]);
          return 'désactivé';
        }
        b.exec('DELETE FROM comptes WHERE entite=? AND numero=?', [entite, numero]);
        return 'supprimé';
      }, nouveau: 'retiré');

  static void reactiverCompte(Session s, {required String entite, required String numero}) => modifier(
      s, 'comptabilite', 'compte:$entite:$numero', () => s.base.exec('UPDATE comptes SET actif=1 WHERE entite=? AND numero=?', [entite, numero]),
      nouveau: 'réactivé');

  /// Change le compte (ou la variable) d'une ligne de schéma d'écriture.
  static void modifierSchema(Session s, {required String entite, required String type, required int ordre, required String compte}) =>
      modifier(s, 'comptabilite', 'schema:$entite:$type:$ordre', () {
        final b = s.base;
        if (!compte.contains('{') && b.valeur('SELECT 1 FROM comptes WHERE entite=? AND numero=? AND actif=1', [entite, compte]) == null) {
          throw RegleMetier("Le compte $compte n'existe pas dans le plan comptable.");
        }
        b.exec('UPDATE schemas_ecritures SET compte=? WHERE entite=? AND type_ecriture=? AND ordre=?', [compte, entite, type, ordre]);
      }, nouveau: compte);

  // ------------------------------------------------------------ comptes de trésorerie
  static String ajouterTresorerie(Session s,
          {required String entite, required String type, required String libelle, required String compte, String? operateur}) =>
      modifier(s, 'parametrage', 'tresorerie:$entite:$libelle', () {
        final b = s.base;
        if (!['caisse', 'banque', 'momo'].contains(type)) throw const RegleMetier('Type : caisse, banque ou momo.');
        _texte(libelle, 'Le libellé');
        if (b.valeur('SELECT 1 FROM comptes WHERE entite=? AND numero=?', [entite, compte]) == null) {
          final ref = b.valeur('SELECT referentiel FROM entites WHERE code=?', [entite]);
          b.exec('INSERT INTO comptes(entite, numero, libelle, origine, a_valider) VALUES (?,?,?,?,0)', [entite, compte, libelle.trim(), ref]);
        }
        final n = b.entier('SELECT COUNT(*) FROM tresoreries WHERE entite=?', [entite]) + 1;
        final journal = '${type == 'banque' ? 'BQ' : type == 'momo' ? 'MM' : 'CA'}$n';
        b.exec("INSERT OR IGNORE INTO journaux(entite, code, libelle, type) VALUES (?,?,?,?)", [entite, journal, libelle.trim(), type]);
        final id = '$entite-${type.toUpperCase()}-$n';
        b.exec('INSERT INTO tresoreries(id, entite, type, libelle, compte, journal, operateur) VALUES (?,?,?,?,?,?,?)',
            [id, entite, type, libelle.trim(), compte, journal, operateur]);
        return id;
      }, nouveau: {'type': type, 'libelle': libelle, 'compte': compte});

  static String retirerTresorerie(Session s, String id) => modifier(s, 'parametrage', 'tresorerie:$id', () {
        final b = s.base;
        final solde = b.entier('SELECT COALESCE(SUM(montant),0) FROM mouvements_tresorerie WHERE tresorerie=?', [id]);
        if (solde != 0) throw const RegleMetier('Le solde doit être nul : videz d’abord ce compte par un mouvement interne.');
        if (b.valeur('SELECT 1 FROM mouvements_tresorerie WHERE tresorerie=? LIMIT 1', [id]) != null) {
          b.exec('UPDATE tresoreries SET actif=0 WHERE id=?', [id]);
          return 'désactivé';
        }
        b.exec('DELETE FROM tresoreries WHERE id=?', [id]);
        return 'supprimé';
      }, nouveau: 'retiré');

  // ------------------------------------------------------------ utilisateurs
  static void desactiverUtilisateur(Session s, String id, {bool actif = false}) {
    final base = s.base;
    base.transaction(() {
      _exigerCentral(base);
      s.exiger('utilisateurs', 'creer');
      if (id == s.utilisateur) throw const RegleMetier('Vous ne pouvez pas désactiver votre propre compte.');
      base.exec('UPDATE utilisateurs SET actif=? WHERE id=?', [actif ? 1 : 0, id]);
      _versionSuivante(base);
      Audit.tracer(base, utilisateur: s.utilisateur, action: 'modification', objet: 'utilisateur:$id', nouveau: actif ? 'réactivé' : 'désactivé');
    });
  }

  /// Instantané du paramétrage, diffusé à un appareil. Les clés de
  /// synchronisation des AUTRES appareils ne sont jamais transmises.
  static Map<String, Object?> exporter(Base base, {required String pourAppareil}) {
    final tables = <String, Object?>{};
    for (final t in tablesDiffusees) {
      var lignes = base.lignes('SELECT * FROM $t');
      if (t == 'appareils') {
        lignes = [
          for (final l in lignes) {...l, 'cle_sync': l['code'] == pourAppareil ? l['cle_sync'] : ''}
        ];
      }
      tables[t] = [
        for (final l in lignes) {for (final e in l.entries) e.key: e.value is Uint8List ? {'\$b64': base64Encode(e.value as Uint8List)} : e.value}
      ];
    }
    return {'version': base.paramInt('version_parametrage'), 'tables': tables};
  }

  /// Remplace le paramétrage local par celui du PC central.
  static void importer(Base base, Map<String, Object?> instantane) {
    final tables = Map<String, Object?>.from(instantane['tables'] as Map);
    base.transaction(() {
      base.exec('PRAGMA defer_foreign_keys = ON');
      for (final t in tablesDiffusees.reversed) {
        base.exec('DELETE FROM $t');
      }
      for (final t in tablesDiffusees) {
        for (final l in (tables[t] as List).cast<Map>()) {
          final cols = l.keys.cast<String>().toList();
          base.exec('INSERT INTO $t(${cols.join(',')}) VALUES (${List.filled(cols.length, '?').join(',')})',
              [for (final c in cols) l[c] is Map ? base64Decode((l[c] as Map)['\$b64'] as String) : l[c]]);
        }
      }
    });
  }
}
