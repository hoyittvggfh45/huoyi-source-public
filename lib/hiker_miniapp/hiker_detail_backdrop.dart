String hikerDetailBackdropUrl({
  required List<String> stills,
  required String poster,
}) {
  for (final still in stills) {
    if (still.isNotEmpty) return still;
  }
  return poster;
}

String hikerDetailPosterUrl({
  required List<String> stills,
  required String poster,
}) {
  if (poster.isNotEmpty) return poster;
  for (final still in stills) {
    if (still.isNotEmpty) return still;
  }
  return '';
}
