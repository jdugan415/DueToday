/// 5-character class codes. Mirrors `SHARE_CODE_ALPHABET` in
/// backend/app/models.py: no 0/O or 1/I/L so codes can be read aloud.
class ShareCode {
  ShareCode._();

  static const String alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const int length = 5;

  static final RegExp _pattern = RegExp('^[$alphabet]{$length}\$');

  static String normalize(String raw) => raw.trim().toUpperCase();

  static bool isValid(String raw) => _pattern.hasMatch(normalize(raw));
}
