// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Guardian Com';

  @override
  String get appSubtitle => 'Secure communication for organizations';

  @override
  String get noConnection => 'No connection';

  @override
  String get cancel => 'Cancel';

  @override
  String get close => 'Close';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get remove => 'Remove';

  @override
  String get create => 'Create';

  @override
  String get invite => 'Invite';

  @override
  String get add => 'Add';

  @override
  String get accept => 'Accept';

  @override
  String get reject => 'Reject';

  @override
  String get transfer => 'Transfer';

  @override
  String get leave => 'Leave';

  @override
  String get archive => 'Archive';

  @override
  String get restore => 'Restore from archive';

  @override
  String get back => 'Back';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String errorMessage(String message) {
    return 'Error: $message';
  }

  @override
  String get signInWithGoogle => 'Sign in with Google';

  @override
  String get or => 'or';

  @override
  String get emailAddress => 'Email address';

  @override
  String get emailHint => 'name@example.com';

  @override
  String get invalidEmailAddress => 'Invalid email address';

  @override
  String get sendSignInLink => 'Send sign-in link';

  @override
  String get emailLinkHint =>
      'We\'ll send you a link by email.\nNo password needed.';

  @override
  String signInFailed(String error) {
    return 'Sign-in failed: $error';
  }

  @override
  String get linkSent => 'Link sent!';

  @override
  String linkSentDescription(String email) {
    return 'We sent a sign-in link to\n$email.';
  }

  @override
  String get desktopLinkInstructions =>
      'Open the email in your browser, click the link\nand copy the full URL from the address bar.';

  @override
  String get pasteLinkLabel => 'Paste link from browser';

  @override
  String get signIn => 'Sign in';

  @override
  String get mobileLinkInstructions =>
      'Open the email and tap the link to sign in.';

  @override
  String get resend => 'Resend';

  @override
  String get useOtherEmail => 'Use a different email';

  @override
  String get invalidLink => 'Invalid link. Please check the URL.';

  @override
  String get helpProfileTitle => 'Profile – Help';

  @override
  String get helpProfilePhotoTitle => 'Changing your profile picture';

  @override
  String get helpProfilePhotoBody =>
      'Tap the circle with your avatar to pick a new image from the gallery. The image is scaled down to 512 × 512 pixels. Then tap \'Save\' in the top right.';

  @override
  String get helpProfileNameTitle => 'Display name';

  @override
  String get helpProfileNameBody =>
      'Your display name is visible to all members in the same organisation. Change it in the text field and save with \'Save\'.';

  @override
  String get helpProfileAppearanceTitle => 'Appearance & language';

  @override
  String get helpProfileAppearanceBody =>
      'Under \'Appearance\' you can choose between Light, Dark, and System default.\n\nUnder \'Language\' you set the app language (German or English). The change takes effect immediately.';

  @override
  String get helpProfileRelTitle => 'Connections';

  @override
  String get helpProfileRelBody =>
      'The \'My connections\' entry takes you to the page where you can manage parent-child links.';

  @override
  String get editProfile => 'Edit profile';

  @override
  String get newImageSelected => 'New image selected — save to apply';

  @override
  String get displayName => 'Display name';

  @override
  String get appearance => 'Appearance';

  @override
  String get chatFontSize => 'Chat font size';

  @override
  String get fontSizeSmall => 'Small';

  @override
  String get fontSizeMedium => 'Medium';

  @override
  String get fontSizeLarge => 'Large';

  @override
  String get fontSizeXL => 'Extra large';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get language => 'Language';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get languageEnglish => 'English';

  @override
  String get uiScale => 'UI scale (desktop)';

  @override
  String get signOut => 'Sign out';

  @override
  String get profileSaved => 'Profile saved.';

  @override
  String get privacyTitle => 'Privacy';

  @override
  String get visibility => 'Visibility';

  @override
  String get showOnlineStatus => 'Show online status';

  @override
  String get showOnlineStatusSubtitle =>
      'Other members can see when you\'re online';

  @override
  String get showLastSeen => 'Last seen';

  @override
  String get showLastSeenSubtitle =>
      'Other members can see when you were last active';

  @override
  String get showProfilePhoto => 'Profile photo visible';

  @override
  String get showProfilePhotoSubtitle => 'Members can see your profile photo';

  @override
  String get legal => 'Legal';

  @override
  String get privacyPolicy => 'Privacy policy';

  @override
  String get openInBrowser => 'Open in browser';

  @override
  String get data => 'Data';

  @override
  String get deleteAccount => 'Delete account';

  @override
  String get deleteAccountSubtitle => 'All data will be permanently deleted';

  @override
  String get deleteAccountConfirmContent =>
      'Do you really want to delete your account? This action cannot be undone.';

  @override
  String get deleteAccountBlockedTitle => 'Cannot delete account';

  @override
  String get deleteAccountBlockedChild =>
      'Your account is linked to a parent. The connection must first be removed by your parent before you can delete your account.';

  @override
  String get deleteAccountBlockedParent =>
      'You still have active connections with children. Please remove all connections under \"My Connections\" first.';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsHint =>
      'These settings apply as the default for all organizations. You can adjust them per organization via the bell icon.';

  @override
  String get messages => 'Messages';

  @override
  String get newMessages => 'New messages';

  @override
  String get chatRequests => 'Chat requests';

  @override
  String get chatRequestsSubtitle => 'When someone requests a chat';

  @override
  String get organizations => 'Organizations';

  @override
  String get invitations => 'Invitations';

  @override
  String get invitationsSubtitle => 'When invited to organizations';

  @override
  String get orgChanges => 'Org changes';

  @override
  String get orgChangesSubtitle => 'When changes occur in my organizations';

  @override
  String get intervalAlways => 'Every message';

  @override
  String get intervalHourly => 'Max. once per hour';

  @override
  String get intervalDaily => 'Max. once per day';

  @override
  String get intervalNever => 'Never';

  @override
  String get keywordsTooltip => 'Keywords';

  @override
  String get keywordsImportCsv => 'Import CSV';

  @override
  String get keywordsExportCsv => 'Export CSV';

  @override
  String keywordsImported(int count) {
    return '$count keywords imported';
  }

  @override
  String get keywordsExported => 'Keywords saved to file';

  @override
  String get keywordsExportFailed => 'Export failed';

  @override
  String get editTooltip => 'Edit';

  @override
  String get editOrganization => 'Edit organization';

  @override
  String get orgName => 'Name';

  @override
  String get category => 'Category';

  @override
  String get orgTagFamilie => 'Family';

  @override
  String get orgTagFreunde => 'Friends';

  @override
  String get orgTagSchule => 'School';

  @override
  String get orgTagVereine => 'Clubs';

  @override
  String get orgTagSonstiges => 'Other';

  @override
  String get chatMode => 'Chat mode';

  @override
  String get keywordsHelpTitle => 'Keywords – Help';

  @override
  String get keywordsHelpBody =>
      'What are keywords for?\nGuardians and moderators are notified whenever one of these words appears in a chat message. This helps detect sensitive topics or risk terms early.\n\nAdding words\nType a word in the text field and tap \'+\' or press Enter. Case is ignored – everything is stored in lowercase.\n\nRemoving words\nTap the \'×\' on a chip.\n\nCSV import / export\n• Import (upload arrow): Load a text file with one word per line or comma-separated.\n• Export (download arrow): Save all words as a CSV file.\n\nChanges only take effect after tapping \'Save\'.';

  @override
  String get keywordsTitle => 'Keywords';

  @override
  String get keywordsDescription =>
      'Guardians and moderators will be notified when one of these words appears in a chat.';

  @override
  String get addKeywordHint => 'Add new word';

  @override
  String get noKeywordsDefined => 'No keywords defined.';

  @override
  String get tabMembers => 'Members';

  @override
  String get helpDetailTopicMembersTitle => 'Member list & roles';

  @override
  String get helpDetailTopicMembersBody =>
      'The \'Members\' tab shows all active members of the organisation with their role (Admin, Moderator, Member, Child).\n\nRoles via the 3-dot menu (Admin):\n• Change role – Admin, Moderator, Member, or Child\n• Assign guardian – links a child to a parent account\n• Remove member\n• Transfer admin role\n\nMembers can leave the org themselves (except admins).';

  @override
  String get helpDetailTopicMembersInviteTitle =>
      'Inviting, suggesting & importing';

  @override
  String get helpDetailTopicMembersInviteBody =>
      'Admin / Moderator – \'+\' button bottom right:\n• Invite individuals by email (choose role and optional guardian)\n• In \'Sheltered\' mode: bulk import via CSV file\n\nInvited children: appear as pending until the guardian approves the invitation in \'My connections\'.\n\nRegular member – \'Suggest member\':\nSuggest a person. An admin or moderator must confirm the suggestion at the top of the tab.\n\nChild (Guardian mode) – \'Request chat\':\nSend a request for a 1-to-1 chat. An admin or moderator approves or declines.';

  @override
  String get helpDetailTopicNotificationsTitle => 'Notifications';

  @override
  String get helpDetailTopicNotificationsBody =>
      'The bell icon (top right) controls notifications for this organization.\n\nMessage notifications:\n• Every message\n• Max. once per hour (default)\n• Max. once per day\n• Never\n\nChild activity (Guardian):\nGet notified when your child sends or receives a message. Interval is also adjustable.';

  @override
  String get helpDetailTopicChatsSendTitle => 'Chats – Messages & Media';

  @override
  String get helpDetailTopicChatsSendBody =>
      'Text messages: Tap the input field and send with the arrow icon.\n\nImages, audio & files: \'+\' icon next to the text field:\n• Images from gallery (JPEG, max. 2 MB)\n• Record voice message (microphone icon)\n• Send files (max. 5 MB)\n\nReply: Long press a message → \'Reply\'. The original message appears as a quote.\n\nReactions: Long press a message → choose an emoji (👍❤️😂😮😢😡👎). Tap again to remove your reaction.\n\nSchedule message: \'+\' → clock icon → pick date and time.\n\nPolls (Sheltered groups): \'+\' → poll icon → create a question with options.';

  @override
  String get helpDetailTopicChatsModTitle => 'Moderate & Report Messages';

  @override
  String get helpDetailTopicChatsModBody =>
      'Edit your own messages: Long press → \'Edit\'. Edited messages are archived in the moderation log.\n\nAdmin/Moderator – manage messages:\n• Edit or delete others\' messages\n• Pin a message → appears as a banner at the top of the chat\n\nReport: Long press a message → \'Report\'. Admins and moderators are notified and see the report in the Reports tab.';

  @override
  String get helpDetailTopicPinnwandTitle => 'Reading the noticeboard';

  @override
  String get helpDetailTopicPinnwandBody =>
      'The noticeboard shows official announcements from the organisation – targeted information from admins and moderators, not back-and-forth like a chat.\n\nPosts have a title, body text, and an optional expiry date. Expired announcements disappear automatically.';

  @override
  String get helpDetailTopicPinnwandManageTitle =>
      'Creating & managing announcements';

  @override
  String get helpDetailTopicPinnwandManageBody =>
      'New announcement: Tap the \'+\' button in the bottom right → enter a title and text.\n\nExpiry date: Optionally set a date until which the announcement is visible. After that date it is hidden automatically.\n\nEdit or delete: Tap the three-dot menu on an announcement.';

  @override
  String get helpDetailTopicReportsTitle => 'Reports';

  @override
  String get helpDetailTopicReportsBody =>
      'The \'Reports\' tab is only visible to admins and moderators.\n\nReported messages are listed here. You can:\n• Jump to the reported message in the chat\n• Delete the message\n• Archive the report as reviewed\n\nArchived reports are hidden – the toggle at the top shows them again.';

  @override
  String get tabChats => 'Chats';

  @override
  String get tabReports => 'Reports';

  @override
  String childChatRequests(int count) {
    return 'Your children\'s chat requests ($count)';
  }

  @override
  String pendingRequests(int count) {
    return 'Pending requests ($count)';
  }

  @override
  String monitoredChats(int count) {
    return 'Monitored chats ($count)';
  }

  @override
  String archivedChats(int count) {
    return 'Archived ($count)';
  }

  @override
  String get noChatsGuardian => 'No chats yet.\nSend a request to get started.';

  @override
  String get noChatsSheltered =>
      'No chats yet.\nThe admin sets up connections.';

  @override
  String get createGroup => 'Create group';

  @override
  String get groupName => 'Group name';

  @override
  String get addMembers => 'Add members';

  @override
  String get csvImport => 'Import CSV';

  @override
  String get inviteMember => 'Invite member';

  @override
  String get suggestMember => 'Suggest member';

  @override
  String get requestChat => 'Request chat';

  @override
  String suggestions(int count) {
    return 'Suggestions ($count)';
  }

  @override
  String pendingChildInvitations(int count) {
    return 'Pending child invitations ($count)';
  }

  @override
  String get noMembers => 'No members yet';

  @override
  String get inviteMemberTitle => 'Invite member';

  @override
  String get role => 'Role';

  @override
  String get guardians => 'Guardians (parents)';

  @override
  String get childGuardianHint =>
      'The child will only be added once a guardian approves.';

  @override
  String get noGuardiansAvailable => 'No members available as guardian.';

  @override
  String get inviteSentChild =>
      'Invitation sent. The child will be added after registration and guardian approval.';

  @override
  String get inviteSent => 'Invitation sent.';

  @override
  String get requestChatTitle => 'Request chat';

  @override
  String get requestChatSubtitle => 'Who would you like to chat with?';

  @override
  String get requestChatHint =>
      'Your request will be reviewed by an admin or moderator.';

  @override
  String get requestChatButton => 'Request';

  @override
  String get chatRequestSent => 'Chat request sent.';

  @override
  String get suggestMemberTitle => 'Suggest member';

  @override
  String get guardian => 'Guardian';

  @override
  String get suggest => 'Suggest';

  @override
  String get suggestionSent => 'Suggestion submitted and awaiting approval.';

  @override
  String get orgNotificationsTitle => 'Organization notifications';

  @override
  String get noMessages => 'No messages yet';

  @override
  String get hideArchived => 'Hide archived';

  @override
  String showArchived(int count) {
    return 'Show archived ($count)';
  }

  @override
  String get noReports => 'No reports';

  @override
  String get noPendingReports => 'No pending reports';

  @override
  String get reportPending => 'Pending';

  @override
  String get reportReviewed => 'Reviewed · Archived';

  @override
  String get markReviewed => 'Mark as reviewed';

  @override
  String get deleteMessage => 'Delete message';

  @override
  String get deleteMessageTitle => 'Delete message';

  @override
  String get deleteMessageContent =>
      'This message will be permanently deleted and the report marked as reviewed.';

  @override
  String get pendingApproval => 'Awaiting approval';

  @override
  String get approveTooltip => 'Approve';

  @override
  String get rejectTooltip => 'Reject';

  @override
  String get roleAdmin => 'Admin';

  @override
  String get roleModerator => 'Moderator';

  @override
  String get roleMember => 'Member';

  @override
  String get roleChild => 'Child';

  @override
  String get notificationSettings => 'Notification settings';

  @override
  String get leaveOrganization => 'Leave organization';

  @override
  String get changeGuardians => 'Change guardians';

  @override
  String get startChat => 'Start chat';

  @override
  String get changeRole => 'Change role';

  @override
  String get transferAdmin => 'Transfer admin role';

  @override
  String get noActionsAvailable => 'No actions available.';

  @override
  String guardiansFor(String name) {
    return 'Guardians for $name';
  }

  @override
  String roleFor(String name) {
    return 'Role for $name';
  }

  @override
  String guardianFor(String name) {
    return 'Guardian for $name';
  }

  @override
  String get selectGuardianHint =>
      'Select at least one guardian for this child:';

  @override
  String get noGuardiansInOrg => 'No possible guardians in this organization.';

  @override
  String get removeMemberTitle => 'Remove member';

  @override
  String removeMemberContent(String name) {
    return 'Really remove $name?';
  }

  @override
  String get leaveOrgTitle => 'Leave organization';

  @override
  String leaveOrgContent(String name) {
    return 'Do you really want to leave the organization \"$name\"?';
  }

  @override
  String get transferAdminTitle => 'Transfer admin role';

  @override
  String transferAdminContent(String name) {
    return 'Do you want to transfer the admin role to $name?\n\nYou will become a regular member of this organization.';
  }

  @override
  String get childActivityNotifications => 'Child activity notifications';

  @override
  String get pendingChildSubtitle => 'Awaiting your approval';

  @override
  String get approveChildTooltip => 'Approve';

  @override
  String memberAdded(String name) {
    return '$name has been added.';
  }

  @override
  String get withdrawInvitationTitle => 'Withdraw invitation';

  @override
  String withdrawInvitationContent(String email) {
    return 'Really withdraw invitation for $email?';
  }

  @override
  String get withdraw => 'Withdraw';

  @override
  String get tabPinboard => 'Pinboard';

  @override
  String announcementExpiresOn(String date) {
    return 'Expires: $date';
  }

  @override
  String get announcementExpired => 'Expired';

  @override
  String get announcementSetExpiry => 'Set expiry date';

  @override
  String get announcementNoExpiry => 'No expiry date';

  @override
  String get announcementRemoveExpiry => 'Remove expiry date';

  @override
  String get pinnedMessage => 'Pinned message';

  @override
  String get pinMessage => 'Pin';

  @override
  String get unpinMessage => 'Unpin';

  @override
  String get anonymousPoll => 'Anonymous';

  @override
  String get pollVotersTitle => 'Poll details';

  @override
  String get pollVoteNotifTitle => 'New vote';

  @override
  String pollVoteNotifBody(String name, String question) {
    return '$name voted on your poll \"$question\".';
  }

  @override
  String get newAnnouncement => 'New announcement';

  @override
  String get editAnnouncement => 'Edit announcement';

  @override
  String get announcementTitleLabel => 'Title';

  @override
  String get announcementContentLabel => 'Message';

  @override
  String get noAnnouncements => 'No announcements yet';

  @override
  String get deleteAnnouncementTitle => 'Delete announcement';

  @override
  String get deleteAnnouncementContent => 'Really delete this announcement?';

  @override
  String get announcementEdited => 'edited';

  @override
  String announcementBy(String name) {
    return 'by $name';
  }

  @override
  String get scheduleMessage => 'Schedule message';

  @override
  String scheduledMessages(int count) {
    return 'Scheduled messages ($count)';
  }

  @override
  String get scheduleFor => 'Send at';

  @override
  String scheduledAt(String time) {
    return 'Scheduled for $time';
  }

  @override
  String get cancelScheduled => 'Cancel';

  @override
  String get scheduleHint => 'Messages are only sent while the app is open.';

  @override
  String get helpChatTitle => 'Chat – Help';

  @override
  String get helpChatWriteTitle => 'Writing & sending messages';

  @override
  String get helpChatWriteBody =>
      'Type your message in the text field and tap the send arrow. URLs in the text are automatically recognised as clickable links.';

  @override
  String get helpChatMediaTitle => 'Images, audio & files';

  @override
  String get helpChatMediaBody =>
      'Tap the \'+\' symbol to the left of the text field to choose an image from the gallery or camera, start a voice recording, or attach a file.';

  @override
  String get helpChatReactTitle => 'Replies & reactions';

  @override
  String get helpChatReactBody =>
      'Long-press a message to open the context menu. From there you can reply to a message or react with an emoji. A reply appears with a preview of the original message.';

  @override
  String get helpChatScheduleTitle => 'Scheduling & polls';

  @override
  String get helpChatScheduleBody =>
      'In the \'+\' menu you can schedule a message for a later time. In groups with \'Sheltered\' mode, creating polls is also available.';

  @override
  String get helpChatModerateTitle => 'Moderating & editing messages';

  @override
  String get helpChatModerateBody =>
      'You can edit or delete your own messages. Administrators and moderators can additionally delete, edit, or pin any message.';

  @override
  String get helpChatReportTitle => 'Reporting, copying & searching';

  @override
  String get helpChatReportBody =>
      'Long-press a message and choose \'Report\' to flag abuse, or \'Copy\' to copy the text. Use the magnifier icon in the title bar to search all messages.';

  @override
  String get searchMessages => 'Search messages';

  @override
  String get searchHint => 'Search…';

  @override
  String get searchNoResults => 'No results';

  @override
  String searchResults(int count) {
    return '$count results';
  }

  @override
  String get reply => 'Reply';

  @override
  String replyingTo(String name) {
    return 'Replying to $name';
  }

  @override
  String get microphoneDenied => 'Microphone access was denied.';

  @override
  String get createPollTitle => 'Create poll';

  @override
  String get pollQuestion => 'Question';

  @override
  String get pollOptions => 'Answer options';

  @override
  String get addOption => 'Add option';

  @override
  String get multipleChoice => 'Multiple choice';

  @override
  String get addMemberTitle => 'Add member';

  @override
  String get allMembersInChat => 'All members are already in the chat.';

  @override
  String get membersTooltip => 'Show members';

  @override
  String get archivedReadOnly => 'Archived – read only';

  @override
  String sendError(String error) {
    return 'Send error: $error';
  }

  @override
  String get olderMessages => 'Older messages';

  @override
  String get copyText => 'Copy text';

  @override
  String get moderate => 'Moderate';

  @override
  String get reportMessage => 'Report message';

  @override
  String get editedPrefix => 'edited · ';

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get sendImage => 'Send image';

  @override
  String get sendFile => 'Send file (max. 5 MB)';

  @override
  String get voiceRecording => 'Voice recording';

  @override
  String get createPoll => 'Create poll';

  @override
  String get messageHint => 'Write a message...';

  @override
  String get attachmentTooltip => 'Attachment';

  @override
  String get voiceTooltip => 'Voice message';

  @override
  String get recordingIndicator => 'Recording…';

  @override
  String get endPollTitle => 'End poll';

  @override
  String get endPollContent =>
      'End the poll? Voting will no longer be possible.';

  @override
  String get endPoll => 'End';

  @override
  String get pollClosed => 'Closed';

  @override
  String get poll => 'Poll';

  @override
  String votes(int count) {
    return '$count votes';
  }

  @override
  String get oneVote => '1 vote';

  @override
  String get removeMembersTitle => 'Remove members';

  @override
  String removeMemberFromChat(String name) {
    return 'Remove $name from chat?';
  }

  @override
  String moderatedBy(String name) {
    return 'moderated by $name';
  }

  @override
  String get moderatedByModerator => 'moderated by moderator';

  @override
  String get helpImportTitle => 'Bulk import – Help';

  @override
  String get helpImportFormatTitle => 'CSV format';

  @override
  String get helpImportFormatBody =>
      'The file must contain the columns email, role and guardians (header row optional). Both , and ; are recognised automatically as delimiters.\n\nExample:\nemail;role;guardians\nchild@school.com;child;parent@school.com\nmember@school.com;member;';

  @override
  String get helpImportRolesTitle => 'Valid roles';

  @override
  String get helpImportRolesBody =>
      'member · moderator (or mod) · child\n\nCase is ignored.';

  @override
  String get helpImportChildrenTitle => 'Importing children';

  @override
  String get helpImportChildrenBody =>
      'For rows with the role \'child\', the guardians column must contain at least one email address. The listed guardians must already be members of this organisation.';

  @override
  String get helpImportPreviewTitle => 'Preview & validation';

  @override
  String get helpImportPreviewBody =>
      'After loading the file, each row is checked. A red symbol indicates an error (row will not be imported), a yellow symbol indicates a warning (import still possible).';

  @override
  String get helpImportRunTitle => 'Start the import';

  @override
  String get helpImportRunBody =>
      'Tap \'Import X\' in the top right. The button only appears when at least one valid row is present. After the import, a log shows whether each row succeeded or failed.';

  @override
  String get importMembers => 'Import members';

  @override
  String get selectCsvFile => 'Select CSV file';

  @override
  String importCount(int count) {
    return 'Import $count';
  }

  @override
  String csvRowsValid(int total, int valid) {
    return '$total rows · $valid valid';
  }

  @override
  String csvRowsErrors(int total, int valid, int errors) {
    return '$total rows · $valid valid · $errors errors';
  }

  @override
  String importSuccess(int count) {
    return '$count invited';
  }

  @override
  String importSuccessWithErrors(int count, int errors) {
    return '$count invited, $errors errors';
  }

  @override
  String get invalidEmail2 => 'Invalid email';

  @override
  String unknownRole(String role) {
    return 'Unknown role: \"$role\"';
  }

  @override
  String get guardianMissing => 'Guardian missing';

  @override
  String get noGuardianInOrg => 'No guardian found in this org';

  @override
  String guardianNotInOrg(String emails) {
    return 'Guardian not in org: $emails';
  }

  @override
  String get donationTitle => 'Support Guardian Com';

  @override
  String get donationContent =>
      'Guardian Com is free and ad-free. If you enjoy the app, I\'d appreciate a small donation!';

  @override
  String get kofiButton => 'Donate via Ko-fi';

  @override
  String get paypalButton => 'Donate via PayPal';

  @override
  String get maybeLater => 'Maybe later';

  @override
  String get aboutApp => 'About';

  @override
  String get aboutAppDialogTitle => 'Guardian Com';

  @override
  String get aboutAppDescription =>
      'Secure, supervised communication for organizations — free and ad-free.';

  @override
  String get openSourceLicenses => 'Open-source licenses';

  @override
  String get githubRepository => 'GitHub repository';

  @override
  String typingOne(String name) {
    return '$name is typing…';
  }

  @override
  String typingMultiple(String names) {
    return '$names are typing…';
  }

  @override
  String get createOrganization => 'Create organization';

  @override
  String get orgNameLabel => 'Organization name';

  @override
  String get myOrganizations => 'My Organizations';

  @override
  String get helpLabel => 'Help';

  @override
  String get helpTourButton => 'Start Tour';

  @override
  String get helpOrgTopicOrgsTitle => 'What are Organizations?';

  @override
  String get helpOrgTopicOrgsBody =>
      'Organizations are groups for secure communication – e.g. family, school, or club. You can create organizations yourself or join via invitation.';

  @override
  String get helpOrgTopicRolesTitle => 'Roles';

  @override
  String get helpOrgTopicRolesBody =>
      'Admin – Full control, manages all members and settings.\nModerator – Can view and approve chats.\nMember – Can request chats and communicate.\nChild – Restricted, requires a Guardian and parental consent for invitations.';

  @override
  String get helpOrgTopicChatModesTitle => 'Chat Modes';

  @override
  String get helpOrgTopicChatModesBody =>
      'Guardian Mode – Members request chats, admins or moderators approve them.\nSheltered Mode – The admin determines in advance who can communicate with whom. Group chats are possible.';

  @override
  String get helpOrgTopicInviteTitle => 'Invite Members';

  @override
  String get helpOrgTopicInviteBody =>
      'Open an organization → tap the people icon → enter email and choose a role. As an admin you can also import multiple members via CSV file in Sheltered orgs.';

  @override
  String get helpOrgTopicFamilyTitle => 'Parent-Child Connection';

  @override
  String get helpOrgTopicFamilyBody =>
      'Child accounts are globally locked to the \'Child\' role. When a child is invited to an org, parents must consent first. The tree button above opens your family overview.';

  @override
  String get tourStepProfileTitle => 'Profile & Settings';

  @override
  String get tourStepProfileDesc =>
      'Tap here to edit your profile, adjust notifications, or sign out.';

  @override
  String get tourStepFamilyTitle => 'Family Overview';

  @override
  String get tourStepFamilyDesc =>
      'Shows your verified parent and child connections. The badge indicates pending actions.';

  @override
  String get tourStepOrgCardTitle => 'Your Organizations';

  @override
  String get tourStepOrgCardDesc =>
      'Tap a card to open the organization. As an admin you see a menu in the top right for more options.';

  @override
  String get tourStepFabTitle => 'Create Organization';

  @override
  String get tourStepFabDesc =>
      'Tap here to create a new organization and set chat mode and category.';

  @override
  String get noOrganizations => 'No organizations yet';

  @override
  String get archivedBadge => 'Archived';

  @override
  String get deleteOrgTitle => 'Delete organization?';

  @override
  String deleteOrgContent(String name) {
    return '\"$name\" and all memberships will be permanently deleted.';
  }

  @override
  String get open => 'Open';

  @override
  String get unarchive => 'Restore';

  @override
  String get saveImage => 'Save image';

  @override
  String get imageSaved => 'Image saved';

  @override
  String get helpRelTitle => 'Connections – Help';

  @override
  String get helpRelOverviewTitle => 'What is a parent-child connection?';

  @override
  String get helpRelOverviewBody =>
      'A connection links a parent account to a child account. The child receives the \'Child\' role in all organisations and cannot join a new organisation without the parent\'s approval.';

  @override
  String get helpRelConnectTitle => 'Connect a child';

  @override
  String get helpRelConnectBody =>
      'Enter the email address of the account you want to link as a child and tap \'Send request\'. The child must then confirm the request in this view.';

  @override
  String get helpRelIncomingTitle => 'Incoming requests';

  @override
  String get helpRelIncomingBody =>
      'When someone sends you a connection request, it appears here. You can confirm or decline it. When you confirm, you will be assigned the \'Child\' role in all your organisations.';

  @override
  String get helpRelConsentsTitle => 'Approve org invitations';

  @override
  String get helpRelConsentsBody =>
      'When a child is invited to an organisation, the invitation appears here for approval. As a parent you can approve or decline the invitation.';

  @override
  String get helpRelRevokeTitle => 'Remove a connection';

  @override
  String get helpRelRevokeBody =>
      'Tap the name of a connected person and choose \'Remove connection\'. Children cannot remove the connection themselves – only the parent can do this.';

  @override
  String get myRelationships => 'My connections';

  @override
  String get myParents => 'My parents';

  @override
  String get myChildren => 'My children';

  @override
  String get noParents => 'No verified parents';

  @override
  String get noChildren => 'No verified children';

  @override
  String get verifiedParent => 'Verified parent';

  @override
  String get verifiedChild => 'Verified child';

  @override
  String get connectChild => 'Connect child';

  @override
  String get connectChildHint => 'Enter the child\'s email address';

  @override
  String get sendClaimRequest => 'Send connection request';

  @override
  String get claimRequestSent => 'Request sent.';

  @override
  String get claimRequestNotFound => 'No user found with this email.';

  @override
  String get claimRequestAlreadyExists =>
      'A request for this user already exists.';

  @override
  String get claimRequestCancelTitle => 'Cancel request';

  @override
  String claimRequestCancelContent(String email) {
    return 'Really cancel the connection request to $email?';
  }

  @override
  String incomingClaimRequests(int count) {
    return 'Incoming requests ($count)';
  }

  @override
  String wantsToBeYourParent(String name) {
    return '$name wants to be your parent';
  }

  @override
  String get confirmClaim => 'Confirm';

  @override
  String get rejectClaim => 'Reject';

  @override
  String get claimConfirmed => 'Connection confirmed.';

  @override
  String get claimRejected => 'Request rejected.';

  @override
  String get revokeConnection => 'Revoke connection';

  @override
  String get revokeConnectionTitle => 'Revoke connection';

  @override
  String revokeConnectionContent(String name) {
    return 'Really revoke connection with $name?';
  }

  @override
  String get roleConflictTitle => 'Role conflict';

  @override
  String roleConflictContent(String orgs) {
    return 'As a child account, other roles are not permitted. The following organizations are affected:\n\n$orgs\n\nDo you want to proceed? The roles in these organizations will be changed to \'Child\'.';
  }

  @override
  String get childAccountLabel => 'Child account';

  @override
  String get childAccountHint =>
      'This account is marked as a child. Only the \'Child\' role is allowed in organizations.';

  @override
  String get isChildAccount => 'Marked as child';

  @override
  String get parentConsentRequired => 'Parental consent required';

  @override
  String parentConsentRequiredContent(String name) {
    return '$name has verified parents. The invitation will be forwarded for their approval.';
  }

  @override
  String pendingParentConsents(int count) {
    return 'Pending parent consents ($count)';
  }

  @override
  String orgInvitationForChild(String orgName, String childName) {
    return '$orgName wants to invite $childName';
  }

  @override
  String orgInvitationInvitedBy(String name) {
    return 'Invited by $name';
  }

  @override
  String get approveOrgInvitation => 'Approve';

  @override
  String get vetoOrgInvitation => 'Reject';

  @override
  String get orgInvitationApproved => 'Invitation approved.';

  @override
  String get orgInvitationVetoed => 'Invitation rejected.';

  @override
  String get myFamily => 'My family';

  @override
  String get familyTreeTooltip => 'Family overview';

  @override
  String get coParentsLabel => 'Co-parents';

  @override
  String get onlyParent => 'Only parent';

  @override
  String get pendingFamilyItems => 'Pending parent-child actions';

  @override
  String systemMemberAdded(String targetName) {
    return '$targetName was added to the chat';
  }

  @override
  String systemMemberRemoved(String targetName) {
    return '$targetName was removed from the chat';
  }

  @override
  String get auditLog => 'Change log';

  @override
  String get auditNoEntries => 'No entries yet';

  @override
  String get auditActionInvitationSent => 'Invitation sent';

  @override
  String get auditActionMemberConfirmed => 'Member confirmed';

  @override
  String get auditActionMemberRemoved => 'Member removed';

  @override
  String get auditActionSettingsChanged => 'Settings changed';

  @override
  String get auditActionRoleChanged => 'Role changed';

  @override
  String get auditActionAdminTransferred => 'Admin role transferred';

  @override
  String get auditActionKeywordsChanged => 'Keywords updated';

  @override
  String auditBy(String name) {
    return 'by $name';
  }
}
