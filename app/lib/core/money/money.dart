import 'package:intl/intl.dart';
import 'currency.dart';

class Money {
  /// Stored in minor units (100 minor units = 1 major unit for HUF, RON, EUR).
  final int amountMinor;
  final CurrencyCode currency;

  const Money(this.amountMinor, [this.currency = CurrencyCode.huf]);

  const Money.zero([this.currency = CurrencyCode.huf]) : amountMinor = 0;

  factory Money.fromMajor(num major, [CurrencyCode currency = CurrencyCode.huf]) =>
      Money((major * currency.minorFactor).round(), currency);

  double get majorAmount => amountMinor / currency.minorFactor;

  Money operator +(Money other) {
    assert(currency == other.currency, 'Cannot add different currencies directly');
    return Money(amountMinor + other.amountMinor, currency);
  }

  Money operator -(Money other) {
    assert(currency == other.currency, 'Cannot subtract different currencies directly');
    return Money(amountMinor - other.amountMinor, currency);
  }

  String format({String locale = 'hu', bool hideAmounts = false}) {
    if (hideAmounts) return '•••• ${currency.symbol}';
    final decimals = currency.displayDecimals;
    final value = decimals == 0 ? (amountMinor / 100).round() : majorAmount;
    final pattern = decimals == 0 ? '#,##0' : '#,##0.00';
    final formatted = NumberFormat(pattern, locale).format(value).replaceAll(',', ' ').replaceAll('\u00A0', ' ');
    return locale.startsWith('hu') || currency == CurrencyCode.huf || currency == CurrencyCode.ron
        ? '$formatted ${currency.symbol}'
        : '${currency.symbol}$formatted';
  }

  @override
  bool operator ==(Object other) =>
      other is Money && other.amountMinor == amountMinor && other.currency == currency;

  @override
  int get hashCode => Object.hash(amountMinor, currency);

  @override
  String toString() => format();
}
