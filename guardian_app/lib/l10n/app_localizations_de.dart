// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Guardian Com';

  @override
  String get appSubtitle => 'Sichere Kommunikation für Organisationen';

  @override
  String get noConnection => 'Keine Verbindung';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get close => 'Schließen';

  @override
  String get save => 'Speichern';

  @override
  String get delete => 'Löschen';

  @override
  String get edit => 'Bearbeiten';

  @override
  String get remove => 'Entfernen';

  @override
  String get create => 'Erstellen';

  @override
  String get invite => 'Einladen';

  @override
  String get add => 'Hinzufügen';

  @override
  String get accept => 'Annehmen';

  @override
  String get reject => 'Ablehnen';

  @override
  String get transfer => 'Übertragen';

  @override
  String get leave => 'Verlassen';

  @override
  String get archive => 'Archivieren';

  @override
  String get restore => 'Aus Archiv wiederherstellen';

  @override
  String get back => 'Zurück';

  @override
  String get yes => 'Ja';

  @override
  String get no => 'Nein';

  @override
  String errorMessage(String message) {
    return 'Fehler: $message';
  }

  @override
  String get signInWithGoogle => 'Mit Google anmelden';

  @override
  String get or => 'oder';

  @override
  String get emailAddress => 'E-Mail-Adresse';

  @override
  String get emailHint => 'name@beispiel.de';

  @override
  String get invalidEmailAddress => 'Ungültige E-Mail-Adresse';

  @override
  String get sendSignInLink => 'Anmeldelink senden';

  @override
  String get emailLinkHint =>
      'Wir senden dir einen Link per E-Mail.\nKein Passwort nötig.';

  @override
  String signInFailed(String error) {
    return 'Anmeldung fehlgeschlagen: $error';
  }

  @override
  String get linkSent => 'Link gesendet!';

  @override
  String linkSentDescription(String email) {
    return 'Wir haben einen Anmeldelink an\n$email gesendet.';
  }

  @override
  String get desktopLinkInstructions =>
      'Öffne die E-Mail in deinem Browser, klicke auf den Link\nund kopiere die vollständige URL aus der Adressleiste.';

  @override
  String get pasteLinkLabel => 'Link aus Browser einfügen';

  @override
  String get signIn => 'Anmelden';

  @override
  String get mobileLinkInstructions =>
      'Öffne die E-Mail und tippe auf den Link um dich anzumelden.';

  @override
  String get resend => 'Erneut senden';

  @override
  String get useOtherEmail => 'Andere E-Mail verwenden';

  @override
  String get invalidLink => 'Ungültiger Link. Bitte prüfe die URL.';

  @override
  String get helpProfileTitle => 'Profil – Hilfe';

  @override
  String get helpProfilePhotoTitle => 'Profilbild ändern';

  @override
  String get helpProfilePhotoBody =>
      'Tippe auf das Kreissymbol mit deinem Avatar, um ein neues Bild aus der Galerie zu wählen. Das Bild wird auf 512 × 512 Pixel verkleinert. Tippe anschliessend oben rechts auf \'Speichern\'.';

  @override
  String get helpProfileNameTitle => 'Anzeigename';

  @override
  String get helpProfileNameBody =>
      'Der Anzeigename ist für alle Mitglieder sichtbar, mit denen du in einer Organisation bist. Ändere ihn im Textfeld und speichere mit \'Speichern\'.';

  @override
  String get helpProfileAppearanceTitle => 'Design & Sprache';

  @override
  String get helpProfileAppearanceBody =>
      'Unter \'Erscheinungsbild\' wählst du zwischen Hell, Dunkel und Systemstandard.\n\nUnter \'Sprache\' stellst du die App-Sprache ein (Deutsch oder Englisch). Die Änderung wird sofort übernommen.';

  @override
  String get helpProfileRelTitle => 'Verknüpfungen';

  @override
  String get helpProfileRelBody =>
      'Der Eintrag \'Meine Verknüpfungen\' führt zur Seite, auf der du Eltern-Kind-Verbindungen verwalten kannst.';

  @override
  String get editProfile => 'Profil bearbeiten';

  @override
  String get newImageSelected =>
      'Neues Bild ausgewählt — speichern um zu übernehmen';

  @override
  String get displayName => 'Anzeigename';

  @override
  String get appearance => 'Erscheinungsbild';

  @override
  String get chatFontSize => 'Schriftgrösse im Chat';

  @override
  String get fontSizeSmall => 'Klein';

  @override
  String get fontSizeMedium => 'Mittel';

  @override
  String get fontSizeLarge => 'Gross';

  @override
  String get fontSizeXL => 'Sehr gross';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Hell';

  @override
  String get themeDark => 'Dunkel';

  @override
  String get language => 'Sprache';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get languageEnglish => 'English';

  @override
  String get uiScale => 'Skalierung (Desktop)';

  @override
  String get signOut => 'Abmelden';

  @override
  String get profileSaved => 'Profil gespeichert.';

  @override
  String get privacyTitle => 'Datenschutz';

  @override
  String get visibility => 'Sichtbarkeit';

  @override
  String get showOnlineStatus => 'Online-Status anzeigen';

  @override
  String get showOnlineStatusSubtitle =>
      'Andere Mitglieder sehen wann du online bist';

  @override
  String get showLastSeen => 'Zuletzt gesehen';

  @override
  String get showLastSeenSubtitle =>
      'Andere Mitglieder sehen wann du zuletzt aktiv warst';

  @override
  String get showProfilePhoto => 'Profilbild sichtbar';

  @override
  String get showProfilePhotoSubtitle =>
      'Mitglieder können dein Profilbild sehen';

  @override
  String get legal => 'Rechtliches';

  @override
  String get privacyPolicy => 'Datenschutzerklärung';

  @override
  String get openInBrowser => 'Im Browser öffnen';

  @override
  String get data => 'Daten';

  @override
  String get deleteAccount => 'Konto löschen';

  @override
  String get deleteAccountSubtitle =>
      'Alle Daten werden unwiderruflich gelöscht';

  @override
  String get deleteAccountConfirmContent =>
      'Möchtest du dein Konto wirklich löschen? Diese Aktion kann nicht rückgängig gemacht werden.';

  @override
  String get deleteAccountBlockedTitle => 'Konto löschen nicht möglich';

  @override
  String get deleteAccountBlockedChild =>
      'Dein Konto ist mit einem Elternteil verknüpft. Die Verbindung muss zuerst durch dein Elternteil aufgehoben werden, bevor du dein Konto löschen kannst.';

  @override
  String get deleteAccountBlockedParent =>
      'Du hast noch aktive Verknüpfungen mit Kindern. Bitte hebe zuerst alle Verbindungen unter \"Meine Verknüpfungen\" auf.';

  @override
  String get notificationsTitle => 'Benachrichtigungen';

  @override
  String get notificationsHint =>
      'Diese Einstellungen gelten als Standard für alle Organisationen. Du kannst sie pro Organisation über das Glocken-Symbol anpassen.';

  @override
  String get messages => 'Nachrichten';

  @override
  String get newMessages => 'Neue Nachrichten';

  @override
  String get chatRequests => 'Chat-Anfragen';

  @override
  String get chatRequestsSubtitle => 'Wenn jemand einen Chat anfragt';

  @override
  String get organizations => 'Organisationen';

  @override
  String get invitations => 'Einladungen';

  @override
  String get invitationsSubtitle => 'Bei Einladungen in Organisationen';

  @override
  String get orgChanges => 'Org-Änderungen';

  @override
  String get orgChangesSubtitle => 'Bei Änderungen in meinen Organisationen';

  @override
  String get intervalAlways => 'Jede Nachricht';

  @override
  String get intervalHourly => 'Max. 1x pro Stunde';

  @override
  String get intervalDaily => 'Max. 1x pro Tag';

  @override
  String get intervalNever => 'Nie';

  @override
  String get keywordsTooltip => 'Schlüsselwörter';

  @override
  String get keywordsImportCsv => 'CSV importieren';

  @override
  String get keywordsExportCsv => 'CSV exportieren';

  @override
  String keywordsImported(int count) {
    return '$count Keywords importiert';
  }

  @override
  String get keywordsExported => 'Keywords als Datei gespeichert';

  @override
  String get keywordsExportFailed => 'Export fehlgeschlagen';

  @override
  String get editTooltip => 'Bearbeiten';

  @override
  String get editOrganization => 'Organisation bearbeiten';

  @override
  String get orgName => 'Name';

  @override
  String get category => 'Kategorie';

  @override
  String get orgTagFamilie => 'Familie';

  @override
  String get orgTagFreunde => 'Freunde';

  @override
  String get orgTagSchule => 'Schule';

  @override
  String get orgTagVereine => 'Vereine';

  @override
  String get orgTagSonstiges => 'Sonstiges';

  @override
  String get chatMode => 'Chat-Modus';

  @override
  String get keywordsHelpTitle => 'Schlüsselwörter – Hilfe';

  @override
  String get keywordsHelpBody =>
      'Wozu dienen Schlüsselwörter?\nGuardians und Moderatoren werden benachrichtigt, sobald eines dieser Wörter in einem Chat-Nachricht erscheint. So lassen sich sensible Themen oder Risikobegriffe frühzeitig erkennen.\n\nWörter hinzufügen\nGib ein Wort in das Textfeld ein und tippe auf \'+\' oder drücke Enter. Gross-/Kleinschreibung wird ignoriert – alles wird in Kleinbuchstaben gespeichert.\n\nWörter entfernen\nTippe auf das \'×\'-Symbol auf einem Chip.\n\nCSV-Import / Export\n• Import (Pfeil nach oben): Lade eine Textdatei mit einem Wort pro Zeile oder kommagetrennt.\n• Export (Pfeil nach unten): Speichere alle Wörter als CSV-Datei.\n\nÄnderungen werden erst nach \'Speichern\' übernommen.';

  @override
  String get keywordsTitle => 'Schlüsselwörter';

  @override
  String get keywordsDescription =>
      'Guardians und Moderatoren werden benachrichtigt, wenn eines dieser Wörter in einem Chat auftaucht.';

  @override
  String get addKeywordHint => 'Neues Wort hinzufügen';

  @override
  String get noKeywordsDefined => 'Keine Schlüsselwörter definiert.';

  @override
  String get tabMembers => 'Mitglieder';

  @override
  String get helpDetailTopicMembersTitle => 'Mitgliederliste & Rollen';

  @override
  String get helpDetailTopicMembersBody =>
      'Im Tab \'Mitglieder\' siehst du alle aktiven Personen der Organisation mit ihrer Rolle (Admin, Moderator, Mitglied, Kind).\n\nRollen im 3-Punkte-Menü (Admin):\n• Rolle ändern – Admin, Moderator, Mitglied oder Kind\n• Guardian zuweisen – verbindet ein Kind mit einem Elternteil\n• Mitglied entfernen\n• Admin-Rolle übertragen\n\nMitglieder können die Org selbst verlassen (ausser Admin).';

  @override
  String get helpDetailTopicMembersInviteTitle =>
      'Einladen, vorschlagen & importieren';

  @override
  String get helpDetailTopicMembersInviteBody =>
      'Admin / Moderator – \'+\'-Schaltfläche unten rechts:\n• Einzeln per E-Mail einladen (Rolle und ggf. Guardian wählbar)\n• Im \'Sheltered\'-Modus: Massenimport per CSV-Datei\n\nEingeladene Kinder: erscheinen als ausstehend, bis der Guardian die Einladung in \'Meine Verknüpfungen\' genehmigt.\n\nReguläres Mitglied – \'Mitglied vorschlagen\':\nSchlage eine Person vor. Admin oder Moderator muss den Vorschlag oben im Tab bestätigen.\n\nKind (Guardian-Modus) – \'Chat anfragen\':\nSende eine Anfrage für einen 1:1-Chat. Admin oder Moderator genehmigt oder lehnt ab.';

  @override
  String get helpDetailTopicNotificationsTitle => 'Benachrichtigungen';

  @override
  String get helpDetailTopicNotificationsBody =>
      'Das Glocken-Symbol (oben rechts) steuert Benachrichtigungen für diese Organisation.\n\nNachrichten-Benachrichtigungen:\n• Jede Nachricht\n• Max. 1x pro Stunde (Standard)\n• Max. 1x pro Tag\n• Nie\n\nKind-Aktivität (Guardian):\nWird benachrichtigt wenn dein Kind eine Nachricht sendet oder empfängt. Intervall ebenfalls einstellbar.';

  @override
  String get helpDetailTopicChatsSendTitle => 'Chats – Nachrichten & Medien';

  @override
  String get helpDetailTopicChatsSendBody =>
      'Textnachrichten: Tippe in das Eingabefeld und sende mit dem Pfeil-Symbol.\n\nBilder, Audio & Dateien: \'+\'-Symbol neben dem Textfeld:\n• Bilder aus der Galerie (JPEG, max. 2 MB)\n• Sprachnachricht aufnehmen (Mikrofon-Symbol)\n• Dateien senden (max. 5 MB)\n\nAntworten: Nachricht lang drücken → \'Antworten\'. Die Ursprungsnachricht erscheint als Zitat.\n\nReaktionen: Nachricht lang drücken → Emoji wählen (👍❤️😂😮😢😡👎). Erneut tippen entfernt die eigene Reaktion.\n\nNachrichten planen: \'+\' → Uhr-Symbol → Datum und Uhrzeit wählen.\n\nUmfragen (Sheltered-Gruppen): \'+\' → Umfrage-Symbol → Frage mit Optionen erstellen.';

  @override
  String get helpDetailTopicChatsModTitle => 'Nachrichten moderieren & melden';

  @override
  String get helpDetailTopicChatsModBody =>
      'Eigene Nachrichten bearbeiten: Nachricht lang drücken → \'Bearbeiten\'. Bearbeitete Nachrichten werden im Moderations-Log archiviert.\n\nAdmin/Moderator – Nachrichten verwalten:\n• Fremde Nachrichten bearbeiten oder löschen\n• Nachricht anpinnen → erscheint als Banner oben im Chat\n\nMelden: Fremde Nachricht lang drücken → \'Melden\'. Admin und Moderatoren werden benachrichtigt und sehen die Meldung im Meldungen-Tab.';

  @override
  String get helpDetailTopicPinnwandTitle => 'Pinnwand lesen';

  @override
  String get helpDetailTopicPinnwandBody =>
      'Die Pinnwand zeigt offizielle Ankündigungen der Organisation – kein Hin-und-Her wie im Chat, sondern gezielte Informationen von Admins und Moderatoren.\n\nBeiträge haben einen Titel, einen Text und optional ein Ablaufdatum. Abgelaufene Ankündigungen verschwinden automatisch.';

  @override
  String get helpDetailTopicPinnwandManageTitle =>
      'Ankündigungen erstellen & verwalten';

  @override
  String get helpDetailTopicPinnwandManageBody =>
      'Neue Ankündigung: Tippe auf das \'+\'-Symbol unten rechts → Titel und Text eingeben.\n\nAblaufdatum: Optional kannst du festlegen, bis wann eine Ankündigung sichtbar ist. Nach diesem Datum wird sie automatisch ausgeblendet.\n\nBearbeiten oder löschen: Tippe auf das Drei-Punkte-Menü einer Ankündigung.';

  @override
  String get helpDetailTopicReportsTitle => 'Meldungen';

  @override
  String get helpDetailTopicReportsBody =>
      'Der Tab \'Meldungen\' ist nur für Admins und Moderatoren sichtbar.\n\nHier werden gemeldete Nachrichten aufgelistet. Du kannst:\n• Zur gemeldeten Nachricht im Chat springen\n• Die Nachricht löschen\n• Die Meldung als geprüft archivieren\n\nArchivierte Meldungen werden ausgeblendet – der Toggle oben zeigt sie wieder an.';

  @override
  String get tabChats => 'Chats';

  @override
  String get tabReports => 'Meldungen';

  @override
  String childChatRequests(int count) {
    return 'Chat-Anfragen deiner Kinder ($count)';
  }

  @override
  String pendingRequests(int count) {
    return 'Ausstehende Anfragen ($count)';
  }

  @override
  String monitoredChats(int count) {
    return 'Überwachte Chats ($count)';
  }

  @override
  String archivedChats(int count) {
    return 'Archiviert ($count)';
  }

  @override
  String get noChatsGuardian =>
      'Noch keine Chats.\nStelle eine Anfrage um zu starten.';

  @override
  String get noChatsSheltered =>
      'Noch keine Chats.\nDer Admin legt Verbindungen fest.';

  @override
  String get createGroup => 'Gruppe erstellen';

  @override
  String get groupName => 'Gruppenname';

  @override
  String get addMembers => 'Mitglieder hinzufügen';

  @override
  String get csvImport => 'CSV importieren';

  @override
  String get inviteMember => 'Mitglied einladen';

  @override
  String get suggestMember => 'Mitglied vorschlagen';

  @override
  String get requestChat => 'Chat anfragen';

  @override
  String suggestions(int count) {
    return 'Vorschläge ($count)';
  }

  @override
  String pendingChildInvitations(int count) {
    return 'Ausstehende Kind-Einladungen ($count)';
  }

  @override
  String get noMembers => 'Noch keine Mitglieder';

  @override
  String get inviteMemberTitle => 'Mitglied einladen';

  @override
  String get role => 'Rolle';

  @override
  String get guardians => 'Guardians (Elternteile)';

  @override
  String get childGuardianHint =>
      'Das Kind wird erst hinzugefügt, wenn ein Guardian zustimmt.';

  @override
  String get noGuardiansAvailable => 'Keine Mitglieder als Guardian verfügbar.';

  @override
  String get inviteSentChild =>
      'Einladung gesendet. Das Kind wird nach Registrierung und Guardian-Zustimmung hinzugefügt.';

  @override
  String get inviteSent => 'Einladung gesendet.';

  @override
  String get requestChatTitle => 'Chat anfragen';

  @override
  String get requestChatSubtitle => 'Mit wem möchtest du chatten?';

  @override
  String get requestChatHint =>
      'Deine Anfrage wird von einem Admin oder Moderator geprüft.';

  @override
  String get requestChatButton => 'Anfragen';

  @override
  String get chatRequestSent => 'Chat-Anfrage wurde gesendet.';

  @override
  String get suggestMemberTitle => 'Mitglied vorschlagen';

  @override
  String get guardian => 'Guardian';

  @override
  String get suggest => 'Vorschlagen';

  @override
  String get suggestionSent =>
      'Vorschlag wurde eingereicht und wartet auf Genehmigung.';

  @override
  String get orgNotificationsTitle => 'Benachrichtigungen dieser Org';

  @override
  String get noMessages => 'Noch keine Nachrichten';

  @override
  String get hideArchived => 'Archivierte ausblenden';

  @override
  String showArchived(int count) {
    return 'Archivierte anzeigen ($count)';
  }

  @override
  String get noReports => 'Keine Meldungen';

  @override
  String get noPendingReports => 'Keine ausstehenden Meldungen';

  @override
  String get reportPending => 'Ausstehend';

  @override
  String get reportReviewed => 'Geprüft · Archiviert';

  @override
  String get markReviewed => 'Als geprüft markieren';

  @override
  String get deleteMessage => 'Nachricht löschen';

  @override
  String get deleteMessageTitle => 'Nachricht löschen';

  @override
  String get deleteMessageContent =>
      'Diese Nachricht wird dauerhaft gelöscht und der Report als geprüft markiert.';

  @override
  String get pendingApproval => 'Wartet auf Genehmigung';

  @override
  String get approveTooltip => 'Genehmigen';

  @override
  String get rejectTooltip => 'Ablehnen';

  @override
  String get roleAdmin => 'Admin';

  @override
  String get roleModerator => 'Moderator';

  @override
  String get roleMember => 'Mitglied';

  @override
  String get roleChild => 'Kind';

  @override
  String get notificationSettings => 'Benachrichtigungseinstellungen';

  @override
  String get leaveOrganization => 'Organisation verlassen';

  @override
  String get changeGuardians => 'Guardians ändern';

  @override
  String get startChat => 'Chat starten';

  @override
  String get changeRole => 'Rolle ändern';

  @override
  String get transferAdmin => 'Admin-Rolle übertragen';

  @override
  String get noActionsAvailable => 'Keine Aktionen verfügbar.';

  @override
  String guardiansFor(String name) {
    return 'Guardians für $name';
  }

  @override
  String roleFor(String name) {
    return 'Rolle für $name';
  }

  @override
  String guardianFor(String name) {
    return 'Guardian für $name';
  }

  @override
  String get selectGuardianHint =>
      'Wähle mindestens einen Guardian für dieses Kind:';

  @override
  String get noGuardiansInOrg =>
      'Keine möglichen Guardians in dieser Organisation.';

  @override
  String get removeMemberTitle => 'Mitglied entfernen';

  @override
  String removeMemberContent(String name) {
    return '$name wirklich entfernen?';
  }

  @override
  String get leaveOrgTitle => 'Organisation verlassen';

  @override
  String leaveOrgContent(String name) {
    return 'Möchtest du die Organisation \"$name\" wirklich verlassen?';
  }

  @override
  String get transferAdminTitle => 'Admin-Rolle übertragen';

  @override
  String transferAdminContent(String name) {
    return 'Möchtest du die Admin-Rolle an $name übertragen?\n\nDu wirst danach ein normales Mitglied dieser Organisation.';
  }

  @override
  String get childActivityNotifications => 'Kind-Aktivität Benachrichtigungen';

  @override
  String get pendingChildSubtitle => 'Wartet auf deine Zustimmung';

  @override
  String get approveChildTooltip => 'Zustimmen';

  @override
  String memberAdded(String name) {
    return '$name wurde hinzugefügt.';
  }

  @override
  String get withdrawInvitationTitle => 'Einladung zurückziehen';

  @override
  String withdrawInvitationContent(String email) {
    return 'Einladung für $email wirklich zurückziehen?';
  }

  @override
  String get withdraw => 'Zurückziehen';

  @override
  String get tabPinboard => 'Pinnwand';

  @override
  String announcementExpiresOn(String date) {
    return 'Läuft ab: $date';
  }

  @override
  String get announcementExpired => 'Abgelaufen';

  @override
  String get announcementSetExpiry => 'Ablaufdatum setzen';

  @override
  String get announcementNoExpiry => 'Kein Ablaufdatum';

  @override
  String get announcementRemoveExpiry => 'Ablaufdatum entfernen';

  @override
  String get pinnedMessage => 'Angepinnte Nachricht';

  @override
  String get pinMessage => 'Anpinnen';

  @override
  String get unpinMessage => 'Loslösen';

  @override
  String get anonymousPoll => 'Anonym';

  @override
  String get pollVotersTitle => 'Abstimmungsdetails';

  @override
  String get pollVoteNotifTitle => 'Neue Stimme';

  @override
  String pollVoteNotifBody(String name, String question) {
    return '$name hat an deiner Abstimmung \"$question\" teilgenommen.';
  }

  @override
  String get newAnnouncement => 'Ankündigung erstellen';

  @override
  String get editAnnouncement => 'Ankündigung bearbeiten';

  @override
  String get announcementTitleLabel => 'Titel';

  @override
  String get announcementContentLabel => 'Nachricht';

  @override
  String get noAnnouncements => 'Noch keine Ankündigungen';

  @override
  String get deleteAnnouncementTitle => 'Ankündigung löschen';

  @override
  String get deleteAnnouncementContent => 'Diese Ankündigung wirklich löschen?';

  @override
  String get announcementEdited => 'bearbeitet';

  @override
  String announcementBy(String name) {
    return 'von $name';
  }

  @override
  String get scheduleMessage => 'Nachricht planen';

  @override
  String scheduledMessages(int count) {
    return 'Geplante Nachrichten ($count)';
  }

  @override
  String get scheduleFor => 'Senden am';

  @override
  String scheduledAt(String time) {
    return 'Geplant für $time';
  }

  @override
  String get cancelScheduled => 'Abbrechen';

  @override
  String get scheduleHint =>
      'Nachrichten werden nur gesendet solange die App geöffnet ist.';

  @override
  String get helpChatTitle => 'Chat – Hilfe';

  @override
  String get helpChatWriteTitle => 'Nachrichten schreiben & senden';

  @override
  String get helpChatWriteBody =>
      'Tippe deine Nachricht in das Textfeld und drücke den Senden-Pfeil. URLs im Text werden automatisch als anklickbare Links erkannt.';

  @override
  String get helpChatMediaTitle => 'Bilder, Audio & Dateien';

  @override
  String get helpChatMediaBody =>
      'Tippe auf das \'+\'-Symbol links neben dem Textfeld, um ein Bild aus der Galerie oder der Kamera zu wählen, eine Sprachaufnahme zu starten oder eine Datei anzuhängen.';

  @override
  String get helpChatReactTitle => 'Antworten & Reaktionen';

  @override
  String get helpChatReactBody =>
      'Halte eine Nachricht gedrückt, um ein Kontextmenü zu öffnen. Dort kannst du auf eine Nachricht antworten oder mit einem Emoji reagieren. Eine Antwort erscheint mit Vorschau der Originalnachricht.';

  @override
  String get helpChatScheduleTitle => 'Planen & Umfragen';

  @override
  String get helpChatScheduleBody =>
      'Im \'+\'-Menü kannst du eine Nachricht zeitgesteuert planen. In Gruppen mit \'Betreut\'-Modus ist ausserdem das Erstellen von Umfragen möglich.';

  @override
  String get helpChatModerateTitle => 'Nachrichten moderieren & bearbeiten';

  @override
  String get helpChatModerateBody =>
      'Du kannst eigene Nachrichten bearbeiten oder löschen. Administratoren und Moderatoren können zusätzlich beliebige Nachrichten löschen, bearbeiten oder anpinnen.';

  @override
  String get helpChatReportTitle => 'Melden, Kopieren & Suchen';

  @override
  String get helpChatReportBody =>
      'Halte eine Nachricht gedrückt und wähle \'Melden\', um Missbrauch zu melden, oder \'Kopieren\', um den Text zu kopieren. Mit dem Lupen-Symbol in der Titelleiste durchsuchst du alle Nachrichten.';

  @override
  String get searchMessages => 'Nachrichten suchen';

  @override
  String get searchHint => 'Suchen…';

  @override
  String get searchNoResults => 'Keine Treffer';

  @override
  String searchResults(int count) {
    return '$count Treffer';
  }

  @override
  String get reply => 'Antworten';

  @override
  String replyingTo(String name) {
    return 'Antwortet $name';
  }

  @override
  String get microphoneDenied => 'Mikrofon-Zugriff wurde verweigert.';

  @override
  String get createPollTitle => 'Umfrage erstellen';

  @override
  String get pollQuestion => 'Frage';

  @override
  String get pollOptions => 'Antwortmöglichkeiten';

  @override
  String get addOption => 'Option hinzufügen';

  @override
  String get multipleChoice => 'Mehrfachauswahl';

  @override
  String get addMemberTitle => 'Mitglied hinzufügen';

  @override
  String get allMembersInChat => 'Alle Mitglieder sind bereits im Chat.';

  @override
  String get membersTooltip => 'Mitglieder anzeigen';

  @override
  String get archivedReadOnly => 'Archiviert – nur lesen';

  @override
  String sendError(String error) {
    return 'Fehler beim Senden: $error';
  }

  @override
  String get olderMessages => 'Ältere Nachrichten';

  @override
  String get copyText => 'Text kopieren';

  @override
  String get moderate => 'Moderieren';

  @override
  String get reportMessage => 'Nachricht melden';

  @override
  String get editedPrefix => 'bearbeitet · ';

  @override
  String get today => 'Heute';

  @override
  String get yesterday => 'Gestern';

  @override
  String get sendImage => 'Bild senden';

  @override
  String get sendFile => 'Datei senden (max. 5 MB)';

  @override
  String get voiceRecording => 'Sprachaufnahme';

  @override
  String get createPoll => 'Umfrage erstellen';

  @override
  String get messageHint => 'Nachricht schreiben...';

  @override
  String get attachmentTooltip => 'Anhang';

  @override
  String get voiceTooltip => 'Sprachnachricht';

  @override
  String get recordingIndicator => 'Aufnahme läuft…';

  @override
  String get endPollTitle => 'Umfrage beenden';

  @override
  String get endPollContent =>
      'Die Umfrage beenden? Danach kann nicht mehr abgestimmt werden.';

  @override
  String get endPoll => 'Beenden';

  @override
  String get pollClosed => 'Abgeschlossen';

  @override
  String get poll => 'Umfrage';

  @override
  String pollExpiresOn(String date) {
    return 'Endet am $date';
  }

  @override
  String get pollExpired => 'Abgelaufen';

  @override
  String get addExpiry => 'Ablaufdatum hinzufügen';

  @override
  String get noExpiry => 'Kein Ablaufdatum';

  @override
  String votes(int count) {
    return '$count Stimmen';
  }

  @override
  String get oneVote => '1 Stimme';

  @override
  String get removeMembersTitle => 'Mitglieder entfernen';

  @override
  String removeMemberFromChat(String name) {
    return '$name aus dem Chat entfernen?';
  }

  @override
  String moderatedBy(String name) {
    return 'von $name moderiert';
  }

  @override
  String get moderatedByModerator => 'von Moderator moderiert';

  @override
  String get helpImportTitle => 'Massenimport – Hilfe';

  @override
  String get helpImportFormatTitle => 'CSV-Format';

  @override
  String get helpImportFormatBody =>
      'Die Datei muss die Spalten email, rolle und guardians enthalten (Kopfzeile optional). Als Trennzeichen werden , und ; automatisch erkannt.\n\nBeispiel:\nemail;rolle;guardians\nkind@schule.de;kind;eltern@schule.de\nmitglied@schule.de;mitglied;';

  @override
  String get helpImportRolesTitle => 'Gültige Rollen';

  @override
  String get helpImportRolesBody =>
      'mitglied (oder member) · moderator (oder mod) · kind (oder child)\n\nGross-/Kleinschreibung wird ignoriert.';

  @override
  String get helpImportChildrenTitle => 'Kinder importieren';

  @override
  String get helpImportChildrenBody =>
      'Für Zeilen mit der Rolle \'kind\' muss die Guardians-Spalte mindestens eine E-Mail-Adresse enthalten. Die genannten Guardians müssen bereits Mitglieder dieser Organisation sein.';

  @override
  String get helpImportPreviewTitle => 'Vorschau & Validierung';

  @override
  String get helpImportPreviewBody =>
      'Nach dem Laden der Datei wird jede Zeile geprüft. Ein rotes Symbol zeigt einen Fehler (Zeile wird nicht importiert), ein gelbes Symbol zeigt eine Warnung (Import trotzdem möglich).';

  @override
  String get helpImportRunTitle => 'Import starten';

  @override
  String get helpImportRunBody =>
      'Tippe oben rechts auf \'X importieren\'. Die Schaltfläche erscheint nur, wenn mindestens eine gültige Zeile vorhanden ist. Nach dem Import zeigt ein Log-Protokoll für jede Zeile ob sie erfolgreich war oder fehlgeschlagen ist.';

  @override
  String get importMembers => 'Mitglieder importieren';

  @override
  String get selectCsvFile => 'CSV-Datei auswählen';

  @override
  String importCount(int count) {
    return '$count importieren';
  }

  @override
  String csvRowsValid(int total, int valid) {
    return '$total Zeilen · $valid gültig';
  }

  @override
  String csvRowsErrors(int total, int valid, int errors) {
    return '$total Zeilen · $valid gültig · $errors fehlerhaft';
  }

  @override
  String importSuccess(int count) {
    return '$count eingeladen';
  }

  @override
  String importSuccessWithErrors(int count, int errors) {
    return '$count eingeladen, $errors Fehler';
  }

  @override
  String get invalidEmail2 => 'Ungültige E-Mail';

  @override
  String unknownRole(String role) {
    return 'Unbekannte Rolle: \"$role\"';
  }

  @override
  String get guardianMissing => 'Guardian fehlt';

  @override
  String get noGuardianInOrg => 'Kein Guardian in dieser Org gefunden';

  @override
  String guardianNotInOrg(String emails) {
    return 'Guardian nicht in Org: $emails';
  }

  @override
  String get donationTitle => 'Guardian Com unterstützen';

  @override
  String get donationContent =>
      'Guardian Com ist kostenlos und werbefrei. Wenn dir die App gefällt, freue ich mich über eine kleine Spende!';

  @override
  String get kofiButton => 'Ko-fi spenden';

  @override
  String get paypalButton => 'PayPal spenden';

  @override
  String get maybeLater => 'Vielleicht später';

  @override
  String get neverShowAgain => 'Nicht mehr anzeigen';

  @override
  String get batteryOptTitle => 'Akku-Optimierung deaktivieren';

  @override
  String get batteryOptContent =>
      'Für zuverlässige Push-Benachrichtigungen empfiehlt es sich, die Akku-Optimierung für Guardian Com zu deaktivieren. Andernfalls kann Android Benachrichtigungen im Hintergrund verzögern oder blockieren.';

  @override
  String get batteryOptSetup => 'Jetzt einrichten';

  @override
  String get batteryOptDontAsk => 'Nicht mehr fragen';

  @override
  String get aboutApp => 'Über die App';

  @override
  String get aboutAppDialogTitle => 'Guardian Com';

  @override
  String get aboutAppDescription =>
      'Sichere, beaufsichtigte Kommunikation für Organisationen – kostenlos und werbefrei.';

  @override
  String get openSourceLicenses => 'Open-Source-Lizenzen';

  @override
  String get githubRepository => 'GitHub-Repository';

  @override
  String typingOne(String name) {
    return '$name schreibt…';
  }

  @override
  String typingMultiple(String names) {
    return '$names schreiben…';
  }

  @override
  String get createOrganization => 'Organisation erstellen';

  @override
  String get orgNameLabel => 'Name der Organisation';

  @override
  String get myOrganizations => 'Meine Organisationen';

  @override
  String get helpLabel => 'Hilfe';

  @override
  String get helpTourButton => 'Tour starten';

  @override
  String get helpOrgTopicOrgsTitle => 'Was sind Organisationen?';

  @override
  String get helpOrgTopicOrgsBody =>
      'Organisationen sind Gruppen für sichere Kommunikation – z. B. Familie, Schule oder Verein. Du kannst selbst Organisationen erstellen oder per Einladung beitreten.';

  @override
  String get helpOrgTopicRolesTitle => 'Rollen';

  @override
  String get helpOrgTopicRolesBody =>
      'Admin – Volle Kontrolle, verwaltet alle Mitglieder und Einstellungen.\nModerator – Kann Chats einsehen und genehmigen.\nMitglied – Kann Chats anfordern und kommunizieren.\nKind – Eingeschränkt, benötigt einen Guardian und Eltern-Zustimmung bei Einladungen.';

  @override
  String get helpOrgTopicChatModesTitle => 'Chat-Modi';

  @override
  String get helpOrgTopicChatModesBody =>
      'Guardian-Modus – Mitglieder beantragen Chats, Admins oder Moderatoren genehmigen sie.\nSheltered-Modus – Der Admin legt vorab fest, wer mit wem kommunizieren darf. Gruppen-Chats sind möglich.';

  @override
  String get helpOrgTopicInviteTitle => 'Mitglieder einladen';

  @override
  String get helpOrgTopicInviteBody =>
      'Öffne eine Organisation → tippe auf das Personen-Symbol → E-Mail eingeben und Rolle wählen. Als Admin kannst du in Sheltered-Orgs auch mehrere Mitglieder per CSV-Datei importieren.';

  @override
  String get helpOrgTopicFamilyTitle => 'Eltern-Kind-Verknüpfung';

  @override
  String get helpOrgTopicFamilyBody =>
      'Kind-Konten sind global auf die Rolle \'Kind\' gesperrt. Wird ein Kind in eine Org eingeladen, müssen die Eltern zuerst zustimmen. Der Baum-Button oben öffnet deine Familienübersicht.';

  @override
  String get tourStepProfileTitle => 'Profil & Einstellungen';

  @override
  String get tourStepProfileDesc =>
      'Tippe hier um dein Profil zu bearbeiten, Benachrichtigungen anzupassen oder dich abzumelden.';

  @override
  String get tourStepFamilyTitle => 'Familienübersicht';

  @override
  String get tourStepFamilyDesc =>
      'Öffnet deine verifizierten Eltern- und Kind-Verbindungen. Das Badge zeigt ausstehende Aktionen.';

  @override
  String get tourStepOrgCardTitle => 'Deine Organisationen';

  @override
  String get tourStepOrgCardDesc =>
      'Tippe auf eine Karte um die Organisation zu öffnen. Als Admin siehst du oben rechts ein Menü mit weiteren Optionen.';

  @override
  String get tourStepFabTitle => 'Organisation erstellen';

  @override
  String get tourStepFabDesc =>
      'Tippe hier um eine neue Organisation zu erstellen und Chat-Modus sowie Kategorie festzulegen.';

  @override
  String get noOrganizations => 'Noch keine Organisationen';

  @override
  String get archivedBadge => 'Archiviert';

  @override
  String get deleteOrgTitle => 'Organisation löschen?';

  @override
  String deleteOrgContent(String name) {
    return '\"$name\" und alle Mitgliedschaften werden unwiderruflich gelöscht.';
  }

  @override
  String get open => 'Öffnen';

  @override
  String get unarchive => 'Wiederherstellen';

  @override
  String get saveImage => 'Bild speichern';

  @override
  String get imageSaved => 'Bild gespeichert';

  @override
  String get helpRelTitle => 'Verknüpfungen – Hilfe';

  @override
  String get helpRelOverviewTitle => 'Was ist eine Eltern-Kind-Verknüpfung?';

  @override
  String get helpRelOverviewBody =>
      'Eine Verknüpfung verbindet ein Elternteil mit einem Kind. Das Kind erhält in allen Organisationen die Rolle \'Kind\' und kann ohne Genehmigung des Elternteils keiner neuen Organisation beitreten.';

  @override
  String get helpRelConnectTitle => 'Kind verbinden';

  @override
  String get helpRelConnectBody =>
      'Gib die E-Mail-Adresse des Kontos ein, das du als Kind verknüpfen möchtest, und tippe auf \'Anfrage senden\'. Das Kind muss die Anfrage anschliessend in dieser Ansicht bestätigen.';

  @override
  String get helpRelIncomingTitle => 'Eingehende Anfragen';

  @override
  String get helpRelIncomingBody =>
      'Wenn jemand eine Verknüpfungsanfrage an dich schickt, erscheint sie hier. Du kannst sie bestätigen oder ablehnen. Beim Bestätigen wirst du der Rolle \'Kind\' in allen deinen Organisationen zugewiesen.';

  @override
  String get helpRelConsentsTitle => 'Org-Einladungen genehmigen';

  @override
  String get helpRelConsentsBody =>
      'Wenn ein Kind zu einer Organisation eingeladen wird, erscheint die Einladung hier zur Genehmigung. Als Elternteil kannst du die Einladung freigeben oder ablehnen.';

  @override
  String get helpRelRevokeTitle => 'Verbindung trennen';

  @override
  String get helpRelRevokeBody =>
      'Tippe auf den Namen einer verknüpften Person und wähle \'Verbindung trennen\'. Kinder können die Verbindung nicht selbst auflösen – das kann nur das Elternteil tun.';

  @override
  String get myRelationships => 'Meine Verknüpfungen';

  @override
  String get myParents => 'Meine Eltern';

  @override
  String get myChildren => 'Meine Kinder';

  @override
  String get noParents => 'Keine verifizierten Eltern';

  @override
  String get noChildren => 'Keine verifizierten Kinder';

  @override
  String get verifiedParent => 'Verifiziertes Elternteil';

  @override
  String get verifiedChild => 'Verifiziertes Kind';

  @override
  String get connectChild => 'Kind verknüpfen';

  @override
  String get connectChildHint => 'E-Mail-Adresse des Kindes eingeben';

  @override
  String get sendClaimRequest => 'Verknüpfungsanfrage senden';

  @override
  String get claimRequestSent => 'Anfrage gesendet.';

  @override
  String get claimRequestNotFound =>
      'Kein Benutzer mit dieser E-Mail gefunden.';

  @override
  String get claimRequestAlreadyExists =>
      'Eine Anfrage für diesen Benutzer existiert bereits.';

  @override
  String get claimRequestCancelTitle => 'Anfrage zurückziehen';

  @override
  String claimRequestCancelContent(String email) {
    return 'Verknüpfungsanfrage an $email wirklich zurückziehen?';
  }

  @override
  String incomingClaimRequests(int count) {
    return 'Eingehende Anfragen ($count)';
  }

  @override
  String wantsToBeYourParent(String name) {
    return '$name möchte dein Elternteil sein';
  }

  @override
  String get confirmClaim => 'Bestätigen';

  @override
  String get rejectClaim => 'Ablehnen';

  @override
  String get claimConfirmed => 'Verknüpfung bestätigt.';

  @override
  String get claimRejected => 'Anfrage abgelehnt.';

  @override
  String get revokeConnection => 'Verknüpfung aufheben';

  @override
  String get revokeConnectionTitle => 'Verknüpfung aufheben';

  @override
  String revokeConnectionContent(String name) {
    return 'Verknüpfung mit $name wirklich aufheben?';
  }

  @override
  String get roleConflictTitle => 'Rollenkonflikt';

  @override
  String roleConflictContent(String orgs) {
    return 'Als Kind-Konto sind andere Rollen nicht erlaubt. Folgende Organisationen sind betroffen:\n\n$orgs\n\nMöchtest du trotzdem fortfahren? Die Rollen in diesen Organisationen werden auf \'Kind\' geändert.';
  }

  @override
  String get childAccountLabel => 'Kind-Konto';

  @override
  String get childAccountHint =>
      'Dieses Konto ist als Kind markiert. Nur die Rolle \'Kind\' ist in Organisationen erlaubt.';

  @override
  String get isChildAccount => 'Als Kind markiert';

  @override
  String get parentConsentRequired => 'Eltern-Einwilligung erforderlich';

  @override
  String parentConsentRequiredContent(String name) {
    return '$name hat verifizierte Eltern. Die Einladung wird zur Genehmigung weitergeleitet.';
  }

  @override
  String pendingParentConsents(int count) {
    return 'Ausstehende Eltern-Einwilligungen ($count)';
  }

  @override
  String orgInvitationForChild(String orgName, String childName) {
    return '$orgName möchte $childName einladen';
  }

  @override
  String orgInvitationInvitedBy(String name) {
    return 'Eingeladen von $name';
  }

  @override
  String get approveOrgInvitation => 'Genehmigen';

  @override
  String get vetoOrgInvitation => 'Ablehnen';

  @override
  String get orgInvitationApproved => 'Einladung genehmigt.';

  @override
  String get orgInvitationVetoed => 'Einladung abgelehnt.';

  @override
  String get myFamily => 'Meine Familie';

  @override
  String get familyTreeTooltip => 'Familienübersicht';

  @override
  String get coParentsLabel => 'Weitere Eltern';

  @override
  String get onlyParent => 'Einziges Elternteil';

  @override
  String get pendingFamilyItems => 'Ausstehende Eltern-Kind-Aktionen';

  @override
  String systemMemberAdded(String targetName) {
    return '$targetName wurde zum Chat hinzugefügt';
  }

  @override
  String systemMemberRemoved(String targetName) {
    return '$targetName wurde aus dem Chat entfernt';
  }

  @override
  String get auditLog => 'Änderungsprotokoll';

  @override
  String get auditNoEntries => 'Noch keine Einträge';

  @override
  String get auditActionInvitationSent => 'Einladung verschickt';

  @override
  String get auditActionMemberConfirmed => 'Mitglied bestätigt';

  @override
  String get auditActionMemberRemoved => 'Mitglied entfernt';

  @override
  String get auditActionSettingsChanged => 'Einstellungen geändert';

  @override
  String get auditActionRoleChanged => 'Rolle geändert';

  @override
  String get auditActionAdminTransferred => 'Admin-Rolle übertragen';

  @override
  String get auditActionKeywordsChanged => 'Schlüsselwörter aktualisiert';

  @override
  String auditBy(String name) {
    return 'von $name';
  }

  @override
  String get chatInfoTitle => 'Chat-Übersicht';

  @override
  String get chatParticipants => 'Teilnehmer';

  @override
  String get chatSupervisors => 'Überwacher';

  @override
  String get chatSupervisorHint => 'Personen, die diesen Chat nur lesen können';

  @override
  String get chatTypeGroup => 'Gruppe';

  @override
  String get chatTypeDirect => 'Direktnachricht';

  @override
  String get renameGroup => 'Gruppe umbenennen';

  @override
  String get personalChatName => 'Eigener Chatname';

  @override
  String get chatNameHint => 'Gruppenname';

  @override
  String get personalNameHint => 'Name nur für dich sichtbar';
}
