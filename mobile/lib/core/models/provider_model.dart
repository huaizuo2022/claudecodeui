/// Model definition for an LLM provider (e.g. Claude, Codex, Cursor).
class ProviderModelOption {
  const ProviderModelOption({
    required this.value,
    required this.label,
    this.description,
    this.isCustom = false,
    this.effortValues = const [],
    this.defaultEffort,
  });

  final String value;
  final String label;
  final String? description;
  final bool isCustom;
  final List<String> effortValues;
  final String? defaultEffort;

  factory ProviderModelOption.fromJson(Map<dynamic, dynamic> json) {
    final effortMap = json['effort'] is Map ? json['effort'] as Map : null;
    final effortValues = <String>[];
    String? defaultEffort;

    if (effortMap != null) {
      if (effortMap['default'] is String) {
        defaultEffort = effortMap['default'] as String;
      }
      if (effortMap['values'] is List) {
        for (final item in effortMap['values'] as List) {
          if (item is Map && item['value'] is String) {
            effortValues.add(item['value'] as String);
          } else if (item is String) {
            effortValues.add(item);
          }
        }
      }
    }

    return ProviderModelOption(
      value: (json['value'] as String?) ?? '',
      label: (json['label'] as String?) ?? (json['value'] as String? ?? ''),
      description: json['description'] as String?,
      isCustom: json['isCustom'] == true,
      effortValues: effortValues,
      defaultEffort: defaultEffort,
    );
  }
}

/// The active model and reasoning effort resolved for a session.
class SessionActiveModel {
  const SessionActiveModel({
    required this.provider,
    required this.sessionId,
    required this.model,
    this.effort,
    this.source,
  });

  final String provider;
  final String sessionId;
  final String model;
  final String? effort;
  final String? source;

  factory SessionActiveModel.fromJson(Map<dynamic, dynamic> json) {
    return SessionActiveModel(
      provider: (json['provider'] as String?) ?? '',
      sessionId: (json['sessionId'] as String?) ?? '',
      model: (json['model'] as String?) ?? '',
      effort: json['effort'] as String?,
      source: json['source'] as String?,
    );
  }
}
