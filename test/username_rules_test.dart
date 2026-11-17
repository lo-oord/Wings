import 'package:flutter_test/flutter_test.dart';
import 'package:wings/data/username/username_rules.dart';

void main() {
  group('UsernameRules.normalize', () {
    test('trims and lower-cases so uniqueness is case-insensitive', () {
      expect(UsernameRules.normalize('  Lord_Shadow '), 'lord_shadow');
      expect(
        UsernameRules.normalize('LORD_SHADOW'),
        UsernameRules.normalize('lord_shadow'),
      );
    });
  });

  group('UsernameRules.validate', () {
    test('accepts a valid handle', () {
      final result = UsernameRules.validate('shadow_07');
      expect(result.ok, isTrue);
      expect(result.normalized, 'shadow_07');
    });

    test('rejects empty, short, long, invalid and reserved names', () {
      expect(UsernameRules.validate('').problem, UsernameProblem.empty);
      expect(UsernameRules.validate('ab').problem, UsernameProblem.tooShort);
      expect(UsernameRules.validate('a' * 21).problem, UsernameProblem.tooLong);
      expect(
        UsernameRules.validate('shadow 07').problem,
        UsernameProblem.invalidCharacters,
      );
      expect(
        UsernameRules.validate('shadow-07').problem,
        UsernameProblem.invalidCharacters,
      );
      expect(UsernameRules.validate('ADMIN').problem, UsernameProblem.reserved);
    });
  });

  group('UsernameRules.suggestions', () {
    test('are unique, valid and close to the requested handle', () {
      final suggestions = UsernameRules.suggestions('shadow');
      expect(suggestions, isNotEmpty);
      expect(suggestions.toSet().length, suggestions.length);
      for (final suggestion in suggestions) {
        expect(UsernameRules.validate(suggestion).ok, isTrue);
        expect(suggestion.startsWith('shadow'), isTrue);
        expect(suggestion, isNot('shadow'));
        expect(suggestion.length, lessThanOrEqualTo(UsernameRules.maxLength));
      }
    });

    test('sanitizes unusable input instead of generating empty handles', () {
      final suggestions = UsernameRules.suggestions('!!');
      expect(suggestions, isNotEmpty);
      for (final suggestion in suggestions) {
        expect(UsernameRules.validate(suggestion).ok, isTrue);
      }
    });
  });
}
