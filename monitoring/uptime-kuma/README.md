# Uptime Kuma: Server-Monitoring

Überwacht den Appwrite-Server `appwrite.guardian-com.de` (204.168.196.27) vom Pi-Hole im Heimnetz aus und meldet Probleme per Telegram.

Anlass war der Ausfall am 10.10.2026: Das Let's-Encrypt-Zertifikat lief ab, weil der Appwrite-Certificates-Worker die Verlängerung still übersprungen hat. Die wichtigste Prüfung ist deshalb die **Zertifikats-Restlaufzeit**.

## 1. Installation auf dem Pi

```bash
# Docker installieren (falls noch nicht vorhanden)
docker --version || curl -fsSL https://get.docker.com | sh

# Diesen Ordner auf den Pi kopieren, z. B. nach ~/uptime-kuma, dann:
cd ~/uptime-kuma
docker compose up -d
```

Danach `http://<pi-ip>:3001` öffnen. Beim ersten Start fragt Kuma v2 nach der Datenbank: **SQLite** wählen. Anschließend ein Admin-Konto anlegen.

**SD-Karte schonen:** Unter *Settings → Monitor History* die Aufbewahrung auf 30 Tage setzen.

## 2. Telegram-Bot

1. In Telegram **@BotFather** öffnen, `/newbot` senden, Namen vergeben und den **Bot-Token** kopieren.
2. Dem neuen Bot einmal eine beliebige Nachricht schicken (sonst darf er dir nicht schreiben).
3. In Kuma: *Settings → Notifications → Setup Notification*
   - Notification Type: **Telegram**
   - Bot Token: einfügen
   - Chat ID: Button **Auto Get** drücken
   - ✅ *Default enabled* und ✅ *Apply on all existing monitors*
   - **Test** drücken, dann speichern.

## 3. Ablaufwarnung für das Zertifikat

*Settings → Notifications → TLS Certificate Expiry*: Tage auf **`25, 14, 7`** setzen.

Appwrite verlängert ungefähr 30 Tage vor Ablauf. Hat das Zertifikat weniger als 25 Tage Restlaufzeit, hängt die Verlängerung. In dem Fall auf dem Server ausführen:

```bash
cd ~/appwrite && docker compose exec appwrite ssl --domain="appwrite.guardian-com.de"
```

## 4. API-Key für die Health-Checks

In der Appwrite-Console im Projekt unter *Overview → Integrations → API Keys → Create API Key*:

- Name: `uptime-kuma`
- Scopes: **nur `health.read`**
- Ablauf: nach Wunsch (bei Ablauf schlagen die Health-Monitore mit 401 an)

In Kuma bei den Monitoren 7–14 unter *Headers* eintragen:

```json
{"X-Appwrite-Project": "6a02e4160023948ef257", "X-Appwrite-Key": "<API-KEY>"}
```

## 5. Monitore

Für jeden Monitor: *Add New Monitor*. Retries jeweils **2**, damit ein einzelner Aussetzer keinen Alarm auslöst.

### Erreichbarkeit (ohne API-Key)

| # | Name | Typ | Ziel | Weitere Einstellungen | Intervall |
|---|------|-----|------|-----------------------|-----------|
| 1 | **HTTPS – Appwrite API** | HTTP(s) - Keyword | `https://appwrite.guardian-com.de/v1/health/version` | Keyword: `version` · ✅ *Certificate Expiry Notification* · ❌ *Ignore TLS Error* | 60 s |
| 2 | **HTTP – Port 80 / ACME** | HTTP(s) - Keyword | `http://appwrite.guardian-com.de/.well-known/acme-challenge/kuma-check` | Accepted Status Codes: **nur `404`** · Keyword: `appwrite-icon` | 300 s |
| 3 | **SSH** | TCP Port | `204.168.196.27` · Port `22` | – | 300 s |
| 4 | **Ping** | Ping | `204.168.196.27` | – | 120 s |
| 5 | **DNS** | DNS | `appwrite.guardian-com.de` | Resolver: `1.1.1.1` · Record Type: `A` | 3600 s |
| 6 | **Realtime (WebSocket)** | HTTP(s) - Keyword | `https://appwrite.guardian-com.de/v1/realtime?project=6a02e4160023948ef257` | Accepted Status Codes: **nur `400`** · Keyword: `Swoole` | 300 s |

Erläuterungen:

- **#1** ist der Hauptcheck und liefert gleichzeitig die Zertifikats-Ablaufwarnung. **Keine Header setzen** (also nicht aus #7–14 klonen): Mit einem `X-Appwrite-Key` antwortet `/health/version` mit 401, weil der Key nur `health.read` hat. Den Haken „Domain-Ablauf“ weglassen, `.de` wird dabei nicht unterstützt.
- **#2** prüft den Pfad, über den Let's Encrypt die Domain validiert. Antwortet dort Appwrite selbst mit 404 (die Seite enthält `appwrite-icon`), funktioniert die Verlängerung von außen. Ein 404 von Traefik oder ein Timeout bedeutet: Die nächste Verlängerung scheitert. Die Startseite `/` eignet sich nicht, sie liefert aktuell einen HTTP 500.
- **#3 und #4** prüfen direkt die IP, damit sie auch bei DNS-Problemen aussagekräftig bleiben. fail2ban sperrt reine TCP-Verbindungen ohne Login-Versuch normalerweise nicht. Sollte der Pi trotzdem gesperrt werden, auf dem Server die Heim-IP in `/etc/fail2ban/jail.local` unter `ignoreip` eintragen.
- **#5** fragt bewusst nicht den Pi-Hole selbst, sondern 1.1.1.1. Sonst würde man nur dessen Cache prüfen.
- **#6:** Ein normaler GET auf den Realtime-Endpunkt wird vom Swoole-WebSocket-Server mit 400 beantwortet. Das zeigt, dass der Realtime-Container läuft (Chat-Live-Updates). Fällt er aus, antwortet Traefik mit 502 oder 404.

### Appwrite-Interna (mit API-Key-Header)

| # | Name | URL (`https://appwrite.guardian-com.de/v1/…`) | Prüft | Intervall |
|---|------|------------------------------------------------|-------|-----------|
| 7 | **Health – Gesamt** | `health` | Appwrite-HTTP-Server | 300 s |
| 8 | **Health – Datenbank** | `health/db` | MongoDB | 300 s |
| 9 | **Health – Cache** | `health/cache` | Redis | 300 s |
| 10 | **Health – PubSub** | `health/pubsub` | Redis PubSub (Realtime-Verteilung) | 300 s |
| 11 | **Health – Storage** | `health/storage/local` | Schreibzugriff auf Storage | 600 s |
| 12 | **Health – Uhrzeit** | `health/time` | Uhrzeit-Abweichung des Servers (relevant für Sessions/TLS) | 3600 s |
| 13 | **Queue – Functions** | `health/queue/functions?threshold=100` | Stau bei Functions (Push-Nachrichten, mark-as-read, Sync-Functions) | 300 s |
| 14 | **Queue – Zertifikate** | `health/queue/certificates?threshold=10` | Stau bei Zertifikats-Jobs | 3600 s |

Typ jeweils **HTTP(s)**, Methode `GET`, Header wie in Abschnitt 4. Die Queue-Endpunkte liefern einen Fehlerstatus, sobald mehr als `threshold` Jobs warten. Kuma meldet den Monitor dann als DOWN.

## 6. Grenzen

- **Den Pi selbst überwacht niemand.** Ist der Pi aus, kommen auch keine Alarme. Ab und zu einen Blick ins Kuma-Dashboard werfen.
- Die „skipped“-Logzeilen des Certificates-Workers sieht Kuma nicht. Die 25-Tage-Warnung ist das Sicherheitsnetz dafür.
- Freier Speicherplatz und Container-Status auf dem Server werden nicht direkt geprüft. Ausfälle zeigen sich indirekt über die Health-Monitore.
