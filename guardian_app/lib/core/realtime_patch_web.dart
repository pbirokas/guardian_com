// Web-Variante von realtime_patch_io.dart: Im Browser sendet RealtimeBrowser
// die Session-Cookies von appwrite.guardian-com.de selbst mit (gleiche
// Hauptdomain wie app.guardian-com.de → kein Third-Party-Cookie). Kein
// Cookie-Jar, kein Workaround nötig.
import 'package:appwrite/appwrite.dart';

Future<void> cacheRealtimeSessionCookie(Client client) async {}

void clearRealtimeSessionCookie() {}

Realtime createPatchedRealtime(Client client) => Realtime(client);
