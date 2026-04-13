import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:guardian_app/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/app_user.dart';
import '../../../core/models/org_member.dart';
import '../../../core/models/organization.dart';
import '../providers/organizations_provider.dart';
import '../../../core/widgets/help_sheet.dart';

// ── CSV row model ─────────────────────────────────────────────────────────────

class _CsvRow {
  final int lineIndex;
  final String email;
  final String roleRaw;
  final String guardiansRaw;

  const _CsvRow({
    required this.lineIndex,
    required this.email,
    required this.roleRaw,
    required this.guardiansRaw,
  });

  OrgRole? get role => _parseRole(roleRaw);

  bool get emailValid =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim());

  bool get roleValid => role != null;

  List<String> get guardianEmails => guardiansRaw
      .split(RegExp(r'[\s,]+'))
      .map((e) => e.trim().toLowerCase())
      .where((e) => e.isNotEmpty)
      .toList();

  static OrgRole? _parseRole(String raw) => switch (raw.toLowerCase().trim()) {
        'moderator' || 'mod' => OrgRole.moderator,
        'mitglied' || 'member' => OrgRole.member,
        'kind' || 'child' => OrgRole.child,
        _ => null,
      };
}

enum _RowStatus { valid, warning, error }

// ── Screen ───────────────────────────────────────────────────────────────────

class BulkImportScreen extends ConsumerStatefulWidget {
  final Organization org;
  final List<OrgMember> members;

  const BulkImportScreen({
    super.key,
    required this.org,
    required this.members,
  });

  @override
  ConsumerState<BulkImportScreen> createState() => _BulkImportScreenState();
}

class _BulkImportScreenState extends ConsumerState<BulkImportScreen> {
  List<_CsvRow>? _rows;
  bool _picking = false;
  bool _importing = false;
  String? _fileName;
  final List<String> _importLog = [];

  Future<void> _pickFile() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;

      String? text;
      if (file.bytes != null) {
        text = String.fromCharCodes(file.bytes!);
      } else if (file.path != null) {
        text = await XFile(file.path!).readAsString();
      }

      if (text != null && mounted) {
        setState(() {
          _fileName = file.name;
          _rows = _parseCSV(text!);
          _importLog.clear();
        });
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  List<_CsvRow> _parseCSV(String text) {
    final lines = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    if (lines.isEmpty) return [];

    final first = lines.first;
    final delimiter =
        (first.split(';').length - 1) >= (first.split(',').length - 1)
            ? ';'
            : ',';

    final start =
        first.split(delimiter).first.trim().toLowerCase() == 'email' ? 1 : 0;

    final rows = <_CsvRow>[];
    for (var i = start; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final parts = line.split(delimiter);
      final email = (parts.isNotEmpty ? parts[0] : '').trim();
      final roleRaw = (parts.length > 1 ? parts[1] : '').trim();
      final guardiansRaw = (parts.length > 2 ? parts[2] : '').trim();
      if (email.isEmpty && roleRaw.isEmpty) continue;
      rows.add(_CsvRow(
        lineIndex: i + 1,
        email: email,
        roleRaw: roleRaw,
        guardiansRaw: guardiansRaw,
      ));
    }
    return rows;
  }

  _RowStatus _rowStatus(_CsvRow row) {
    if (!row.emailValid || !row.roleValid) return _RowStatus.error;
    if (row.role == OrgRole.child) {
      if (row.guardianEmails.isEmpty) return _RowStatus.error;
      final resolved = _resolveGuardianUids(row.guardianEmails);
      if (resolved.isEmpty) return _RowStatus.error;
      if (resolved.length < row.guardianEmails.length) return _RowStatus.warning;
    }
    return _RowStatus.valid;
  }

  String _rowStatusMessage(_CsvRow row, AppLocalizations l) {
    final issues = <String>[];
    if (!row.emailValid) issues.add(l.invalidEmail2);
    if (!row.roleValid) issues.add(l.unknownRole(row.roleRaw));
    if (row.role == OrgRole.child) {
      if (row.guardianEmails.isEmpty) {
        issues.add(l.guardianMissing);
      } else {
        final resolved = _resolveGuardianUids(row.guardianEmails);
        if (resolved.isEmpty) {
          issues.add(l.noGuardianInOrg);
        } else if (resolved.length < row.guardianEmails.length) {
          final missing = row.guardianEmails
              .where((e) => !widget.members.any((m) => m.email.toLowerCase() == e))
              .toList();
          issues.add(l.guardianNotInOrg(missing.join(', ')));
        }
      }
    }
    if (issues.isNotEmpty) return issues.join(' · ');
    final roleLabel = switch (row.role!) {
      OrgRole.admin => l.roleAdmin,
      OrgRole.moderator => l.roleModerator,
      OrgRole.member => l.roleMember,
      OrgRole.child => l.roleChild,
    };
    if (row.role == OrgRole.child) {
      final count = _resolveGuardianUids(row.guardianEmails).length;
      return '$roleLabel · $count Guardian(s)';
    }
    return roleLabel;
  }

  List<String> _resolveGuardianUids(List<String> emails) {
    final byEmail = {
      for (final m in widget.members) m.email.toLowerCase(): m.uid,
    };
    return emails
        .map((e) => byEmail[e.toLowerCase()])
        .whereType<String>()
        .toList();
  }

  Future<void> _import(AppLocalizations l) async {
    final rows = _rows;
    if (rows == null) return;
    final validRows =
        rows.where((r) => _rowStatus(r) != _RowStatus.error).toList();
    if (validRows.isEmpty) return;

    setState(() {
      _importing = true;
      _importLog.clear();
    });

    int success = 0;
    int errors = 0;

    for (final row in validRows) {
      try {
        final guardianUids = row.role == OrgRole.child
            ? _resolveGuardianUids(row.guardianEmails)
            : <String>[];
        await ref.read(organizationServiceProvider).inviteMember(
              widget.org.id,
              row.email,
              row.role!,
              guardianUids: guardianUids,
            );
        success++;
        if (mounted) setState(() => _importLog.add('✓ ${row.email}'));
      } catch (e) {
        errors++;
        if (mounted) setState(() => _importLog.add('✗ ${row.email}: $e'));
      }
    }

    if (mounted) {
      setState(() => _importing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errors > 0
              ? l.importSuccessWithErrors(success, errors)
              : l.importSuccess(success)),
        ),
      );
      if (errors == 0) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final rows = _rows;
    final validCount =
        rows?.where((r) => _rowStatus(r) != _RowStatus.error).length ?? 0;
    final showLog = _importLog.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.importMembers),
        actions: [
          if (rows != null && validCount > 0 && !showLog)
            TextButton(
              onPressed: _importing ? null : () => _import(l),
              child: _importing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l.importCount(validCount)),
            ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: l.helpLabel,
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => HelpSheet(
                screenTitle: l.helpImportTitle,
                topics: [
                  HelpTopic(
                    icon: Icons.table_rows_outlined,
                    title: l.helpImportFormatTitle,
                    body: l.helpImportFormatBody,
                  ),
                  HelpTopic(
                    icon: Icons.badge_outlined,
                    title: l.helpImportRolesTitle,
                    body: l.helpImportRolesBody,
                  ),
                  HelpTopic(
                    icon: Icons.child_care_outlined,
                    title: l.helpImportChildrenTitle,
                    body: l.helpImportChildrenBody,
                  ),
                  HelpTopic(
                    icon: Icons.rule_outlined,
                    title: l.helpImportPreviewTitle,
                    body: l.helpImportPreviewBody,
                  ),
                  HelpTopic(
                    icon: Icons.upload_outlined,
                    title: l.helpImportRunTitle,
                    body: l.helpImportRunBody,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: OutlinedButton.icon(
              onPressed: _picking ? null : _pickFile,
              icon: _picking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_outlined),
              label: Text(
                _fileName ?? l.selectCsvFile,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          if (rows == null)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.table_chart_outlined,
                        size: 48, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'CSV-Datei mit folgenden Spalten:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'email;rolle;guardians\n'
                        'kind@schule.de;kind;elternteil@schule.de\n'
                        'mitglied@schule.de;mitglied;\n'
                        'mod@schule.de;moderator;',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Rollen: mitglied · moderator · kind\n'
                      'Delimiter , oder ; wird automatisch erkannt\n'
                      'Guardians (Leerzeichen getrennt) nur für "kind" nötig\n'
                      'Guardians müssen bereits Org-Mitglieder sein',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

          if (rows != null && !showLog) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                rows.length - validCount > 0
                    ? l.csvRowsErrors(rows.length, validCount, rows.length - validCount)
                    : l.csvRowsValid(rows.length, validCount),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final row = rows[i];
                  final status = _rowStatus(row);
                  return _RowTile(
                    row: row,
                    status: status,
                    message: _rowStatusMessage(row, l),
                  );
                },
              ),
            ),
          ],

          if (showLog)
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _importLog.length,
                itemBuilder: (context, i) {
                  final entry = _importLog[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      entry,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: entry.startsWith('✓') ? Colors.green : Colors.red,
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ── Row tile ──────────────────────────────────────────────────────────────────

class _RowTile extends StatelessWidget {
  final _CsvRow row;
  final _RowStatus status;
  final String message;

  const _RowTile({
    required this.row,
    required this.status,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      _RowStatus.valid => (Icons.check_circle_outline, Colors.green),
      _RowStatus.warning => (Icons.warning_amber_outlined, Colors.orange),
      _RowStatus.error => (Icons.error_outline, Colors.red),
    };

    return ListTile(
      dense: true,
      leading: Icon(icon, color: color, size: 20),
      title: Text(
        row.email.isEmpty ? '(leer)' : row.email,
        style: TextStyle(
          fontSize: 13,
          color: status == _RowStatus.error ? Colors.red : null,
        ),
      ),
      subtitle: Text(
        message,
        style: TextStyle(fontSize: 11, color: color),
      ),
      trailing: Text(
        'Z. ${row.lineIndex}',
        style: const TextStyle(fontSize: 10, color: Colors.grey),
      ),
    );
  }
}
