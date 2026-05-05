# Ship — Post-Implementierung Checkliste

Führe nach einer abgeschlossenen Implementierung automatisch folgende Schritte durch. **Halte die Reihenfolge ein.** Breche ab und berichte, wenn ein Schritt fehlschlägt.

---

## Schritt 1 — Code-Qualität & Vereinfachung

Führe den `/simplify`-Skill aus:
- Starte drei parallele Review-Agenten (Reuse, Quality, Efficiency) mit dem aktuellen `git diff HEAD`
- Warte bis alle drei fertig sind
- Behebe alle Findings mit Konfidenz ≥ 8/10
- Baue die App danach (`flutter build apk --debug` aus `guardian_app/`) um sicherzustellen, dass alles kompiliert

---

## Schritt 2 — Sicherheitsprüfung

Führe den `/security-review`-Skill aus:
- Analysiere alle geänderten Dateien auf Sicherheitslücken
- Behebe alle HIGH-Findings sofort, MEDIUM-Findings nach Rücksprache
- Falls kritische Sicherheitslücken gefunden werden: **stoppe und berichte** — fahre nicht mit Schritt 3 fort

---

## Schritt 3 — Dokumentation aktualisieren

Ermittle zuerst was geändert wurde (`git diff HEAD`) und heute's Datum.

### CHANGELOG.md
- Füge einen neuen Abschnitt am Anfang der Datei ein (unter dem Titel, vor dem letzten Eintrag)
- Format:
  ```
  ## YYYY-MM-DD

  - Beschreibung der Änderung 1
  - Beschreibung der Änderung 2
  ```
- Formuliere die Punkte aus **Nutzerperspektive** (was sich verändert hat, nicht technische Details)
- Zusammenfassen: Mehrere kleine Fixes zu einem Punkt wenn sinnvoll

### README.md
- Aktualisiere nur wenn neue Features hinzugekommen sind oder sich bestehende Features wesentlich geändert haben
- Keine Änderung bei reinen Bug-Fixes oder internen Refactorings

### CLAUDE.md
- Aktualisiere nur wenn:
  - Neue Architektur-Muster oder Konventionen eingeführt wurden
  - Neue Befehle oder Tools hinzugekommen sind
  - Sich der Projektaufbau wesentlich geändert hat
- Bei normalen Features oder Bug-Fixes: **keine Änderung notwendig**

---

## Schritt 4 — Lokalisierungen prüfen

Falls ARB-Dateien (`app_de.arb`, `app_en.arb`) geändert wurden:
- Führe `flutter gen-l10n` in `guardian_app/` aus
- Stelle sicher, dass die generierten `app_localizations*.dart` Dateien im Diff enthalten sind

Falls Riverpod-Annotationen (`@riverpod`) geändert wurden:
- Führe `dart run build_runner build --delete-conflicting-outputs` in `guardian_app/` aus

---

## Schritt 5 — Git Commit & Push

### Staging
Füge alle geänderten Dateien hinzu. **Nicht** hinzufügen:
- `firebase_options.dart` (enthält API-Keys, ist gitignored)
- Temporäre Build-Dateien

```bash
git add -A
```

Zeige `git status` und prüfe ob unerwartete Dateien im Staging sind.

### Commit-Message
Erstelle eine Commit-Message die:
- Auf Deutsch ist (wie die bisherigen Commits in diesem Repo)
- Das Format `Typ: Kurzbeschreibung` verwendet
- Typen: `Feat:`, `Fix:`, `Refactor:`, `Docs:`, `Style:`
- Bei mehreren Typen den dominanten wählen
- In der Body-Sektion (nach Leerzeile) die wichtigsten Punkte als Liste aufführt
- Mit `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>` endet

Beispiel:
```
Feat: Hilfe-Icon in AppBar & Chat-Übersicht nach Typ sortiert

- Hilfe-Symbol direkt in der AppBar sichtbar (statt im 3-Punkte-Menü)
- Chat-Liste: Gruppen → Einzel-Chats → Überwachte Chats
- Dunkelmodus: Textfarben jetzt theme-aware
- Überwachter Chat bleibt sichtbar wenn Guardian die Gruppe verlässt

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
```

### Push
```bash
git push origin main
```

---

## Abschlussbericht

Gib am Ende eine kurze Zusammenfassung aus:
```
✅ Ship abgeschlossen
- Simplify: [X Findings behoben / Code war sauber]
- Security: [Keine Lücken / X Findings behoben]
- Docs: CHANGELOG ✅ | README [✅/–] | CLAUDE.md [✅/–]
- Commit: [erste Zeile der Commit-Message]
- Push: ✅ origin/main
```
