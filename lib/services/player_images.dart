import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import '../config.dart';
import '../providers/game_state_provider.dart';

/// Global custom player images, stored in the data repo and shared by everyone.
///
/// Layout:
///   `images/players/<id>.jpg`       — the image bytes
///   `images/players/manifest.json`  — `{ "players": { "<id>": "<version>" } }`
///
/// The manifest's version (upload timestamp) is appended to the image URL so
/// updating an image busts Flutter's in-memory image cache without needing a
/// disk cache plugin (which is fragile on Windows desktop).
const String _manifestPath = 'images/players/manifest.json';

String _imagePath(String id) => 'images/players/$id.jpg';

/// URL that returns the raw image bytes via the GitHub Contents API.
String playerImageUrl(String playerId, String version) =>
    '$kGithubBaseUrl${_imagePath(playerId)}?ref=main&v=$version';

/// Headers required to fetch raw bytes from the Contents API (works for
/// private repos, unlike raw.githubusercontent).
const Map<String, String> kGithubImageHeaders = {
  'Authorization': 'Bearer $kGithubToken',
  'Accept': 'application/vnd.github.raw',
};

final playerImageServiceProvider = Provider<PlayerImageService>(
  (ref) => PlayerImageService(ref.read(githubServiceProvider)),
);

/// Maps playerId → version for players that currently have a custom image.
final playerImagesProvider = FutureProvider<Map<String, String>>(
  (ref) => ref.read(playerImageServiceProvider).loadManifest(),
);

class PlayerImageService {
  final DataStore gh;
  PlayerImageService(this.gh);

  Future<Map<String, String>> loadManifest() async {
    final f = await gh.getJson(_manifestPath);
    if (f == null) return {};
    final players =
        (f.data as Map<String, dynamic>)['players'] as Map<String, dynamic>? ??
        {};
    return players.map((k, v) => MapEntry(k, v.toString()));
  }

  /// Compresses [raw] and stores it as this player's global image.
  Future<void> upload(String playerId, Uint8List raw) async {
    final processed = _compress(raw);
    if (gh.isLocal) {
      // On-device store: keep the (small) JPEG inline as a data URI.
      await _setManifest(
        playerId,
        'data:image/jpeg;base64,${base64.encode(processed)}',
      );
      return;
    }
    final sha = await gh.getSha(_imagePath(playerId));
    await gh.putFileBytes(
      _imagePath(playerId),
      processed,
      sha,
      'admin: set image $playerId',
    );
    await _setManifest(playerId, DateTime.now().toIso8601String());
  }

  /// Uses an external image URL (http/https only) as this player's photo.
  Future<void> setUrl(String playerId, String url) async {
    final u = Uri.tryParse(url.trim());
    if (u == null || !(u.scheme == 'http' || u.scheme == 'https') || u.host.isEmpty) {
      throw const FormatException('Invalid image URL');
    }
    await _setManifest(playerId, u.toString());
  }

  Future<void> remove(String playerId) async {
    final sha = gh.isLocal ? null : await gh.getSha(_imagePath(playerId));
    if (sha != null) {
      await gh.deleteFile(
        _imagePath(playerId),
        sha,
        'admin: remove image $playerId',
      );
    }
    await _setManifest(playerId, null);
  }

  Future<void> _setManifest(String id, String? version) async {
    // Conflict-safe per-key merge so concurrent image uploads don't drop each
    // other's manifest entries.
    await gh.mutateJson(
      _manifestPath,
      message: 'admin: image manifest',
      transform: (current) {
        final players = <String, String>{};
        final p =
            (current is Map ? current['players'] : null)
                as Map<String, dynamic>? ??
            {};
        p.forEach((k, v) => players[k] = v.toString());
        if (version == null) {
          players.remove(id);
        } else {
          players[id] = version;
        }
        return {'players': players};
      },
    );
  }

  /// Downscales to max 256px on the long edge and re-encodes as JPEG q85 so
  /// stored images stay small. Returns the original bytes if decoding fails.
  Uint8List _compress(Uint8List raw) {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return raw;
    final needsResize = decoded.width > 256 || decoded.height > 256;
    final out = needsResize
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? 256 : null,
            height: decoded.height > decoded.width ? 256 : null,
          )
        : decoded;
    return Uint8List.fromList(img.encodeJpg(out, quality: 85));
  }
}
