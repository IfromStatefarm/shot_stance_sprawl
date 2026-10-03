import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../account/account_models.dart';
import '../account/social_account_gate.dart';
import '../drill/providers.dart';
import '../onboarding/season_schedule.dart';
import 'social_providers.dart';
import 'team_repository.dart';

String teamInviteMessage(String code) =>
    'You say you want to get better. Prove it.\n'
    'Join my team on Snap & Go. Train your stance, shots, sprawls, and wrestling skills anywhere... then challenge me and see who actually puts in the work.\n'
    'Get the app: https://keepkidswrestling.com/Snap-and-go/\n'
    'Enter team code: $code\n'
    'No excuses. No spectators. Get better.';

Future<void> showTeamSheet(BuildContext context, WidgetRef ref) async {
  if (!await requireSocialAccount(context, ref) || !context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const TeamSheet(),
  );
}

enum _TeamForm { choices, create, join, edit }

class TeamSheet extends ConsumerStatefulWidget {
  const TeamSheet({super.key});

  @override
  ConsumerState<TeamSheet> createState() => _TeamSheetState();
}

class _TeamSheetState extends ConsumerState<TeamSheet> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final Map<String, Future<String>> _photoUrls = {};
  String? _state;
  XFile? _photo;
  Uint8List? _photoBytes;
  _TeamForm _form = _TeamForm.choices;
  bool _busy = false;
  String? _error;
  String? _editingTeamId;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEs = ref.watch(languageProvider) == 'es';
    final membership = ref.watch(teamMembershipProvider);
    final team = ref.watch(currentTeamProvider);
    final access = ref.watch(teamAccessCodeProvider);
    final members = ref.watch(teamMemberIdsProvider);
    final joined = membership.asData?.value;
    final current = team.asData?.value;

    return SafeArea(
      top: false,
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: (MediaQuery.sizeOf(context).height -
                  MediaQuery.viewInsetsOf(context).bottom) *
              0.83,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isEs ? 'Mi equipo' : 'My Team',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: isEs ? 'Cerrar' : 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (membership.isLoading || (joined != null && team.isLoading))
                const Center(child: CircularProgressIndicator())
              else if (membership.hasError || team.hasError)
                _message(isEs
                    ? 'No se pudo cargar el equipo.'
                    : 'Could not load your team.')
              else if (joined != null &&
                  current != null &&
                  current.status == 'active')
                _teamDetails(current, joined, access, members, isEs)
              else if (joined != null)
                Column(
                  children: [
                    _message(isEs
                        ? 'Este equipo ya no está disponible.'
                        : 'This team is no longer available.'),
                    if (joined.isOwner)
                      FilledButton(
                        onPressed: _busy
                            ? null
                            : () => unawaited(_confirmAndAct(delete: true)),
                        child: Text(isEs
                            ? 'Terminar eliminación'
                            : 'Finish deleting team'),
                      ),
                  ],
                )
              else
                _noTeam(isEs),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _message(String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Text(value, textAlign: TextAlign.center),
      );

  Widget _noTeam(bool isEs) {
    if (_form == _TeamForm.create) return _teamForm(isEs, editing: false);
    if (_form == _TeamForm.join) return _joinForm(isEs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        const Icon(Icons.groups_outlined, size: 64),
        const SizedBox(height: 12),
        Text(
          isEs
              ? 'Crea un equipo o únete con un código.'
              : 'Create a team or join one with an access code.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => setState(() {
            _name.text = ref.read(userProfileProvider).teamName ?? '';
            _form = _TeamForm.create;
          }),
          icon: const Icon(Icons.add_circle_outline),
          label: Text(isEs ? 'Crear equipo' : 'Create a team'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => setState(() => _form = _TeamForm.join),
          icon: const Icon(Icons.key_outlined),
          label: Text(isEs ? 'Unirme a un equipo' : 'Join a team'),
        ),
      ],
    );
  }

  Widget _teamForm(bool isEs, {required bool editing}) {
    final states = seasonDatesByState.keys.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(
            editing
                ? (isEs ? 'Editar equipo' : 'Edit team')
                : (isEs ? 'Crear equipo' : 'Create a team'),
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          enabled: !_busy,
          maxLength: 80,
          decoration: InputDecoration(
            labelText: isEs ? 'Nombre del equipo' : 'Team name',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: states.contains(_state) ? _state : null,
          decoration: InputDecoration(
            labelText: isEs ? 'Estado' : 'State',
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final value in states)
              DropdownMenuItem(value: value, child: Text(value))
          ],
          onChanged: _busy ? null : (value) => setState(() => _state = value),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => unawaited(_pickPhoto()),
          icon: const Icon(Icons.add_a_photo_outlined),
          label: Text(_photo == null
              ? (editing
                  ? (isEs ? 'Cambiar foto' : 'Change photo')
                  : (isEs ? 'Elegir foto' : 'Choose photo'))
              : _photo!.name),
        ),
        if (_photoBytes != null) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(_photoBytes!, height: 150, fit: BoxFit.cover),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_saveTeam(editing)),
          child: Text(_busy
              ? (isEs ? 'Guardando...' : 'Saving...')
              : editing
                  ? (isEs ? 'Guardar cambios' : 'Save changes')
                  : (isEs ? 'Crear equipo' : 'Create team')),
        ),
        TextButton(
          onPressed:
              _busy ? null : () => setState(() => _form = _TeamForm.choices),
          child: Text(isEs ? 'Cancelar' : 'Cancel'),
        ),
      ],
    );
  }

  Widget _joinForm(bool isEs) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Text(isEs ? 'Unirme a un equipo' : 'Join a team',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: isEs ? 'Código de acceso' : 'Access code',
              hintText: 'XXXX-XXXX-XXXX',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : () => unawaited(_joinTeam()),
            child: Text(_busy
                ? (isEs ? 'Uniéndote...' : 'Joining...')
                : (isEs ? 'Unirme' : 'Join team')),
          ),
          TextButton(
            onPressed:
                _busy ? null : () => setState(() => _form = _TeamForm.choices),
            child: Text(isEs ? 'Cancelar' : 'Cancel'),
          ),
        ],
      );

  Widget _teamDetails(
    Team team,
    TeamMembership membership,
    AsyncValue<String?> access,
    AsyncValue<List<String>> members,
    bool isEs,
  ) {
    if (_form == _TeamForm.edit) {
      if (_editingTeamId != team.id) {
        _name.text = team.name;
        _state = team.state;
        _editingTeamId = team.id;
      }
      return _teamForm(isEs, editing: true);
    }
    final code = access.asData?.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        FutureBuilder<String>(
          future: _photoUrls.putIfAbsent(
            team.photoPath,
            () => ref.read(teamRepositoryProvider).photoUrl(team.photoPath),
          ),
          builder: (context, snapshot) => ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: snapshot.hasData
                ? Image.network(snapshot.data!, height: 190, fit: BoxFit.cover)
                : Container(
                    height: 190,
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.groups, size: 64),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        Text(team.name, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(team.state),
        if (members.asData?.value != null)
          Text(isEs
              ? '${members.asData!.value.length} integrantes'
              : '${members.asData!.value.length} members'),
        const SizedBox(height: 20),
        if (membership.isOwner) ...[
          Text(isEs ? 'Código de acceso' : 'Access code',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 5),
          SelectableText(code ?? (access.isLoading ? '...' : 'Unavailable'),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: code == null ? null : () => unawaited(_copyCode(code)),
            icon: const Icon(Icons.copy_outlined),
            label: Text(isEs ? 'Copiar código' : 'Copy code'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed:
                code == null ? null : () => unawaited(_inviteByText(code)),
            icon: const Icon(Icons.sms_outlined),
            label: Text(isEs ? 'Invitar por mensaje' : 'Invite by text'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _editingTeamId = null;
                      _photo = null;
                      _photoBytes = null;
                      _form = _TeamForm.edit;
                    }),
            icon: const Icon(Icons.edit_outlined),
            label: Text(isEs ? 'Editar equipo' : 'Edit team'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed:
                _busy ? null : () => unawaited(_confirmAndAct(delete: true)),
            icon: const Icon(Icons.delete_outline),
            label: Text(isEs ? 'Eliminar equipo' : 'Delete team'),
          ),
        ] else
          OutlinedButton.icon(
            onPressed:
                _busy ? null : () => unawaited(_confirmAndAct(delete: false)),
            icon: const Icon(Icons.logout),
            label: Text(isEs ? 'Salir del equipo' : 'Leave team'),
          ),
      ],
    );
  }

  Future<void> _pickPhoto() async {
    try {
      final selected = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (selected == null) return;
      final bytes = await selected.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        throw const AccountException('Choose a team photo under 5 MB.');
      }
      if (mounted) {
        setState(() {
          _photo = selected;
          _photoBytes = bytes;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = accountErrorMessage(error));
      }
    }
  }

  Future<void> _saveTeam(bool editing) async {
    if (_name.text.trim().isEmpty ||
        _state == null ||
        (!editing && _photo == null)) {
      setState(
          () => _error = 'Enter a name, choose a state, and select a photo.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = ref.read(teamRepositoryProvider);
      if (editing) {
        await repository.editTeam(
            name: _name.text, state: _state!, photo: _photo);
      } else {
        await repository.createTeam(
            name: _name.text, state: _state!, photo: _photo!);
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _form = _TeamForm.choices;
          _photo = null;
          _photoBytes = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = accountErrorMessage(error);
        });
      }
    }
  }

  Future<void> _joinTeam() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(teamRepositoryProvider).joinTeam(_code.text);
      if (mounted) {
        setState(() {
          _busy = false;
          _form = _TeamForm.choices;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = accountErrorMessage(error);
        });
      }
    }
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) _notice('Team code copied.');
  }

  Future<void> _inviteByText(String code) async {
    final message = teamInviteMessage(code);
    await Clipboard.setData(ClipboardData(text: message));
    final url = Uri(scheme: 'sms', queryParameters: {'body': message});
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (mounted) _notice('Invite copied. Paste it into a text message.');
      }
    } catch (_) {
      if (mounted) _notice('Invite copied. Paste it into a text message.');
    }
  }

  Future<void> _confirmAndAct({required bool delete}) async {
    final isEs = ref.read(languageProvider) == 'es';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(delete
            ? (isEs ? '¿Eliminar equipo?' : 'Delete team?')
            : (isEs ? '¿Salir del equipo?' : 'Leave team?')),
        content: Text(delete
            ? (isEs
                ? 'Todos los integrantes saldrán y el código dejará de funcionar.'
                : 'All members will be removed and the access code will stop working.')
            : (isEs
                ? 'Ya no podrás enviar nuevos workouts a este equipo.'
                : 'You will no longer be able to send new workouts to this team.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(isEs ? 'Cancelar' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(delete
                ? (isEs ? 'Eliminar' : 'Delete')
                : (isEs ? 'Salir' : 'Leave')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (delete) {
        await ref.read(teamRepositoryProvider).deleteTeam();
      } else {
        await ref.read(teamRepositoryProvider).leaveTeam();
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _form = _TeamForm.choices;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = accountErrorMessage(error);
        });
      }
    }
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
