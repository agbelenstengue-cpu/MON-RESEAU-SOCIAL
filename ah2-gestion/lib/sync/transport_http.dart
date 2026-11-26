/// Transport HTTP sur le réseau Wi-Fi local (aucun Internet).
///
/// Le PC central écoute sur un port local (8765 par défaut). Le contenu est
/// déjà chiffré par [Enveloppe] : HTTP ne sert que de canal sur le Wi-Fi.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'synchronisation.dart';

const portParDefaut = 8765;

class ServeurHttpSync {
  final ServeurSync service;
  HttpServer? _serveur;
  ServeurHttpSync(this.service);

  Future<int> demarrer({int port = portParDefaut}) async {
    final s = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _serveur = s;
    s.listen(_traiter);
    return s.port;
  }

  Future<void> _traiter(HttpRequest r) async {
    try {
      if (r.method == 'GET' && r.uri.path == '/ping') {
        r.response
          ..statusCode = 200
          ..write('AH2');
      } else if (r.method == 'POST' && r.uri.path == '/sync') {
        final corps = await utf8.decoder.bind(r).join();
        if (corps.length > 64 * 1024 * 1024) throw const FormatException('Requête trop volumineuse');
        final reponse = service.traiter(Map<String, Object?>.from(jsonDecode(corps) as Map));
        r.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(reponse));
      } else {
        r.response.statusCode = 404;
      }
    } catch (e) {
      r.response
        ..statusCode = 400
        ..write(jsonEncode({'erreur': 'requete_invalide'}));
    }
    await r.response.close();
  }

  Future<void> arreter() async => _serveur?.close(force: true);
}

/// Côté appareil : envoie l'enveloppe au PC central à [adresse] (ex. 192.168.1.10).
Transport transportHttp(String adresse, {int port = portParDefaut, Duration delai = const Duration(seconds: 30)}) {
  return (enveloppe) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.post(adresse, port, '/sync').timeout(delai);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(enveloppe));
      final rep = await req.close().timeout(delai);
      final corps = await utf8.decoder.bind(rep).join();
      return Map<String, Object?>.from(jsonDecode(corps) as Map);
    } finally {
      client.close(force: true);
    }
  };
}

/// Le PC central est-il joignable (appareil sur le Wi-Fi de la structure) ?
Future<bool> centralJoignable(String adresse, {int port = portParDefaut}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final req = await client.get(adresse, port, '/ping');
    final rep = await req.close().timeout(const Duration(seconds: 3));
    return rep.statusCode == 200;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}
