import 'package:flutter_test/flutter_test.dart';
import 'package:shot_stance_sprawl/core/firebase_environment.dart';

void main() {
  group('FirebaseEnvironmentConfig', () {
    test('maps development flavor names', () {
      expect(
        FirebaseEnvironmentConfig.environmentForFlavor('dev'),
        FirebaseEnvironment.development,
      );
      expect(
        FirebaseEnvironmentConfig.environmentForFlavor('development'),
        FirebaseEnvironment.development,
      );
    });

    test('maps production flavor names', () {
      expect(
        FirebaseEnvironmentConfig.environmentForFlavor('prod'),
        FirebaseEnvironment.production,
      );
      expect(
        FirebaseEnvironmentConfig.environmentForFlavor('production'),
        FirebaseEnvironment.production,
      );
    });

    test('rejects unknown flavors', () {
      expect(
        () => FirebaseEnvironmentConfig.environmentForFlavor('staging'),
        throwsStateError,
      );
    });
  });
}
