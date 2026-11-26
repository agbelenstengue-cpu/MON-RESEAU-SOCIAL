/// Chiffrement AES-256-GCM (authentifié) : synchronisation et sauvegardes.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'securite.dart';

class Chiffrement {
  static final _rng = Random.secure();

  static Uint8List aleatoire(int n) => Uint8List.fromList(List<int>.generate(n, (_) => _rng.nextInt(256)));

  /// Chiffre [donnees] : renvoie nonce (12 octets) + texte chiffré + étiquette.
  /// [associees] est authentifié sans être chiffré (code appareil, horodatage).
  static Uint8List chiffrer(Uint8List cle, Uint8List donnees, {Uint8List? associees}) {
    final nonce = aleatoire(12);
    final c = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(cle), 128, nonce, associees ?? Uint8List(0)));
    return Uint8List.fromList([...nonce, ...c.process(donnees)]);
  }

  /// Déchiffre ; lève une exception si la clé est fausse ou les données altérées.
  static Uint8List dechiffrer(Uint8List cle, Uint8List paquet, {Uint8List? associees}) {
    if (paquet.length < 28) throw const FormatException('Paquet chiffré invalide.');
    final c = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(cle), 128, paquet.sublist(0, 12), associees ?? Uint8List(0)));
    return c.process(paquet.sublist(12));
  }

  /// Clé dérivée d'un mot de passe (sauvegardes).
  static Uint8List cleDepuisMotDePasse(String motDePasse, String selBase64) =>
      base64Decode(Securite.hacher(motDePasse, selBase64));
}
