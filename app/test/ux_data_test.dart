import 'dart:convert';

import 'package:duo_wallet/core/db/app_database.dart';
import 'package:duo_wallet/core/money/currency.dart';
import 'package:duo_wallet/core/money/money.dart';
import 'package:duo_wallet/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('money preserves decimal punctuation in both supported locales', () {
    for (final currency in CurrencyCode.values) {
      for (final amount in [0, 1234, -1234, 123456789]) {
        final m = Money(amount, currency);
        for (final locale in ['en', 'hu']) {
          final number = m.formatNumber(locale: locale);
          expect(m.format(locale: locale), contains(number));
          if (currency != CurrencyCode.huf) {
            expect(
                number,
                endsWith(
                    '${locale == 'hu' ? ',' : '.'}${(amount.abs() % 100).toString().padLeft(2, '0')}'));
          }
        }
      }
    }
    expect(const Money(1234, CurrencyCode.eur).format(locale: 'hu'), '12,34 €');
    expect(const Money(1234, CurrencyCode.eur).format(locale: 'en'), '€12.34');
  });

  test('positive input rejects unsafe or ambiguous values', () {
    for (final input in [
      '',
      'NaN',
      'Infinity',
      '-1',
      '1,2.3',
      '1e100',
      'zero'
    ]) {
      expect(parsePositiveAmount(input), isNull, reason: input);
    }
    expect(parsePositiveAmount(' 12,34 '), 12.34);
    expect(parsePositiveAmount('0'), isNull);
    expect(parsePositiveAmount('0', allowZero: true), 0);
  });

  test('a malformed later backup row cannot partially alter data', () {
    final db = AppDatabase();
    final before = db.exportVisibleJson();
    final broken = jsonDecode(jsonEncode(before)) as Map<String, dynamic>;
    (broken['accounts'] as List).first['name'] = 'SHOULD NOT APPLY';
    (broken['transactions'] as List).add({'id': 'broken'});
    expect(() => db.restoreFromJson(broken), throwsA(anything));
    final after = db.exportVisibleJson()..remove('exported_at');
    before.remove('exported_at');
    expect(after, before);
  });

  test(
      'visible backup excludes partner private records and round-trips all tables',
      () {
    final source = AppDatabase();
    final data = source.exportVisibleJson(meId: 'user-sam');
    expect(
        (data['accounts'] as List).every(
            (a) => a['ownership'] == 'common' || a['owner_id'] == 'user-sam'),
        isTrue);
    expect(
        (data['transactions'] as List).every((t) =>
            t['visibility'] == 'shared' || t['created_by'] == 'user-sam'),
        isTrue);
    final target = AppDatabase(seedDemo: false);
    target.restoreFromJson(data, meId: 'user-sam', validateOnly: true);
    expect(target.accounts, isEmpty);
    target.restoreFromJson(data, meId: 'user-sam');
    final restored = target.exportVisibleJson(meId: 'user-sam')
      ..remove('exported_at');
    data.remove('exported_at');
    expect(restored, data);
  });

  test(
      'backup rejects incompatible households, private records and unsupported versions',
      () {
    final db = AppDatabase();
    final own = db.exportVisibleJson(meId: 'user-sam');
    expect(() => db.restoreFromJson({...own, 'schema_version': 999}),
        throwsFormatException);
    final foreign = jsonDecode(jsonEncode(own)) as Map<String, dynamic>;
    foreign['household']['id'] = 'foreign';
    expect(() => db.restoreFromJson(foreign, meId: 'user-sam'),
        throwsFormatException);
    final all = jsonDecode(jsonEncode(own)) as Map<String, dynamic>;
    (all['accounts'] as List).add({
      ...((all['accounts'] as List).first as Map),
      'id': 'partner-private',
      'ownership': 'personal',
      'owner_id': 'user-anna'
    });
    expect(
        () => db.restoreFromJson(all, meId: 'user-sam'), throwsFormatException);
  });
}
