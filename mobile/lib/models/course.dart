class Course {
  const Course({
    required this.code,
    this.name,
    this.colorIndex = 0,
    this.shareCode,
  });

  /// Normalized course code, e.g. `CSC 4330`. Primary key on device.
  final String code;
  final String? name;

  /// Index into `courseColors` in theme.dart.
  final int colorIndex;

  /// 5-character class code from `POST /api/courses`, once shared.
  final String? shareCode;

  static String normalizeCode(String raw) =>
      raw.trim().toUpperCase().split(RegExp(r'\s+')).join(' ');

  String get displayName => name == null || name!.isEmpty ? code : '$code · $name';

  factory Course.fromJson(Map<String, dynamic> json) => Course(
        code: json['code'] as String,
        name: json['name'] as String?,
        colorIndex: json['colorIndex'] as int? ?? 0,
        shareCode: json['shareCode'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'colorIndex': colorIndex,
        'shareCode': shareCode,
      };

  Course copyWith({String? name, int? colorIndex, String? shareCode}) => Course(
        code: code,
        name: name ?? this.name,
        colorIndex: colorIndex ?? this.colorIndex,
        shareCode: shareCode ?? this.shareCode,
      );
}
