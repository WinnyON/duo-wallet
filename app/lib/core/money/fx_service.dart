import 'currency.dart';
import 'money.dart';

enum FxSource {
  ecb('ecb'),
  cached('cached'),
  manual('manual');

  final String value;
  const FxSource(this.value);

  static FxSource fromString(String? v) => switch (v) {
    'cached' => FxSource.cached,
    'manual' => FxSource.manual,
    _ => FxSource.ecb,
  };
}

class FxQuote {
  final CurrencyCode from;
  final CurrencyCode to;
  final double rate;
  final FxSource source;
  final DateTime rateDate;

  const FxQuote({
    required this.from,
    required this.to,
    required this.rate,
    required this.source,
    required this.rateDate,
  });
}

class FxService {
  final Map<String, FxQuote> _cache = {};

  /// Default fallback rates to HUF when completely offline on first launch.
  static const Map<CurrencyCode, double> defaultRatesToHuf = {
    CurrencyCode.huf: 1.0,
    CurrencyCode.eur: 395.0,
    CurrencyCode.ron: 79.4,
  };

  FxService([Iterable<FxQuote>? initialQuotes]) {
    if (initialQuotes != null) {
      for (final q in initialQuotes) {
        putQuote(q);
      }
    }
  }

  void putQuote(FxQuote quote) {
    _cache['${quote.from.code}_${quote.to.code}'] = quote;
  }

  FxQuote getRate(CurrencyCode from, [CurrencyCode to = CurrencyCode.huf]) {
    if (from == to) {
      return FxQuote(
        from: from,
        to: to,
        rate: 1.0,
        source: FxSource.ecb,
        rateDate: DateTime.now(),
      );
    }
    final cached = _cache['${from.code}_${to.code}'];
    if (cached != null) return cached;

    final fromToHuf = defaultRatesToHuf[from] ?? 1.0;
    final toToHuf = defaultRatesToHuf[to] ?? 1.0;
    return FxQuote(
      from: from,
      to: to,
      rate: fromToHuf / toToHuf,
      source: FxSource.cached,
      rateDate: DateTime.now(),
    );
  }

  static int convertMinor(int amountMinor, double rate) =>
      (amountMinor * rate).round();

  Money convert(Money money, CurrencyCode target, {double? overrideRate}) {
    if (money.currency == target) return money;
    final r = overrideRate ?? getRate(money.currency, target).rate;
    return Money(convertMinor(money.amountMinor, r), target);
  }
}
