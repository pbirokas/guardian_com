/// Leitet die Avatar-Initiale ab: erster Buchstabe von [primary] (als
/// Großbuchstabe), sonst von [secondary] (z. B. E-Mail), sonst `'?'`.
/// Ersetzt das an vielen Stellen duplizierte
/// `(name.isNotEmpty ? name[0] : '?').toUpperCase()`.
String initialsFor(String? primary, [String? secondary]) {
  final p = primary?.trim() ?? '';
  if (p.isNotEmpty) return p[0].toUpperCase();
  final s = secondary?.trim() ?? '';
  if (s.isNotEmpty) return s[0].toUpperCase();
  return '?';
}
