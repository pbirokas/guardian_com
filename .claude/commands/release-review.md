# Release-Review — Nachträgliches Review aller gemergten Änderungen

Prüft **alles, was seit dem letzten geprüften Stand auf `main` gelandet ist** — typischerweise mehrere PRs aus verschiedenen Sessions — auf Fehler und Sicherheitslücken, vor allem im **Zusammenspiel** der Änderungen. Gegenstück zu `/ship`: `/ship` prüft nicht committete Arbeit direkt nach einer Implementierung; `/release-review` prüft bereits gemergte Arbeit, z. B. während ein Release im Store geprüft wird.

**Nichts wird ohne Rückfrage geändert, gepusht oder am Server angefasst.** Das Review selbst ist rein lesend.

Argument (optional): Basis des Reviews — ein Tag (`v2.0.0+141`, `reviewed-167`), ein Commit oder eine Build-Nummer (`141`). Ohne Argument wird die Basis automatisch bestimmt (Schritt 1).

---

## Schritt 1 — Basis und Umfang bestimmen

1. `git fetch origin` und sicherstellen, dass gegen **`origin/main`** geprüft wird (nicht gegen einen lokalen, evtl. veralteten Stand). Lokale, nicht committete Änderungen sind nicht Teil des Reviews.
2. Basis bestimmen, in dieser Reihenfolge:
   - Argument angegeben → verwenden. Eine reine Zahl ist eine **Build-Nummer** = Anzahl der Commits (`git rev-list --count <commit>`, dieselbe Regel wie der Android-`versionCode`). Den passenden Commit so finden:
     ```bash
     for c in $(git rev-list origin/main); do [ "$(git rev-list --count $c)" = "141" ] && { echo $c; break; }; done
     ```
   - Sonst den neuesten Tag `reviewed-*` (Marke des letzten abgeschlossenen Reviews): `git tag --list 'reviewed-*' --sort=-creatordate | head -1`
   - Gibt es keinen, den neuesten Release-Tag `v*` nehmen und den Nutzer kurz bestätigen lassen, dass das die richtige Basis ist.
3. Ziel = `origin/main`. Ausgeben:
   - Basis und Ziel mit Build-Nummern (`git rev-list --count`)
   - gemergte PRs dazwischen: `git log --merges --oneline BASE..origin/main` (PR-Nummern als `pbirokas/guardian_com#N`)
   - Umfang: `git diff --stat BASE..origin/main` (Dateien, Zeilen)
4. Ist der Diff leer → melden und beenden.

---

## Schritt 2 — Änderungen nach Bereichen gliedern

Die geänderten Dateien in Bereiche einteilen, damit jeder Prüfer einen überschaubaren, zusammenhängenden Teil bekommt:

| Bereich | Pfade |
|---|---|
| **Server-Functions** | `appwrite/functions/**` |
| **Berechtigungen & Migrationen** | `appwrite/*.js` (u. a. `fix-permissions.js`, `harden-*.js`, `lock-own-docs.js`, `setup.js`, `deploy-*.js`), `docs/security/**` |
| **App: Services & Daten** | `guardian_app/lib/core/**` |
| **App: Oberfläche** | `guardian_app/lib/features/**`, `guardian_app/lib/l10n/*.arb`, `guardian_app/web/**` |
| **Sonstiges** | Doku, Konfiguration, Tests |

Sehr kleine Bereiche zusammenlegen; sehr große (> ~1500 geänderte Zeilen) nach Unterordnern teilen.

---

## Schritt 3 — Parallel prüfen

Für jeden Bereich **einen eigenen Review-Agenten parallel** starten (Agent-Tool, `subagent_type: general-purpose`), dazu **einen Querschnitts-Agenten für Sicherheit**. Jeder Agent bekommt im Prompt:
- Basis- und Ziel-Commit (SHA) und seine Pfade; er liest den Diff selbst mit `git diff BASE..TARGET -- <pfade>` und den Code im Ziel-Stand mit `git show TARGET:<datei>` (nicht das lokale Arbeitsverzeichnis — das kann abweichen).
- Den Auftrag, **nur echte Probleme** zu melden, jeweils mit Datei:Zeile, konkretem Fehlerszenario (Eingabe/Zustand → falsches Ergebnis) und Konfidenz 1–10. Keine Stilfragen, keine Spekulation ohne Szenario.
- Die Projektregeln aus `CLAUDE.md` als Prüfmaßstab, insbesondere:
  - Collection-Rechte höchstens `create("users")`; jeder Schreibpfad auf ein fremdes Dokument braucht Doc-ACL oder Function.
  - `users`/`members` für Clients nur lesbar; eigene Felder nur über `self-service` (Feld-Whitelist); fremde `users`-Docs liest der Client nie.
  - Conversations schreibt der Client nie direkt (`conversation-action`); neue Nachrichten-Arten mit `_msgPerms(convId)`.
  - Functions: Rolle **live** aus dem Member-Doc prüfen, Aufrufer über `x-appwrite-user-id`, Endpoint `http://`→`https://`, Body als String parsen.
  - App: nur `executeRaw` (nie `createExecution`), `statusCode` prüfen; kein `dart:io` in gemeinsamem Code, immer zuerst `kIsWeb`; ARB in DE **und** EN.
  - Indexe für jedes gefilterte/sortierte Attribut in `setup.js`.

Zusätzliche Schwerpunkte:
- **Sicherheits-Agent:** Rechteausweitung (Kind → Eltern/Admin, Mitglied → Aufsicht, fremde Org), Datenabfluss (E-Mails, `isChild`, Eltern-Links, `fcmToken`, fremde Chats), Functions ohne/mit falscher Rollenprüfung, IDOR (fremde IDs im Request-Body), Löschpfade (fremde Daten/Dateien mitgelöscht?), Migrationsskripte ohne Dry-Run/Rollback, Secrets im Code.
- **Server-Functions:** Fehlerfälle (nicht vorhandene Docs, Teil-Fehler mitten in Schleifen), Idempotenz, Pagination (> 25/100 Docs), Timeouts, Event-Rekursion (Function löst ihr eigenes Event aus).
- **App:** Verhalten mit alten Server-/Datenständen (fehlende Felder, alte Apps parallel), Fehleranzeige statt stillem Scheitern, Web vs. Android.
- **Querschnitt:** Passen App und Function zusammen (Feldnamen, Aktionsnamen, Antwortformat)? Widersprechen sich Änderungen aus verschiedenen PRs?

---

## Schritt 4 — Befunde prüfen

Jeden gemeldeten Befund mit Konfidenz ≥ 6 **selbst im Code nachvollziehen** (im Ziel-Stand). Verwerfen, was sich nicht bestätigt; Duplikate zusammenlegen. Für jeden bestätigten Befund festhalten:
- Schwere: 🔴 kritisch (Sicherheit/Datenverlust) · 🟠 hoch (Funktion kaputt) · 🟡 mittel · ⚪ niedrig
- ob ein **App-Release** nötig ist oder ein **reiner Server-Fix** (Function/Migration) reicht
- ob der Befund **schon live** ist (Function deployt, Migration gelaufen, Build im Store)

---

## Schritt 5 — Bericht

Befunde nach Schwere sortiert ausgeben (Tabelle: Schwere · Datei:Zeile · Problem · Szenario · Release/Server · live?), danach:
- welche Bereiche ohne Befund geprüft wurden
- was **nicht** geprüft werden konnte (z. B. Live-Konfiguration am Server, Verhalten auf echten Geräten)

Dann den Nutzer fragen, welche Befunde behoben werden sollen. **Nicht von selbst fixen.**

---

## Schritt 6 — Fixes (nur nach Freigabe)

- Eigenen Branch von `origin/main` anlegen: `fix/release-review-<Ziel-Build>`.
- Freigegebene Befunde beheben; pro Befund ein nachvollziehbarer Commit (`Fix: …`, deutsch, mit der aktuellen Co-Authored-By-Zeile aus den Systemhinweisen).
- Je nach Änderung: `flutter analyze`, `flutter test`, `flutter build web --release --no-wasm-dry-run`, `node appwrite/test-functions-mock.cjs`.
- CHANGELOG ergänzen (Nutzerperspektive); CLAUDE.md nur bei neuen Regeln.
- Pushen und PR gegen `main` erst nach Freigabe. **Nichts am Live-Server deployen oder migrieren** — dafür Befehle und Reihenfolge nennen (`deploy-functions.js --only=…`, Dry-Run zuerst).

---

## Schritt 7 — Review-Stand markieren

Wenn der Nutzer das Review als abgeschlossen bestätigt (mit oder ohne Fixes), den geprüften Ziel-Commit markieren, damit der nächste `/release-review` dort ansetzt:
```bash
git tag reviewed-<Ziel-Build> <Ziel-SHA>
git push origin reviewed-<Ziel-Build>
```
Den Tag-Push vorher bestätigen lassen.

---

## Abschlussbericht

```
✅ Release-Review abgeschlossen
- Bereich: <Basis> (Build X) → origin/main (Build Y), N PRs, M Dateien
- Befunde: 🔴 a · 🟠 b · 🟡 c · ⚪ d (verworfen: e)
- Fixes: <PR-Link / keine / offen>
- Markiert: reviewed-<Y> [✅ / offen]
- Nicht geprüft: <…>
```
