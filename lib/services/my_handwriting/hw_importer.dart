import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;

import 'hw_freeform.dart';
import 'hw_geom.dart';
import 'hw_profile.dart';
import 'hw_vision.dart';

/// Шаблондун сүрөтүн окуп, тамгаларды кесип, сактоого даярдайт.
class HwImportResult {
  final bool ok;
  final String message;
  final int count;
  final Uint8List? bin;
  const HwImportResult(this.ok, this.message, this.count, this.bin);
}

/// compute() үчүн жогорку деңгээлдеги функция (өзүнчө isolate'та иштейт).
Map<String, Object?> _process(List<Object> args) {
  final gray = args[0] as Uint8List;
  final w = args[1] as int;
  final h = args[2] as int;
  final page = args[3] as int;

  final canvas = HwVision.rectify(gray, w, h);
  if (canvas == null) {
    return {'ok': false, 'count': 0, 'bin': null};
  }
  final glyphs = HwVision.extract(canvas, page);
  return {
    'ok': true,
    'count': glyphs.length,
    'bin': MyHandwriting.encode(glyphs),
  };
}

Map<String, Object?> _processFree(List<Object> args) {
  final gray = args[0] as Uint8List;
  final w = args[1] as int;
  final h = args[2] as int;
  final set = HwGeom.freeSets.firstWhere((e) => e.id == (args[3] as String));
  final r = HwFreeform.extract(gray, w, h, set);
  if (r.error != null) {
    return {'ok': false, 'error': r.error, 'count': 0, 'bin': null};
  }
  return {
    'ok': true,
    'error': null,
    'count': r.glyphs.length,
    'bin': MyHandwriting.encode(r.glyphs),
  };
}

class HwImporter {
  static const int _maxWidth = 2400;

  static Future<HwImportResult> importFreeform(
      String setId, Uint8List imageBytes) async {
    final set = HwGeom.freeSets.firstWhere((e) => e.id == setId);
    // 1) Сүрөттү декоддоо (экинчи өлчөмгө кичирейтип)
    int w, h;
    Uint8List rgba;
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(imageBytes);
      final desc = await ui.ImageDescriptor.encoded(buffer);
      final tw = desc.width > 1800 ? 1800 : null;
      final codec = await desc.instantiateCodec(targetWidth: tw);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      w = img.width;
      h = img.height;
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bd == null) {
        return const HwImportResult(false, 'Сүрөттү окуу мүмкүн болгон жок.', 0, null);
      }
      rgba = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
      img.dispose();
      codec.dispose();
      desc.dispose();
      buffer.dispose();
    } catch (_) {
      return const HwImportResult(
          false, 'Бул файл сүрөт эмес же бузулган экен.', 0, null);
    }

    // 2) Боз түскө өткөрүү
    final gray = Uint8List(w * h);
    for (var i = 0, p = 0; i < gray.length; i++, p += 4) {
      gray[i] = ((rgba[p] * 299 + rgba[p + 1] * 587 + rgba[p + 2] * 114) ~/ 1000);
    }

    final res = await compute(_processFree, <Object>[gray, w, h, setId]);
    if (res['ok'] != true) {
      return HwImportResult(false, (res['error'] as String?) ?? 'Ката.', 0, null);
    }
    final count = res['count'] as int;
    return HwImportResult(true, '${set.title}: ${set.chars.length} тамга окулду.',
        count, res['bin'] as Uint8List);
  }

  static Future<HwImportResult> importPage(int page, Uint8List imageBytes) async {
    // 1) Сүрөттү декоддоо (экинчи өлчөмгө кичирейтип)
    int w, h;
    Uint8List rgba;
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(imageBytes);
      final desc = await ui.ImageDescriptor.encoded(buffer);
      final tw = desc.width > _maxWidth ? _maxWidth : null;
      final codec = await desc.instantiateCodec(targetWidth: tw);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      w = img.width;
      h = img.height;
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bd == null) {
        return const HwImportResult(false, 'Сүрөттү окуу мүмкүн болгон жок.', 0, null);
      }
      rgba = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
      img.dispose();
      codec.dispose();
      desc.dispose();
      buffer.dispose();
    } catch (_) {
      return const HwImportResult(
          false, 'Бул файл сүрөт эмес же бузулган экен.', 0, null);
    }

    // 2) Боз түскө өткөрүү
    final gray = Uint8List(w * h);
    for (var i = 0, p = 0; i < gray.length; i++, p += 4) {
      gray[i] = ((rgba[p] * 299 + rgba[p + 1] * 587 + rgba[p + 2] * 114) ~/ 1000);
    }

    // 3) Оор эсептөө — өзүнчө isolate'та
    final res = await compute(_process, <Object>[gray, w, h, page]);
    if (res['ok'] != true) {
      return const HwImportResult(
        false,
        'Төрт бурчтагы кара квадраттар табылган жок. Барактын төрт бурчу '
        'тең сүрөткө толук түшүп, жарык тегиз болушу керек. Баракты '
        'үстөлгө жайып, түз жогортон тартып көрүңүз.',
        0,
        null,
      );
    }
    final count = res['count'] as int;
    final expected = HwGeom.pageChars(page).length;
    if (count < expected ~/ 3) {
      return HwImportResult(
        false,
        'Бул барактан $count тамга гана табылды (керек: $expected). '
        'Туура баракты жүктөдүңүзбү? Тамгаларды кара сыя менен жана '
        'чийменин ичине жазгансыз деп текшериңиз.',
        count,
        null,
      );
    }
    return HwImportResult(
        true, '$count / $expected тамга окулду.', count, res['bin'] as Uint8List);
  }
}
