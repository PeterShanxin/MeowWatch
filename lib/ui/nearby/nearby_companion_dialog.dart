import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/nearby/desktop_nearby_service.dart';
import '../../core/nearby/lan_interfaces.dart';
import '../../core/theme/meow_context.dart';
import '../../core/theme/tokens/icon_sizes.dart';
import '../../core/theme/tokens/radii.dart';
import '../../core/theme/tokens/spacing.dart';
import '../../core/theme/tokens/type_scale.dart';

Future<void> showNearbyCompanionDialog(
  BuildContext context,
  DesktopNearbyService service,
) async {
  try {
    await showDialog<void>(
      context: context,
      builder: (_) => NearbyCompanionDialog(service: service),
    );
  } finally {
    await service.closePairing();
  }
}

class NearbyCompanionDialog extends StatefulWidget {
  const NearbyCompanionDialog({super.key, required this.service});

  final DesktopNearbyService service;

  @override
  State<NearbyCompanionDialog> createState() => _NearbyCompanionDialogState();
}

class _NearbyCompanionDialogState extends State<NearbyCompanionDialog> {
  DesktopNearbyService get service => widget.service;

  @override
  void initState() {
    super.initState();
    unawaited(service.initialize().catchError((Object _) {}));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.meow;
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: colors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 480,
          maxWidth: 620,
          maxHeight: 760,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.xxl,
                Spacing.xl,
                Spacing.md,
                Spacing.md,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.phone_android,
                    color: colors.accent,
                    size: IconSizes.lg,
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nearby companion',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: TypeScale.title,
                            fontWeight: TypeScale.semibold,
                          ),
                        ),
                        const SizedBox(height: Spacing.xs),
                        Text(
                          'Control this active session from a paired phone.',
                          style: TextStyle(
                            color: colors.textDim,
                            fontSize: TypeScale.body,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: colors.textDim),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.border),
            Flexible(
              child: ListenableBuilder(
                listenable: service,
                builder: (context, _) => SingleChildScrollView(
                  padding: const EdgeInsets.all(Spacing.xxl),
                  child: _buildBody(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return switch (service.phase) {
      DesktopNearbyPhase.disabled || DesktopNearbyPhase.initializing =>
        const _BusyState(label: 'Preparing protected Nearby identity…'),
      DesktopNearbyPhase.enabling => const _BusyState(
        label: 'Opening a private LAN listener…',
      ),
      DesktopNearbyPhase.stopping => const _BusyState(
        label: 'Stopping Nearby…',
      ),
      DesktopNearbyPhase.ready => _ReadyState(service: service),
      DesktopNearbyPhase.enabled => _EnabledState(service: service),
      DesktopNearbyPhase.failed => _FailedState(service: service),
      DesktopNearbyPhase.closed => const SizedBox.shrink(),
    };
  }
}

class _BusyState extends StatelessWidget {
  const _BusyState({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.meow;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xxxl),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.accent,
            ),
          ),
          const SizedBox(width: Spacing.md),
          Text(
            label,
            style: TextStyle(color: colors.textDim, fontSize: TypeScale.body),
          ),
        ],
      ),
    );
  }
}

class _ReadyState extends StatelessWidget {
  const _ReadyState({required this.service});
  final DesktopNearbyService service;

  @override
  Widget build(BuildContext context) {
    final colors = context.meow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose a Windows Private network',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: TypeScale.label,
            fontWeight: TypeScale.semibold,
          ),
        ),
        const SizedBox(height: Spacing.sm),
        Text(
          'Nearby stays off until you choose an eligible connection. '
          'MeowWatch never changes your firewall or Windows network profile.',
          style: TextStyle(
            color: colors.textDim,
            fontSize: TypeScale.body,
            height: 1.45,
          ),
        ),
        const SizedBox(height: Spacing.lg),
        if (service.interfaces.isEmpty)
          const _Notice(
            icon: Icons.wifi_off,
            text:
                'No supported private or link-local IPv4 connection was found.',
          )
        else
          for (final interface in service.interfaces) ...[
            _InterfaceCard(service: service, interface: interface),
            const SizedBox(height: Spacing.sm),
          ],
        const SizedBox(height: Spacing.sm),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: service.refreshInterfaces,
            icon: const Icon(Icons.refresh, size: IconSizes.sm),
            label: const Text('Refresh networks'),
          ),
        ),
        if (service.pairedDevices.isNotEmpty) ...[
          const SizedBox(height: Spacing.xl),
          _PairedDevices(service: service),
        ],
      ],
    );
  }
}

class _InterfaceCard extends StatelessWidget {
  const _InterfaceCard({required this.service, required this.interface});
  final DesktopNearbyService service;
  final LanInterfaceAddress interface;

  @override
  Widget build(BuildContext context) {
    final colors = context.meow;
    final eligible =
        interface.automaticEligibility == LanAutomaticEligibility.eligible &&
        interface.prefixLength <= 30;
    final reason = interface.prefixLength > 30
        ? 'This connection has no usable peer subnet.'
        : interface.automaticRejectionReason;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.peerBubble,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              eligible ? Icons.lan : Icons.shield_outlined,
              color: eligible ? colors.online : colors.textDim,
              size: IconSizes.md,
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    interface.friendlyName,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: TypeScale.body,
                      fontWeight: TypeScale.semibold,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    '${interface.address}/${interface.prefixLength} · '
                    '${_profileLabel(interface.profile)}',
                    style: TextStyle(
                      color: colors.textDim,
                      fontSize: TypeScale.caption,
                    ),
                  ),
                  if (reason != null) ...[
                    const SizedBox(height: Spacing.sm),
                    Text(
                      reason,
                      style: TextStyle(
                        color: colors.textDim,
                        fontSize: TypeScale.caption,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: Spacing.md),
            FilledButton(
              onPressed: eligible
                  ? () async {
                      try {
                        await service.enable(interface);
                      } catch (_) {}
                    }
                  : null,
              child: const Text('Enable'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnabledState extends StatelessWidget {
  const _EnabledState({required this.service});
  final DesktopNearbyService service;

  @override
  Widget build(BuildContext context) {
    final colors = context.meow;
    final interface = service.selectedInterface!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle, color: colors.online, size: IconSizes.md),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                'Nearby is on for ${interface.friendlyName}',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: TypeScale.label,
                  fontWeight: TypeScale.semibold,
                ),
              ),
            ),
            TextButton(
              onPressed: service.stop,
              style: TextButton.styleFrom(foregroundColor: colors.error),
              child: const Text('Stop Nearby'),
            ),
          ],
        ),
        const SizedBox(height: Spacing.xs),
        Text(
          service.mdnsAvailable
              ? 'Phones on this network can discover this desktop.'
              : 'Automatic discovery is unavailable. Pair with the QR code instead.',
          style: TextStyle(color: colors.textDim, fontSize: TypeScale.body),
        ),
        const SizedBox(height: Spacing.xl),
        if (service.pendingApprovalName case final name?)
          _ApprovalCard(service: service, clientName: name)
        else if (service.invitationQr != null)
          _InvitationCard(service: service)
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                try {
                  await service.openPairing();
                } catch (_) {}
              },
              icon: const Icon(Icons.qr_code_2),
              label: const Text('Pair a phone'),
            ),
          ),
        if (service.pairedDevices.isNotEmpty) ...[
          const SizedBox(height: Spacing.xxl),
          _PairedDevices(service: service),
        ],
      ],
    );
  }
}

class _InvitationCard extends StatelessWidget {
  const _InvitationCard({required this.service});
  final DesktopNearbyService service;

  @override
  Widget build(BuildContext context) {
    final colors = context.meow;
    final data = service.invitationQr!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.peerBubble,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          children: [
            Text(
              'Scan in MeowWatch Mobile',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: TypeScale.label,
                fontWeight: TypeScale.semibold,
              ),
            ),
            const SizedBox(height: Spacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.sm),
              child: ColoredBox(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.sm),
                  child: QrImageView(
                    data: data,
                    version: QrVersions.auto,
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),
            Text(
              'Expires in ${service.invitationSeconds}s',
              style: TextStyle(color: colors.textDim, fontSize: TypeScale.body),
            ),
            const SizedBox(height: Spacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Clipboard.setData(ClipboardData(text: data)),
                  icon: const Icon(Icons.copy, size: IconSizes.sm),
                  label: const Text('Copy full invite'),
                ),
                const SizedBox(width: Spacing.sm),
                TextButton(
                  onPressed: service.closePairing,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({required this.service, required this.clientName});
  final DesktopNearbyService service;
  final String clientName;

  @override
  Widget build(BuildContext context) {
    final colors = context.meow;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.myBubble,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: colors.accent),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Allow $clientName to control this MeowWatch session?',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: TypeScale.label,
                fontWeight: TypeScale.semibold,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'This request expires in 30 seconds.',
              style: TextStyle(color: colors.textDim, fontSize: TypeScale.body),
            ),
            const SizedBox(height: Spacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: service.denyPending,
                  child: const Text('Deny'),
                ),
                const SizedBox(width: Spacing.sm),
                FilledButton(
                  onPressed: service.approvePending,
                  child: const Text('Allow'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PairedDevices extends StatelessWidget {
  const _PairedDevices({required this.service});
  final DesktopNearbyService service;

  @override
  Widget build(BuildContext context) {
    final colors = context.meow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Paired phones',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: TypeScale.label,
            fontWeight: TypeScale.semibold,
          ),
        ),
        const SizedBox(height: Spacing.sm),
        for (final device in service.pairedDevices)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.phone_iphone, color: colors.textDim),
            title: Text(
              device.clientName,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: TypeScale.body,
              ),
            ),
            subtitle: Text(
              'Last used ${_dateLabel(device.lastUsedAt)}',
              style: TextStyle(
                color: colors.textDim,
                fontSize: TypeScale.caption,
              ),
            ),
            trailing: TextButton(
              onPressed: () => _confirmRevoke(context, service, device.tokenId),
              style: TextButton.styleFrom(foregroundColor: colors.error),
              child: const Text('Revoke'),
            ),
          ),
      ],
    );
  }
}

class _FailedState extends StatelessWidget {
  const _FailedState({required this.service});
  final DesktopNearbyService service;

  @override
  Widget build(BuildContext context) {
    final colors = context.meow;
    return Column(
      children: [
        Icon(Icons.gpp_bad_outlined, color: colors.error, size: IconSizes.xl),
        const SizedBox(height: Spacing.md),
        Text(
          _errorMessage(service.errorCode),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: TypeScale.body,
            height: 1.45,
          ),
        ),
        const SizedBox(height: Spacing.lg),
        OutlinedButton.icon(
          onPressed: () async {
            try {
              await service.initialize();
            } catch (_) {}
          },
          icon: const Icon(Icons.refresh, size: IconSizes.sm),
          label: const Text('Try again'),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.meow;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: colors.textDim, size: IconSizes.md),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: colors.textDim,
              fontSize: TypeScale.body,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _confirmRevoke(
  BuildContext context,
  DesktopNearbyService service,
  String tokenId,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final colors = context.meow;
      return AlertDialog(
        backgroundColor: colors.surface,
        title: const Text('Revoke this phone?'),
        content: const Text('It will need to pair again before reconnecting.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revoke'),
          ),
        ],
      );
    },
  );
  if (confirmed == true) {
    try {
      await service.revoke(tokenId);
    } catch (_) {}
  }
}

String _profileLabel(LanNetworkProfile profile) => switch (profile) {
  LanNetworkProfile.private => 'Private',
  LanNetworkProfile.public => 'Public',
  LanNetworkProfile.domainAuthenticated => 'Domain',
  LanNetworkProfile.unknown => 'Unknown',
};

String _errorMessage(String? code) => switch (code) {
  'storage_unavailable' || 'storage_corrupt' =>
    'Nearby could not open its protected credentials. It stays off.',
  'permission_denied' =>
    'Choose a Windows connection that is currently marked Private.',
  _ =>
    'The selected private network changed or became unavailable. Nearby was stopped.',
};

String _dateLabel(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}
