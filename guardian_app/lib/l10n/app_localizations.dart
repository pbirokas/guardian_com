import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In de, this message translates to:
  /// **'Guardian Com'**
  String get appTitle;

  /// No description provided for @appSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Sichere Kommunikation für Organisationen'**
  String get appSubtitle;

  /// No description provided for @noConnection.
  ///
  /// In de, this message translates to:
  /// **'Keine Verbindung'**
  String get noConnection;

  /// No description provided for @cancel.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get cancel;

  /// No description provided for @close.
  ///
  /// In de, this message translates to:
  /// **'Schließen'**
  String get close;

  /// No description provided for @save.
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In de, this message translates to:
  /// **'Bearbeiten'**
  String get edit;

  /// No description provided for @remove.
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get remove;

  /// No description provided for @create.
  ///
  /// In de, this message translates to:
  /// **'Erstellen'**
  String get create;

  /// No description provided for @invite.
  ///
  /// In de, this message translates to:
  /// **'Einladen'**
  String get invite;

  /// No description provided for @add.
  ///
  /// In de, this message translates to:
  /// **'Hinzufügen'**
  String get add;

  /// No description provided for @accept.
  ///
  /// In de, this message translates to:
  /// **'Annehmen'**
  String get accept;

  /// No description provided for @reject.
  ///
  /// In de, this message translates to:
  /// **'Ablehnen'**
  String get reject;

  /// No description provided for @transfer.
  ///
  /// In de, this message translates to:
  /// **'Übertragen'**
  String get transfer;

  /// No description provided for @leave.
  ///
  /// In de, this message translates to:
  /// **'Verlassen'**
  String get leave;

  /// No description provided for @archive.
  ///
  /// In de, this message translates to:
  /// **'Archivieren'**
  String get archive;

  /// No description provided for @restore.
  ///
  /// In de, this message translates to:
  /// **'Aus Archiv wiederherstellen'**
  String get restore;

  /// No description provided for @back.
  ///
  /// In de, this message translates to:
  /// **'Zurück'**
  String get back;

  /// No description provided for @yes.
  ///
  /// In de, this message translates to:
  /// **'Ja'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In de, this message translates to:
  /// **'Nein'**
  String get no;

  /// No description provided for @errorMessage.
  ///
  /// In de, this message translates to:
  /// **'Fehler: {message}'**
  String errorMessage(String message);

  /// No description provided for @signInWithGoogle.
  ///
  /// In de, this message translates to:
  /// **'Mit Google anmelden'**
  String get signInWithGoogle;

  /// No description provided for @or.
  ///
  /// In de, this message translates to:
  /// **'oder'**
  String get or;

  /// No description provided for @emailAddress.
  ///
  /// In de, this message translates to:
  /// **'E-Mail-Adresse'**
  String get emailAddress;

  /// No description provided for @emailHint.
  ///
  /// In de, this message translates to:
  /// **'name@beispiel.de'**
  String get emailHint;

  /// No description provided for @invalidEmailAddress.
  ///
  /// In de, this message translates to:
  /// **'Ungültige E-Mail-Adresse'**
  String get invalidEmailAddress;

  /// No description provided for @sendSignInLink.
  ///
  /// In de, this message translates to:
  /// **'Anmeldelink senden'**
  String get sendSignInLink;

  /// No description provided for @emailLinkHint.
  ///
  /// In de, this message translates to:
  /// **'Wir senden dir einen Link per E-Mail.\nKein Passwort nötig.'**
  String get emailLinkHint;

  /// No description provided for @signInFailed.
  ///
  /// In de, this message translates to:
  /// **'Anmeldung fehlgeschlagen: {error}'**
  String signInFailed(String error);

  /// No description provided for @linkSent.
  ///
  /// In de, this message translates to:
  /// **'Link gesendet!'**
  String get linkSent;

  /// No description provided for @linkSentDescription.
  ///
  /// In de, this message translates to:
  /// **'Wir haben einen Anmeldelink an\n{email} gesendet.'**
  String linkSentDescription(String email);

  /// No description provided for @desktopLinkInstructions.
  ///
  /// In de, this message translates to:
  /// **'Öffne die E-Mail in deinem Browser, klicke auf den Link\nund kopiere die vollständige URL aus der Adressleiste.'**
  String get desktopLinkInstructions;

  /// No description provided for @pasteLinkLabel.
  ///
  /// In de, this message translates to:
  /// **'Link aus Browser einfügen'**
  String get pasteLinkLabel;

  /// No description provided for @signIn.
  ///
  /// In de, this message translates to:
  /// **'Anmelden'**
  String get signIn;

  /// No description provided for @mobileLinkInstructions.
  ///
  /// In de, this message translates to:
  /// **'Öffne die E-Mail und tippe auf den Link um dich anzumelden.'**
  String get mobileLinkInstructions;

  /// No description provided for @resend.
  ///
  /// In de, this message translates to:
  /// **'Erneut senden'**
  String get resend;

  /// No description provided for @useOtherEmail.
  ///
  /// In de, this message translates to:
  /// **'Andere E-Mail verwenden'**
  String get useOtherEmail;

  /// No description provided for @invalidLink.
  ///
  /// In de, this message translates to:
  /// **'Ungültiger Link. Bitte prüfe die URL.'**
  String get invalidLink;

  /// No description provided for @helpProfileTitle.
  ///
  /// In de, this message translates to:
  /// **'Profil – Hilfe'**
  String get helpProfileTitle;

  /// No description provided for @helpProfilePhotoTitle.
  ///
  /// In de, this message translates to:
  /// **'Profilbild ändern'**
  String get helpProfilePhotoTitle;

  /// No description provided for @helpProfilePhotoBody.
  ///
  /// In de, this message translates to:
  /// **'Tippe auf das Kreissymbol mit deinem Avatar, um ein neues Bild aus der Galerie zu wählen. Das Bild wird auf 512 × 512 Pixel verkleinert. Tippe anschliessend oben rechts auf \'Speichern\'.'**
  String get helpProfilePhotoBody;

  /// No description provided for @helpProfileNameTitle.
  ///
  /// In de, this message translates to:
  /// **'Anzeigename'**
  String get helpProfileNameTitle;

  /// No description provided for @helpProfileNameBody.
  ///
  /// In de, this message translates to:
  /// **'Der Anzeigename ist für alle Mitglieder sichtbar, mit denen du in einer Organisation bist. Ändere ihn im Textfeld und speichere mit \'Speichern\'.'**
  String get helpProfileNameBody;

  /// No description provided for @helpProfileAppearanceTitle.
  ///
  /// In de, this message translates to:
  /// **'Design & Sprache'**
  String get helpProfileAppearanceTitle;

  /// No description provided for @helpProfileAppearanceBody.
  ///
  /// In de, this message translates to:
  /// **'Unter \'Erscheinungsbild\' wählst du zwischen Hell, Dunkel und Systemstandard.\n\nUnter \'Sprache\' stellst du die App-Sprache ein (Deutsch oder Englisch). Die Änderung wird sofort übernommen.'**
  String get helpProfileAppearanceBody;

  /// No description provided for @helpProfileRelTitle.
  ///
  /// In de, this message translates to:
  /// **'Verknüpfungen'**
  String get helpProfileRelTitle;

  /// No description provided for @helpProfileRelBody.
  ///
  /// In de, this message translates to:
  /// **'Der Eintrag \'Meine Verknüpfungen\' führt zur Seite, auf der du Eltern-Kind-Verbindungen verwalten kannst.'**
  String get helpProfileRelBody;

  /// No description provided for @editProfile.
  ///
  /// In de, this message translates to:
  /// **'Profil bearbeiten'**
  String get editProfile;

  /// No description provided for @newImageSelected.
  ///
  /// In de, this message translates to:
  /// **'Neues Bild ausgewählt — speichern um zu übernehmen'**
  String get newImageSelected;

  /// No description provided for @displayName.
  ///
  /// In de, this message translates to:
  /// **'Anzeigename'**
  String get displayName;

  /// No description provided for @appearance.
  ///
  /// In de, this message translates to:
  /// **'Erscheinungsbild'**
  String get appearance;

  /// No description provided for @chatFontSize.
  ///
  /// In de, this message translates to:
  /// **'Schriftgrösse im Chat'**
  String get chatFontSize;

  /// No description provided for @fontSizeSmall.
  ///
  /// In de, this message translates to:
  /// **'Klein'**
  String get fontSizeSmall;

  /// No description provided for @fontSizeMedium.
  ///
  /// In de, this message translates to:
  /// **'Mittel'**
  String get fontSizeMedium;

  /// No description provided for @fontSizeLarge.
  ///
  /// In de, this message translates to:
  /// **'Gross'**
  String get fontSizeLarge;

  /// No description provided for @fontSizeXL.
  ///
  /// In de, this message translates to:
  /// **'Sehr gross'**
  String get fontSizeXL;

  /// No description provided for @themeSystem.
  ///
  /// In de, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In de, this message translates to:
  /// **'Hell'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In de, this message translates to:
  /// **'Dunkel'**
  String get themeDark;

  /// No description provided for @language.
  ///
  /// In de, this message translates to:
  /// **'Sprache'**
  String get language;

  /// No description provided for @languageGerman.
  ///
  /// In de, this message translates to:
  /// **'Deutsch'**
  String get languageGerman;

  /// No description provided for @languageEnglish.
  ///
  /// In de, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @uiScale.
  ///
  /// In de, this message translates to:
  /// **'Skalierung (Desktop)'**
  String get uiScale;

  /// No description provided for @signOut.
  ///
  /// In de, this message translates to:
  /// **'Abmelden'**
  String get signOut;

  /// No description provided for @profileSaved.
  ///
  /// In de, this message translates to:
  /// **'Profil gespeichert.'**
  String get profileSaved;

  /// No description provided for @privacyTitle.
  ///
  /// In de, this message translates to:
  /// **'Datenschutz'**
  String get privacyTitle;

  /// No description provided for @visibility.
  ///
  /// In de, this message translates to:
  /// **'Sichtbarkeit'**
  String get visibility;

  /// No description provided for @showOnlineStatus.
  ///
  /// In de, this message translates to:
  /// **'Online-Status anzeigen'**
  String get showOnlineStatus;

  /// No description provided for @showOnlineStatusSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Andere Mitglieder sehen wann du online bist'**
  String get showOnlineStatusSubtitle;

  /// No description provided for @showLastSeen.
  ///
  /// In de, this message translates to:
  /// **'Zuletzt gesehen'**
  String get showLastSeen;

  /// No description provided for @showLastSeenSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Andere Mitglieder sehen wann du zuletzt aktiv warst'**
  String get showLastSeenSubtitle;

  /// No description provided for @showProfilePhoto.
  ///
  /// In de, this message translates to:
  /// **'Profilbild sichtbar'**
  String get showProfilePhoto;

  /// No description provided for @showProfilePhotoSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Mitglieder können dein Profilbild sehen'**
  String get showProfilePhotoSubtitle;

  /// No description provided for @legal.
  ///
  /// In de, this message translates to:
  /// **'Rechtliches'**
  String get legal;

  /// No description provided for @privacyPolicy.
  ///
  /// In de, this message translates to:
  /// **'Datenschutzerklärung'**
  String get privacyPolicy;

  /// No description provided for @openInBrowser.
  ///
  /// In de, this message translates to:
  /// **'Im Browser öffnen'**
  String get openInBrowser;

  /// No description provided for @data.
  ///
  /// In de, this message translates to:
  /// **'Daten'**
  String get data;

  /// No description provided for @deleteAccount.
  ///
  /// In de, this message translates to:
  /// **'Konto löschen'**
  String get deleteAccount;

  /// No description provided for @deleteAccountSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Alle Daten werden unwiderruflich gelöscht'**
  String get deleteAccountSubtitle;

  /// No description provided for @deleteAccountConfirmContent.
  ///
  /// In de, this message translates to:
  /// **'Möchtest du dein Konto wirklich löschen? Diese Aktion kann nicht rückgängig gemacht werden.'**
  String get deleteAccountConfirmContent;

  /// No description provided for @deleteAccountBlockedTitle.
  ///
  /// In de, this message translates to:
  /// **'Konto löschen nicht möglich'**
  String get deleteAccountBlockedTitle;

  /// No description provided for @deleteAccountBlockedChild.
  ///
  /// In de, this message translates to:
  /// **'Dein Konto ist mit einem Elternteil verknüpft. Die Verbindung muss zuerst durch dein Elternteil aufgehoben werden, bevor du dein Konto löschen kannst.'**
  String get deleteAccountBlockedChild;

  /// No description provided for @deleteAccountBlockedParent.
  ///
  /// In de, this message translates to:
  /// **'Du hast noch aktive Verknüpfungen mit Kindern. Bitte hebe zuerst alle Verbindungen unter \"Meine Verknüpfungen\" auf.'**
  String get deleteAccountBlockedParent;

  /// No description provided for @notificationsTitle.
  ///
  /// In de, this message translates to:
  /// **'Benachrichtigungen'**
  String get notificationsTitle;

  /// No description provided for @notificationsHint.
  ///
  /// In de, this message translates to:
  /// **'Diese Einstellungen gelten als Standard für alle Organisationen. Du kannst sie pro Organisation über das Glocken-Symbol anpassen.'**
  String get notificationsHint;

  /// No description provided for @messages.
  ///
  /// In de, this message translates to:
  /// **'Nachrichten'**
  String get messages;

  /// No description provided for @newMessages.
  ///
  /// In de, this message translates to:
  /// **'Neue Nachrichten'**
  String get newMessages;

  /// No description provided for @chatRequests.
  ///
  /// In de, this message translates to:
  /// **'Chat-Anfragen'**
  String get chatRequests;

  /// No description provided for @chatRequestsSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Wenn jemand einen Chat anfragt'**
  String get chatRequestsSubtitle;

  /// No description provided for @organizations.
  ///
  /// In de, this message translates to:
  /// **'Organisationen'**
  String get organizations;

  /// No description provided for @invitations.
  ///
  /// In de, this message translates to:
  /// **'Einladungen'**
  String get invitations;

  /// No description provided for @invitationsSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Bei Einladungen in Organisationen'**
  String get invitationsSubtitle;

  /// No description provided for @orgChanges.
  ///
  /// In de, this message translates to:
  /// **'Org-Änderungen'**
  String get orgChanges;

  /// No description provided for @orgChangesSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Bei Änderungen in meinen Organisationen'**
  String get orgChangesSubtitle;

  /// No description provided for @intervalAlways.
  ///
  /// In de, this message translates to:
  /// **'Jede Nachricht'**
  String get intervalAlways;

  /// No description provided for @intervalHourly.
  ///
  /// In de, this message translates to:
  /// **'Max. 1x pro Stunde'**
  String get intervalHourly;

  /// No description provided for @intervalDaily.
  ///
  /// In de, this message translates to:
  /// **'Max. 1x pro Tag'**
  String get intervalDaily;

  /// No description provided for @intervalNever.
  ///
  /// In de, this message translates to:
  /// **'Nie'**
  String get intervalNever;

  /// No description provided for @keywordsTooltip.
  ///
  /// In de, this message translates to:
  /// **'Schlüsselwörter'**
  String get keywordsTooltip;

  /// No description provided for @keywordsImportCsv.
  ///
  /// In de, this message translates to:
  /// **'CSV importieren'**
  String get keywordsImportCsv;

  /// No description provided for @keywordsExportCsv.
  ///
  /// In de, this message translates to:
  /// **'CSV exportieren'**
  String get keywordsExportCsv;

  /// No description provided for @keywordsImported.
  ///
  /// In de, this message translates to:
  /// **'{count} Keywords importiert'**
  String keywordsImported(int count);

  /// No description provided for @keywordsExported.
  ///
  /// In de, this message translates to:
  /// **'Keywords als Datei gespeichert'**
  String get keywordsExported;

  /// No description provided for @keywordsExportFailed.
  ///
  /// In de, this message translates to:
  /// **'Export fehlgeschlagen'**
  String get keywordsExportFailed;

  /// No description provided for @editTooltip.
  ///
  /// In de, this message translates to:
  /// **'Bearbeiten'**
  String get editTooltip;

  /// No description provided for @editOrganization.
  ///
  /// In de, this message translates to:
  /// **'Organisation bearbeiten'**
  String get editOrganization;

  /// No description provided for @orgName.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get orgName;

  /// No description provided for @category.
  ///
  /// In de, this message translates to:
  /// **'Kategorie'**
  String get category;

  /// No description provided for @orgTagFamilie.
  ///
  /// In de, this message translates to:
  /// **'Familie'**
  String get orgTagFamilie;

  /// No description provided for @orgTagFreunde.
  ///
  /// In de, this message translates to:
  /// **'Freunde'**
  String get orgTagFreunde;

  /// No description provided for @orgTagSchule.
  ///
  /// In de, this message translates to:
  /// **'Schule'**
  String get orgTagSchule;

  /// No description provided for @orgTagVereine.
  ///
  /// In de, this message translates to:
  /// **'Vereine'**
  String get orgTagVereine;

  /// No description provided for @orgTagSonstiges.
  ///
  /// In de, this message translates to:
  /// **'Sonstiges'**
  String get orgTagSonstiges;

  /// No description provided for @chatMode.
  ///
  /// In de, this message translates to:
  /// **'Chat-Modus'**
  String get chatMode;

  /// No description provided for @keywordsHelpTitle.
  ///
  /// In de, this message translates to:
  /// **'Schlüsselwörter – Hilfe'**
  String get keywordsHelpTitle;

  /// No description provided for @keywordsHelpBody.
  ///
  /// In de, this message translates to:
  /// **'Wozu dienen Schlüsselwörter?\nGuardians und Moderatoren werden benachrichtigt, sobald eines dieser Wörter in einem Chat-Nachricht erscheint. So lassen sich sensible Themen oder Risikobegriffe frühzeitig erkennen.\n\nWörter hinzufügen\nGib ein Wort in das Textfeld ein und tippe auf \'+\' oder drücke Enter. Gross-/Kleinschreibung wird ignoriert – alles wird in Kleinbuchstaben gespeichert.\n\nWörter entfernen\nTippe auf das \'×\'-Symbol auf einem Chip.\n\nCSV-Import / Export\n• Import (Pfeil nach oben): Lade eine Textdatei mit einem Wort pro Zeile oder kommagetrennt.\n• Export (Pfeil nach unten): Speichere alle Wörter als CSV-Datei.\n\nÄnderungen werden erst nach \'Speichern\' übernommen.'**
  String get keywordsHelpBody;

  /// No description provided for @keywordsTitle.
  ///
  /// In de, this message translates to:
  /// **'Schlüsselwörter'**
  String get keywordsTitle;

  /// No description provided for @keywordsDescription.
  ///
  /// In de, this message translates to:
  /// **'Guardians und Moderatoren werden benachrichtigt, wenn eines dieser Wörter in einem Chat auftaucht.'**
  String get keywordsDescription;

  /// No description provided for @addKeywordHint.
  ///
  /// In de, this message translates to:
  /// **'Neues Wort hinzufügen'**
  String get addKeywordHint;

  /// No description provided for @noKeywordsDefined.
  ///
  /// In de, this message translates to:
  /// **'Keine Schlüsselwörter definiert.'**
  String get noKeywordsDefined;

  /// No description provided for @tabMembers.
  ///
  /// In de, this message translates to:
  /// **'Mitglieder'**
  String get tabMembers;

  /// No description provided for @helpDetailTopicMembersTitle.
  ///
  /// In de, this message translates to:
  /// **'Mitgliederliste & Rollen'**
  String get helpDetailTopicMembersTitle;

  /// No description provided for @helpDetailTopicMembersBody.
  ///
  /// In de, this message translates to:
  /// **'Im Tab \'Mitglieder\' siehst du alle aktiven Personen der Organisation mit ihrer Rolle (Admin, Moderator, Mitglied, Kind).\n\nRollen im 3-Punkte-Menü (Admin):\n• Rolle ändern – Admin, Moderator, Mitglied oder Kind\n• Guardian zuweisen – verbindet ein Kind mit einem Elternteil\n• Mitglied entfernen\n• Admin-Rolle übertragen\n\nMitglieder können die Org selbst verlassen (ausser Admin).'**
  String get helpDetailTopicMembersBody;

  /// No description provided for @helpDetailTopicMembersInviteTitle.
  ///
  /// In de, this message translates to:
  /// **'Einladen, vorschlagen & importieren'**
  String get helpDetailTopicMembersInviteTitle;

  /// No description provided for @helpDetailTopicMembersInviteBody.
  ///
  /// In de, this message translates to:
  /// **'Admin / Moderator – \'+\'-Schaltfläche unten rechts:\n• Einzeln per E-Mail einladen (Rolle und ggf. Guardian wählbar)\n• Im \'Sheltered\'-Modus: Massenimport per CSV-Datei\n\nEingeladene Kinder: erscheinen als ausstehend, bis der Guardian die Einladung in \'Meine Verknüpfungen\' genehmigt.\n\nReguläres Mitglied – \'Mitglied vorschlagen\':\nSchlage eine Person vor. Admin oder Moderator muss den Vorschlag oben im Tab bestätigen.\n\nKind (Guardian-Modus) – \'Chat anfragen\':\nSende eine Anfrage für einen 1:1-Chat. Admin oder Moderator genehmigt oder lehnt ab.'**
  String get helpDetailTopicMembersInviteBody;

  /// No description provided for @helpDetailTopicNotificationsTitle.
  ///
  /// In de, this message translates to:
  /// **'Benachrichtigungen'**
  String get helpDetailTopicNotificationsTitle;

  /// No description provided for @helpDetailTopicNotificationsBody.
  ///
  /// In de, this message translates to:
  /// **'Das Glocken-Symbol (oben rechts) steuert Benachrichtigungen für diese Organisation.\n\nNachrichten-Benachrichtigungen:\n• Jede Nachricht\n• Max. 1x pro Stunde (Standard)\n• Max. 1x pro Tag\n• Nie\n\nKind-Aktivität (Guardian):\nWird benachrichtigt wenn dein Kind eine Nachricht sendet oder empfängt. Intervall ebenfalls einstellbar.'**
  String get helpDetailTopicNotificationsBody;

  /// No description provided for @helpDetailTopicChatsSendTitle.
  ///
  /// In de, this message translates to:
  /// **'Chats – Nachrichten & Medien'**
  String get helpDetailTopicChatsSendTitle;

  /// No description provided for @helpDetailTopicChatsSendBody.
  ///
  /// In de, this message translates to:
  /// **'Textnachrichten: Tippe in das Eingabefeld und sende mit dem Pfeil-Symbol.\n\nBilder, Audio & Dateien: \'+\'-Symbol neben dem Textfeld:\n• Bilder aus der Galerie (JPEG, max. 2 MB)\n• Sprachnachricht aufnehmen (Mikrofon-Symbol)\n• Dateien senden (max. 5 MB)\n\nAntworten: Nachricht lang drücken → \'Antworten\'. Die Ursprungsnachricht erscheint als Zitat.\n\nReaktionen: Nachricht lang drücken → Emoji wählen (👍❤️😂😮😢😡👎). Erneut tippen entfernt die eigene Reaktion.\n\nNachrichten planen: \'+\' → Uhr-Symbol → Datum und Uhrzeit wählen.\n\nUmfragen (Sheltered-Gruppen): \'+\' → Umfrage-Symbol → Frage mit Optionen erstellen.'**
  String get helpDetailTopicChatsSendBody;

  /// No description provided for @helpDetailTopicChatsModTitle.
  ///
  /// In de, this message translates to:
  /// **'Nachrichten moderieren & melden'**
  String get helpDetailTopicChatsModTitle;

  /// No description provided for @helpDetailTopicChatsModBody.
  ///
  /// In de, this message translates to:
  /// **'Eigene Nachrichten bearbeiten: Nachricht lang drücken → \'Bearbeiten\'. Bearbeitete Nachrichten werden im Moderations-Log archiviert.\n\nAdmin/Moderator – Nachrichten verwalten:\n• Fremde Nachrichten bearbeiten oder löschen\n• Nachricht anpinnen → erscheint als Banner oben im Chat\n\nMelden: Fremde Nachricht lang drücken → \'Melden\'. Admin und Moderatoren werden benachrichtigt und sehen die Meldung im Meldungen-Tab.'**
  String get helpDetailTopicChatsModBody;

  /// No description provided for @helpDetailTopicPinnwandTitle.
  ///
  /// In de, this message translates to:
  /// **'Pinnwand lesen'**
  String get helpDetailTopicPinnwandTitle;

  /// No description provided for @helpDetailTopicPinnwandBody.
  ///
  /// In de, this message translates to:
  /// **'Die Pinnwand zeigt offizielle Ankündigungen der Organisation – kein Hin-und-Her wie im Chat, sondern gezielte Informationen von Admins und Moderatoren.\n\nBeiträge haben einen Titel, einen Text und optional ein Ablaufdatum. Abgelaufene Ankündigungen verschwinden automatisch.'**
  String get helpDetailTopicPinnwandBody;

  /// No description provided for @helpDetailTopicPinnwandManageTitle.
  ///
  /// In de, this message translates to:
  /// **'Ankündigungen erstellen & verwalten'**
  String get helpDetailTopicPinnwandManageTitle;

  /// No description provided for @helpDetailTopicPinnwandManageBody.
  ///
  /// In de, this message translates to:
  /// **'Neue Ankündigung: Tippe auf das \'+\'-Symbol unten rechts → Titel und Text eingeben.\n\nAblaufdatum: Optional kannst du festlegen, bis wann eine Ankündigung sichtbar ist. Nach diesem Datum wird sie automatisch ausgeblendet.\n\nBearbeiten oder löschen: Tippe auf das Drei-Punkte-Menü einer Ankündigung.'**
  String get helpDetailTopicPinnwandManageBody;

  /// No description provided for @helpDetailTopicReportsTitle.
  ///
  /// In de, this message translates to:
  /// **'Meldungen'**
  String get helpDetailTopicReportsTitle;

  /// No description provided for @helpDetailTopicReportsBody.
  ///
  /// In de, this message translates to:
  /// **'Der Tab \'Meldungen\' ist nur für Admins und Moderatoren sichtbar.\n\nHier werden gemeldete Nachrichten aufgelistet. Du kannst:\n• Zur gemeldeten Nachricht im Chat springen\n• Die Nachricht löschen\n• Die Meldung als geprüft archivieren\n\nArchivierte Meldungen werden ausgeblendet – der Toggle oben zeigt sie wieder an.'**
  String get helpDetailTopicReportsBody;

  /// No description provided for @tabChats.
  ///
  /// In de, this message translates to:
  /// **'Chats'**
  String get tabChats;

  /// No description provided for @tabReports.
  ///
  /// In de, this message translates to:
  /// **'Meldungen'**
  String get tabReports;

  /// No description provided for @childChatRequests.
  ///
  /// In de, this message translates to:
  /// **'Chat-Anfragen deiner Kinder ({count})'**
  String childChatRequests(int count);

  /// No description provided for @pendingRequests.
  ///
  /// In de, this message translates to:
  /// **'Ausstehende Anfragen ({count})'**
  String pendingRequests(int count);

  /// No description provided for @monitoredChats.
  ///
  /// In de, this message translates to:
  /// **'Überwachte Chats ({count})'**
  String monitoredChats(int count);

  /// No description provided for @archivedChats.
  ///
  /// In de, this message translates to:
  /// **'Archiviert ({count})'**
  String archivedChats(int count);

  /// No description provided for @noChatsGuardian.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Chats.\nStelle eine Anfrage um zu starten.'**
  String get noChatsGuardian;

  /// No description provided for @noChatsSheltered.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Chats.\nDer Admin legt Verbindungen fest.'**
  String get noChatsSheltered;

  /// No description provided for @createGroup.
  ///
  /// In de, this message translates to:
  /// **'Gruppe erstellen'**
  String get createGroup;

  /// No description provided for @groupName.
  ///
  /// In de, this message translates to:
  /// **'Gruppenname'**
  String get groupName;

  /// No description provided for @addMembers.
  ///
  /// In de, this message translates to:
  /// **'Mitglieder hinzufügen'**
  String get addMembers;

  /// No description provided for @csvImport.
  ///
  /// In de, this message translates to:
  /// **'CSV importieren'**
  String get csvImport;

  /// No description provided for @inviteMember.
  ///
  /// In de, this message translates to:
  /// **'Mitglied einladen'**
  String get inviteMember;

  /// No description provided for @suggestMember.
  ///
  /// In de, this message translates to:
  /// **'Mitglied vorschlagen'**
  String get suggestMember;

  /// No description provided for @requestChat.
  ///
  /// In de, this message translates to:
  /// **'Chat anfragen'**
  String get requestChat;

  /// No description provided for @suggestions.
  ///
  /// In de, this message translates to:
  /// **'Vorschläge ({count})'**
  String suggestions(int count);

  /// No description provided for @pendingChildInvitations.
  ///
  /// In de, this message translates to:
  /// **'Ausstehende Kind-Einladungen ({count})'**
  String pendingChildInvitations(int count);

  /// No description provided for @noMembers.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Mitglieder'**
  String get noMembers;

  /// No description provided for @inviteMemberTitle.
  ///
  /// In de, this message translates to:
  /// **'Mitglied einladen'**
  String get inviteMemberTitle;

  /// No description provided for @role.
  ///
  /// In de, this message translates to:
  /// **'Rolle'**
  String get role;

  /// No description provided for @guardians.
  ///
  /// In de, this message translates to:
  /// **'Guardians (Elternteile)'**
  String get guardians;

  /// No description provided for @childGuardianHint.
  ///
  /// In de, this message translates to:
  /// **'Das Kind wird erst hinzugefügt, wenn ein Guardian zustimmt.'**
  String get childGuardianHint;

  /// No description provided for @noGuardiansAvailable.
  ///
  /// In de, this message translates to:
  /// **'Keine Mitglieder als Guardian verfügbar.'**
  String get noGuardiansAvailable;

  /// No description provided for @inviteSentChild.
  ///
  /// In de, this message translates to:
  /// **'Einladung gesendet. Das Kind wird nach Registrierung und Guardian-Zustimmung hinzugefügt.'**
  String get inviteSentChild;

  /// No description provided for @inviteSent.
  ///
  /// In de, this message translates to:
  /// **'Einladung gesendet.'**
  String get inviteSent;

  /// No description provided for @requestChatTitle.
  ///
  /// In de, this message translates to:
  /// **'Chat anfragen'**
  String get requestChatTitle;

  /// No description provided for @requestChatSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Mit wem möchtest du chatten?'**
  String get requestChatSubtitle;

  /// No description provided for @requestChatHint.
  ///
  /// In de, this message translates to:
  /// **'Deine Anfrage wird von einem Admin oder Moderator geprüft.'**
  String get requestChatHint;

  /// No description provided for @requestChatButton.
  ///
  /// In de, this message translates to:
  /// **'Anfragen'**
  String get requestChatButton;

  /// No description provided for @chatRequestSent.
  ///
  /// In de, this message translates to:
  /// **'Chat-Anfrage wurde gesendet.'**
  String get chatRequestSent;

  /// No description provided for @suggestMemberTitle.
  ///
  /// In de, this message translates to:
  /// **'Mitglied vorschlagen'**
  String get suggestMemberTitle;

  /// No description provided for @guardian.
  ///
  /// In de, this message translates to:
  /// **'Guardian'**
  String get guardian;

  /// No description provided for @suggest.
  ///
  /// In de, this message translates to:
  /// **'Vorschlagen'**
  String get suggest;

  /// No description provided for @suggestionSent.
  ///
  /// In de, this message translates to:
  /// **'Vorschlag wurde eingereicht und wartet auf Genehmigung.'**
  String get suggestionSent;

  /// No description provided for @orgNotificationsTitle.
  ///
  /// In de, this message translates to:
  /// **'Benachrichtigungen dieser Org'**
  String get orgNotificationsTitle;

  /// No description provided for @noMessages.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Nachrichten'**
  String get noMessages;

  /// No description provided for @hideArchived.
  ///
  /// In de, this message translates to:
  /// **'Archivierte ausblenden'**
  String get hideArchived;

  /// No description provided for @showArchived.
  ///
  /// In de, this message translates to:
  /// **'Archivierte anzeigen ({count})'**
  String showArchived(int count);

  /// No description provided for @noReports.
  ///
  /// In de, this message translates to:
  /// **'Keine Meldungen'**
  String get noReports;

  /// No description provided for @noPendingReports.
  ///
  /// In de, this message translates to:
  /// **'Keine ausstehenden Meldungen'**
  String get noPendingReports;

  /// No description provided for @reportPending.
  ///
  /// In de, this message translates to:
  /// **'Ausstehend'**
  String get reportPending;

  /// No description provided for @reportReviewed.
  ///
  /// In de, this message translates to:
  /// **'Geprüft · Archiviert'**
  String get reportReviewed;

  /// No description provided for @markReviewed.
  ///
  /// In de, this message translates to:
  /// **'Als geprüft markieren'**
  String get markReviewed;

  /// No description provided for @deleteMessage.
  ///
  /// In de, this message translates to:
  /// **'Nachricht löschen'**
  String get deleteMessage;

  /// No description provided for @deleteMessageTitle.
  ///
  /// In de, this message translates to:
  /// **'Nachricht löschen'**
  String get deleteMessageTitle;

  /// No description provided for @deleteMessageContent.
  ///
  /// In de, this message translates to:
  /// **'Diese Nachricht wird dauerhaft gelöscht und der Report als geprüft markiert.'**
  String get deleteMessageContent;

  /// No description provided for @pendingApproval.
  ///
  /// In de, this message translates to:
  /// **'Wartet auf Genehmigung'**
  String get pendingApproval;

  /// No description provided for @approveTooltip.
  ///
  /// In de, this message translates to:
  /// **'Genehmigen'**
  String get approveTooltip;

  /// No description provided for @rejectTooltip.
  ///
  /// In de, this message translates to:
  /// **'Ablehnen'**
  String get rejectTooltip;

  /// No description provided for @roleAdmin.
  ///
  /// In de, this message translates to:
  /// **'Admin'**
  String get roleAdmin;

  /// No description provided for @roleModerator.
  ///
  /// In de, this message translates to:
  /// **'Moderator'**
  String get roleModerator;

  /// No description provided for @roleMember.
  ///
  /// In de, this message translates to:
  /// **'Mitglied'**
  String get roleMember;

  /// No description provided for @roleChild.
  ///
  /// In de, this message translates to:
  /// **'Kind'**
  String get roleChild;

  /// No description provided for @notificationSettings.
  ///
  /// In de, this message translates to:
  /// **'Benachrichtigungseinstellungen'**
  String get notificationSettings;

  /// No description provided for @leaveOrganization.
  ///
  /// In de, this message translates to:
  /// **'Organisation verlassen'**
  String get leaveOrganization;

  /// No description provided for @changeGuardians.
  ///
  /// In de, this message translates to:
  /// **'Guardians ändern'**
  String get changeGuardians;

  /// No description provided for @startChat.
  ///
  /// In de, this message translates to:
  /// **'Chat starten'**
  String get startChat;

  /// No description provided for @changeRole.
  ///
  /// In de, this message translates to:
  /// **'Rolle ändern'**
  String get changeRole;

  /// No description provided for @transferAdmin.
  ///
  /// In de, this message translates to:
  /// **'Admin-Rolle übertragen'**
  String get transferAdmin;

  /// No description provided for @noActionsAvailable.
  ///
  /// In de, this message translates to:
  /// **'Keine Aktionen verfügbar.'**
  String get noActionsAvailable;

  /// No description provided for @guardiansFor.
  ///
  /// In de, this message translates to:
  /// **'Guardians für {name}'**
  String guardiansFor(String name);

  /// No description provided for @roleFor.
  ///
  /// In de, this message translates to:
  /// **'Rolle für {name}'**
  String roleFor(String name);

  /// No description provided for @guardianFor.
  ///
  /// In de, this message translates to:
  /// **'Guardian für {name}'**
  String guardianFor(String name);

  /// No description provided for @selectGuardianHint.
  ///
  /// In de, this message translates to:
  /// **'Wähle mindestens einen Guardian für dieses Kind:'**
  String get selectGuardianHint;

  /// No description provided for @noGuardiansInOrg.
  ///
  /// In de, this message translates to:
  /// **'Keine möglichen Guardians in dieser Organisation.'**
  String get noGuardiansInOrg;

  /// No description provided for @removeMemberTitle.
  ///
  /// In de, this message translates to:
  /// **'Mitglied entfernen'**
  String get removeMemberTitle;

  /// No description provided for @removeMemberContent.
  ///
  /// In de, this message translates to:
  /// **'{name} wirklich entfernen?'**
  String removeMemberContent(String name);

  /// No description provided for @leaveOrgTitle.
  ///
  /// In de, this message translates to:
  /// **'Organisation verlassen'**
  String get leaveOrgTitle;

  /// No description provided for @leaveOrgContent.
  ///
  /// In de, this message translates to:
  /// **'Möchtest du die Organisation \"{name}\" wirklich verlassen?'**
  String leaveOrgContent(String name);

  /// No description provided for @transferAdminTitle.
  ///
  /// In de, this message translates to:
  /// **'Admin-Rolle übertragen'**
  String get transferAdminTitle;

  /// No description provided for @transferAdminContent.
  ///
  /// In de, this message translates to:
  /// **'Möchtest du die Admin-Rolle an {name} übertragen?\n\nDu wirst danach ein normales Mitglied dieser Organisation.'**
  String transferAdminContent(String name);

  /// No description provided for @childActivityNotifications.
  ///
  /// In de, this message translates to:
  /// **'Kind-Aktivität Benachrichtigungen'**
  String get childActivityNotifications;

  /// No description provided for @pendingChildSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Wartet auf deine Zustimmung'**
  String get pendingChildSubtitle;

  /// No description provided for @approveChildTooltip.
  ///
  /// In de, this message translates to:
  /// **'Zustimmen'**
  String get approveChildTooltip;

  /// No description provided for @memberAdded.
  ///
  /// In de, this message translates to:
  /// **'{name} wurde hinzugefügt.'**
  String memberAdded(String name);

  /// No description provided for @withdrawInvitationTitle.
  ///
  /// In de, this message translates to:
  /// **'Einladung zurückziehen'**
  String get withdrawInvitationTitle;

  /// No description provided for @withdrawInvitationContent.
  ///
  /// In de, this message translates to:
  /// **'Einladung für {email} wirklich zurückziehen?'**
  String withdrawInvitationContent(String email);

  /// No description provided for @withdraw.
  ///
  /// In de, this message translates to:
  /// **'Zurückziehen'**
  String get withdraw;

  /// No description provided for @tabPinboard.
  ///
  /// In de, this message translates to:
  /// **'Pinnwand'**
  String get tabPinboard;

  /// No description provided for @announcementExpiresOn.
  ///
  /// In de, this message translates to:
  /// **'Läuft ab: {date}'**
  String announcementExpiresOn(String date);

  /// No description provided for @announcementExpired.
  ///
  /// In de, this message translates to:
  /// **'Abgelaufen'**
  String get announcementExpired;

  /// No description provided for @announcementSetExpiry.
  ///
  /// In de, this message translates to:
  /// **'Ablaufdatum setzen'**
  String get announcementSetExpiry;

  /// No description provided for @announcementNoExpiry.
  ///
  /// In de, this message translates to:
  /// **'Kein Ablaufdatum'**
  String get announcementNoExpiry;

  /// No description provided for @announcementRemoveExpiry.
  ///
  /// In de, this message translates to:
  /// **'Ablaufdatum entfernen'**
  String get announcementRemoveExpiry;

  /// No description provided for @pinnedMessage.
  ///
  /// In de, this message translates to:
  /// **'Angepinnte Nachricht'**
  String get pinnedMessage;

  /// No description provided for @pinMessage.
  ///
  /// In de, this message translates to:
  /// **'Anpinnen'**
  String get pinMessage;

  /// No description provided for @unpinMessage.
  ///
  /// In de, this message translates to:
  /// **'Loslösen'**
  String get unpinMessage;

  /// No description provided for @anonymousPoll.
  ///
  /// In de, this message translates to:
  /// **'Anonym'**
  String get anonymousPoll;

  /// No description provided for @pollVotersTitle.
  ///
  /// In de, this message translates to:
  /// **'Abstimmungsdetails'**
  String get pollVotersTitle;

  /// No description provided for @pollVoteNotifTitle.
  ///
  /// In de, this message translates to:
  /// **'Neue Stimme'**
  String get pollVoteNotifTitle;

  /// No description provided for @pollVoteNotifBody.
  ///
  /// In de, this message translates to:
  /// **'{name} hat an deiner Abstimmung \"{question}\" teilgenommen.'**
  String pollVoteNotifBody(String name, String question);

  /// No description provided for @newAnnouncement.
  ///
  /// In de, this message translates to:
  /// **'Ankündigung erstellen'**
  String get newAnnouncement;

  /// No description provided for @editAnnouncement.
  ///
  /// In de, this message translates to:
  /// **'Ankündigung bearbeiten'**
  String get editAnnouncement;

  /// No description provided for @announcementTitleLabel.
  ///
  /// In de, this message translates to:
  /// **'Titel'**
  String get announcementTitleLabel;

  /// No description provided for @announcementContentLabel.
  ///
  /// In de, this message translates to:
  /// **'Nachricht'**
  String get announcementContentLabel;

  /// No description provided for @noAnnouncements.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Ankündigungen'**
  String get noAnnouncements;

  /// No description provided for @deleteAnnouncementTitle.
  ///
  /// In de, this message translates to:
  /// **'Ankündigung löschen'**
  String get deleteAnnouncementTitle;

  /// No description provided for @deleteAnnouncementContent.
  ///
  /// In de, this message translates to:
  /// **'Diese Ankündigung wirklich löschen?'**
  String get deleteAnnouncementContent;

  /// No description provided for @announcementEdited.
  ///
  /// In de, this message translates to:
  /// **'bearbeitet'**
  String get announcementEdited;

  /// No description provided for @announcementBy.
  ///
  /// In de, this message translates to:
  /// **'von {name}'**
  String announcementBy(String name);

  /// No description provided for @scheduleMessage.
  ///
  /// In de, this message translates to:
  /// **'Nachricht planen'**
  String get scheduleMessage;

  /// No description provided for @scheduledMessages.
  ///
  /// In de, this message translates to:
  /// **'Geplante Nachrichten ({count})'**
  String scheduledMessages(int count);

  /// No description provided for @scheduleFor.
  ///
  /// In de, this message translates to:
  /// **'Senden am'**
  String get scheduleFor;

  /// No description provided for @scheduledAt.
  ///
  /// In de, this message translates to:
  /// **'Geplant für {time}'**
  String scheduledAt(String time);

  /// No description provided for @cancelScheduled.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get cancelScheduled;

  /// No description provided for @scheduleHint.
  ///
  /// In de, this message translates to:
  /// **'Nachrichten werden nur gesendet solange die App geöffnet ist.'**
  String get scheduleHint;

  /// No description provided for @helpChatTitle.
  ///
  /// In de, this message translates to:
  /// **'Chat – Hilfe'**
  String get helpChatTitle;

  /// No description provided for @helpChatWriteTitle.
  ///
  /// In de, this message translates to:
  /// **'Nachrichten schreiben & senden'**
  String get helpChatWriteTitle;

  /// No description provided for @helpChatWriteBody.
  ///
  /// In de, this message translates to:
  /// **'Tippe deine Nachricht in das Textfeld und drücke den Senden-Pfeil. URLs im Text werden automatisch als anklickbare Links erkannt.'**
  String get helpChatWriteBody;

  /// No description provided for @helpChatMediaTitle.
  ///
  /// In de, this message translates to:
  /// **'Bilder, Audio & Dateien'**
  String get helpChatMediaTitle;

  /// No description provided for @helpChatMediaBody.
  ///
  /// In de, this message translates to:
  /// **'Tippe auf das \'+\'-Symbol links neben dem Textfeld, um ein Bild aus der Galerie oder der Kamera zu wählen, eine Sprachaufnahme zu starten oder eine Datei anzuhängen.'**
  String get helpChatMediaBody;

  /// No description provided for @helpChatReactTitle.
  ///
  /// In de, this message translates to:
  /// **'Antworten & Reaktionen'**
  String get helpChatReactTitle;

  /// No description provided for @helpChatReactBody.
  ///
  /// In de, this message translates to:
  /// **'Halte eine Nachricht gedrückt, um ein Kontextmenü zu öffnen. Dort kannst du auf eine Nachricht antworten oder mit einem Emoji reagieren. Eine Antwort erscheint mit Vorschau der Originalnachricht.'**
  String get helpChatReactBody;

  /// No description provided for @helpChatScheduleTitle.
  ///
  /// In de, this message translates to:
  /// **'Planen & Umfragen'**
  String get helpChatScheduleTitle;

  /// No description provided for @helpChatScheduleBody.
  ///
  /// In de, this message translates to:
  /// **'Im \'+\'-Menü kannst du eine Nachricht zeitgesteuert planen. In Gruppen mit \'Betreut\'-Modus ist ausserdem das Erstellen von Umfragen möglich.'**
  String get helpChatScheduleBody;

  /// No description provided for @helpChatModerateTitle.
  ///
  /// In de, this message translates to:
  /// **'Nachrichten moderieren & bearbeiten'**
  String get helpChatModerateTitle;

  /// No description provided for @helpChatModerateBody.
  ///
  /// In de, this message translates to:
  /// **'Du kannst eigene Nachrichten bearbeiten oder löschen. Administratoren und Moderatoren können zusätzlich beliebige Nachrichten löschen, bearbeiten oder anpinnen.'**
  String get helpChatModerateBody;

  /// No description provided for @helpChatReportTitle.
  ///
  /// In de, this message translates to:
  /// **'Melden, Kopieren & Suchen'**
  String get helpChatReportTitle;

  /// No description provided for @helpChatReportBody.
  ///
  /// In de, this message translates to:
  /// **'Halte eine Nachricht gedrückt und wähle \'Melden\', um Missbrauch zu melden, oder \'Kopieren\', um den Text zu kopieren. Mit dem Lupen-Symbol in der Titelleiste durchsuchst du alle Nachrichten.'**
  String get helpChatReportBody;

  /// No description provided for @searchMessages.
  ///
  /// In de, this message translates to:
  /// **'Nachrichten suchen'**
  String get searchMessages;

  /// No description provided for @searchHint.
  ///
  /// In de, this message translates to:
  /// **'Suchen…'**
  String get searchHint;

  /// No description provided for @searchNoResults.
  ///
  /// In de, this message translates to:
  /// **'Keine Treffer'**
  String get searchNoResults;

  /// No description provided for @searchResults.
  ///
  /// In de, this message translates to:
  /// **'{count} Treffer'**
  String searchResults(int count);

  /// No description provided for @reply.
  ///
  /// In de, this message translates to:
  /// **'Antworten'**
  String get reply;

  /// No description provided for @replyingTo.
  ///
  /// In de, this message translates to:
  /// **'Antwortet {name}'**
  String replyingTo(String name);

  /// No description provided for @microphoneDenied.
  ///
  /// In de, this message translates to:
  /// **'Mikrofon-Zugriff wurde verweigert.'**
  String get microphoneDenied;

  /// No description provided for @createPollTitle.
  ///
  /// In de, this message translates to:
  /// **'Umfrage erstellen'**
  String get createPollTitle;

  /// No description provided for @pollQuestion.
  ///
  /// In de, this message translates to:
  /// **'Frage'**
  String get pollQuestion;

  /// No description provided for @pollOptions.
  ///
  /// In de, this message translates to:
  /// **'Antwortmöglichkeiten'**
  String get pollOptions;

  /// No description provided for @addOption.
  ///
  /// In de, this message translates to:
  /// **'Option hinzufügen'**
  String get addOption;

  /// No description provided for @multipleChoice.
  ///
  /// In de, this message translates to:
  /// **'Mehrfachauswahl'**
  String get multipleChoice;

  /// No description provided for @addMemberTitle.
  ///
  /// In de, this message translates to:
  /// **'Mitglied hinzufügen'**
  String get addMemberTitle;

  /// No description provided for @allMembersInChat.
  ///
  /// In de, this message translates to:
  /// **'Alle Mitglieder sind bereits im Chat.'**
  String get allMembersInChat;

  /// No description provided for @membersTooltip.
  ///
  /// In de, this message translates to:
  /// **'Mitglieder anzeigen'**
  String get membersTooltip;

  /// No description provided for @archivedReadOnly.
  ///
  /// In de, this message translates to:
  /// **'Archiviert – nur lesen'**
  String get archivedReadOnly;

  /// No description provided for @sendError.
  ///
  /// In de, this message translates to:
  /// **'Fehler beim Senden: {error}'**
  String sendError(String error);

  /// No description provided for @olderMessages.
  ///
  /// In de, this message translates to:
  /// **'Ältere Nachrichten'**
  String get olderMessages;

  /// No description provided for @copyText.
  ///
  /// In de, this message translates to:
  /// **'Text kopieren'**
  String get copyText;

  /// No description provided for @moderate.
  ///
  /// In de, this message translates to:
  /// **'Moderieren'**
  String get moderate;

  /// No description provided for @reportMessage.
  ///
  /// In de, this message translates to:
  /// **'Nachricht melden'**
  String get reportMessage;

  /// No description provided for @editedPrefix.
  ///
  /// In de, this message translates to:
  /// **'bearbeitet · '**
  String get editedPrefix;

  /// No description provided for @today.
  ///
  /// In de, this message translates to:
  /// **'Heute'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In de, this message translates to:
  /// **'Gestern'**
  String get yesterday;

  /// No description provided for @sendImage.
  ///
  /// In de, this message translates to:
  /// **'Bild senden'**
  String get sendImage;

  /// No description provided for @sendFile.
  ///
  /// In de, this message translates to:
  /// **'Datei senden (max. 5 MB)'**
  String get sendFile;

  /// No description provided for @voiceRecording.
  ///
  /// In de, this message translates to:
  /// **'Sprachaufnahme'**
  String get voiceRecording;

  /// No description provided for @createPoll.
  ///
  /// In de, this message translates to:
  /// **'Umfrage erstellen'**
  String get createPoll;

  /// No description provided for @messageHint.
  ///
  /// In de, this message translates to:
  /// **'Nachricht schreiben...'**
  String get messageHint;

  /// No description provided for @attachmentTooltip.
  ///
  /// In de, this message translates to:
  /// **'Anhang'**
  String get attachmentTooltip;

  /// No description provided for @voiceTooltip.
  ///
  /// In de, this message translates to:
  /// **'Sprachnachricht'**
  String get voiceTooltip;

  /// No description provided for @recordingIndicator.
  ///
  /// In de, this message translates to:
  /// **'Aufnahme läuft…'**
  String get recordingIndicator;

  /// No description provided for @endPollTitle.
  ///
  /// In de, this message translates to:
  /// **'Umfrage beenden'**
  String get endPollTitle;

  /// No description provided for @endPollContent.
  ///
  /// In de, this message translates to:
  /// **'Die Umfrage beenden? Danach kann nicht mehr abgestimmt werden.'**
  String get endPollContent;

  /// No description provided for @endPoll.
  ///
  /// In de, this message translates to:
  /// **'Beenden'**
  String get endPoll;

  /// No description provided for @pollClosed.
  ///
  /// In de, this message translates to:
  /// **'Abgeschlossen'**
  String get pollClosed;

  /// No description provided for @poll.
  ///
  /// In de, this message translates to:
  /// **'Umfrage'**
  String get poll;

  /// No description provided for @pollExpiresOn.
  ///
  /// In de, this message translates to:
  /// **'Endet am {date}'**
  String pollExpiresOn(String date);

  /// No description provided for @pollExpired.
  ///
  /// In de, this message translates to:
  /// **'Abgelaufen'**
  String get pollExpired;

  /// No description provided for @addExpiry.
  ///
  /// In de, this message translates to:
  /// **'Ablaufdatum hinzufügen'**
  String get addExpiry;

  /// No description provided for @noExpiry.
  ///
  /// In de, this message translates to:
  /// **'Kein Ablaufdatum'**
  String get noExpiry;

  /// No description provided for @votes.
  ///
  /// In de, this message translates to:
  /// **'{count} Stimmen'**
  String votes(int count);

  /// No description provided for @oneVote.
  ///
  /// In de, this message translates to:
  /// **'1 Stimme'**
  String get oneVote;

  /// No description provided for @removeMembersTitle.
  ///
  /// In de, this message translates to:
  /// **'Mitglieder entfernen'**
  String get removeMembersTitle;

  /// No description provided for @removeMemberFromChat.
  ///
  /// In de, this message translates to:
  /// **'{name} aus dem Chat entfernen?'**
  String removeMemberFromChat(String name);

  /// No description provided for @moderatedBy.
  ///
  /// In de, this message translates to:
  /// **'von {name} moderiert'**
  String moderatedBy(String name);

  /// No description provided for @moderatedByModerator.
  ///
  /// In de, this message translates to:
  /// **'von Moderator moderiert'**
  String get moderatedByModerator;

  /// No description provided for @helpImportTitle.
  ///
  /// In de, this message translates to:
  /// **'Massenimport – Hilfe'**
  String get helpImportTitle;

  /// No description provided for @helpImportFormatTitle.
  ///
  /// In de, this message translates to:
  /// **'CSV-Format'**
  String get helpImportFormatTitle;

  /// No description provided for @helpImportFormatBody.
  ///
  /// In de, this message translates to:
  /// **'Die Datei muss die Spalten email, rolle und guardians enthalten (Kopfzeile optional). Als Trennzeichen werden , und ; automatisch erkannt.\n\nBeispiel:\nemail;rolle;guardians\nkind@schule.de;kind;eltern@schule.de\nmitglied@schule.de;mitglied;'**
  String get helpImportFormatBody;

  /// No description provided for @helpImportRolesTitle.
  ///
  /// In de, this message translates to:
  /// **'Gültige Rollen'**
  String get helpImportRolesTitle;

  /// No description provided for @helpImportRolesBody.
  ///
  /// In de, this message translates to:
  /// **'mitglied (oder member) · moderator (oder mod) · kind (oder child)\n\nGross-/Kleinschreibung wird ignoriert.'**
  String get helpImportRolesBody;

  /// No description provided for @helpImportChildrenTitle.
  ///
  /// In de, this message translates to:
  /// **'Kinder importieren'**
  String get helpImportChildrenTitle;

  /// No description provided for @helpImportChildrenBody.
  ///
  /// In de, this message translates to:
  /// **'Für Zeilen mit der Rolle \'kind\' muss die Guardians-Spalte mindestens eine E-Mail-Adresse enthalten. Die genannten Guardians müssen bereits Mitglieder dieser Organisation sein.'**
  String get helpImportChildrenBody;

  /// No description provided for @helpImportPreviewTitle.
  ///
  /// In de, this message translates to:
  /// **'Vorschau & Validierung'**
  String get helpImportPreviewTitle;

  /// No description provided for @helpImportPreviewBody.
  ///
  /// In de, this message translates to:
  /// **'Nach dem Laden der Datei wird jede Zeile geprüft. Ein rotes Symbol zeigt einen Fehler (Zeile wird nicht importiert), ein gelbes Symbol zeigt eine Warnung (Import trotzdem möglich).'**
  String get helpImportPreviewBody;

  /// No description provided for @helpImportRunTitle.
  ///
  /// In de, this message translates to:
  /// **'Import starten'**
  String get helpImportRunTitle;

  /// No description provided for @helpImportRunBody.
  ///
  /// In de, this message translates to:
  /// **'Tippe oben rechts auf \'X importieren\'. Die Schaltfläche erscheint nur, wenn mindestens eine gültige Zeile vorhanden ist. Nach dem Import zeigt ein Log-Protokoll für jede Zeile ob sie erfolgreich war oder fehlgeschlagen ist.'**
  String get helpImportRunBody;

  /// No description provided for @importMembers.
  ///
  /// In de, this message translates to:
  /// **'Mitglieder importieren'**
  String get importMembers;

  /// No description provided for @selectCsvFile.
  ///
  /// In de, this message translates to:
  /// **'CSV-Datei auswählen'**
  String get selectCsvFile;

  /// No description provided for @importCount.
  ///
  /// In de, this message translates to:
  /// **'{count} importieren'**
  String importCount(int count);

  /// No description provided for @csvRowsValid.
  ///
  /// In de, this message translates to:
  /// **'{total} Zeilen · {valid} gültig'**
  String csvRowsValid(int total, int valid);

  /// No description provided for @csvRowsErrors.
  ///
  /// In de, this message translates to:
  /// **'{total} Zeilen · {valid} gültig · {errors} fehlerhaft'**
  String csvRowsErrors(int total, int valid, int errors);

  /// No description provided for @importSuccess.
  ///
  /// In de, this message translates to:
  /// **'{count} eingeladen'**
  String importSuccess(int count);

  /// No description provided for @importSuccessWithErrors.
  ///
  /// In de, this message translates to:
  /// **'{count} eingeladen, {errors} Fehler'**
  String importSuccessWithErrors(int count, int errors);

  /// No description provided for @invalidEmail2.
  ///
  /// In de, this message translates to:
  /// **'Ungültige E-Mail'**
  String get invalidEmail2;

  /// No description provided for @unknownRole.
  ///
  /// In de, this message translates to:
  /// **'Unbekannte Rolle: \"{role}\"'**
  String unknownRole(String role);

  /// No description provided for @guardianMissing.
  ///
  /// In de, this message translates to:
  /// **'Guardian fehlt'**
  String get guardianMissing;

  /// No description provided for @noGuardianInOrg.
  ///
  /// In de, this message translates to:
  /// **'Kein Guardian in dieser Org gefunden'**
  String get noGuardianInOrg;

  /// No description provided for @guardianNotInOrg.
  ///
  /// In de, this message translates to:
  /// **'Guardian nicht in Org: {emails}'**
  String guardianNotInOrg(String emails);

  /// No description provided for @donationTitle.
  ///
  /// In de, this message translates to:
  /// **'Guardian Com unterstützen'**
  String get donationTitle;

  /// No description provided for @donationContent.
  ///
  /// In de, this message translates to:
  /// **'Guardian Com ist kostenlos und werbefrei. Wenn dir die App gefällt, freue ich mich über eine kleine Spende!'**
  String get donationContent;

  /// No description provided for @kofiButton.
  ///
  /// In de, this message translates to:
  /// **'Ko-fi spenden'**
  String get kofiButton;

  /// No description provided for @paypalButton.
  ///
  /// In de, this message translates to:
  /// **'PayPal spenden'**
  String get paypalButton;

  /// No description provided for @maybeLater.
  ///
  /// In de, this message translates to:
  /// **'Vielleicht später'**
  String get maybeLater;

  /// No description provided for @neverShowAgain.
  ///
  /// In de, this message translates to:
  /// **'Nicht mehr anzeigen'**
  String get neverShowAgain;

  /// No description provided for @batteryOptTitle.
  ///
  /// In de, this message translates to:
  /// **'Akku-Optimierung deaktivieren'**
  String get batteryOptTitle;

  /// No description provided for @batteryOptContent.
  ///
  /// In de, this message translates to:
  /// **'Für zuverlässige Push-Benachrichtigungen empfiehlt es sich, die Akku-Optimierung für Guardian Com zu deaktivieren. Andernfalls kann Android Benachrichtigungen im Hintergrund verzögern oder blockieren.'**
  String get batteryOptContent;

  /// No description provided for @batteryOptSetup.
  ///
  /// In de, this message translates to:
  /// **'Jetzt einrichten'**
  String get batteryOptSetup;

  /// No description provided for @batteryOptDontAsk.
  ///
  /// In de, this message translates to:
  /// **'Nicht mehr fragen'**
  String get batteryOptDontAsk;

  /// No description provided for @aboutApp.
  ///
  /// In de, this message translates to:
  /// **'Über die App'**
  String get aboutApp;

  /// No description provided for @aboutAppDialogTitle.
  ///
  /// In de, this message translates to:
  /// **'Guardian Com'**
  String get aboutAppDialogTitle;

  /// No description provided for @aboutAppDescription.
  ///
  /// In de, this message translates to:
  /// **'Sichere, beaufsichtigte Kommunikation für Organisationen – kostenlos und werbefrei.'**
  String get aboutAppDescription;

  /// No description provided for @openSourceLicenses.
  ///
  /// In de, this message translates to:
  /// **'Open-Source-Lizenzen'**
  String get openSourceLicenses;

  /// No description provided for @githubRepository.
  ///
  /// In de, this message translates to:
  /// **'GitHub-Repository'**
  String get githubRepository;

  /// No description provided for @typingOne.
  ///
  /// In de, this message translates to:
  /// **'{name} schreibt…'**
  String typingOne(String name);

  /// No description provided for @typingMultiple.
  ///
  /// In de, this message translates to:
  /// **'{names} schreiben…'**
  String typingMultiple(String names);

  /// No description provided for @createOrganization.
  ///
  /// In de, this message translates to:
  /// **'Organisation erstellen'**
  String get createOrganization;

  /// No description provided for @orgNameLabel.
  ///
  /// In de, this message translates to:
  /// **'Name der Organisation'**
  String get orgNameLabel;

  /// No description provided for @myOrganizations.
  ///
  /// In de, this message translates to:
  /// **'Meine Organisationen'**
  String get myOrganizations;

  /// No description provided for @helpLabel.
  ///
  /// In de, this message translates to:
  /// **'Hilfe'**
  String get helpLabel;

  /// No description provided for @helpTourButton.
  ///
  /// In de, this message translates to:
  /// **'Tour starten'**
  String get helpTourButton;

  /// No description provided for @helpOrgTopicOrgsTitle.
  ///
  /// In de, this message translates to:
  /// **'Was sind Organisationen?'**
  String get helpOrgTopicOrgsTitle;

  /// No description provided for @helpOrgTopicOrgsBody.
  ///
  /// In de, this message translates to:
  /// **'Organisationen sind Gruppen für sichere Kommunikation – z. B. Familie, Schule oder Verein. Du kannst selbst Organisationen erstellen oder per Einladung beitreten.'**
  String get helpOrgTopicOrgsBody;

  /// No description provided for @helpOrgTopicRolesTitle.
  ///
  /// In de, this message translates to:
  /// **'Rollen'**
  String get helpOrgTopicRolesTitle;

  /// No description provided for @helpOrgTopicRolesBody.
  ///
  /// In de, this message translates to:
  /// **'Admin – Volle Kontrolle, verwaltet alle Mitglieder und Einstellungen.\nModerator – Kann Chats einsehen und genehmigen.\nMitglied – Kann Chats anfordern und kommunizieren.\nKind – Eingeschränkt, benötigt einen Guardian und Eltern-Zustimmung bei Einladungen.'**
  String get helpOrgTopicRolesBody;

  /// No description provided for @helpOrgTopicChatModesTitle.
  ///
  /// In de, this message translates to:
  /// **'Chat-Modi'**
  String get helpOrgTopicChatModesTitle;

  /// No description provided for @helpOrgTopicChatModesBody.
  ///
  /// In de, this message translates to:
  /// **'Guardian-Modus – Mitglieder beantragen Chats, Admins oder Moderatoren genehmigen sie.\nSheltered-Modus – Der Admin legt vorab fest, wer mit wem kommunizieren darf. Gruppen-Chats sind möglich.'**
  String get helpOrgTopicChatModesBody;

  /// No description provided for @helpOrgTopicInviteTitle.
  ///
  /// In de, this message translates to:
  /// **'Mitglieder einladen'**
  String get helpOrgTopicInviteTitle;

  /// No description provided for @helpOrgTopicInviteBody.
  ///
  /// In de, this message translates to:
  /// **'Öffne eine Organisation → tippe auf das Personen-Symbol → E-Mail eingeben und Rolle wählen. Als Admin kannst du in Sheltered-Orgs auch mehrere Mitglieder per CSV-Datei importieren.'**
  String get helpOrgTopicInviteBody;

  /// No description provided for @helpOrgTopicFamilyTitle.
  ///
  /// In de, this message translates to:
  /// **'Eltern-Kind-Verknüpfung'**
  String get helpOrgTopicFamilyTitle;

  /// No description provided for @helpOrgTopicFamilyBody.
  ///
  /// In de, this message translates to:
  /// **'Kind-Konten sind global auf die Rolle \'Kind\' gesperrt. Wird ein Kind in eine Org eingeladen, müssen die Eltern zuerst zustimmen. Der Baum-Button oben öffnet deine Familienübersicht.'**
  String get helpOrgTopicFamilyBody;

  /// No description provided for @tourStepProfileTitle.
  ///
  /// In de, this message translates to:
  /// **'Profil & Einstellungen'**
  String get tourStepProfileTitle;

  /// No description provided for @tourStepProfileDesc.
  ///
  /// In de, this message translates to:
  /// **'Tippe hier um dein Profil zu bearbeiten, Benachrichtigungen anzupassen oder dich abzumelden.'**
  String get tourStepProfileDesc;

  /// No description provided for @tourStepFamilyTitle.
  ///
  /// In de, this message translates to:
  /// **'Familienübersicht'**
  String get tourStepFamilyTitle;

  /// No description provided for @tourStepFamilyDesc.
  ///
  /// In de, this message translates to:
  /// **'Öffnet deine verifizierten Eltern- und Kind-Verbindungen. Das Badge zeigt ausstehende Aktionen.'**
  String get tourStepFamilyDesc;

  /// No description provided for @tourStepOrgCardTitle.
  ///
  /// In de, this message translates to:
  /// **'Deine Organisationen'**
  String get tourStepOrgCardTitle;

  /// No description provided for @tourStepOrgCardDesc.
  ///
  /// In de, this message translates to:
  /// **'Tippe auf eine Karte um die Organisation zu öffnen. Als Admin siehst du oben rechts ein Menü mit weiteren Optionen.'**
  String get tourStepOrgCardDesc;

  /// No description provided for @tourStepFabTitle.
  ///
  /// In de, this message translates to:
  /// **'Organisation erstellen'**
  String get tourStepFabTitle;

  /// No description provided for @tourStepFabDesc.
  ///
  /// In de, this message translates to:
  /// **'Tippe hier um eine neue Organisation zu erstellen und Chat-Modus sowie Kategorie festzulegen.'**
  String get tourStepFabDesc;

  /// No description provided for @noOrganizations.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Organisationen'**
  String get noOrganizations;

  /// No description provided for @archivedBadge.
  ///
  /// In de, this message translates to:
  /// **'Archiviert'**
  String get archivedBadge;

  /// No description provided for @deleteOrgTitle.
  ///
  /// In de, this message translates to:
  /// **'Organisation löschen?'**
  String get deleteOrgTitle;

  /// No description provided for @deleteOrgContent.
  ///
  /// In de, this message translates to:
  /// **'\"{name}\" und alle Mitgliedschaften werden unwiderruflich gelöscht.'**
  String deleteOrgContent(String name);

  /// No description provided for @open.
  ///
  /// In de, this message translates to:
  /// **'Öffnen'**
  String get open;

  /// No description provided for @unarchive.
  ///
  /// In de, this message translates to:
  /// **'Wiederherstellen'**
  String get unarchive;

  /// No description provided for @saveImage.
  ///
  /// In de, this message translates to:
  /// **'Bild speichern'**
  String get saveImage;

  /// No description provided for @imageSaved.
  ///
  /// In de, this message translates to:
  /// **'Bild gespeichert'**
  String get imageSaved;

  /// No description provided for @helpRelTitle.
  ///
  /// In de, this message translates to:
  /// **'Verknüpfungen – Hilfe'**
  String get helpRelTitle;

  /// No description provided for @helpRelOverviewTitle.
  ///
  /// In de, this message translates to:
  /// **'Was ist eine Eltern-Kind-Verknüpfung?'**
  String get helpRelOverviewTitle;

  /// No description provided for @helpRelOverviewBody.
  ///
  /// In de, this message translates to:
  /// **'Eine Verknüpfung verbindet ein Elternteil mit einem Kind. Das Kind erhält in allen Organisationen die Rolle \'Kind\' und kann ohne Genehmigung des Elternteils keiner neuen Organisation beitreten.'**
  String get helpRelOverviewBody;

  /// No description provided for @helpRelConnectTitle.
  ///
  /// In de, this message translates to:
  /// **'Kind verbinden'**
  String get helpRelConnectTitle;

  /// No description provided for @helpRelConnectBody.
  ///
  /// In de, this message translates to:
  /// **'Gib die E-Mail-Adresse des Kontos ein, das du als Kind verknüpfen möchtest, und tippe auf \'Anfrage senden\'. Das Kind muss die Anfrage anschliessend in dieser Ansicht bestätigen.'**
  String get helpRelConnectBody;

  /// No description provided for @helpRelIncomingTitle.
  ///
  /// In de, this message translates to:
  /// **'Eingehende Anfragen'**
  String get helpRelIncomingTitle;

  /// No description provided for @helpRelIncomingBody.
  ///
  /// In de, this message translates to:
  /// **'Wenn jemand eine Verknüpfungsanfrage an dich schickt, erscheint sie hier. Du kannst sie bestätigen oder ablehnen. Beim Bestätigen wirst du der Rolle \'Kind\' in allen deinen Organisationen zugewiesen.'**
  String get helpRelIncomingBody;

  /// No description provided for @helpRelConsentsTitle.
  ///
  /// In de, this message translates to:
  /// **'Org-Einladungen genehmigen'**
  String get helpRelConsentsTitle;

  /// No description provided for @helpRelConsentsBody.
  ///
  /// In de, this message translates to:
  /// **'Wenn ein Kind zu einer Organisation eingeladen wird, erscheint die Einladung hier zur Genehmigung. Als Elternteil kannst du die Einladung freigeben oder ablehnen.'**
  String get helpRelConsentsBody;

  /// No description provided for @helpRelRevokeTitle.
  ///
  /// In de, this message translates to:
  /// **'Verbindung trennen'**
  String get helpRelRevokeTitle;

  /// No description provided for @helpRelRevokeBody.
  ///
  /// In de, this message translates to:
  /// **'Tippe auf den Namen einer verknüpften Person und wähle \'Verbindung trennen\'. Kinder können die Verbindung nicht selbst auflösen – das kann nur das Elternteil tun.'**
  String get helpRelRevokeBody;

  /// No description provided for @myRelationships.
  ///
  /// In de, this message translates to:
  /// **'Meine Verknüpfungen'**
  String get myRelationships;

  /// No description provided for @myParents.
  ///
  /// In de, this message translates to:
  /// **'Meine Eltern'**
  String get myParents;

  /// No description provided for @myChildren.
  ///
  /// In de, this message translates to:
  /// **'Meine Kinder'**
  String get myChildren;

  /// No description provided for @noParents.
  ///
  /// In de, this message translates to:
  /// **'Keine verifizierten Eltern'**
  String get noParents;

  /// No description provided for @noChildren.
  ///
  /// In de, this message translates to:
  /// **'Keine verifizierten Kinder'**
  String get noChildren;

  /// No description provided for @verifiedParent.
  ///
  /// In de, this message translates to:
  /// **'Verifiziertes Elternteil'**
  String get verifiedParent;

  /// No description provided for @verifiedChild.
  ///
  /// In de, this message translates to:
  /// **'Verifiziertes Kind'**
  String get verifiedChild;

  /// No description provided for @connectChild.
  ///
  /// In de, this message translates to:
  /// **'Kind verknüpfen'**
  String get connectChild;

  /// No description provided for @connectChildHint.
  ///
  /// In de, this message translates to:
  /// **'E-Mail-Adresse des Kindes eingeben'**
  String get connectChildHint;

  /// No description provided for @sendClaimRequest.
  ///
  /// In de, this message translates to:
  /// **'Verknüpfungsanfrage senden'**
  String get sendClaimRequest;

  /// No description provided for @claimRequestSent.
  ///
  /// In de, this message translates to:
  /// **'Anfrage gesendet.'**
  String get claimRequestSent;

  /// No description provided for @claimRequestNotFound.
  ///
  /// In de, this message translates to:
  /// **'Kein Benutzer mit dieser E-Mail gefunden.'**
  String get claimRequestNotFound;

  /// No description provided for @claimRequestAlreadyExists.
  ///
  /// In de, this message translates to:
  /// **'Eine Anfrage für diesen Benutzer existiert bereits.'**
  String get claimRequestAlreadyExists;

  /// No description provided for @claimRequestCancelTitle.
  ///
  /// In de, this message translates to:
  /// **'Anfrage zurückziehen'**
  String get claimRequestCancelTitle;

  /// No description provided for @claimRequestCancelContent.
  ///
  /// In de, this message translates to:
  /// **'Verknüpfungsanfrage an {email} wirklich zurückziehen?'**
  String claimRequestCancelContent(String email);

  /// No description provided for @incomingClaimRequests.
  ///
  /// In de, this message translates to:
  /// **'Eingehende Anfragen ({count})'**
  String incomingClaimRequests(int count);

  /// No description provided for @wantsToBeYourParent.
  ///
  /// In de, this message translates to:
  /// **'{name} möchte dein Elternteil sein'**
  String wantsToBeYourParent(String name);

  /// No description provided for @confirmClaim.
  ///
  /// In de, this message translates to:
  /// **'Bestätigen'**
  String get confirmClaim;

  /// No description provided for @rejectClaim.
  ///
  /// In de, this message translates to:
  /// **'Ablehnen'**
  String get rejectClaim;

  /// No description provided for @claimConfirmed.
  ///
  /// In de, this message translates to:
  /// **'Verknüpfung bestätigt.'**
  String get claimConfirmed;

  /// No description provided for @claimRejected.
  ///
  /// In de, this message translates to:
  /// **'Anfrage abgelehnt.'**
  String get claimRejected;

  /// No description provided for @revokeConnection.
  ///
  /// In de, this message translates to:
  /// **'Verknüpfung aufheben'**
  String get revokeConnection;

  /// No description provided for @revokeConnectionTitle.
  ///
  /// In de, this message translates to:
  /// **'Verknüpfung aufheben'**
  String get revokeConnectionTitle;

  /// No description provided for @revokeConnectionContent.
  ///
  /// In de, this message translates to:
  /// **'Verknüpfung mit {name} wirklich aufheben?'**
  String revokeConnectionContent(String name);

  /// No description provided for @roleConflictTitle.
  ///
  /// In de, this message translates to:
  /// **'Rollenkonflikt'**
  String get roleConflictTitle;

  /// No description provided for @roleConflictContent.
  ///
  /// In de, this message translates to:
  /// **'Als Kind-Konto sind andere Rollen nicht erlaubt. Folgende Organisationen sind betroffen:\n\n{orgs}\n\nMöchtest du trotzdem fortfahren? Die Rollen in diesen Organisationen werden auf \'Kind\' geändert.'**
  String roleConflictContent(String orgs);

  /// No description provided for @childAccountLabel.
  ///
  /// In de, this message translates to:
  /// **'Kind-Konto'**
  String get childAccountLabel;

  /// No description provided for @childAccountHint.
  ///
  /// In de, this message translates to:
  /// **'Dieses Konto ist als Kind markiert. Nur die Rolle \'Kind\' ist in Organisationen erlaubt.'**
  String get childAccountHint;

  /// No description provided for @isChildAccount.
  ///
  /// In de, this message translates to:
  /// **'Als Kind markiert'**
  String get isChildAccount;

  /// No description provided for @parentConsentRequired.
  ///
  /// In de, this message translates to:
  /// **'Eltern-Einwilligung erforderlich'**
  String get parentConsentRequired;

  /// No description provided for @parentConsentRequiredContent.
  ///
  /// In de, this message translates to:
  /// **'{name} hat verifizierte Eltern. Die Einladung wird zur Genehmigung weitergeleitet.'**
  String parentConsentRequiredContent(String name);

  /// No description provided for @pendingParentConsents.
  ///
  /// In de, this message translates to:
  /// **'Ausstehende Eltern-Einwilligungen ({count})'**
  String pendingParentConsents(int count);

  /// No description provided for @orgInvitationForChild.
  ///
  /// In de, this message translates to:
  /// **'{orgName} möchte {childName} einladen'**
  String orgInvitationForChild(String orgName, String childName);

  /// No description provided for @orgInvitationInvitedBy.
  ///
  /// In de, this message translates to:
  /// **'Eingeladen von {name}'**
  String orgInvitationInvitedBy(String name);

  /// No description provided for @approveOrgInvitation.
  ///
  /// In de, this message translates to:
  /// **'Genehmigen'**
  String get approveOrgInvitation;

  /// No description provided for @vetoOrgInvitation.
  ///
  /// In de, this message translates to:
  /// **'Ablehnen'**
  String get vetoOrgInvitation;

  /// No description provided for @orgInvitationApproved.
  ///
  /// In de, this message translates to:
  /// **'Einladung genehmigt.'**
  String get orgInvitationApproved;

  /// No description provided for @orgInvitationVetoed.
  ///
  /// In de, this message translates to:
  /// **'Einladung abgelehnt.'**
  String get orgInvitationVetoed;

  /// No description provided for @myFamily.
  ///
  /// In de, this message translates to:
  /// **'Meine Familie'**
  String get myFamily;

  /// No description provided for @familyTreeTooltip.
  ///
  /// In de, this message translates to:
  /// **'Familienübersicht'**
  String get familyTreeTooltip;

  /// No description provided for @coParentsLabel.
  ///
  /// In de, this message translates to:
  /// **'Weitere Eltern'**
  String get coParentsLabel;

  /// No description provided for @onlyParent.
  ///
  /// In de, this message translates to:
  /// **'Einziges Elternteil'**
  String get onlyParent;

  /// No description provided for @pendingFamilyItems.
  ///
  /// In de, this message translates to:
  /// **'Ausstehende Eltern-Kind-Aktionen'**
  String get pendingFamilyItems;

  /// No description provided for @systemMemberAdded.
  ///
  /// In de, this message translates to:
  /// **'{targetName} wurde zum Chat hinzugefügt'**
  String systemMemberAdded(String targetName);

  /// No description provided for @systemMemberRemoved.
  ///
  /// In de, this message translates to:
  /// **'{targetName} wurde aus dem Chat entfernt'**
  String systemMemberRemoved(String targetName);

  /// No description provided for @auditLog.
  ///
  /// In de, this message translates to:
  /// **'Änderungsprotokoll'**
  String get auditLog;

  /// No description provided for @auditNoEntries.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Einträge'**
  String get auditNoEntries;

  /// No description provided for @auditActionInvitationSent.
  ///
  /// In de, this message translates to:
  /// **'Einladung verschickt'**
  String get auditActionInvitationSent;

  /// No description provided for @auditActionMemberConfirmed.
  ///
  /// In de, this message translates to:
  /// **'Mitglied bestätigt'**
  String get auditActionMemberConfirmed;

  /// No description provided for @auditActionMemberRemoved.
  ///
  /// In de, this message translates to:
  /// **'Mitglied entfernt'**
  String get auditActionMemberRemoved;

  /// No description provided for @auditActionSettingsChanged.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen geändert'**
  String get auditActionSettingsChanged;

  /// No description provided for @auditActionRoleChanged.
  ///
  /// In de, this message translates to:
  /// **'Rolle geändert'**
  String get auditActionRoleChanged;

  /// No description provided for @auditActionAdminTransferred.
  ///
  /// In de, this message translates to:
  /// **'Admin-Rolle übertragen'**
  String get auditActionAdminTransferred;

  /// No description provided for @auditActionKeywordsChanged.
  ///
  /// In de, this message translates to:
  /// **'Schlüsselwörter aktualisiert'**
  String get auditActionKeywordsChanged;

  /// No description provided for @auditBy.
  ///
  /// In de, this message translates to:
  /// **'von {name}'**
  String auditBy(String name);

  /// No description provided for @chatInfoTitle.
  ///
  /// In de, this message translates to:
  /// **'Chat-Übersicht'**
  String get chatInfoTitle;

  /// No description provided for @chatParticipants.
  ///
  /// In de, this message translates to:
  /// **'Teilnehmer'**
  String get chatParticipants;

  /// No description provided for @chatSupervisors.
  ///
  /// In de, this message translates to:
  /// **'Überwacher'**
  String get chatSupervisors;

  /// No description provided for @chatSupervisorHint.
  ///
  /// In de, this message translates to:
  /// **'Personen, die diesen Chat nur lesen können'**
  String get chatSupervisorHint;

  /// No description provided for @chatTypeGroup.
  ///
  /// In de, this message translates to:
  /// **'Gruppe'**
  String get chatTypeGroup;

  /// No description provided for @chatTypeDirect.
  ///
  /// In de, this message translates to:
  /// **'Direktnachricht'**
  String get chatTypeDirect;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
