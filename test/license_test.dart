import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:srs_generator/services/license_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  group('Ачкыч текшергич', () {
    test('коммерциялык генератор чыгарган ачкычтар жарактуу', () {
      // Python генератору менен ушул эле купуя сандан түзүлгөн ачкычтар.
      const samples = [
        'AED6-7563-B908-0E72',
        '3739-0810-9354-10CE',
        '0134-19E5-E8E5-34AF',
      ];
      for (final k in samples) {
        expect(LicenseService.verify(k), isTrue, reason: k);
      }
    });

    test('бир тамгасы өзгөртүлгөн ачкыч четке кагылат', () {
      const k = 'AED6-7563-B908-0E72';
      final bad = '${k.substring(0, k.length - 1)}'
          '${k.endsWith('2') ? '3' : '2'}';
      expect(LicenseService.verify(bad), isFalse);
    });

    test('туура эмес узундук/формат четке кагылат', () {
      expect(LicenseService.verify(''), isFalse);
      expect(LicenseService.verify('1234'), isFalse);
      expect(LicenseService.verify('ZZZZ-ZZZZ-ZZZZ-ZZZZ'), isFalse);
    });

    test('дефис/кичине тамга менен да иштейт', () {
      const k = 'aed6 7563 b908 0e72';
      expect(LicenseService.verify(k), isTrue);
    });

    test('activate/isActivated бирге иштейт', () async {
      await LicenseService.deactivate();
      expect(await LicenseService.isActivated(), isFalse);

      final ok = await LicenseService.activate('zzzz-zzzz-zzzz-zzzz');
      expect(ok, isFalse);
      expect(await LicenseService.isActivated(), isFalse);

      final ok2 = await LicenseService.activate('AED6-7563-B908-0E72');
      expect(ok2, isTrue);
      expect(await LicenseService.isActivated(), isTrue);

      await LicenseService.deactivate();
      expect(await LicenseService.isActivated(), isFalse);
    });
  });
}
