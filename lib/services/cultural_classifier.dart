import '../models/movie.dart';

class CulturalClassifier {
  /// İngilizce konuşulan ana akım sinema (Hollywood ekseni).
  /// GB/IE Avrupa kümesinde kalır — ortak yapımlar her iki etiketi de alabilir.
  static const _hollywoodCountries = {'US', 'AU', 'CA', 'NZ'};

  static const _europeanCountries = {
    'AT',
    'BE',
    'CH',
    'CZ',
    'DE',
    'DK',
    'ES',
    'FI',
    'FR',
    'GB',
    'GR',
    'HU',
    'IE',
    'IS',
    'IT',
    'NL',
    'NO',
    'PL',
    'PT',
    'RO',
    'RS',
    'SE',
  };
  static const _latinAmericanCountries = {
    'AR',
    'BO',
    'BR',
    'CL',
    'CO',
    'CR',
    'CU',
    'DO',
    'EC',
    'GT',
    'MX',
    'PE',
    'PR',
    'PY',
    'UY',
    'VE',
  };

  static Set<String> classify(Movie movie) {
    final countries = movie.originCountries
        .map((country) => country.toUpperCase())
        .toSet();
    final language = movie.originalLanguage?.toLowerCase();
    final result = <String>{};

    if (countries.contains('TR') || language == 'tr') result.add('turkish');
    if (countries.contains('KR') || language == 'ko') result.add('korean');
    if (countries.contains('JP') || language == 'ja') result.add('japanese');
    if (countries.contains('IN') ||
        {'hi', 'ta', 'te', 'ml', 'bn', 'pa'}.contains(language)) {
      result.add('indian');
    }
    if (countries.contains('IR') || language == 'fa') result.add('iranian');
    if (countries.any(_hollywoodCountries.contains)) {
      result.add('hollywood');
    }
    if (countries.any(_europeanCountries.contains)) result.add('european');
    if (countries.any(_latinAmericanCountries.contains)) {
      result.add('latin_american');
    }
    if (countries.any({'CN', 'HK', 'TW'}.contains) ||
        {'zh', 'cn'}.contains(language)) {
      result.add('east_asian');
    }
    return result;
  }
}
