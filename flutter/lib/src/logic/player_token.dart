import 'dart:convert';

/// Who a player token says it is. Read on the device to key local state; only the server's
/// verification counts, so nothing here is a security check.
class PlayerTokenClaims {
  const PlayerTokenClaims({required this.playerId, required this.workspaceId});

  final String playerId;
  final String workspaceId;

  /// `sub` and `wid` of a JWT's payload, unverified. Null when they can't be read.
  static PlayerTokenClaims? tryRead(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final claims = jsonDecode(payload);
      if (claims is! Map) return null;
      final sub = claims['sub'];
      final wid = claims['wid'];
      if (sub is! String || sub.isEmpty || wid is! String || wid.isEmpty) return null;
      return PlayerTokenClaims(playerId: sub, workspaceId: wid);
    } on FormatException {
      return null;
    }
  }
}
