import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ачкыч (лицензия) текшергич.
///
/// Бул класс колдонуучуга эч кандай көрүнбөйт — UI'да "ачкыч", "лицензия"
/// деген сөз, баскыч же талаа жок. Ачкычты киргизүү жашыруун ишарат аркылуу
/// гана ачылат (качта: [IntroScreen]).
///
/// Ачкыч түзүмү: 16 hex-тамга, 4төн топтолуп көрсөтүлөт (мис. "7B3F-A901-
/// 2C44-E8D1"). Алгачкы 12 тамга — туш келди "пайлоад" (6 байт), акыркы 4
/// тамга — ошол пайлоаддын HMAC-SHA256 текшерме суммасы (биринчи 2 байты).
/// Текшерме сумма ушул эле купуя сан менен эсептелет, андыктан ачкычты
/// колдон ойлоп табуу (туура текшерме суммасы менен) мүмкүн эмес — бирок
/// бул өтө катуу криптографиялык коргоо эмес, жөнөкөй, жеңил деңгээл.
class LicenseService {
  static const _kStoredKey = 'dk';
  static const _kActive = 'da';

  // Купуя сан код ичинде бир сап катары жатпайт — эки бөлүк XOR аркылуу
  // гана иштетилгенде чогулат. Бул decompile кылганда түз көрүнүүнү
  // кыйындатат (толук коргоо эмес, бир кичине тоскоолдук).
  static const List<int> _secretA = [
    0x7a, 0x1c, 0x9e, 0x44, 0x6b, 0x2d, 0xf1, 0x08,
    0x93, 0x5e, 0xc7, 0x31, 0xa4, 0x6f, 0x12, 0xd8,
  ];
  static const List<int> _secretB = [
    0x11, 0x55, 0xe2, 0x39, 0x0a, 0x7c, 0x9d, 0x66,
    0xf0, 0x23, 0xb8, 0x4e, 0x17, 0x82, 0xc5, 0xab,
  ];

  static List<int> get _secret =>
      List.generate(_secretA.length, (i) => _secretA[i] ^ _secretB[i]);

  static String _bytesToHex(List<int> b) =>
      b.map((e) => e.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

  /// Ачкычты адамга окууга ыңгайлуу "XXXX-XXXX-XXXX-XXXX" түрүнө келтирет.
  static String format(String rawKey) {
    final k = _clean(rawKey);
    final b = StringBuffer();
    for (var i = 0; i < k.length; i += 4) {
      if (i > 0) b.write('-');
      final end = (i + 4) > k.length ? k.length : i + 4;
      b.write(k.substring(i, end));
    }
    return b.toString();
  }

  static String _clean(String rawKey) =>
      rawKey.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();

  /// Ачкыч туурабы? (форматын жана текшерме суммасын текшерет).
  static bool verify(String rawKey) {
    final k = _clean(rawKey);
    if (k.length != 16) return false;
    final payloadHex = k.substring(0, 12);
    final checksumHex = k.substring(12, 16);
    final List<int> payload;
    try {
      payload = List.generate(6,
          (i) => int.parse(payloadHex.substring(i * 2, i * 2 + 2), radix: 16));
    } catch (_) {
      return false;
    }
    final mac = Hmac(sha256, _secret).convert(payload).bytes;
    return _bytesToHex(mac.sublist(0, 2)) == checksumHex;
  }

  /// Ачкычты сактайт (мурда текшерилген болсо). Кайтарат: ийгиликтүүбү.
  static Future<bool> activate(String rawKey) async {
    final k = _clean(rawKey);
    if (!verify(k)) return false;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kStoredKey, k);
    await p.setBool(_kActive, true);
    return true;
  }

  /// Азыркы учурда программа иштетилгенби? Ар бир чакырууда сакталган
  /// ачкычты кайра текшерет — жөн гана туура/туура эмес деген флагга
  /// ишенбейт (флагды кол менен "true" кылып коюу жетишсиз болсун үчүн).
  static Future<bool> isActivated() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_kActive) != true) return false;
    final k = p.getString(_kStoredKey);
    if (k == null) return false;
    return verify(k);
  }

  /// Иштетүүнү өчүрөт (керек болсо — колдонулбайт, бирок даяр турсун).
  static Future<void> deactivate() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kStoredKey);
    await p.remove(_kActive);
  }
}
