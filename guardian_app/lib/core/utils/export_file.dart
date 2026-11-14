/// Gibt eine erzeugte Datei (CSV, ICS …) an den Nutzer weiter:
/// nativ als Temp-Datei, die mit der Standard-App geöffnet wird; im Web als
/// Browser-Download.
library;

export 'export_file_web.dart' if (dart.library.io) 'export_file_io.dart';
