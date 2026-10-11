import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'hw_geom.dart';
import 'hw_synth.dart';

/// Тамганын жазуу сызыгына жакын улоо чекити (тамганын өз пикселдеринде).
class HwJoin {
  final double x;
  final double y;

  /// Сызыктын ушул чекиттеги багыты (бирдик вектор, оңго карай).
  final double tx;
  final double ty;
  const HwJoin(this.x, this.y, [this.tx = 1, this.ty = 0]);
}

/// Бир тамганын сыя маскасы (0..255) жана жазуу сызыгына карата абалы.
class HwGlyph {
  final int code;
  final int w;
  final int h;

  /// Тамганын үстүнөн жазуу сызыгына (baseline) чейинки аралык, пиксель.
  final int baseOff;
  final Uint8List alpha;

  Int32List? _integral;

  // ------------------------------------------------ улоо чекиттери
  double? _sw;
  double _jxh = -1;
  HwJoin? _exit;
  HwJoin? _entry;

  /// Сызыктын болжолдуу жоондугу (пиксель): 2 * аянт / периметр.
  double get strokeW {
    final cached = _sw;
    if (cached != null) return cached;
    var area = 0;
    var per = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (alpha[y * w + x] < 128) continue;
        area++;
        final l = x == 0 || alpha[y * w + x - 1] < 128;
        final r = x == w - 1 || alpha[y * w + x + 1] < 128;
        final u = y == 0 || alpha[(y - 1) * w + x] < 128;
        final d = y == h - 1 || alpha[(y + 1) * w + x] < 128;
        if (l) per++;
        if (r) per++;
        if (u) per++;
        if (d) per++;
      }
    }
    final v = per > 0 ? 2.0 * area / per : 3.0;
    _sw = v.clamp(1.5, 12.0).toDouble();
    return _sw!;
  }

  /// Тамгадан кийинки тамгага чыгуучу чекит (оң жагында, жазуу сызыгына жакын).
  HwJoin? exitJoin(double xh) {
    _findJoins(xh);
    return _exit;
  }

  /// Мурунку тамгадан келген сызык кирүүчү чекит (сол жагында).
  HwJoin? entryJoin(double xh) {
    _findJoins(xh);
    return _entry;
  }

  /// [x] мамычасынын [yLo]..[yHi] аралыгындагы эң төмөнкү сыя сегменти:
  /// борбордук y кайтарат, жок болсо null.
  double? _bottomCentre(int x, int yLo, int yHi) {
    if (x < 0 || x >= w) return null;
    var bottom = -1;
    for (var y = yHi; y >= yLo; y--) {
      if (alpha[y * w + x] >= 128) {
        bottom = y;
        break;
      }
    }
    if (bottom < 0) return null;
    var len = 0;
    for (var y = bottom; y >= yLo; y--) {
      if (alpha[y * w + x] < 128) break;
      len++;
    }
    final t = math.min(len.toDouble(), strokeW);
    return bottom + 1 - t / 2;
  }

  /// Чекиттин жанындагы сызыктын багытын эсептейт: терезедеги сыя
  /// пикселдеринин борборунан чекитке чейинки вектор. Өйдө карай (же
  /// горизонталдуу) гана ийилет, ошондо улоо ылдый чөгүп кетпейт.
  (double, double) _tangent(double tipX, double tipY, int x0, int x1, int yLo,
      int yHi, bool outward) {
    var sx = 0.0, sy = 0.0;
    var n = 0;
    for (var x = math.max(0, x0); x <= x1 && x < w; x++) {
      for (var y = yLo; y <= yHi; y++) {
        if (alpha[y * w + x] >= 128) {
          sx += x + 0.5;
          sy += y + 0.5;
          n++;
        }
      }
    }
    if (n == 0) return (1.0, 0.0);
    final cx = sx / n, cy = sy / n;
    final dx = outward ? tipX - cx : cx - tipX;
    final dy = outward ? tipY - cy : cy - tipY;
    var ang = math.atan2(dy, dx);
    if (dx >= 0) {
      ang = ang.clamp(-1.05, 0.15).toDouble();
    } else {
      ang = dy < 0 ? -1.05 : 0.15;
    }
    return (math.cos(ang), math.sin(ang));
  }

  void _findJoins(double xh) {
    if (_jxh == xh) return;
    _jxh = xh;
    _exit = null;
    _entry = null;
    final sw = strokeW;
    final yLo = math.max(0, (baseOff - 0.42 * xh).floor());
    final yHi = math.min(h - 1, (baseOff + 0.04 * xh).ceil());
    if (yHi < yLo) return;
    final span = math.max(2, (w * 0.6).floor());

    // чыгуу: оң жактагы эң чет мамыча
    for (var x = w - 1; x >= w - span && x >= 0; x--) {
      if (_bottomCentre(x, yLo, yHi) == null) continue;
      final inside = math.max(0, (x + 1 - 0.5 * sw).floor());
      final yc = _bottomCentre(inside, yLo, yHi) ?? _bottomCentre(x, yLo, yHi)!;
      final ex = math.max(0.0, x + 1 - 0.5 * sw);
      final t = _tangent(ex + 0.5 * sw, yc, (ex - 2.5 * sw).floor(),
          (ex - 0.5 * sw).floor(), yLo, yHi, true);
      _exit = HwJoin(ex, yc, t.$1, t.$2);
      break;
    }
    // кирүү: сол жактагы эң чет мамыча
    for (var x = 0; x < span && x < w; x++) {
      if (_bottomCentre(x, yLo, yHi) == null) continue;
      final inside = math.min(w - 1, (x + 0.5 * sw).floor());
      final yc = _bottomCentre(inside, yLo, yHi) ?? _bottomCentre(x, yLo, yHi)!;
      final en = math.min(w.toDouble(), x + 0.5 * sw);
      final t = _tangent(en - 0.5 * sw, yc, (en + 0.5 * sw).ceil(),
          (en + 2.5 * sw).ceil(), yLo, yHi, false);
      _entry = HwJoin(en, yc, t.$1, t.$2);
      break;
    }
  }

  HwGlyph(this.code, this.w, this.h, this.baseOff, this.alpha);

  /// Масштабдоо үчүн интегралдык сүрөт ((w+1) x (h+1)).
  Int32List get integral {
    var ii = _integral;
    if (ii != null) return ii;
    ii = Int32List((w + 1) * (h + 1));
    final iw = w + 1;
    for (var y = 0; y < h; y++) {
      var rowSum = 0;
      for (var x = 0; x < w; x++) {
        rowSum += alpha[y * w + x];
        ii[(y + 1) * iw + (x + 1)] = ii[y * iw + (x + 1)] + rowSum;
      }
    }
    _integral = ii;
    return ii;
  }
}

/// Колдонуучунун үйрөтүлгөн кол жазмасы: тамга -> глиф.
class MyHandwriting {
  final Map<int, HwGlyph> glyphs;
  MyHandwriting(this.glyphs);

  HwGlyph? glyphFor(String ch) {
    final g = glyphs[ch.codeUnitAt(0)];
    if (g != null) return g;
    // Чоң/кичине тамга жок болсо, экинчисин колдонобуз (өлчөмү масштабдалат).
    final lo = ch.toLowerCase();
    final up = ch.toUpperCase();
    final alt = lo != ch ? lo : up;
    if (alt.length == 1 && alt != ch) return glyphs[alt.codeUnitAt(0)];
    return null;
  }

  late final double xHeight = _computeXHeight();

  double _computeXHeight() {
    final vals = <int>[];
    for (final c in 'аеоспинмз'.codeUnits) {
      final g = glyphs[c];
      if (g != null) vals.add(g.baseOff);
    }
    if (vals.isEmpty) return 36;
    vals.sort();
    return vals[vals.length ~/ 2].toDouble();
  }

  /// Кичине кирилл тамгалардын канчасы бар (толуктугун көрсөтүү үчүн).
  int get lowerCount {
    var n = 0;
    for (final c in HwGeom.lower.codeUnits) {
      if (glyphs.containsKey(c)) n++;
    }
    return n;
  }

  bool get usable => lowerCount >= 20;

  List<String> get missingLetters {
    final out = <String>[];
    for (final s in HwGeom.lower.split('') + HwGeom.digits.split('')) {
      if (!glyphs.containsKey(s.codeUnitAt(0))) out.add(s);
    }
    return out;
  }

  // ------------------------------------------------------- сериялоо
  static Uint8List encode(List<HwGlyph> list) {
    var size = 4;
    for (final g in list) {
      size += 16 + g.alpha.length;
    }
    final out = Uint8List(size);
    final bd = ByteData.view(out.buffer);
    bd.setInt32(0, list.length, Endian.little);
    var p = 4;
    for (final g in list) {
      bd.setInt32(p, g.code, Endian.little);
      bd.setInt32(p + 4, g.w, Endian.little);
      bd.setInt32(p + 8, g.h, Endian.little);
      bd.setInt32(p + 12, g.baseOff, Endian.little);
      p += 16;
      out.setRange(p, p + g.alpha.length, g.alpha);
      p += g.alpha.length;
    }
    return out;
  }

  static List<HwGlyph> decode(Uint8List bytes) {
    final out = <HwGlyph>[];
    if (bytes.length < 4) return out;
    final bd = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
    final n = bd.getInt32(0, Endian.little);
    var p = 4;
    for (var i = 0; i < n; i++) {
      if (p + 16 > bytes.length) break;
      final code = bd.getInt32(p, Endian.little);
      final w = bd.getInt32(p + 4, Endian.little);
      final h = bd.getInt32(p + 8, Endian.little);
      final base = bd.getInt32(p + 12, Endian.little);
      p += 16;
      final len = w * h;
      if (w <= 0 || h <= 0 || p + len > bytes.length) break;
      out.add(HwGlyph(code, w, h, base, Uint8List.sublistView(bytes, p, p + len)));
      p += len;
    }
    return out;
  }
}

/// Бир адамдын кол жазмасы (профиль): аты жана өзүнчө папкасы.
class HwProfileInfo {
  final String id;
  final String name;
  const HwProfileInfo(this.id, this.name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// Үйрөтүлгөн кол жазманы дискте сактоо (ар бир шаблон барагы өзүнчө файл).
///
/// Бир нече адамдын кол жазмасы сакталат. Биринчиси ([defaultId]) мурдагы
/// `my_handwriting` папкасынын өзүндө турат (эски тамгалар жоголбойт),
/// калгандары `my_handwriting/p_<id>` папкаларында.
class MyHandwritingStore {
  static const String defaultId = 'default';
  static const String defaultName = 'Менин кол жазмам';

  /// Учурда үйрөтүлүп жаткан профиль (MyHandwritingScreen коёт).
  static String current = defaultId;

  static Future<Directory> _root() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}my_handwriting');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<Directory> _dir([String? profile]) async {
    final root = await _root();
    final id = profile ?? current;
    if (id == defaultId) return root;
    final d = Directory('${root.path}${Platform.pathSeparator}p_$id');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  // ---------------------------------------------------- профилдер тизмеси
  static Future<File> _listFile() async {
    final root = await _root();
    return File('${root.path}${Platform.pathSeparator}profiles.json');
  }

  /// Бардык кол жазмалар (биринчиси — негизгиси, ар дайым бар).
  static Future<List<HwProfileInfo>> profiles() async {
    final out = <HwProfileInfo>[];
    try {
      final f = await _listFile();
      if (await f.exists()) {
        final data = jsonDecode(await f.readAsString());
        if (data is List) {
          for (final e in data) {
            if (e is Map && e['id'] != null) {
              out.add(HwProfileInfo(
                  e['id'].toString(), (e['name'] ?? '').toString()));
            }
          }
        }
      }
    } catch (_) {}
    if (!out.any((p) => p.id == defaultId)) {
      out.insert(0, const HwProfileInfo(defaultId, defaultName));
    }
    return out;
  }

  static Future<void> _saveList(List<HwProfileInfo> list) async {
    final f = await _listFile();
    await f.writeAsString(jsonEncode([for (final p in list) p.toJson()]));
  }

  static Future<String> nameOf(String? id) async {
    final want = id ?? defaultId;
    for (final p in await profiles()) {
      if (p.id == want) return p.name;
    }
    return defaultName;
  }

  /// Жаңы кол жазма (бош) кошот жана аны кайтарат.
  static Future<HwProfileInfo> addProfile(String name) async {
    final list = await profiles();
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final p = HwProfileInfo(id, name.trim().isEmpty ? 'Кол жазма' : name.trim());
    list.add(p);
    await _saveList(list);
    await _dir(id);
    return p;
  }

  static Future<void> renameProfile(String id, String name) async {
    final list = await profiles();
    final i = list.indexWhere((p) => p.id == id);
    if (i < 0 || name.trim().isEmpty) return;
    list[i] = HwProfileInfo(id, name.trim());
    await _saveList(list);
  }

  /// Кол жазманы толугу менен өчүрөт. Негизгиси өчпөйт, тазаланат гана.
  static Future<void> deleteProfile(String id) async {
    if (id == defaultId) {
      final keep = current;
      current = defaultId;
      await deleteAll();
      current = keep;
      return;
    }
    final root = await _root();
    final d = Directory('${root.path}${Platform.pathSeparator}p_$id');
    if (await d.exists()) await d.delete(recursive: true);
    final list = await profiles()
      ..removeWhere((p) => p.id == id);
    await _saveList(list);
    if (current == id) current = defaultId;
  }

  static Future<File> _file(int page, [String? profile]) async {
    final d = await _dir(profile);
    return File('${d.path}${Platform.pathSeparator}page$page.bin');
  }

  static Future<void> savePage(int page, Uint8List bin) async {
    final f = await _file(page);
    await f.writeAsBytes(bin, flush: true);
  }

  static Future<void> deletePage(int page) async {
    final f = await _file(page);
    if (await f.exists()) await f.delete();
  }

  static Future<void> deleteAll() async {
    for (var p = 0; p < HwGeom.pageCount; p++) {
      await deletePage(p);
    }
    for (final st in HwGeom.freeSets) {
      await deleteFree(st.id);
    }
  }

  // ---- шаблонсуз (дептерге жазылган) топтомдор
  static Future<File> _freeFile(String id, [String? profile]) async {
    final d = await _dir(profile);
    // v2 — тамгаларды бөлүү алгоритми жаңыртылганда эски файлдар эсептелбейт.
    final old = File('${d.path}${Platform.pathSeparator}free_$id.bin');
    if (await old.exists()) await old.delete();
    return File('${d.path}${Platform.pathSeparator}free2_$id.bin');
  }

  static Future<void> saveFree(String id, Uint8List bin) async {
    final f = await _freeFile(id);
    await f.writeAsBytes(bin, flush: true);
  }

  static Future<void> deleteFree(String id) async {
    final f = await _freeFile(id);
    if (await f.exists()) await f.delete();
  }

  /// Топтомдун тамгаларынын саны (0 — жүктөлө элек).
  static Future<int> freeCount(HwSet set) async {
    final f = await _freeFile(set.id);
    if (!await f.exists()) return 0;
    final codes = set.chars.codeUnits.toSet();
    return MyHandwriting.decode(await f.readAsBytes())
        .where((g) => codes.contains(g.code))
        .length;
  }

  /// Ар бир барактагы жүктөлгөн тамгалардын саны (0 — жүктөлө элек).
  static Future<List<int>> pageCounts() async {
    final res = <int>[];
    for (var p = 0; p < HwGeom.pageCount; p++) {
      final f = await _file(p);
      if (!await f.exists()) {
        res.add(0);
        continue;
      }
      res.add(MyHandwriting.decode(await f.readAsBytes()).length);
    }
    return res;
  }

  /// Бардык барактарды окуйт. Эч нерсе жок болсо null.
  /// [profile] берилбесе — учурдагы ([current]) кол жазма.
  static Future<MyHandwriting?> load({String? profile}) async {
    final map = <int, HwGlyph>{};
    for (var p = 0; p < HwGeom.pageCount; p++) {
      final f = await _file(p, profile);
      if (!await f.exists()) continue;
      for (final g in MyHandwriting.decode(await f.readAsBytes())) {
        map[g.code] = g;
      }
    }
    for (final st in HwGeom.freeSets) {
      final f = await _freeFile(st.id, profile);
      if (!await f.exists()) continue;
      for (final g in MyHandwriting.decode(await f.readAsBytes())) {
        map[g.code] = g;
      }
    }
    if (map.isEmpty) return null;
    // Формула/белги тамгалары жок болсо — кол чийгендей кошобуз.
    HwSynth.fillMissing(map, 44);
    // ё, й (Ё, Й) — е, и тамгаларынан ручка менен жасалат
    HwSynth.composeDiacritics(map);
    return MyHandwriting(map);
  }
}
