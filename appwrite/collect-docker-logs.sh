#!/usr/bin/env bash
# Sammelt Docker-Logs + Kennzahlen des Appwrite-Servers rund um die mark-as-read-
# Hänger vom 2026-11-13 in ein Archiv. Liest nur, ändert nichts.
#
# Aufruf auf dem Server (im Verzeichnis mit der docker-compose.yml):
#   bash collect-docker-logs.sh
# Ergebnis: ./appwrite-diag-<zeitstempel>.tar.gz
#
# Vor dem Weitergeben kurz reinschauen: Logs können Nutzer-IDs, IPs und Pfade
# enthalten. Secrets werden nicht ausgelesen (nur ausgewählte, unkritische Env-Vars).
set -u

OUT="appwrite-diag-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$OUT/logs"

# Zeitfenster (UTC) um die Fehler — je ±2-5 min.
WINDOWS=(
  "2026-11-13T08:45:00Z 2026-11-13T09:02:00Z"
  "2026-11-13T09:50:00Z 2026-11-13T09:56:00Z"
  "2026-11-13T12:58:00Z 2026-11-13T13:32:00Z"
  "2026-11-13T16:22:00Z 2026-11-13T16:30:00Z"
  "2026-11-13T16:45:00Z 2026-11-13T17:02:00Z"
  "2026-11-13T17:28:00Z 2026-11-13T17:36:00Z"
)

# Alle Appwrite-bezogenen Container (Namen je nach Installation leicht verschieden).
CONTAINERS=$(docker ps -a --format '{{.Names}}' | grep -Ei 'appwrite|openruntimes|executor|^exc|traefik|mariadb|mongo|redis' | sort)
echo "$CONTAINERS" > "$OUT/containers.txt"
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.RunningFor}}' > "$OUT/docker-ps.txt"

for c in $CONTAINERS; do
  for w in "${WINDOWS[@]}"; do
    set -- $w
    docker logs --timestamps --since "$1" --until "$2" "$c" \
      >> "$OUT/logs/$c.log" 2>&1
  done
  # Neustarts / OOM-Kills erkennen
  docker inspect --format '{{.Name}} restarts={{.RestartCount}} oom={{.State.OOMKilled}} started={{.State.StartedAt}}' "$c" \
    >> "$OUT/inspect.txt" 2>&1
done
# Leere Logdateien entfernen (Container ohne Ausgabe im Fenster)
find "$OUT/logs" -type f -empty -delete

# Host-Ressourcen
{
  echo "## nproc";  nproc
  echo "## free -m"; free -m
  echo "## uptime"; uptime
  echo "## df -h";  df -h /
  echo "## docker stats (Momentaufnahme)"
  docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}'
} > "$OUT/host.txt" 2>&1

# Kernel: OOM-Killer / Hänger am 13.11.
journalctl -k --since "2026-11-13 00:00" --until "2026-11-14 00:00" --no-pager 2>/dev/null \
  | grep -Ei 'oom|killed process|hung|blocked for' > "$OUT/kernel.txt"

# Nur unkritische Appwrite-Env-Vars (Worker-/Function-Limits), KEINE Secrets.
API=$(echo "$CONTAINERS" | grep -E '^appwrite$' || echo "$CONTAINERS" | grep -m1 -E 'appwrite$')
if [ -n "$API" ]; then
  docker exec "$API" printenv 2>/dev/null \
    | grep -E '^_APP_(VERSION|WORKER_PER_CORE|FUNCTIONS_(TIMEOUT|BUILD_TIMEOUT|CPUS|MEMORY|INACTIVE_THRESHOLD|MAINTENANCE_INTERVAL|RUNTIMES_NETWORK)|COMPUTE_.*|EXECUTOR_HOST|DB_HOST|REDIS_HOST|POOL_.*|CONNECTIONS_.*)=' \
    > "$OUT/appwrite-env.txt"
fi

# MariaDB: Verbindungs-/Lock-Kennzahlen (Passwort bleibt im Container).
DB=$(echo "$CONTAINERS" | grep -m1 -i mariadb)
if [ -n "$DB" ]; then
  docker exec "$DB" sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
    SHOW VARIABLES WHERE Variable_name IN (\"max_connections\",\"slow_query_log\",\"long_query_time\",\"innodb_buffer_pool_size\",\"innodb_lock_wait_timeout\",\"wait_timeout\");
    SHOW GLOBAL STATUS WHERE Variable_name IN (\"Uptime\",\"Threads_connected\",\"Max_used_connections\",\"Aborted_connects\",\"Innodb_row_lock_waits\",\"Innodb_row_lock_time_max\",\"Slow_queries\");"' \
    > "$OUT/mariadb.txt" 2>&1
fi

tar czf "$OUT.tar.gz" "$OUT" && rm -rf "$OUT"
echo "Fertig: $(pwd)/$OUT.tar.gz ($(du -h "$OUT.tar.gz" | cut -f1))"
