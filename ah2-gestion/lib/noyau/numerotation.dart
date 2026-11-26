/// Numérotation automatique, continue et sans trou des pièces.
///
/// Une série par appareil, entité, type de pièce et exercice :
/// `REC-CS-T01-2026-000451`. Le numéro est attribué sur l'appareil, même hors
/// ligne, DANS la transaction de l'opération : si l'enregistrement échoue
/// (coupure, erreur), le compteur revient en arrière avec lui, donc aucun trou.
library;

import 'base.dart';

class Numerotation {
  /// Réserve le numéro suivant. Doit être appelé dans une transaction.
  static int suivant(Base base,
      {required String entite,
      required String typePiece,
      required int exercice,
      String? appareil}) {
    if (!base.enTransaction) {
      throw StateError('La numérotation doit se faire dans une transaction.');
    }
    final app = appareil ?? base.appareil;
    final dernier = base.valeur(
        'SELECT dernier FROM compteurs WHERE appareil=? AND entite=? AND type_piece=? AND exercice=?',
        [app, entite, typePiece, exercice]) as int?;
    if (dernier == null) {
      base.exec(
          'INSERT INTO compteurs(appareil, entite, type_piece, exercice, dernier) VALUES (?,?,?,?,1)',
          [app, entite, typePiece, exercice]);
      return 1;
    }
    base.exec(
        'UPDATE compteurs SET dernier = dernier + 1 WHERE appareil=? AND entite=? AND type_piece=? AND exercice=?',
        [app, entite, typePiece, exercice]);
    return dernier + 1;
  }

  /// Numéro de pièce standard : TYPE-ENTITE-APPAREIL-EXERCICE-NNNNNN.
  static String piece(Base base,
      {required String entite, required String typePiece, required int exercice}) {
    final n = suivant(base, entite: entite, typePiece: typePiece, exercice: exercice);
    return '$typePiece-$entite-${base.appareil}-$exercice-${n.toString().padLeft(6, '0')}';
  }

  /// Numéro de dossier patient : P-APPAREIL-EXERCICE-NNNNN (unique même hors ligne).
  static String dossier(Base base, {required String prefixe, required int exercice}) {
    final n = suivant(base, entite: '*', typePiece: prefixe, exercice: exercice);
    return '$prefixe-${base.appareil}-$exercice-${n.toString().padLeft(5, '0')}';
  }
}
