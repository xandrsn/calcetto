import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config.dart';
import '../providers/game_state_provider.dart';
import 'player_images.dart' show kGithubImageHeaders;

/// Default power-up card artwork, stored in the data repo and shared by everyone
/// (mirrors the player-image system).
///
/// Layout:
///   `images/cards/<typeId>.png`     — the image bytes (e.g. red_card.png)
///   `images/cards/manifest.json`    — `{ "cards": { "<typeId>": "<version>" } }`
const String _manifestPath = 'images/cards/manifest.json';

String _imagePath(String typeId) => 'images/cards/$typeId.png';

/// URL that returns the raw card image bytes via the GitHub Contents API.
String cardImageUrl(String typeId, String version) =>
    '$kGithubBaseUrl${_imagePath(typeId)}?ref=main&v=$version';

/// Re-export so callers only import this file for card images.
const Map<String, String> kCardImageHeaders = kGithubImageHeaders;

/// Maps card typeId → version for card types that have a hub image.
final cardImagesProvider = FutureProvider<Map<String, String>>((ref) async {
  final gh = ref.read(githubServiceProvider);
  final f = await gh.getJson(_manifestPath);
  if (f == null) return {};
  final cards =
      (f.data as Map<String, dynamic>)['cards'] as Map<String, dynamic>? ?? {};
  return cards.map((k, v) => MapEntry(k, v.toString()));
});
