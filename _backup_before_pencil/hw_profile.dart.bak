import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'hw_geom.dart';
import 'hw_synth.dart';

/// Бир тамганын сыя маскасы (0..255) жана жазуу сызыгына карата абалы.
class HwGlyph {
  final int code;
  final int w;
  final int h;

  /// Тамганын үстүнөн жазуу сызыгына (baseline) чейинки аралык, пиксель.
  final int baseOff;
  final Uint8List alpha;

  Int32List? _integral;

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

/// Үйрөтүлгөн кол жазманы дискте сактоо (ар бир шаблон барагы өзүнчө файл).
class MyHandwritingStore {
  static Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}my_handwriting');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<File> _file(int page) async {
    final d = await _dir();
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
  static Future<File> _freeFile(String id) async {
    final d = await _dir();
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
  static Future<MyHandwriting?> load() async {
    final map = <int, HwGlyph>{};
    for (var p = 0; p < HwGeom.pageCount; p++) {
      final f = await _file(p);
      if (!await f.exists()) continue;
      for (final g in MyHandwriting.decode(await f.readAsBytes())) {
        map[g.code] = g;
      }
    }
    for (final st in HwGeom.freeSets) {
      final f = await _freeFile(st.id);
      if (!await f.exists()) continue;
      for (final g in MyHandwriting.decode(await f.readAsBytes())) {
        map[g.code] = g;
      }
    }
    if (map.isEmpty) return null;
    // Формула/белги тамгалары жок болсо — кол чийгендей кошобуз.
    HwSynth.fillMissing(map, 44);
    return MyHandwriting(map);
  }
}
