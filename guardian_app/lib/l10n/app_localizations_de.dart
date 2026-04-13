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
  String get save => 'Speichern';

  @override
  String get delete => 'Löschen';

  @override
  String get edit => 'Bearbeiten';

  @override
  String get close => 'Schließen';

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
  String get editProfile => 'Profil bearbeiten';

  @override
  String get newImageSelected =>
      'Neues Bild ausgewählt — speichern um zu übernehmen';

  @override
  String get displayName => 'Anzeigename';

  @override
  String get appearance => 'Erscheinungsbild';

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
  String get chatMode => 'Chat-Modus';

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
}
