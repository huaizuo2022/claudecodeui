import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// Message font scale, persisted in preferences and applied app-wide through
/// `MediaQuery.textScaler`.
class FontScaleController extends Notifier<double> {
  @override
  double build() => ref.read(prefsStoreProvider).fontScale;

  Future<void> set(double value) async {
    await ref.read(prefsStoreProvider).setFontScale(value);
    state = value;
  }
}

final fontScaleProvider =
    NotifierProvider<FontScaleController, double>(FontScaleController.new);
