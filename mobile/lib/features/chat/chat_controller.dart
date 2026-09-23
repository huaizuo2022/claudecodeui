import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/assets_api.dart';
import '../../core/api/models_api.dart';
import '../../core/models/chat_message.dart';
import '../../core/models/provider_capability.dart';
import '../../core/models/provider_model.dart';
import '../../core/providers.dart';
import '../../core/storage/prefs_store.dart';
import '../../core/util/logger.dart';
import '../../core/ws/server_event.dart';
import '../sessions/session_list_controller.dart';
import 'chat_reducer.dart';

const _historyPageSize = 20;

/// Per-session chat state: history pages + the live run. The socket is shared;
/// this controller only listens while the provider is alive.
class ChatController extends Notifier<ChatState> {
  ChatController(this.sessionId);

  final String sessionId;
  static const _log = Logger('chat');

  bool _subscribedToSocket = false;
  Timer? _streamFlushTimer;
  Timer? _liveSyncTimer;
  String _pendingStreamText = '';
  int _historyOffset = 0;
  bool _loadingModels = false;

  @override
  ChatState build() {
    final socket = ref.read(chatSocketProvider);
    socket.addListener(_onFrame);
    _subscribedToSocket = true;
    ref.onDispose(() {
      if (_subscribedToSocket) socket.removeListener(_onFrame);
      _streamFlushTimer?.cancel();
      _liveSyncTimer?.cancel();
      // The chat screen for this session is gone: release it as the one being
      // viewed so future background frames can light its attention dot again.
      // (Plain value on purpose — provider writes are forbidden here.)
      if (activeViewedSessionId == sessionId) {
        activeViewedSessionId = null;
      }
    });

    Future.microtask(() async {
      _subscribe();
      await _loadInitialHistory();
    });

    return const ChatState();
  }

  // ── Socket plumbing ──────────────────────────────────────────────────────

  void _onFrame(Map<dynamic, dynamic> frame) {
    final kind = frame['kind'] as String?;
    if (kind == 'socket_connected') {
      // Reconnect: replay what was missed since our highest seq.
      if (state.historyLoaded) _subscribe();
      return;
    }
    if (frame['sessionId'] != null) {
      final frameSid = frame['sessionId'].toString().trim().toLowerCase();
      if (frameSid != sessionId.trim().toLowerCase()) return;
    }

    // `session_upserted` for THIS session while idle means the transcript
    // changed elsewhere (another tab, the CLI, a scheduled message): reload
    // the newest page quietly, exactly like the web's externalMessageUpdate.
    if (frame['kind'] == 'session_upserted') {
      if (frame['isProcessing'] != true && !state.isProcessing) {
        _refreshLatest(banner: false);
      }
      return;
    }

    _handleEvent(ServerEvent.fromJson(frame));
  }

  void _subscribe() {
    if (!ref.mounted) return;
    final socket = ref.read(chatSocketProvider);
    final url = ref.read(apiClientProvider).webSocketUrl;
    if (url != null && !socket.isConnected) {
      socket.connect(url);
    }
    socket.send({
      'type': 'chat.subscribe',
      'sessions': [
        {'sessionId': sessionId, 'lastSeq': state.lastSeq},
      ],
    });
    _log.info('subscribed to $sessionId (lastSeq=${state.lastSeq})');
  }

  void _handleEvent(ServerEvent event) {
    // stream_delta arrives per token; buffer and flush at a sane rate so the
    // widget tree is not rebuilt hundreds of times per second.
    if (event.kind == ServerEventKind.streamDelta) {
      _pendingStreamText += event.content ?? '';
      final delta = _pendingStreamText;
      _streamFlushTimer?.cancel();
      _streamFlushTimer = Timer(const Duration(milliseconds: 80), () {
        _flushStream(delta);
      });
      state = state.copyWith(
        isProcessing: true,
        runStartedAt: state.isProcessing ? null : DateTime.now(),
      );
      if (_liveSyncTimer == null) {
        _startLiveSyncTimer();
      }
      return;
    }

    _flushStreamNow();
    state = reduceChatEvent(state, event);

    if (state.isProcessing && _liveSyncTimer == null) {
      _startLiveSyncTimer();
    } else if (!state.isProcessing && _liveSyncTimer != null) {
      _stopLiveSyncTimer();
    }

    if (event.kind == ServerEventKind.historyTruncated ||
        event.kind == ServerEventKind.complete ||
        event.kind == ServerEventKind.protocolError) {
      _stopLiveSyncTimer();
      _refreshAfterRun();
    }
  }

  void _flushStream(String text) {
    _pendingStreamText = '';
    if (!state.isStreaming && text.isEmpty) return;
    state = state.copyWith(
      streamingText: text,
      isStreaming: true,
      isProcessing: true,
      unreadCount: state.following ? 0 : state.unreadCount + 1,
    );
  }

  void _flushStreamNow() {
    if (_pendingStreamText.isEmpty) return;
    final text = _pendingStreamText;
    _streamFlushTimer?.cancel();
    _flushStream(text);
  }

  /// Pulls the newest history page and merges it (server rows win by id).
  /// Mirrors the web's requestLatestMessages: also used for `session_upserted`
  /// (content changed elsewhere) and after a run settles.
  Future<void> _refreshLatest({required bool banner}) async {
    try {
      final page = await ref.read(messagesApiProvider).fetchHistory(
            sessionId,
            limit: _historyPageSize,
            offset: 0,
          );
      if (!ref.mounted) return;
      _historyOffset = page.messages.length;
      final merged = _mergeServerMessages(state.messages, page.messages, dropSynthetic: true);
      state = state.copyWith(
        messages: merged,
        totalMessages: page.total,
        hasMoreHistory: page.hasMore,
      );
      unawaited(ref.read(cacheDatabaseProvider).saveMessages(sessionId, merged));
    } catch (error) {
      _log.warn('refresh failed: $error');
      if (banner && ref.mounted) {
        state = state.copyWith(clearHistoryError: true);
      }
    }
    await _refreshTokenUsage();
  }

  Future<void> _refreshAfterRun() => _refreshLatest(banner: false);

  void _startLiveSyncTimer() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) async {
      if (!ref.mounted || !state.isProcessing) {
        _stopLiveSyncTimer();
        return;
      }
      await _refreshLatest(banner: false);
    });
  }

  void _stopLiveSyncTimer() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = null;
  }

  // ── History ──────────────────────────────────────────────────────────────

  Future<void> _loadInitialHistory() async {
    final cacheDb = ref.read(cacheDatabaseProvider);
    final cached = await cacheDb.getMessages(sessionId);
    if (!ref.mounted) return;

    if (cached.isNotEmpty) {
      _historyOffset = cached.length;
      state = state.copyWith(
        messages: cached,
        totalMessages: cached.length,
        hasMoreHistory: false,
        loadingHistory: false,
        historyLoaded: true,
        clearHistoryError: true,
      );
    } else {
      state = state.copyWith(loadingHistory: true, clearHistoryError: true);
    }

    try {
      final page = await ref.read(messagesApiProvider).fetchHistory(
            sessionId,
            limit: _historyPageSize,
            offset: 0,
          );
      if (!ref.mounted) return;
      _historyOffset = page.messages.length;
      state = state.copyWith(
        messages: page.messages,
        totalMessages: page.total,
        hasMoreHistory: page.hasMore,
        loadingHistory: false,
        historyLoaded: true,
        clearHistoryError: true,
      );
      unawaited(cacheDb.saveMessages(sessionId, page.messages));
    } catch (error) {
      if (!ref.mounted) return;
      if (cached.isNotEmpty) {
        _log.warn('fetchHistory failed, using cached messages: $error');
        state = state.copyWith(
          loadingHistory: false,
          historyLoaded: true,
          clearHistoryError: true,
        );
      } else {
        state = state.copyWith(
          loadingHistory: false,
          historyLoaded: true,
          historyError: '$error',
        );
      }
    }
  }

  Future<void> loadOlder() async {
    if (state.loadingHistory || !state.hasMoreHistory) return;
    state = state.copyWith(loadingHistory: true, clearHistoryError: true);
    try {
      final page = await ref.read(messagesApiProvider).fetchHistory(
            sessionId,
            limit: _historyPageSize,
            offset: _historyOffset,
          );
      if (!ref.mounted) return;
      final existingIds = state.messages.map((message) => message.id).toSet();
      final older = page.messages
          .where((message) => !existingIds.contains(message.id))
          .toList(growable: false);
      _historyOffset += page.messages.length;
      final allMessages = [...older, ...state.messages];
      state = state.copyWith(
        messages: allMessages,
        hasMoreHistory: page.hasMore,
        loadingHistory: false,
      );
      unawaited(ref.read(cacheDatabaseProvider).saveMessages(sessionId, allMessages));
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(loadingHistory: false, historyError: '$error');
    }
  }

  /// Merges live rows with a server page by id (server wins on conflict).
  List<ChatMessage> _mergeServerMessages(
    List<ChatMessage> current,
    List<ChatMessage> serverPage, {
    bool dropSynthetic = false,
  }) {
    final byId = {for (final message in serverPage) message.id: message};
    final kept = current
        .where((message) => !_isSynthetic(message) && !byId.containsKey(message.id))
        .toList();
    final liveTail = dropSynthetic
        ? <ChatMessage>[]
        : current.where(_isSynthetic).toList();
    return [...kept, ...serverPage, ...liveTail]
      ..sort((a, b) => _compareTimestamps(a.timestamp, b.timestamp));
  }

  /// Rows this client synthesized (optimistic sends, streamed text) never
  /// survive a server-page merge: the persisted row replaces them.
  bool _isSynthetic(ChatMessage message) =>
      message.id.startsWith('local_') ||
      message.id.startsWith('stream_') ||
      message.id.startsWith('protocol_error_');

  int _compareTimestamps(String a, String b) {
    final ta = DateTime.tryParse(a)?.millisecondsSinceEpoch ?? 0;
    final tb = DateTime.tryParse(b)?.millisecondsSinceEpoch ?? 0;
    return ta.compareTo(tb);
  }

  // ── User actions ─────────────────────────────────────────────────────────

  /// Opens the image picker, previews the picks immediately, and uploads them
  /// in the background so the descriptor is ready when the user hits send.
  Future<void> addImages() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(imageQuality: 85);
    if (images.isEmpty) return;

    final stamp = DateTime.now().microsecondsSinceEpoch;
    final locals = [
      for (var i = 0; i < images.length; i++)
        PendingAttachment(
          localId: 'attach_${stamp}_$i',
          localPath: images[i].path,
          name: images[i].name,
          mimeType: guessMimeType(images[i].name),
        ),
    ];
    state = state.copyWith(pendingAttachments: [...state.pendingAttachments, ...locals]);

    try {
      final uploaded = await ref.read(assetsApiProvider).uploadImages(images);
      final byId = {
        for (var i = 0; i < locals.length && i < uploaded.length; i++)
          locals[i].localId: uploaded[i],
      };
      state = state.copyWith(
        pendingAttachments: [
          for (final pending in state.pendingAttachments)
            if (byId[pending.localId] case final asset?)
              PendingAttachment(
                localId: pending.localId,
                localPath: pending.localPath,
                name: pending.name,
                mimeType: pending.mimeType,
                uploadedDescriptor: asset.toAttachmentDescriptor(),
              )
            else
              pending,
        ],
      );
    } catch (error) {
      state = state.copyWith(
        pendingAttachments: [
          for (final pending in state.pendingAttachments)
            if (locals.any((local) => local.localId == pending.localId) && pending.isUploading)
              PendingAttachment(
                localId: pending.localId,
                localPath: pending.localPath,
                name: pending.name,
                mimeType: pending.mimeType,
                error: '上传失败：$error',
              )
            else
              pending,
        ],
      );
    }
  }

  void removeAttachment(String localId) {
    state = state.copyWith(
      pendingAttachments: state.pendingAttachments
          .where((pending) => pending.localId != localId)
          .toList(growable: false),
    );
  }

  Future<bool> send(String content) async {
    final text = content.trim();
    final attachments = [
      for (final pending in state.pendingAttachments)
        if (pending.uploadedDescriptor != null) pending.uploadedDescriptor!,
    ];
    final blocked = state.pendingAttachments.any(
      (pending) => pending.isUploading || pending.hasFailed,
    );
    if ((text.isEmpty && attachments.isEmpty) || state.isProcessing || blocked) {
      return false;
    }

    final optimisticId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    final previous = state;
    state = previous.copyWith(
      messages: [
        ...previous.messages,
        ChatMessage(
          id: optimisticId,
          kind: 'text',
          timestamp: DateTime.now().toIso8601String(),
          role: 'user',
          content: text,
        ),
      ],
      pendingAttachments: const [],
      following: true,
      unreadCount: 0,
      isProcessing: true,
      runStartedAt: DateTime.now(),
      statusText: '正在连接...',
    );

    _startLiveSyncTimer();

    final socket = ref.read(chatSocketProvider);
    final url = ref.read(apiClientProvider).webSocketUrl;
    if (url != null && (!socket.isConnected || socket.url == null)) {
      socket.connect(url);
    }

    final sent = await socket.sendWhenConnected({
      'type': 'chat.send',
      'sessionId': sessionId,
      'content': text,
      'options': <String, dynamic>{
        if (state.currentModel != null && state.currentModel!.isNotEmpty)
          'model': state.currentModel,
        if (state.currentEffort != null &&
            state.currentEffort!.isNotEmpty &&
            state.currentEffort != 'default')
          'effort': state.currentEffort,
        'permissionMode': state.permissionMode,
        if (attachments.isNotEmpty) 'attachments': attachments,
      },
    });
    if (!sent && ref.mounted) {
      _stopLiveSyncTimer();
      _log.warn('chat.send could not reach the server; rolling back');
      state = previous.copyWith(
        isProcessing: false,
        clearRunStartedAt: true,
        clearStatusText: true,
      );
    }
    return sent;
  }

  void abort() {
    _stopLiveSyncTimer();
    ref.read(chatSocketProvider).send({
      'type': 'chat.abort',
      'sessionId': sessionId,
    });
  }

  void answerPermission(String requestId, {required bool allow, bool remember = false}) {
    final match = state.pendingPermissions
        .where((pending) => pending.requestId == requestId)
        .toList(growable: false);
    if (match.isEmpty) return;
    final permission = match.first;
    state = state.copyWith(
      pendingPermissions: state.pendingPermissions
          .where((pending) => pending.requestId != requestId)
          .toList(growable: false),
    );
    ref.read(chatSocketProvider).send({
      'type': 'chat.permission-response',
      'requestId': requestId,
      'allow': allow,
      if (remember) 'rememberEntry': buildPermissionRememberEntry(permission.toolName, permission.input),
      if (!allow) 'message': 'User denied tool use',
    });
  }

  // ── Scroll follow state (driven by the message list) ─────────────────────

  /// Retry button / manual refresh. An already-hydrated session refreshes
  /// through the bounded tail path instead of clearing the transcript.
  Future<void> reload() async {
    if (state.historyLoaded && state.messages.isNotEmpty) {
      await _refreshLatest(banner: true);
    } else {
      await _loadInitialHistory();
    }
    if (!ref.mounted) return;
    _subscribe();
  }

  /// App returned to the foreground: iOS may have suspended the socket, and
  /// the transcript may have changed meanwhile. Reconnect + pull the newest
  /// page, mirroring the web's visibility/focus refresh.
  void handleAppResume() {
    if (!state.historyLoaded) return;
    _subscribe();
    _refreshLatest(banner: false);
  }

  void setFollowing(bool following) {
    if (state.following == following) return;
    state = state.copyWith(
      following: following,
      unreadCount: following ? 0 : state.unreadCount,
    );
  }

  void jumpToLatest() => setFollowing(true);

  // ── Provider, Model & Token Usage ────────────────────────────────────────

  PrefsStore? get _prefsStore {
    try {
      return ref.read(prefsStoreProvider);
    } catch (_) {
      return null;
    }
  }

  void initSession({String? provider, String? initialModel, String? initialEffort}) {
    var nextProvider = state.provider;
    if (provider != null && provider.trim().isNotEmpty) {
      nextProvider = provider.trim().toLowerCase();
    }
    final nextModel = (initialModel != null && initialModel.trim().isNotEmpty)
        ? initialModel.trim()
        : state.currentModel;
    final nextEffort = (initialEffort != null && initialEffort.trim().isNotEmpty)
        ? initialEffort.trim()
        : state.currentEffort;

    final prefs = _prefsStore;
    final sessionSaved = prefs?.getSessionPermissionMode(sessionId);
    final providerSaved = prefs?.getProviderPermissionMode(nextProvider);
    final initialPermissionMode = sessionSaved ?? providerSaved ?? state.permissionMode;

    final changed = nextProvider != state.provider ||
        nextModel != state.currentModel ||
        nextEffort != state.currentEffort ||
        initialPermissionMode != state.permissionMode;
    if (changed) {
      state = state.copyWith(
        provider: nextProvider,
        currentModel: nextModel,
        currentModelLabel: nextModel != null ? (state.currentModelLabel ?? nextModel) : null,
        currentEffort: nextEffort,
        permissionMode: initialPermissionMode,
      );
    }
    _loadModelsAndUsage();
  }

  Future<void> _refreshTokenUsage() async {
    try {
      final tokenText = await ref.read(modelsApiProvider).fetchSessionTokenUsage(sessionId);
      if (!ref.mounted) return;
      if (tokenText != null) {
        state = state.copyWith(tokenUsageText: tokenText);
      }
    } catch (_) {}
  }

  Future<void> _loadModelsAndUsage({bool force = false}) async {
    if (_loadingModels && !force) return;
    _loadingModels = true;
    final provider = state.provider;

    try {
      final modelsApi = ref.read(modelsApiProvider);
      final tokenFuture = modelsApi.fetchSessionTokenUsage(sessionId).catchError((_) => null);
      final activeModelFuture = modelsApi
          .fetchSessionActiveModel(provider, sessionId)
          .catchError((_) => SessionActiveModel(provider: provider, sessionId: sessionId, model: ''));
      final hasProvider = provider.isNotEmpty;
      final catalogFuture = hasProvider
          ? modelsApi
              .fetchProviderModels(provider)
              .catchError((_) => ProviderModelsCatalog(provider: provider, defaultModel: '', options: const []))
          : Future.value(const ProviderModelsCatalog(provider: '', defaultModel: '', options: []));
      final capsFuture = hasProvider
          ? modelsApi
              .fetchProviderCapabilities(provider)
              .catchError((_) => ProviderCapabilities(
                    provider: provider,
                    permissionModes: fallbackPermissionModes[provider] ?? const ['default'],
                    defaultPermissionMode: 'default',
                  ))
          : Future.value(const ProviderCapabilities(
                provider: '',
                permissionModes: ['default'],
                defaultPermissionMode: 'default',
              ));

      final results = await Future.wait([tokenFuture, activeModelFuture, catalogFuture, capsFuture]);
      if (!ref.mounted) return;

      final tokenText = results[0] as String?;
      final active = results[1] as SessionActiveModel;
      final catalog = results[2] as ProviderModelsCatalog;
      final caps = results[3] as ProviderCapabilities;

      final available = catalog.options;
      var chosen = active.model.isNotEmpty
          ? active.model
          : (catalog.defaultModel.isNotEmpty ? catalog.defaultModel : state.currentModel);

      String? label;
      if (chosen != null && chosen.isNotEmpty) {
        final match = available.where((option) => option.value == chosen);
        label = match.isNotEmpty ? match.first.label : chosen;
      }

      // Reasoning effort: prefer the per-session stored value, fall back to
      // the selected model's default (mirrors the web's DEFAULT_EFFORT_VALUE).
      final modelMatch = chosen == null
          ? null
          : available.where((option) => option.value == chosen).firstOrNull;
      final effortChoices = modelMatch?.effortValues ?? const <String>[];
      var effort = active.effort?.isNotEmpty == true
          ? active.effort
          : (modelMatch?.defaultEffort?.isNotEmpty == true ? modelMatch!.defaultEffort : null);
      if (effort == null || effort.isEmpty) effort = 'default';
      if (effortChoices.isNotEmpty && !effortChoices.contains(effort)) {
        effort = modelMatch?.defaultEffort ?? 'default';
      }

      final validModes = caps.permissionModes;
      final isCurrentValid = validModes.contains(state.permissionMode);
      final resolvedMode = isCurrentValid ? state.permissionMode : caps.defaultPermissionMode;

      state = state.copyWith(
        tokenUsageText: tokenText ?? state.tokenUsageText,
        availableModels: available,
        currentModel: chosen,
        currentModelLabel: label,
        currentEffort: effort,
        availableEfforts: effortChoices,
        availablePermissionModes: validModes,
        permissionMode: resolvedMode,
        loadingModels: false,
      );
    } catch (error) {
      _log.warn('failed to load models: $error');
      if (ref.mounted) {
        state = state.copyWith(loadingModels: false);
      }
    } finally {
      _loadingModels = false;
    }
  }

  Future<void> selectModel(String model) async {
    final prevModel = state.currentModel;
    final prevLabel = state.currentModelLabel;
    final prevEffort = state.currentEffort;

    final match = state.availableModels.where((option) => option.value == model);
    final label = match.isNotEmpty ? match.first.label : model;
    final effortChoices = match.isNotEmpty ? match.first.effortValues : const <String>[];
    final nextEffort = effortChoices.isEmpty || (state.currentEffort ?? 'default') == 'default'
        ? 'default'
        : (effortChoices.contains(state.currentEffort) ? state.currentEffort : 'default');

    state = state.copyWith(
      currentModel: model,
      currentModelLabel: label,
      availableEfforts: effortChoices,
      currentEffort: nextEffort,
    );

    try {
      await ref.read(modelsApiProvider).setSessionActiveModel(
            state.provider,
            sessionId,
            model,
          );
    } catch (error) {
      _log.warn('failed to set active model: $error');
      state = state.copyWith(
        currentModel: prevModel,
        currentModelLabel: prevLabel,
        currentEffort: prevEffort,
      );
      rethrow;
    }
  }

  /// Picks a reasoning effort for the next turn and persists it per session
  /// (the same tolerant endpoint the web composer uses).
  Future<void> selectEffort(String effort) async {
    final prevEffort = state.currentEffort;
    state = state.copyWith(currentEffort: effort);
    try {
      await ref.read(modelsApiProvider).setSessionActiveEffort(
            state.provider,
            sessionId,
            effort,
          );
    } catch (error) {
      _log.warn('failed to set active effort: $error');
      state = state.copyWith(currentEffort: prevEffort);
      rethrow;
    }
  }

  Future<void> selectPermissionMode(String mode) async {
    state = state.copyWith(permissionMode: mode);
    final prefs = _prefsStore;
    if (prefs != null) {
      await prefs.setSessionPermissionMode(sessionId, mode);
      await prefs.setProviderPermissionMode(state.provider, mode);
    }
  }
}

final chatControllerProvider =
    NotifierProvider.autoDispose.family<ChatController, ChatState, String>(ChatController.new);
