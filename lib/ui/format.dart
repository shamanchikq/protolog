/// UI-side entry point for the shared display formatters. The helpers live
/// in the pure-Dart `lib/format.dart` so `engine/` can use them without
/// importing from the UI layer; widgets keep importing this file.
library;

export '../format.dart';
