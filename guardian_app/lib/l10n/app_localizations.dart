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

  /// No description provided for @close.
  ///
  /// In de, this message translates to:
  /// **'Schließen'**
  String get close;

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

  /// No description provided for @chatMode.
  ///
  /// In de, this message translates to:
  /// **'Chat-Modus'**
  String get chatMode;

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
