/// Paramétrage : installation, utilisateurs, appareils, tarifs, seuils.
///
/// Le PC central fait autorité : le paramétrage ne se modifie que sur lui,
/// puis il est diffusé à tous les appareils à chaque synchronisation.
library;

import 'dart:convert';
import 'dart:math';

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
            ['$ent-BQ', ent, 'Banque – compte courant', '5211', 'BQ1']);
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
      base.exec("INSERT INTO appareils(code, nom, type, central, cle_sync) VALUES (?,?,'pc',1,?)",
          [base.appareil, nomAppareil, _cleAleatoire()]);
      _insererUtilisateur(base, identifiantAdmin, nomAdmin, 'admin', motDePasseAdmin, null, null);
      base.exec("INSERT INTO etat_sync(cle, valeur) VALUES ('installe_le', ?)", [base.maintenant.toIso8601String()]);
      Audit.tracer(base, utilisateur: 'installation', action: 'installation', objet: 'PC central ${base.appareil}');
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
      tables[t] = lignes;
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
              [for (final c in cols) l[c]]);
        }
      }
    });
  }
}
