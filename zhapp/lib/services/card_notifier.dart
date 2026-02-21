import 'package:flutter/foundation.dart';

/// Singleton notifier that fires when the card list changes.
/// Listeners (e.g., RepositoryPage) should reload their data when notified.
///
/// Usage:
///   CardNotifier().addListener(_reload);   // subscribe
///   CardNotifier().notifyCardsChanged();    // fire
class CardNotifier extends ChangeNotifier {
  static final CardNotifier _instance = CardNotifier._internal();

  factory CardNotifier() => _instance;

  CardNotifier._internal();

  /// Call after creating, updating, or deleting a card so that
  /// any listening view refreshes its list.
  void notifyCardsChanged() {
    notifyListeners();
  }
}
