# Web-App: `Cache-Control` über Traefik setzen

**Problem (2026-11-26):** Die Appwrite Site `app.guardian-com.de` liefert alle Dateien **ohne** `Cache-Control`-Header aus (nur `Last-Modified`). Browser cachen `index.html`, `flutter_bootstrap.js` und `main.dart.js` dann nach eigener Faustregel (ca. 10 % der Zeit seit der letzten Änderung, also oft Stunden bis Tage). Folge: Nach einem Deploy läuft im Browser noch der alte Code, während „Über die App“ schon die neue Build-Nummer zeigt (die wird live aus `version.json` gelesen). Aufgefallen beim Einladen mit Build 167: Der Browser nutzte noch den alten Client-Pfad.

**Lösung:** Traefik (der Reverse-Proxy vor Appwrite) setzt für `app.guardian-com.de` auf **alle** Antworten `Cache-Control: no-cache`. `no-cache` heißt *nicht* „nie cachen“, sondern „vor jeder Nutzung beim Server nachfragen“. Unveränderte Dateien kommen als kurzes `304 Not Modified` zurück, nur nach einem Deploy wird neu geladen. Mehrkosten: eine kleine Anfrage pro Datei beim Laden der App.

Betrifft nur die Web-App-Domain; API (`appwrite.guardian-com.de`) und Console bleiben unberührt.

## 0. Vorher prüfen (Server, als der Nutzer mit `~/appwrite`)

```bash
cd ~/appwrite
# Ist-Zustand: sollte KEINE cache-control-Zeile zeigen
curl -sI https://app.guardian-com.de/main.dart.js | grep -i cache-control

# Namen von Entrypoints/Service/Routern im aktuellen Compose nachsehen
docker compose config | grep -E 'traefik\.(http\.(routers|services)\.appwrite_api|entrypoints)|entrypoints\.' | sort -u
```

Erwartet (Appwrite 1.9.x Standard): Entrypoints `appwrite_web` (:80) und `appwrite_websecure` (:443), Service `appwrite_api` (Port 80), Router `appwrite_api_http` / `appwrite_api_https` mit `PathPrefix(`/`)`. **Weichen die Namen ab, unten entsprechend anpassen.**

Backup der Override-Datei:

```bash
cp docker-compose.override.yml docker-compose.override.yml.$(date +%F).bak
```

## 1. Labels in `~/appwrite/docker-compose.override.yml` ergänzen

Eigene Anpassungen gehören in die Override-Datei, weil der Appwrite-Installer `docker-compose.yml` bei Upgrades komplett neu schreibt. In der Override-Datei gibt es schon einen Block `services: appwrite:` (mindestens mit `restart: unless-stopped`). Dort `labels:` ergänzen. Falls `appwrite:` schon `labels:` hat, die Zeilen dort anhängen.

```yaml
services:
  appwrite:
    # restart: unless-stopped   ← bestehende Zeilen unverändert lassen
    labels:
      # Header-Middleware: Browser fragen vor jeder Nutzung nach (304 wenn unverändert)
      - "traefik.http.middlewares.webapp-nocache.headers.customresponseheaders.Cache-Control=no-cache"
      # Eigene Router NUR für die Web-App-Domain. Host()-Regel ist länger als
      # PathPrefix(`/`) → Traefik gibt ihr automatisch Vorrang vor appwrite_api_*.
      - "traefik.http.routers.webapp_http.rule=Host(`app.guardian-com.de`)"
      - "traefik.http.routers.webapp_http.entrypoints=appwrite_web"
      - "traefik.http.routers.webapp_http.service=appwrite_api"
      - "traefik.http.routers.webapp_https.rule=Host(`app.guardian-com.de`)"
      - "traefik.http.routers.webapp_https.entrypoints=appwrite_websecure"
      - "traefik.http.routers.webapp_https.service=appwrite_api"
      - "traefik.http.routers.webapp_https.tls=true"
      - "traefik.http.routers.webapp_https.middlewares=webapp-nocache"
```

Hinweise:
- Der HTTP-Router (`webapp_http`) bekommt bewusst **keine** Middleware und leitet wie bisher an Appwrite weiter. So bleiben die HTTP→HTTPS-Umleitung und die Let's-Encrypt-Prüfung (`/.well-known/acme-challenge`) für die Domain unverändert in Appwrites Hand.
- `tls=true` ohne `certresolver`: Traefik nimmt das Zertifikat, das Appwrite für die Domain ausgestellt hat (Datei-Provider `/storage/config`). Am Zertifikat ändert sich nichts.

Syntax prüfen, **bevor** etwas neu gestartet wird:

```bash
docker compose config --quiet && echo "Compose OK"
docker compose config | grep -A12 'webapp'   # die neuen Labels müssen auftauchen
```

## 2. Übernehmen

Labels wirken erst, wenn der Container neu erstellt wird. Das bedeutet **ein paar Sekunden API-Ausfall**; laufende Uploads und Function-Aufrufe können abbrechen. Am besten zu einer ruhigen Zeit.

```bash
docker compose up -d appwrite
docker compose ps appwrite        # Status "running"/"healthy"
```

Nur `appwrite` wird neu erstellt; Traefik liest die Labels über den Docker-Provider selbst neu ein.

## 3. Prüfen

```bash
# Web-App: jetzt mit no-cache
curl -sI https://app.guardian-com.de/            | grep -iE '^HTTP|cache-control'
curl -sI https://app.guardian-com.de/main.dart.js | grep -iE '^HTTP|cache-control'
# Revalidierung funktioniert: zweite Anfrage mit If-Modified-Since → 304
LM=$(curl -sI https://app.guardian-com.de/main.dart.js | grep -i last-modified | cut -d' ' -f2- | tr -d '\r')
curl -sI -H "If-Modified-Since: $LM" https://app.guardian-com.de/main.dart.js | head -1   # HTTP/… 304
# HTTP → HTTPS-Umleitung wie bisher
curl -sI http://app.guardian-com.de/ | head -3
# API unverändert (KEIN cache-control von uns)
curl -sI https://appwrite.guardian-com.de/v1/health/version | grep -iE '^HTTP|cache-control'
```

Erwartet: `cache-control: no-cache` bei den ersten beiden, `304` beim dritten, Umleitung (301/308) beim vierten, `200` ohne unseren Header bei der API. Danach die Web-App im Browser öffnen, einloggen, einen Chat öffnen (Realtime läuft über die API-Domain, ist also nicht betroffen).

Bestehende Browser-Caches leeren sich dadurch **nicht rückwirkend**. Wer die alte Version noch gecacht hat, lädt einmal hart neu (Strg+F5). Auf dem iPhone reicht spätestens der nächste Ablauf der Faustregel. Ab dem nächsten Deploy greift es für alle.

## Rollback

```bash
cd ~/appwrite
cp docker-compose.override.yml.<datum>.bak docker-compose.override.yml
docker compose up -d appwrite
```

## Nach Appwrite-Upgrades

Die Override-Datei bleibt erhalten. Trotzdem nach jedem Upgrade Schritt 0 (Namen der Entrypoints/Service) und Schritt 3 erneut ausführen: Benennt Appwrite `appwrite_api`/`appwrite_web*` um, zeigen die Labels ins Leere. Ein Router auf einen nicht existierenden Service lässt Traefik die Domain mit 404 beantworten.
