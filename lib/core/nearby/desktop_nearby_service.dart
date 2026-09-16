import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:nearby_bridge/nearby_bridge.dart';
import 'package:nearby_platform/nearby_platform.dart';
import 'package:path/path.dart' as p;

import '../data/app_support_dir.dart';
import 'lan_interfaces.dart';

enum DesktopNearbyPhase {
  disabled,
  initializing,
  ready,
  enabling,
  enabled,
  stopping,
  failed,
  closed,
}

final class DesktopNearbyHandlerBinding {
  const DesktopNearbyHandlerBinding({
    required this.handler,
    required this.close,
  });

  final NearbyCommandHandler handler;
  final Future<void> Function() close;
}

typedef DesktopNearbyHandlerFactory =
    DesktopNearbyHandlerBinding Function({
      required String desktopId,
      required String desktopName,
      required String sessionEpoch,
    });

abstract interface class DesktopNearbyPersistence {
  NearbySecretStore get secretStore;
  Future<PersistedDesktopIdentity> loadOrCreateIdentity();
  Future<List<PairedDeviceMetadata>> listPairedDevices();
}

abstract interface class DesktopNearbyServerHandle {
  int get port;
  Future<void> close();
}

typedef DesktopNearbyServerBinder =
    Future<DesktopNearbyServerHandle> Function({
      required LanSubnet subnet,
      required TlsIdentity identity,
      required NearbyAuthority authority,
      required NearbyCommandHandler handler,
      required Future<bool> Function(PendingApproval approval) approvePairing,
    });

abstract interface class DesktopNearbyAdvertisement {
  Future<void> start();
  Future<void> dispose();
}

typedef DesktopNearbyAdvertisementFactory =
    DesktopNearbyAdvertisement Function({
      required String desktopId,
      required String displayName,
      required int port,
      required bool pairingOpen,
    });

typedef DesktopNearbyPersistenceFactory =
    DesktopNearbyPersistence Function(String namespaceHash);

final class DesktopNearbyService extends ChangeNotifier {
  DesktopNearbyService({
    required this.desktopName,
    required this.handlerFactory,
    Future<Directory> Function()? supportDirectoryResolver,
    Future<String> Function(Directory directory)? canonicalPathResolver,
    Future<List<LanInterfaceAddress>> Function()? interfacesProvider,
    DesktopNearbyPersistenceFactory? persistenceFactory,
    DesktopNearbyServerBinder? serverBinder,
    DesktopNearbyAdvertisementFactory? advertisementFactory,
    this.interfacePollInterval = const Duration(seconds: 3),
  }) : _supportDirectoryResolver =
           supportDirectoryResolver ?? resolveAppSupportDir,
       _canonicalPathResolver = canonicalPathResolver ?? _canonicalPath,
       _interfacesProvider = interfacesProvider ?? LanInterfaces().list,
       _persistenceFactory =
           persistenceFactory ??
           ((hash) => _ProtectedPersistence(
             ProtectedNearbyStore(namespaceHash: hash),
           )),
       _serverBinder = serverBinder ?? _bindServer,
       _advertisementFactory = advertisementFactory ?? _createAdvertisement {
    validateName(desktopName);
    if (utf8.encode(desktopName).length > 63) {
      throw ArgumentError.value(
        desktopName,
        'desktopName',
        'must be at most 63 UTF-8 bytes',
      );
    }
  }

  static const invitationLifetime = Duration(seconds: 120);
  static const approvalLifetime = Duration(seconds: 30);

  final String desktopName;
  final DesktopNearbyHandlerFactory handlerFactory;
  final Duration interfacePollInterval;
  final Future<Directory> Function() _supportDirectoryResolver;
  final Future<String> Function(Directory directory) _canonicalPathResolver;
  final Future<List<LanInterfaceAddress>> Function() _interfacesProvider;
  final DesktopNearbyPersistenceFactory _persistenceFactory;
  final DesktopNearbyServerBinder _serverBinder;
  final DesktopNearbyAdvertisementFactory _advertisementFactory;

  DesktopNearbyPhase _phase = DesktopNearbyPhase.disabled;
  String? _errorCode;
  List<LanInterfaceAddress> _interfaces = const [];
  List<PairedDeviceMetadata> _pairedDevices = const [];
  DesktopNearbyPersistence? _persistence;
  PersistedDesktopIdentity? _identity;
  LanInterfaceAddress? _selectedInterface;
  NearbyAuthority? _authority;
  DesktopNearbyServerHandle? _server;
  DesktopNearbyHandlerBinding? _handlerBinding;
  DesktopNearbyAdvertisement? _advertisement;
  Future<void>? _handlerClosing;
  PairingInvitation? _invitation;
  DateTime? _invitationDeadline;
  int _invitationSeconds = 0;
  _ApprovalRequest? _approval;
  Timer? _invitationTimer;
  Timer? _interfaceTimer;
  Future<void>? _initializing;
  Future<void>? _enabling;
  Future<void>? _stopping;
  bool _checkingInterfaces = false;
  bool _mdnsAvailable = false;
  bool _disposed = false;
  int _generation = 0;
  int _advertisementGeneration = 0;

  DesktopNearbyPhase get phase => _phase;
  String? get errorCode => _errorCode;
  List<LanInterfaceAddress> get interfaces => _interfaces;
  List<PairedDeviceMetadata> get pairedDevices => _pairedDevices;
  LanInterfaceAddress? get selectedInterface => _selectedInterface;
  bool get isEnabled => _phase == DesktopNearbyPhase.enabled;
  bool get mdnsAvailable => _mdnsAvailable;
  String? get desktopId => _identity?.desktopId;
  PairingInvitation? get invitation => _invitation;
  String? get invitationQr => _invitation?.encodeQr();
  String? get manualCode => _invitation?.manualCode;
  int get invitationSeconds => _invitationSeconds;
  String? get pendingApprovalName => _approval?.clientName;
  LanEndpoint? get endpoint {
    final server = _server;
    final interfaceAddress = _selectedInterface;
    if (server == null || interfaceAddress == null) return null;
    return LanEndpoint(
      address: LanIpv4Address.parse(interfaceAddress.address),
      port: server.port,
    );
  }

  Future<void> initialize() {
    if (_disposed) return Future.error(const NearbyException('disposed'));
    final existing = _initializing;
    if (existing != null) return existing;
    if (_persistence != null) return refreshInterfaces();
    final future = _initialize();
    _initializing = future;
    unawaited(
      future.then<void>(
        (_) => _clearInitializing(future),
        onError: (Object _, StackTrace _) => _clearInitializing(future),
      ),
    );
    return future;
  }

  void _clearInitializing(Future<void> future) {
    if (identical(_initializing, future)) _initializing = null;
  }

  Future<void> _initialize() async {
    _setPhase(DesktopNearbyPhase.initializing);
    late final DesktopNearbyPersistence persistence;
    try {
      final directory = await _supportDirectoryResolver();
      final canonical = await _canonicalPathResolver(directory);
      final namespace = sha256.convert(utf8.encode(canonical)).toString();
      persistence = _persistenceFactory(namespace);
      final results = await Future.wait<Object>([
        persistence.loadOrCreateIdentity(),
        persistence.listPairedDevices(),
      ]);
      if (_disposed) throw const NearbyException('cancelled');
      _persistence = persistence;
      _identity = results[0] as PersistedDesktopIdentity;
      _pairedDevices = List.unmodifiable(
        results[1] as List<PairedDeviceMetadata>,
      );
    } catch (error) {
      if (_disposed) rethrow;
      _errorCode = _storageError(error);
      _setPhase(DesktopNearbyPhase.failed);
      throw NearbyException(_errorCode!);
    }
    try {
      final interfaces = await _interfacesProvider();
      if (_disposed) throw const NearbyException('cancelled');
      _interfaces = List.unmodifiable(interfaces);
      _errorCode = null;
      _setPhase(DesktopNearbyPhase.ready);
    } catch (_) {
      if (_disposed) throw const NearbyException('cancelled');
      _errorCode = 'lan_unavailable';
      _setPhase(DesktopNearbyPhase.failed);
      throw const NearbyException('lan_unavailable');
    }
  }

  Future<void> enable(LanInterfaceAddress selected) {
    if (_disposed) return Future.error(const NearbyException('disposed'));
    final existing = _enabling;
    if (existing != null) return existing;
    final future = _enable(selected);
    _enabling = future;
    unawaited(
      future.then<void>(
        (_) => _clearEnabling(future),
        onError: (Object _, StackTrace _) => _clearEnabling(future),
      ),
    );
    return future;
  }

  void _clearEnabling(Future<void> future) {
    if (identical(_enabling, future)) _enabling = null;
  }

  Future<void> _enable(LanInterfaceAddress selected) async {
    if (_persistence == null) await initialize();
    if (_server != null || _phase == DesktopNearbyPhase.enabled) return;
    _setPhase(DesktopNearbyPhase.enabling);
    final generation = ++_generation;
    NearbyAuthority? authority;
    DesktopNearbyHandlerBinding? binding;
    DesktopNearbyServerHandle? server;
    var corePublished = false;
    var serverPublished = false;
    try {
      final current = await _interfacesProvider();
      if (_disposed || generation != _generation) {
        throw const NearbyException('cancelled');
      }
      final eligible = _matchingEligibleInterface(selected, current);
      _interfaces = List.unmodifiable(current);
      if (eligible == null || eligible.prefixLength > 30) {
        throw const NearbyException('permission_denied');
      }
      final identity = _identity!;
      final persistence = _persistence!;
      final subnet = LanSubnet(
        localAddress: LanIpv4Address.parse(eligible.address),
        prefixLength: eligible.prefixLength,
      );
      authority = NearbyAuthority(
        desktopId: identity.desktopId,
        certificateSha256: identity.tlsIdentity.certificateSha256,
        store: persistence.secretStore,
      );
      binding = handlerFactory(
        desktopId: identity.desktopId,
        desktopName: desktopName,
        sessionEpoch: authority.sessionEpoch,
      );
      _authority = authority;
      _handlerBinding = binding;
      _selectedInterface = eligible;
      corePublished = true;
      server = await _serverBinder(
        subnet: subnet,
        identity: identity.tlsIdentity,
        authority: authority,
        handler: binding.handler,
        approvePairing: _requestApproval,
      );
      if (_disposed || generation != _generation) {
        throw const NearbyException('cancelled');
      }
      _server = server;
      serverPublished = true;
      _errorCode = null;
      _setPhase(DesktopNearbyPhase.enabled);
      await _replaceAdvertisement(pairingOpen: false, generation: generation);
      if (_disposed || generation != _generation) {
        throw const NearbyException('cancelled');
      }
      _startInterfaceMonitor();
    } catch (error) {
      if (!serverPublished) {
        await server?.close();
      }
      if (!corePublished) {
        await binding?.close();
        await authority?.dispose();
      } else if (!_disposed && generation == _generation) {
        _authority = null;
        _handlerBinding = null;
        _selectedInterface = null;
        await binding?.close();
        await authority?.dispose();
      }
      if (_disposed || generation != _generation) {
        throw const NearbyException('cancelled');
      }
      _errorCode = _enableError(error);
      _setPhase(DesktopNearbyPhase.failed);
      throw NearbyException(_errorCode!);
    }
  }

  Future<PairingInvitation> openPairing() async {
    final authority = _authority;
    final currentEndpoint = endpoint;
    if (_phase != DesktopNearbyPhase.enabled ||
        authority == null ||
        currentEndpoint == null) {
      throw const NearbyException('not_connected');
    }
    if (_invitation != null || _approval != null) {
      await closePairing();
    } else {
      authority.cancelInvitation();
    }
    final generation = _generation;
    final invitation = authority.openInvitation(currentEndpoint);
    _invitation = invitation;
    _invitationDeadline = DateTime.now().toUtc().add(invitationLifetime);
    _invitationSeconds = invitationLifetime.inSeconds;
    _invitationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateInvitationCountdown();
    });
    notifyListeners();
    await _replaceAdvertisement(pairingOpen: true, generation: generation);
    if (_disposed || generation != _generation || _invitation != invitation) {
      throw const NearbyException('cancelled');
    }
    return invitation;
  }

  Future<void> closePairing() async {
    _invitationTimer?.cancel();
    _invitationTimer = null;
    _invitationDeadline = null;
    _invitationSeconds = 0;
    _invitation = null;
    _authority?.cancelInvitation();
    _completeApproval(false);
    if (!_disposed) notifyListeners();
    if (_server != null) {
      await _replaceAdvertisement(pairingOpen: false, generation: _generation);
    }
  }

  void approvePending() {
    if (_disposed) return;
    final request = _approval;
    if (request == null) return;
    _invitationTimer?.cancel();
    _invitationTimer = null;
    _invitationDeadline = null;
    _invitationSeconds = 0;
    _invitation = null;
    _completeApproval(true);
    notifyListeners();
    unawaited(
      _replaceAdvertisement(pairingOpen: false, generation: _generation),
    );
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 500)).then((_) {
        if (!_disposed) return _refreshPairedDevices();
      }),
    );
  }

  void denyPending() {
    if (_disposed) return;
    _completeApproval(false);
    notifyListeners();
  }

  Future<void> revoke(String tokenId) async {
    final persistence = _persistence;
    if (persistence == null) throw const NearbyException('storage_unavailable');
    final authority = _authority;
    if (authority != null) {
      await authority.revoke(tokenId);
    } else {
      await persistence.secretStore.revoke(tokenId);
    }
    await _refreshPairedDevices();
  }

  Future<void> refreshInterfaces() async {
    if (_disposed || _checkingInterfaces) return;
    _checkingInterfaces = true;
    try {
      final current = await _interfacesProvider();
      if (_disposed) return;
      _interfaces = List.unmodifiable(current);
      final selected = _selectedInterface;
      if (_server != null &&
          (selected == null ||
              _matchingEligibleInterface(selected, current) == null)) {
        await _stop(failureCode: 'lan_unavailable');
        return;
      }
      if (_server == null && _phase == DesktopNearbyPhase.failed) {
        _errorCode = null;
        _setPhase(DesktopNearbyPhase.ready);
      } else {
        notifyListeners();
      }
    } catch (_) {
      if (_disposed) return;
      if (_server != null) {
        await _stop(failureCode: 'lan_unavailable');
      } else {
        _errorCode = 'lan_unavailable';
        _setPhase(DesktopNearbyPhase.failed);
      }
    } finally {
      _checkingInterfaces = false;
    }
  }

  Future<void> stop() => _stop();

  Future<void> _stop({String? failureCode}) {
    if (_phase == DesktopNearbyPhase.closed) return Future.value();
    _generation++;
    _advertisementGeneration++;
    _interfaceTimer?.cancel();
    _interfaceTimer = null;
    _invitationTimer?.cancel();
    _invitationTimer = null;
    _authority?.stop();
    final binding = _handlerBinding;
    if (binding != null && _handlerClosing == null) {
      _handlerClosing = Future<void>.sync(binding.close);
    }
    _completeApproval(false);
    _invitation = null;
    _invitationDeadline = null;
    _invitationSeconds = 0;
    final existing = _stopping;
    if (existing != null) return existing;
    if (_server == null &&
        _enabling == null &&
        _advertisement == null &&
        _handlerBinding == null) {
      _errorCode = failureCode;
      _setPhase(
        failureCode == null
            ? DesktopNearbyPhase.ready
            : DesktopNearbyPhase.failed,
      );
      return Future.value();
    }
    _phase = DesktopNearbyPhase.stopping;
    final future = _finishStop(failureCode);
    _stopping = future;
    if (!_disposed) notifyListeners();
    unawaited(
      future.then<void>(
        (_) {
          if (identical(_stopping, future)) _stopping = null;
        },
        onError: (Object _, StackTrace _) {
          if (identical(_stopping, future)) _stopping = null;
        },
      ),
    );
    return future;
  }

  Future<void> _finishStop(String? failureCode) async {
    final advertisement = _advertisement;
    final server = _server;
    final binding = _handlerBinding;
    final handlerClosing = _handlerClosing;
    final authority = _authority;
    _advertisement = null;
    _server = null;
    _authority = null;
    _handlerBinding = null;
    _handlerClosing = null;
    _selectedInterface = null;
    _mdnsAvailable = false;
    Object? cleanupError;
    StackTrace? cleanupStack;
    Future<void> attempt(Future<void>? operation) async {
      if (operation == null) return;
      try {
        await operation;
      } catch (error, stackTrace) {
        cleanupError ??= error;
        cleanupStack ??= stackTrace;
      }
    }

    try {
      await attempt(handlerClosing ?? binding?.close());
      await attempt(advertisement?.dispose());
      await attempt(server?.close());
      if (server == null) await attempt(authority?.dispose());
      final enabling = _enabling;
      if (enabling != null) {
        try {
          await enabling;
        } on NearbyException catch (error) {
          if (error.code != 'cancelled') rethrow;
        }
      }
      if (cleanupError != null) {
        Error.throwWithStackTrace(cleanupError!, cleanupStack!);
      }
    } finally {
      if (!_disposed) {
        _errorCode = failureCode;
        _setPhase(
          failureCode == null
              ? DesktopNearbyPhase.ready
              : DesktopNearbyPhase.failed,
        );
      }
    }
  }

  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _advertisementGeneration++;
    _interfaceTimer?.cancel();
    _interfaceTimer = null;
    _invitationTimer?.cancel();
    _invitationTimer = null;
    _authority?.stop();
    final binding = _handlerBinding;
    if (binding != null && _handlerClosing == null) {
      _handlerClosing = Future<void>.sync(binding.close);
    }
    _completeApproval(false);
    _invitation = null;
    _invitationDeadline = null;
    _invitationSeconds = 0;
    _phase = DesktopNearbyPhase.closed;
    try {
      final stopping = _stopping;
      if (stopping != null) {
        await stopping;
      } else {
        await _finishStop(null);
      }
      final initializing = _initializing;
      if (initializing != null) {
        try {
          await initializing;
        } catch (_) {}
      }
    } finally {
      super.dispose();
    }
  }

  Future<bool> _requestApproval(PendingApproval approval) async {
    if (_disposed || _phase != DesktopNearbyPhase.enabled) return false;
    _completeApproval(false);
    final request = _ApprovalRequest(approval.clientName);
    _approval = request;
    request.timer = Timer(approvalLifetime, () {
      if (identical(_approval, request)) {
        _completeApproval(false);
        notifyListeners();
      }
    });
    notifyListeners();
    return request.result.future;
  }

  void _completeApproval(bool allowed) {
    final request = _approval;
    _approval = null;
    request?.timer?.cancel();
    if (request != null && !request.result.isCompleted) {
      request.result.complete(allowed);
    }
  }

  void _updateInvitationCountdown() {
    final deadline = _invitationDeadline;
    if (deadline == null || _invitation == null) return;
    final remaining = deadline.difference(DateTime.now().toUtc()).inSeconds + 1;
    if (remaining <= 0) {
      unawaited(closePairing());
      return;
    }
    if (_invitationSeconds != remaining) {
      _invitationSeconds = remaining;
      notifyListeners();
    }
  }

  Future<void> _replaceAdvertisement({
    required bool pairingOpen,
    required int generation,
  }) async {
    final advertisementGeneration = ++_advertisementGeneration;
    final previous = _advertisement;
    _advertisement = null;
    _mdnsAvailable = false;
    try {
      await previous?.dispose();
    } catch (_) {
      // Discovery is optional. A QR invitation remains available when mDNS
      // cleanup or registration fails.
    }
    final server = _server;
    final identity = _identity;
    if (server == null ||
        identity == null ||
        generation != _generation ||
        advertisementGeneration != _advertisementGeneration) {
      if (!_disposed) notifyListeners();
      return;
    }
    final next = _advertisementFactory(
      desktopId: identity.desktopId,
      displayName: desktopName,
      port: server.port,
      pairingOpen: pairingOpen,
    );
    try {
      await next.start();
      if (_disposed ||
          generation != _generation ||
          advertisementGeneration != _advertisementGeneration ||
          _server == null) {
        try {
          await next.dispose();
        } catch (_) {}
        return;
      }
      _advertisement = next;
      _mdnsAvailable = true;
    } catch (_) {
      try {
        await next.dispose();
      } catch (_) {}
      if (advertisementGeneration == _advertisementGeneration) {
        _mdnsAvailable = false;
      }
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _refreshPairedDevices() async {
    final persistence = _persistence;
    if (persistence == null) return;
    try {
      _pairedDevices = List.unmodifiable(await persistence.listPairedDevices());
      if (!_disposed) notifyListeners();
    } catch (_) {
      await _stop(failureCode: 'storage_unavailable');
    }
  }

  void _startInterfaceMonitor() {
    _interfaceTimer?.cancel();
    _interfaceTimer = Timer.periodic(interfacePollInterval, (_) {
      unawaited(refreshInterfaces());
    });
  }

  void _setPhase(DesktopNearbyPhase phase) {
    _phase = phase;
    if (!_disposed) notifyListeners();
  }

  static LanInterfaceAddress? _matchingEligibleInterface(
    LanInterfaceAddress selected,
    List<LanInterfaceAddress> current,
  ) {
    for (final candidate in current) {
      if (candidate.interfaceId == selected.interfaceId &&
          candidate.interfaceIndex == selected.interfaceIndex &&
          candidate.address == selected.address &&
          candidate.prefixLength == selected.prefixLength &&
          candidate.profile == LanNetworkProfile.private &&
          candidate.automaticEligibility == LanAutomaticEligibility.eligible) {
        return candidate;
      }
    }
    return null;
  }

  static Future<String> _canonicalPath(Directory directory) async {
    var path = p.normalize(directory.absolute.path);
    try {
      path = p.normalize(await directory.resolveSymbolicLinks());
    } on FileSystemException {
      // resolveAppSupportDir creates the directory. An injected resolver may
      // deliberately avoid I/O; its absolute normalized path remains isolated.
    }
    if (Platform.isWindows) path = path.toLowerCase();
    return path;
  }

  static String _storageError(Object error) =>
      error is NearbyStorageException ? error.code : 'storage_unavailable';

  static String _enableError(Object error) {
    if (error is NearbyException &&
        const {
          'permission_denied',
          'lan_unavailable',
          'storage_unavailable',
        }.contains(error.code)) {
      return error.code;
    }
    return 'lan_unavailable';
  }
}

final class _ApprovalRequest {
  _ApprovalRequest(this.clientName);
  final String clientName;
  final result = Completer<bool>();
  Timer? timer;
}

final class _ProtectedPersistence implements DesktopNearbyPersistence {
  const _ProtectedPersistence(this.store);
  final ProtectedNearbyStore store;

  @override
  NearbySecretStore get secretStore => store;

  @override
  Future<PersistedDesktopIdentity> loadOrCreateIdentity() => store
      .loadOrCreateDesktopIdentity(createTlsIdentity: TlsIdentity.generate);

  @override
  Future<List<PairedDeviceMetadata>> listPairedDevices() =>
      store.listPairedDevices();
}

final class _ServerHandle implements DesktopNearbyServerHandle {
  const _ServerHandle(this.server);
  final NearbyServer server;
  @override
  int get port => server.port;
  @override
  Future<void> close() => server.close();
}

Future<DesktopNearbyServerHandle> _bindServer({
  required LanSubnet subnet,
  required TlsIdentity identity,
  required NearbyAuthority authority,
  required NearbyCommandHandler handler,
  required Future<bool> Function(PendingApproval approval) approvePairing,
}) async => _ServerHandle(
  await NearbyServer.bind(
    subnet: subnet,
    identity: identity,
    authority: authority,
    handler: handler,
    approvePairing: approvePairing,
  ),
);

final class _Advertisement implements DesktopNearbyAdvertisement {
  const _Advertisement(this.registration);
  final NearbyAdvertisementRegistration registration;
  @override
  Future<void> start() => registration.start();
  @override
  Future<void> dispose() => registration.dispose();
}

DesktopNearbyAdvertisement _createAdvertisement({
  required String desktopId,
  required String displayName,
  required int port,
  required bool pairingOpen,
}) => _Advertisement(
  NearbyAdvertisementRegistration(
    desktopId: desktopId,
    displayName: displayName,
    port: port,
    pairingOpen: pairingOpen,
  ),
);
