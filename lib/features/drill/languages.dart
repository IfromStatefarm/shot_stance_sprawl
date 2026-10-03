class AppLanguage {
  final String code;
  final String name;

  const AppLanguage({
    required this.code,
    required this.name,
  });
}

/// Languages supported by the interface. Voice packs use the same language
/// codes, so adding another language here and a matching voice-pack manifest
/// automatically adds it to the unified language workflow.
const supportedAppLanguages = <AppLanguage>[
  AppLanguage(code: 'en', name: 'English'),
  AppLanguage(code: 'es', name: 'Español'),
];

bool isSupportedAppLanguage(String code) =>
    supportedAppLanguages.any((language) => language.code == code);
