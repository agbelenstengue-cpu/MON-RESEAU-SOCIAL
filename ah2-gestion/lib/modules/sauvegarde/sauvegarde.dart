/// Sauvegardes chiffrées de la base du PC central et restauration (§11).
///
/// Format du fichier .ah2s : en-tête « AH2S1 », sel (24 caractères base64),
/// puis la base SQLite chiffrée en AES-256-GCM avec une clé dérivée du mot
/// de passe de sauvegarde.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../noyau/audit.dart';
import '../../noyau/base.dart';
import '../../noyau/chiffrement.dart';
import '../../noyau/outils.dart';
import '../../noyau/securite.dart';
import '../../noyau/session.dart';

class Sauvegarde {
  static const _entete = 'AH2S1';

  /// Crée une sauvegarde chiffrée dans [dossier] (disque externe, clé USB).
  static String sauvegarder(Session s, {required String dossier, required String motDePasse}) {
    final base = s.base;
    s.exiger('sauvegardes', 'creer');
    if (motDePasse.length < 8) throw const RegleMetier('Mot de passe de sauvegarde : 8 caractères minimum.');
    final d = Directory(dossier);
    if (!d.existsSync()) throw RegleMetier('Dossier de sauvegarde introuvable : $dossier');
    final h = base.maintenant;
    final nom = 'AH2-${base.appareil}-${dateIso(h)}-${h.hour.toString().padLeft(2, '0')}${h.minute.toString().padLeft(2, '0')}${h.second.toString().padLeft(2, '0')}.ah2s';
    final temp = p.join(Directory.systemTemp.path, 'ah2-${base.nouvelUuid()}.db');
    final precedente = base.valeur("SELECT valeur FROM etat_sync WHERE cle='derniere_sauvegarde'") as String?;
    void marquer(String? valeur) => base.exec(
        "INSERT INTO etat_sync(cle, valeur) VALUES ('derniere_sauvegarde', ?) ON CONFLICT(cle) DO UPDATE SET valeur=excluded.valeur",
        [valeur ?? '']);
    // La trace est écrite AVANT la copie : la sauvegarde contient sa propre
    // trace, et une restauration redonne exactement la même base.
    base.transaction(() {
      marquer(h.toIso8601String());
      Audit.tracer(base, utilisateur: s.utilisateur, action: 'sauvegarde', objet: nom);
    });
    try {
      base.copierVers(temp);
      final clair = File(temp).readAsBytesSync();
      final sel = Securite.nouveauSel();
      final cle = Chiffrement.cleDepuisMotDePasse(motDePasse, sel);
      final chiffre = Chiffrement.chiffrer(cle, clair, associees: Uint8List.fromList(utf8.encode(_entete)));
      final cible = p.join(dossier, nom);
      File(cible).writeAsBytesSync([...utf8.encode(_entete), ...utf8.encode(sel), ...chiffre], flush: true);
      _purger(base, dossier);
      return cible;
    } catch (e) {
      base.transaction(() {
        marquer(precedente);
        Audit.tracer(base, utilisateur: s.utilisateur, action: 'sauvegarde_echec', objet: nom, nouveau: '$e');
      });
      rethrow;
    } finally {
      final f = File(temp);
      if (f.existsSync()) f.deleteSync();
    }
  }

  static void _purger(Base base, String dossier) {
    final jours = base.paramInt('sauvegarde_conservation_jours');
    final limite = base.maintenant.subtract(Duration(days: jours));
    for (final f in Directory(dossier).listSync().whereType<File>()) {
      if (f.path.endsWith('.ah2s') && f.lastModifiedSync().isBefore(limite)) f.deleteSync();
    }
  }

  /// Déchiffre une sauvegarde vers [cheminBase]. Vérifie l'intégrité SQLite.
  static void restaurer({required String fichier, required String motDePasse, required String cheminBase}) {
    final octets = File(fichier).readAsBytesSync();
    final entete = utf8.decode(octets.sublist(0, _entete.length));
    if (entete != _entete) throw const RegleMetier("Ce fichier n'est pas une sauvegarde AH2 Gestion.");
    final sel = utf8.decode(octets.sublist(_entete.length, _entete.length + 24));
    final cle = Chiffrement.cleDepuisMotDePasse(motDePasse, sel);
    Uint8List clair;
    try {
      clair = Chiffrement.dechiffrer(cle, Uint8List.fromList(octets.sublist(_entete.length + 24)),
          associees: Uint8List.fromList(utf8.encode(_entete)));
    } catch (_) {
      throw const RegleMetier('Mot de passe incorrect ou sauvegarde endommagée.');
    }
    final temp = '$cheminBase.restauration';
    File(temp).writeAsBytesSync(clair, flush: true);
    final b = Base.ouvrir(chemin: temp, appareil: 'RESTAURATION');
    try {
      final ok = b.valeur('PRAGMA integrity_check');
      if (ok != 'ok') throw const RegleMetier('La sauvegarde est corrompue.');
      if (Audit.verifier(b) != null) throw const RegleMetier("Le journal d'audit de la sauvegarde est altéré.");
    } finally {
      b.fermer();
    }
    for (final suffixe in ['', '-wal', '-shm']) {
      final f = File('$cheminBase$suffixe');
      if (f.existsSync()) f.deleteSync();
    }
    File(temp).renameSync(cheminBase);
    for (final suffixe in ['-wal', '-shm']) {
      final f = File('$temp$suffixe');
      if (f.existsSync()) f.deleteSync();
    }
  }

  /// Empreinte du contenu logique d'une base (toutes tables, toutes lignes) :
  /// sert à prouver qu'une restauration redonne une base identique.
  static String empreinteContenu(Base base) {
    final h = <String>[];
    for (final t in base.lignes("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")) {
      final nom = t['name'] as String;
      final lignes = base.lignes('SELECT * FROM "$nom" ORDER BY rowid');
      h.add('$nom:${jsonEncode(lignes)}');
    }
    return sha256.convert(utf8.encode(h.join('\n'))).toString();
  }
}
