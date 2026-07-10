const { Client, Functions, Query } = require('node-appwrite');
const https = require('https');

function brevoSend({ apiKey, to, subject, html, attachment }) {
  return new Promise((resolve, reject) => {
    const payload = {
      sender: { name: 'Guardian Com', email: 'savespacedev@gmail.com' },
      to: [{ email: to }],
      subject,
      htmlContent: html,
    };
    // attachment: [{ name, content(base64) }]
    if (attachment && attachment.length) payload.attachment = attachment;
    const body = JSON.stringify(payload);
    const req = https.request({
      hostname: 'api.brevo.com',
      path: '/v3/smtp/email',
      method: 'POST',
      headers: {
        'api-key': apiKey,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
      },
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) resolve(data);
        else reject(new Error(`Brevo ${res.statusCode}: ${data}`));
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

function escapeHtml(str) {
  return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// RFC-4180-CSV-Feld: bei Komma/Anführungszeichen/Zeilenumbruch in Quotes setzen
// und enthaltene Quotes verdoppeln.
function csvEscape(value) {
  const s = String(value ?? '');
  return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

module.exports = async ({ req, res, log, error }) => {
  const reportEmail = process.env.ERROR_REPORT_EMAIL;
  const brevoApiKey = process.env.BREVO_API_KEY;

  if (!reportEmail || !brevoApiKey) {
    error('ERROR_REPORT_EMAIL or BREVO_API_KEY not set');
    return res.empty();
  }

  try {
    const client = new Client()
      .setEndpoint(process.env.APPWRITE_ENDPOINT)
      .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
      .setKey(process.env.APPWRITE_API_KEY);

    const functions = new Functions(client);
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

    // Paginated function list
    const allFunctions = [];
    let fnCursor = null;
    do {
      const q = [Query.limit(100)];
      if (fnCursor) q.push(Query.cursorAfter(fnCursor));
      const page = await functions.list(q);
      allFunctions.push(...page.functions);
      fnCursor = page.functions.length === 100 ? page.functions[page.functions.length - 1].$id : null;
    } while (fnCursor);

    log(`Checking ${allFunctions.length} functions for errors since ${since}`);

    // Alle fehlgeschlagenen Executions einer Funktion holen (paginiert, gedeckelt).
    // Damit lässt sich sowohl die HTML-Zusammenfassung (3 Samples) als auch der
    // vollständige CSV-Anhang bauen.
    const PAGE = 100;
    const MAX_ROWS_PER_FN = 1000;
    const fetchFailed = async (fn) => {
      log(`Checking function: ${fn.name}`);
      const rows = [];
      let total = 0;
      let cursor = null;
      do {
        const q = [
          Query.equal('status', 'failed'),
          Query.greaterThan('$createdAt', since),
          Query.limit(PAGE),
        ];
        if (cursor) q.push(Query.cursorAfter(cursor));
        const page = await functions.listExecutions(fn.$id, q);
        total = page.total;
        rows.push(...page.executions);
        cursor = (page.executions.length === PAGE && rows.length < MAX_ROWS_PER_FN)
          ? page.executions[page.executions.length - 1].$id
          : null;
      } while (cursor);
      if (total === 0) return null;
      return { name: fn.name, failCount: total, rows };
    };

    const checkResults = await Promise.all(allFunctions.map(fetchFailed));
    const results = checkResults.filter(Boolean);

    if (results.length === 0) {
      log('No function errors in the last 24h — no email sent');
      return res.empty();
    }

    const rows = results.map(r => {
      const sampleHtml = r.rows.slice(0, 3).map(s =>
        `<tr style="font-size:12px;color:#555">
          <td style="padding:2px 8px">${escapeHtml(s.$id)}</td>
          <td style="padding:2px 8px">${escapeHtml(s.trigger)}</td>
          <td style="padding:2px 8px">${escapeHtml(s.duration)}s</td>
          <td style="padding:2px 8px;font-family:monospace">${escapeHtml((s.errors || '').substring(0, 200))}</td>
        </tr>`
      ).join('');
      return `
        <tr>
          <td style="padding:8px;font-weight:bold">${escapeHtml(r.name)}</td>
          <td style="padding:8px;color:#c0392b;font-weight:bold">${r.failCount}</td>
        </tr>
        <tr><td colspan="2">
          <table style="width:100%;border-collapse:collapse;margin-bottom:12px">
            <tr style="background:#f5f5f5;font-size:11px">
              <th style="padding:2px 8px;text-align:left">Execution ID</th>
              <th style="padding:2px 8px;text-align:left">Trigger</th>
              <th style="padding:2px 8px;text-align:left">Dauer</th>
              <th style="padding:2px 8px;text-align:left">Fehler (Auszug)</th>
            </tr>
            ${sampleHtml}
          </table>
        </td></tr>`;
    }).join('');

    const totalErrors = results.reduce((sum, r) => sum + r.failCount, 0);

    // Vollständige Fehlerliste als CSV-Anhang (UTF-8 mit BOM für Excel-Umlaute).
    // Gedeckelt (Zeilen + Fehlerlänge), damit der Anhang Brevos Nachrichten-
    // Größenlimit nicht sprengt — sonst käme der Report gar nicht mehr an.
    const MAX_CSV_ROWS = 5000;
    const MAX_ERR_LEN = 500;
    const csvHeader = 'function,executionId,trigger,createdAt,durationSec,status,error';
    const allCsvLines = results.flatMap(r =>
      r.rows.map(e => [
        r.name,
        e.$id,
        e.trigger,
        e.$createdAt,
        e.duration,
        e.status,
        (e.errors || '').replace(/\r?\n/g, ' ').slice(0, MAX_ERR_LEN),
      ].map(csvEscape).join(','))
    );
    const csvLines = allCsvLines.slice(0, MAX_CSV_ROWS);
    if (allCsvLines.length > MAX_CSV_ROWS) {
      log(`CSV auf ${MAX_CSV_ROWS} von ${allCsvLines.length} Zeilen gekürzt`);
    }
    const csv = '﻿' + [csvHeader, ...csvLines].join('\r\n') + '\r\n';
    const dateStr = new Date().toISOString().slice(0, 10);
    const csvName = `funktionsfehler-${dateStr}.csv`;

    const html = `
      <h2 style="color:#2c3e50">Guardian Com — Täglicher Funktionsfehler-Report</h2>
      <p>Zeitraum: letzte 24 Stunden (bis ${new Date().toISOString()})</p>
      <p>Insgesamt <b>${totalErrors}</b> Fehler in <b>${results.length}</b> Funktion(en). Die vollständige Liste befindet sich im CSV-Anhang (<code>${escapeHtml(csvName)}</code>).</p>
      <table style="border-collapse:collapse;width:100%">
        <tr style="background:#ecf0f1">
          <th style="padding:8px;text-align:left">Funktion</th>
          <th style="padding:8px;text-align:left">Fehler</th>
        </tr>
        ${rows}
      </table>
      <p style="color:#888;font-size:12px">Guardian Com Appwrite – automatischer Report</p>`;

    await brevoSend({
      apiKey: brevoApiKey,
      to: reportEmail,
      subject: `[Guardian Com] ${results.length} Funktion(en) mit Fehlern – ${new Date().toLocaleDateString('de-DE')}`,
      html,
      attachment: [{
        name: csvName,
        content: Buffer.from(csv, 'utf8').toString('base64'),
      }],
    });

    log(`Error report sent to ${reportEmail} (${totalErrors} errors, CSV attached): ${results.map(r => `${r.name}(${r.failCount})`).join(', ')}`);
    return res.empty();
  } catch (e) {
    error(`daily-error-report failed: ${e.message}`);
    return res.empty();
  }
};
