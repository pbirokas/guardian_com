const { Client, Functions, Query } = require('node-appwrite');
const https = require('https');

function brevoSend({ apiKey, to, subject, html }) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      sender: { name: 'Guardian Com', email: 'savespacedev@gmail.com' },
      to: [{ email: to }],
      subject,
      htmlContent: html,
    });
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

    const sampleQueries = [
      Query.equal('status', 'failed'),
      Query.greaterThan('$createdAt', since),
      Query.limit(3),
    ];

    const checkFn = async (fn) => {
      log(`Checking function: ${fn.name}`);
      const execs = await functions.listExecutions(fn.$id, sampleQueries);
      if (execs.total === 0) return null;
      return {
        name: fn.name,
        failCount: execs.total,
        samples: execs.executions.map(exec => ({
          id: exec.$id,
          trigger: exec.trigger,
          duration: exec.duration,
          errors: (exec.errors || '').substring(0, 200),
        })),
      };
    };

    const checkResults = await Promise.all(allFunctions.map(checkFn));
    const results = checkResults.filter(Boolean);

    if (results.length === 0) {
      log('No function errors in the last 24h — no email sent');
      return res.empty();
    }

    const rows = results.map(r => {
      const sampleHtml = r.samples.map(s =>
        `<tr style="font-size:12px;color:#555">
          <td style="padding:2px 8px">${escapeHtml(s.id)}</td>
          <td style="padding:2px 8px">${escapeHtml(s.trigger)}</td>
          <td style="padding:2px 8px">${escapeHtml(s.duration)}s</td>
          <td style="padding:2px 8px;font-family:monospace">${escapeHtml(s.errors)}</td>
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

    const html = `
      <h2 style="color:#2c3e50">Guardian Com — Täglicher Funktionsfehler-Report</h2>
      <p>Zeitraum: letzte 24 Stunden (bis ${new Date().toISOString()})</p>
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
    });

    log(`Error report sent to ${reportEmail}: ${results.map(r => `${r.name}(${r.failCount})`).join(', ')}`);
    return res.empty();
  } catch (e) {
    error(`daily-error-report failed: ${e.message}`);
    return res.empty();
  }
};
