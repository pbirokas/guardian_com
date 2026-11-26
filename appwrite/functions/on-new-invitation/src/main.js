const { Client, Databases, Query } = require('node-appwrite');
const nodemailer = require('nodemailer');
const { sendToUsers } = require('./fcm');

const DB_ID = 'guardian';

module.exports = async ({ req, res, log, error }) => {
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);

  const invite = req.body;
  if (!invite || !invite.$id) {
    error('No document in payload');
    return res.empty();
  }

  const { email, orgName, role, guardianUids, inviterName } = invite;
  if (!email) {
    error('Missing email in invitation');
    return res.empty();
  }

  // „Registriert“ = es gibt ein users-Doc (Profil) — dieselbe Definition wie
  // admin-member-action/inviteByEmail, das nur dann eine Einladung anlegt.
  // Ein reines Auth-Konto entsteht schon beim Anfordern des Login-Codes
  // (createEmailToken); wer die Anmeldung nie abgeschlossen hat, bekam
  // deshalb bisher keine Mail (2026-11-26).
  let userExists = false;
  try {
    const result = await db.listDocuments(DB_ID, 'users', [Query.equal('email', email), Query.limit(1)]);
    userExists = result.total > 0;
  } catch (err) {
    error(`Failed to check user by email: ${err.message}`);
  }

  // Einladungs-E-Mail an nicht registrierte Nutzer senden
  if (!userExists) {
    const gmailPassword = process.env.GMAIL_APP_PASSWORD;
    if (gmailPassword) {
      const roleLabel = {
        admin: 'Administrator',
        moderator: 'Moderator',
        member: 'Mitglied',
        child: 'Kind',
      }[role] ?? role;

      const inviterLine = inviterName
        ? `<p>${inviterName} hat dich eingeladen.</p>`
        : '';

      const html = `
<!DOCTYPE html>
<html lang="de">
<head><meta charset="UTF-8" /></head>
<body style="font-family:sans-serif;max-width:520px;margin:0 auto;padding:24px;color:#1a1a1a">
  <h2 style="color:#1565C0">Einladung zu Guardian Com</h2>
  ${inviterLine}
  <p>Du wurdest als <strong>${roleLabel}</strong> zur Organisation <strong>${orgName ?? ''}</strong> eingeladen.</p>
  <p>Melde dich mit dieser E-Mail-Adresse bei <strong>Guardian Com</strong> an, um die Einladung anzunehmen:</p>
  <p style="margin:24px 0 8px"><strong>Android:</strong> App aus dem Play Store laden</p>
  <p style="margin:0 0 20px">
    <a href="https://play.google.com/store/apps/details?id=com.guardianapp.guardian_app"
       style="background:#1565C0;color:#fff;padding:12px 24px;border-radius:6px;text-decoration:none;font-weight:bold;display:inline-block">
      App herunterladen
    </a>
  </p>
  <p style="margin:0 0 8px"><strong>iPhone, iPad oder Computer:</strong> direkt im Browser nutzen</p>
  <p style="margin:0 0 8px">
    <a href="https://app.guardian-com.de"
       style="background:#1565C0;color:#fff;padding:12px 24px;border-radius:6px;text-decoration:none;font-weight:bold;display:inline-block">
      Im Browser öffnen
    </a>
  </p>
  <p style="font-size:0.85rem;color:#666;margin:0 0 24px">
    Tipp für iPhone/iPad: In Safari auf „Teilen“ und dann „Zum Home-Bildschirm“ tippen – dann startet Guardian Com wie eine App.
  </p>
  <p style="font-size:0.85rem;color:#666">
    Wenn du diese Einladung nicht erwartet hast, kannst du diese E-Mail ignorieren.
  </p>
</body>
</html>`;

      try {
        // Port 587 (STARTTLS) statt `service: 'gmail'` (= 465): Hetzner sperrt
        // ausgehend 25/465 für Cloud-Server → die Verbindung hing bis zum
        // Function-Timeout, ohne Log (2026-11-26). Kurze Timeouts, damit ein
        // Fehler im Log landet statt eines stummen Timeouts.
        const transporter = nodemailer.createTransport({
          host: 'smtp.gmail.com',
          port: 587,
          secure: false,
          requireTLS: true,
          auth: { user: 'savespacedev@gmail.com', pass: gmailPassword },
          connectionTimeout: 8000,
          greetingTimeout: 8000,
          socketTimeout: 12000,
        });
        await transporter.sendMail({
          from: '"Guardian Com" <savespacedev@gmail.com>',
          to: email,
          subject: `Einladung zu "${orgName ?? 'Guardian Com'}"`,
          html,
        });
        log(`Invitation email sent to ${email}`);
      } catch (mailErr) {
        error(`Failed to send invitation email: ${mailErr.message}`);
      }
    } else {
      log('GMAIL_APP_PASSWORD not set — skipping invitation email');
    }
  }

  // Guardians bei Kind-Einladungen benachrichtigen
  if (role !== 'child' || !guardianUids || guardianUids.length === 0) {
    return res.empty();
  }

  await sendToUsers(
    db,
    guardianUids,
    '👶 Kind-Einladung ausstehend',
    `${email} wurde als Kind in "${orgName ?? ''}" eingeladen. Bitte stimme zu.`,
    { type: 'child_invitation', inviteId: invite.$id },
    log,
    error,
  );

  log(`on-new-invitation: sent ${guardianUids.length} guardian notification(s)`);
  return res.empty();
};
