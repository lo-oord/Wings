import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/errors/user_facing_error.dart';
import '../../core/services/community_media_service.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/chat.dart';
import '../../data/models/user_profile.dart';
import '../community/community_providers.dart';
import '../community/community_video.dart';
import '../community/report_sheet.dart';
import '../profile/avatar_view.dart';
import 'chat_providers.dart';

/// One open conversation. This is the only screen in the app with a message
/// listener; leaving it cancels the listener, stops presence and disposes any
/// audio player it created.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.chatId});

  final String chatId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();

  ChatMessage? _replyTo;
  ChatMessage? _editing;
  bool _searching = false;
  String _query = '';
  bool _uploading = false;
  String _uploadStage = '';
  bool? _canMessage;
  ChatPrivacy _myPrivacy = ChatPrivacy.defaults;
  ChatPrivacy _peerPrivacy = ChatPrivacy.defaults;
  Timer? _presenceTimer;
  Timer? _typingTimer;
  String? _lastReadId;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _text.addListener(_onText);
    unawaited(_boot());
    _presenceTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => unawaited(_presence(true)),
    );
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    _typingTimer?.cancel();
    _scroll.dispose();
    _text.dispose();
    _focus.dispose();
    final uid = ref.read(authProvider)?.id;
    if (uid != null) {
      unawaited(
        ref.read(chatRepositoryProvider).setPresence(uid, online: false),
      );
      unawaited(
        ref.read(chatRepositoryProvider).clearTyping(widget.chatId, uid),
      );
    }
    super.dispose();
  }

  Future<void> _boot() async {
    final uid = ref.read(authProvider)?.id;
    if (uid == null) return;
    final repo = ref.read(chatRepositoryProvider);
    try {
      _myPrivacy = await repo.fetchPrivacy(uid);
      final chat = await repo.fetchChat(widget.chatId);
      final peer = chat?.peerOf(uid) ?? '';
      if (peer.isNotEmpty) {
        _peerPrivacy = await repo.fetchPrivacy(peer);
        final following =
            ref.read(followingIdsProvider(uid)).value ?? const <String>{};
        final allowed = await repo.canMessage(
          uid: uid,
          peerUid: peer,
          following: following.contains(peer),
        );
        if (mounted) setState(() => _canMessage = allowed);
      }
      await _presence(true);
    } on Object {
      if (mounted) setState(() => _canMessage = true);
    }
  }

  Future<void> _presence(bool online) async {
    final uid = ref.read(authProvider)?.id;
    if (uid == null) return;
    await ref
        .read(chatRepositoryProvider)
        .setPresence(
          uid,
          online: online,
          writeLastSeen: _myPrivacy.showLastSeen,
        );
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240) {
      unawaited(
        ref.read(chatMessagesProvider(widget.chatId).notifier).loadMore(),
      );
    }
  }

  void _onText() {
    final uid = ref.read(authProvider)?.id;
    if (uid == null) return;
    final text = _text.text.trim();
    if (text.isEmpty) {
      _typingTimer?.cancel();
      unawaited(
        ref.read(chatRepositoryProvider).clearTyping(widget.chatId, uid),
      );
      return;
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      unawaited(ref.read(chatRepositoryProvider).setTyping(widget.chatId, uid));
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final uid = ref.watch(authProvider)?.id;
    final chatAsync = ref.watch(chatProvider(widget.chatId));
    final chat = chatAsync.value;
    final messages = ref.watch(chatMessagesProvider(widget.chatId));
    final peer = chat?.peer;
    final peerUid = chat?.peerOf(uid ?? '') ?? '';
    final presence = peerUid.isEmpty
        ? null
        : ref.watch(presenceProvider(peerUid)).value;
    final profile = ref.watch(profileProvider);

    if (uid == null) {
      return Scaffold(
        appBar: WingsAppBar(
          showBack: true,
          title: Text(Tr.of(context, ar: 'المحادثة', en: 'Chat')),
        ),
        body: Center(
          child: Text(
            Tr.of(context, ar: 'سجّل الدخول.', en: 'Please sign in.'),
          ),
        ),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markReadIfNeeded(messages.messages, chat);
    });

    final visible = _query.isEmpty
        ? messages.messages
        : messages.messages
              .where(
                (message) =>
                    message.text.toLowerCase().contains(_query.toLowerCase()),
              )
              .toList(growable: false);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: _searching
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(() {
                  _searching = false;
                  _query = '';
                }),
              ),
              title: TextField(
                autofocus: true,
                onChanged: (value) => setState(() => _query = value.trim()),
                decoration: InputDecoration(
                  hintText: Tr.of(
                    context,
                    ar: 'ابحث داخل المحادثة',
                    en: 'Search this chat',
                  ),
                  border: InputBorder.none,
                ),
              ),
            )
          : AppBar(
              leading: IconButton(
                icon: Icon(
                  context.isRtl
                      ? Icons.arrow_forward_rounded
                      : Icons.arrow_back_rounded,
                ),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              titleSpacing: 0,
              title: InkWell(
                onTap: peerUid.isEmpty
                    ? null
                    : () => context.push(RoutePaths.publicProfile(peerUid)),
                child: Row(
                  children: <Widget>[
                    UserAvatar(
                      uid: peerUid,
                      photoVersion: peer?.photoVersion ?? 0,
                      name: peer?.displayName ?? '',
                      size: 34,
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            (peer?.displayName.trim().isNotEmpty ?? false)
                                ? peer!.displayName
                                : (peer?.username.isNotEmpty ?? false)
                                ? '@${peer!.username}'
                                : Tr.of(context, ar: 'محادثة', en: 'Chat'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            _presenceLine(chat, presence),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelSmall?.copyWith(
                              color:
                                  chat?.peerTyping(uid, DateTime.now()) ?? false
                                  ? palette.primary
                                  : palette.textMuted,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                IconButton(
                  tooltip: Tr.of(context, ar: 'بحث', en: 'Search'),
                  icon: const Icon(Icons.search_rounded, size: 20),
                  onPressed: () => setState(() => _searching = true),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) => _menu(value, chat, uid),
                  itemBuilder: (context) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'media',
                      child: Text(
                        Tr.of(
                          context,
                          ar: 'الوسائط المشتركة',
                          en: 'Shared media',
                        ),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'mute',
                      child: Text(
                        chat?.mutedFor(uid) == true
                            ? Tr.of(context, ar: 'إلغاء الكتم', en: 'Unmute')
                            : Tr.of(context, ar: 'كتم', en: 'Mute'),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'privacy',
                      child: Text(
                        Tr.of(context, ar: 'الخصوصية', en: 'Privacy'),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'report',
                      child: Text(Tr.of(context, ar: 'إبلاغ', en: 'Report')),
                    ),
                    PopupMenuItem<String>(
                      value: 'block',
                      child: Text(Tr.of(context, ar: 'حظر', en: 'Block')),
                    ),
                  ],
                ),
              ],
            ),
      body: Column(
        children: <Widget>[
          if (_canMessage == false)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Space.sm),
              color: palette.surfaceAlt,
              child: Text(
                Tr.of(
                  context,
                  ar: 'لا يمكنك إرسال رسائل في هذه المحادثة بسبب إعدادات الخصوصية أو الحظر.',
                  en: 'You cannot send messages here because of privacy settings or a block.',
                ),
                textAlign: TextAlign.center,
                style: context.text.labelSmall?.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ),
          Expanded(
            child: messages.loading && messages.messages.isEmpty
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : visible.isEmpty
                ? Center(
                    child: Text(
                      _query.isNotEmpty
                          ? Tr.of(context, ar: 'لا نتائج.', en: 'No matches.')
                          : Tr.of(
                              context,
                              ar: 'ابدأ المحادثة برسالة.',
                              en: 'Start the conversation.',
                            ),
                      style: context.text.labelSmall?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.sm,
                      vertical: Space.sm,
                    ),
                    itemCount: visible.length + (messages.loadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= visible.length) {
                        return const Padding(
                          padding: EdgeInsets.all(Space.md),
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      final message = visible[visible.length - 1 - index];
                      final mine = message.senderUid == uid;
                      return _MessageBubble(
                        message: message,
                        chat: chat,
                        uid: uid,
                        mine: mine,
                        peerName: peer?.displayName ?? '',
                        onReply: () => setState(() {
                          _editing = null;
                          _replyTo = message;
                          _focus.requestFocus();
                        }),
                        onEdit: () => setState(() {
                          _replyTo = null;
                          _editing = message;
                          _text.text = message.text;
                          _focus.requestFocus();
                        }),
                        onDelete: () => _delete(message),
                        onCopy: () => _copy(message),
                        onReact: (reaction) => _react(message, reaction),
                        onRetry: chat == null || profile == null
                            ? null
                            : () => ref
                                  .read(
                                    chatMessagesProvider(widget.chatId)
                                        .notifier,
                                  )
                                  .retry(
                                    chat: chat,
                                    author: profile,
                                    message: message,
                                    peerMuted:
                                        chat.mutedFor(chat.peerOf(uid)) == true,
                                  ),
                        onForward: () => _forward(message, chat, profile),
                      );
                    },
                  ),
          ),
          if (messages.error != null && messages.messages.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4),
              color: palette.surfaceAlt,
              child: Text(
                Tr.of(
                  context,
                  ar: 'تعذّر تحديث الرسائل. المحفوظة معروضة، وستُزامن عند عودة الاتصال.',
                  en: 'Messages could not refresh. Cached ones are shown and will sync when the connection returns.',
                ),
                textAlign: TextAlign.center,
                style: context.text.labelSmall?.copyWith(
                  color: palette.textMuted,
                  fontSize: 9,
                ),
              ),
            ),
          _Composer(
            enabled: _canMessage != false && chat != null && !_uploading,
            text: _text,
            focus: _focus,
            replyTo: _replyTo,
            editing: _editing,
            uploading: _uploading,
            stage: _uploadStage,
            onCancelReply: () => setState(() {
              _replyTo = null;
              _editing = null;
            }),
            onSend: () => _send(chat, profile),
            onAttach: () => _attach(chat, profile, uid),
          ),
        ],
      ),
    );
  }

  String _presenceLine(Chat? chat, ChatPresence? presence) {
    if (chat?.peerTyping(ref.read(authProvider)?.id ?? '', DateTime.now()) ??
        false) {
      return Tr.of(context, ar: 'يكتب…', en: 'typing…');
    }
    if (presence == null) return '';
    if (_peerPrivacy.showOnline && presence.online) {
      return Tr.of(context, ar: 'متصل الآن', en: 'online');
    }
    if (_peerPrivacy.showLastSeen && presence.lastSeen != null) {
      return '${Tr.of(context, ar: 'آخر ظهور', en: 'last seen')} '
          '${relativeTime(presence.lastSeen!, context.l10n)}';
    }
    return '';
  }

  Future<void> _markReadIfNeeded(List<ChatMessage> messages, Chat? chat) async {
    final uid = ref.read(authProvider)?.id;
    if (uid == null || chat == null || messages.isEmpty) return;
    final last = messages.last;
    if (last.id == _lastReadId) return;
    _lastReadId = last.id;
    try {
      await ref
          .read(chatRepositoryProvider)
          .markRead(widget.chatId, uid: uid, receipts: _myPrivacy.readReceipts);
    } on Object {
      // Offline; the next opened message retries.
    }
  }

  Future<void> _send(Chat? chat, UserProfile? author) async {
    final uid = ref.read(authProvider)?.id;
    if (chat == null || author == null || uid == null) return;
    final editing = _editing;
    if (editing != null) {
      final text = _text.text.trim();
      if (text.isEmpty) return;
      await ref
          .read(chatMessagesProvider(widget.chatId).notifier)
          .edit(editing, text);
      setState(() {
        _editing = null;
        _text.clear();
      });
      return;
    }
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final reply = _replyTo;
    final message = ChatMessage(
      id: ref.read(chatRepositoryProvider).newMessageId(),
      chatId: widget.chatId,
      senderUid: uid,
      type: ChatMessageType.text,
      text: text,
      replyToId: reply?.id ?? '',
      replyToSender: reply?.senderUid ?? '',
      replyToPreview: reply?.preview ?? '',
      replyToType: reply?.type ?? ChatMessageType.text,
      createdAt: DateTime.now(),
      status: ChatMessageStatus.sending,
    );
    _text.clear();
    setState(() => _replyTo = null);
    await ref
        .read(chatMessagesProvider(widget.chatId).notifier)
        .send(
          chat: chat,
          author: author,
          draft: message,
          peerMuted: chat.mutedFor(chat.peerOf(uid)) == true,
        );
    await _scrollToLatest();
  }

  Future<void> _scrollToLatest() async {
    if (!_scroll.hasClients) return;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (_scroll.hasClients) {
      unawaited(
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  Future<void> _attach(Chat? chat, UserProfile? author, String uid) async {
    if (chat == null || author == null) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(Tr.of(context, ar: 'صورة', en: 'Photo')),
              onTap: () => Navigator.of(context).pop('image'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: Text(Tr.of(context, ar: 'فيديو', en: 'Video')),
              onTap: () => Navigator.of(context).pop('video'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file_rounded),
              title: Text(Tr.of(context, ar: 'ملف', en: 'File')),
              onTap: () => Navigator.of(context).pop('file'),
            ),
            ListTile(
              leading: const Icon(Icons.mic_none_rounded),
              title: Text(
                Tr.of(context, ar: 'رسالة صوتية', en: 'Voice message'),
              ),
              onTap: () => Navigator.of(context).pop('audio'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'image':
      case 'video':
        await _pickVisual(chat, author, uid, choice == 'video');
      case 'file':
        await _pickFile(chat, author, uid);
      case 'audio':
        await _recordAudio(chat, author, uid);
    }
  }

  Future<void> _pickVisual(
    Chat chat,
    UserProfile author,
    String uid,
    bool video,
  ) async {
    try {
      final picker = ImagePicker();
      final picked = video
          ? await picker.pickVideo(
              source: ImageSource.gallery,
              maxDuration: const Duration(seconds: 60),
            )
          : await picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 82,
              maxWidth: 1800,
            );
      if (picked == null || !mounted) return;
      final file = File(picked.path);
      final bytes = await file.readAsBytes();
      final mime = video ? 'video/mp4' : 'image/jpeg';
      final limit = video
          ? CommunityMediaService.maxVideoBytes
          : CommunityMediaService.maxImageBytes;
      if (bytes.length > limit) {
        if (mounted) {
          context.showSnack(
            Tr.of(
              context,
              ar: video
                  ? 'الفيديو أكبر من ٥٠ ميجابايت.'
                  : 'الصورة أكبر من ٥ ميجابايت.',
              en: video
                  ? 'The video is larger than 50 MB.'
                  : 'The image is larger than 5 MB.',
            ),
            isError: true,
          );
        }
        return;
      }
      await _uploadAndSend(
        chat: chat,
        author: author,
        uid: uid,
        bytes: bytes,
        mime: mime,
        extension: video ? 'mp4' : 'jpg',
        type: video ? ChatMessageType.video : ChatMessageType.image,
        name: picked.name,
        width: video ? 0 : 0,
      );
    } on Object catch (error) {
      if (mounted) {
        context.showSnack(userFacingError(context, error), isError: true);
      }
    }
  }

  Future<void> _pickFile(Chat chat, UserProfile author, String uid) async {
    try {
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const <String>['pdf', 'zip', 'txt'],
      );
      final path = result?.path;
      if (path == null || !mounted) return;
      final file = File(path);
      final size = await file.length();
      if (size > CommunityMediaService.maxFileBytes) {
        if (mounted) {
          context.showSnack(
            Tr.of(
              context,
              ar: 'الملف أكبر من ٢٠ ميجابايت.',
              en: 'The file is larger than 20 MB.',
            ),
            isError: true,
          );
        }
        return;
      }
      final name = result!.name;
      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
      final mime = _mimeFor(ext);
      if (mime == null) {
        if (mounted) {
          context.showSnack(
            Tr.of(
              context,
              ar: 'نوع الملف غير مدعوم. المدعوم: PDF وZIP وTXT.',
              en: 'Unsupported file type. PDF, ZIP and TXT are supported.',
            ),
            isError: true,
          );
        }
        return;
      }
      await _uploadAndSend(
        chat: chat,
        author: author,
        uid: uid,
        bytes: await file.readAsBytes(),
        mime: mime,
        extension: ext,
        type: ChatMessageType.file,
        name: name,
      );
    } on Object catch (error) {
      if (mounted) {
        context.showSnack(userFacingError(context, error), isError: true);
      }
    }
  }

  String? _mimeFor(String extension) => switch (extension) {
    'pdf' => 'application/pdf',
    'zip' => 'application/zip',
    'txt' => 'text/plain',
    _ => null,
  };

  Future<void> _recordAudio(Chat chat, UserProfile author, String uid) async {
    final recorder = AudioRecorder();
    try {
      if (!await recorder.hasPermission()) {
        if (mounted) {
          context.showSnack(
            Tr.of(
              context,
              ar: 'يجب السماح بالميكروفون لتسجيل رسالة صوتية.',
              en: 'Allow microphone access to record a voice message.',
            ),
            isError: true,
          );
        }
        return;
      }
      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      if (!mounted) return;
      final send = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(Tr.of(context, ar: 'تسجيل صوتي', en: 'Voice message')),
          content: Text(
            Tr.of(
              context,
              ar: 'جارٍ التسجيل… اضغط إرسال عند الانتهاء.',
              en: 'Recording… tap Send when you are done.',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(Tr.of(context, ar: 'إلغاء', en: 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(Tr.of(context, ar: 'إرسال', en: 'Send')),
            ),
          ],
        ),
      );
      final recorded = await recorder.stop();
      if (send != true || recorded == null) {
        try {
          await File(recorded ?? path).delete();
        } on Object {
          // Already gone.
        }
        return;
      }
      final file = File(recorded);
      final size = await file.length();
      if (size > CommunityMediaService.maxAudioBytes) {
        if (mounted) {
          context.showSnack(
            Tr.of(
              context,
              ar: 'التسجيل أطول من الحد المسموح (١٢ ميجابايت).',
              en: 'The recording is larger than the allowed 12 MB.',
            ),
            isError: true,
          );
        }
        return;
      }
      await _uploadAndSend(
        chat: chat,
        author: author,
        uid: uid,
        bytes: await file.readAsBytes(),
        mime: 'audio/mp4',
        extension: 'm4a',
        type: ChatMessageType.audio,
        name: 'voice.m4a',
        durationMs: 0,
      );
    } on Object catch (error) {
      if (mounted) {
        context.showSnack(userFacingError(context, error), isError: true);
      }
    } finally {
      unawaited(recorder.dispose());
    }
  }

  Future<void> _uploadAndSend({
    required Chat chat,
    required UserProfile author,
    required String uid,
    required List<int> bytes,
    required String mime,
    required String extension,
    required ChatMessageType type,
    required String name,
    int durationMs = 0,
    int width = 0,
    int height = 0,
  }) async {
    setState(() {
      _uploading = true;
      _uploadStage = Tr.of(context, ar: 'جارٍ رفع المرفق…', en: 'Uploading…');
    });
    try {
      final key = await ref
          .read(communityMediaProvider)
          .uploadChatFile(
            chatId: widget.chatId,
            file: MediaFile(
              bytes: Uint8List.fromList(bytes),
              contentType: mime,
              extension: extension,
            ),
            onProgress: (sent, total) {
              if (!mounted || total <= 0) return;
              setState(
                () => _uploadStage =
                    '${Tr.of(context, ar: 'جارٍ الرفع', en: 'Uploading')} '
                    '${((sent / total) * 100).round()}%',
              );
            },
          );
      final reply = _replyTo;
      final message = ChatMessage(
        id: ref.read(chatRepositoryProvider).newMessageId(),
        chatId: widget.chatId,
        senderUid: uid,
        type: type,
        text: '',
        mediaKey: key,
        mediaMime: mime,
        mediaName: name,
        mediaSize: bytes.length,
        mediaDurationMs: durationMs,
        mediaWidth: width,
        mediaHeight: height,
        replyToId: reply?.id ?? '',
        replyToSender: reply?.senderUid ?? '',
        replyToPreview: reply?.preview ?? '',
        replyToType: reply?.type ?? ChatMessageType.text,
        createdAt: DateTime.now(),
        status: ChatMessageStatus.sending,
      );
      await ref
          .read(chatMessagesProvider(widget.chatId).notifier)
          .send(
            chat: chat,
            author: author,
            draft: message,
            peerMuted: chat.mutedFor(chat.peerOf(uid)) == true,
          );
      if (mounted) setState(() => _replyTo = null);
      await _scrollToLatest();
    } on Object catch (error) {
      if (mounted) {
        context.showSnack(userFacingError(context, error), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _uploadStage = '';
        });
      }
    }
  }

  Future<void> _delete(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(Tr.of(context, ar: 'حذف الرسالة؟', en: 'Delete message?')),
        content: Text(
          Tr.of(
            context,
            ar: 'ستُحذف الرسالة لك وللطرف الآخر.',
            en: 'The message is removed for you and the other side.',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(Tr.of(context, ar: 'حذف', en: 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(chatMessagesProvider(widget.chatId).notifier)
          .delete(message);
    } on Object catch (error) {
      if (mounted) {
        context.showSnack(userFacingError(context, error), isError: true);
      }
    }
  }

  Future<void> _react(ChatMessage message, String reaction) async {
    try {
      await ref
          .read(chatMessagesProvider(widget.chatId).notifier)
          .react(message, reaction);
    } on Object catch (error) {
      if (mounted) {
        context.showSnack(userFacingError(context, error), isError: true);
      }
    }
  }

  Future<void> _copy(ChatMessage message) async {
    if (message.text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: message.text));
    if (mounted) {
      context.showSnack(Tr.of(context, ar: 'تم النسخ.', en: 'Copied.'));
    }
  }

  Future<void> _forward(
    ChatMessage message,
    Chat? chat,
    UserProfile? author,
  ) async {
    if (chat == null || author == null) return;
    final uid = author.uid;
    final chats = ref.read(chatsProvider).value ?? const <Chat>[];
    final targets = chats
        .where((item) => !item.deletedFor(uid) && item.id != chat.id)
        .toList(growable: false);
    if (targets.isEmpty) {
      context.showSnack(
        Tr.of(context, ar: 'لا محادثات أخرى.', en: 'No other chats.'),
      );
      return;
    }
    final selected = await showModalBottomSheet<Chat>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Text(
                Tr.of(context, ar: 'إعادة التوجيه إلى', en: 'Forward to'),
                style: context.text.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final target in targets)
              ListTile(
                leading: UserAvatar(
                  uid: target.peerOf(uid),
                  name: target.peer?.displayName ?? '',
                  size: 34,
                ),
                title: Text(
                  target.peer?.displayName.isNotEmpty == true
                      ? target.peer!.displayName
                      : '@${target.peer?.username ?? ''}',
                ),
                onTap: () => Navigator.of(context).pop(target),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    final forward = ChatMessage(
      id: ref.read(chatRepositoryProvider).newMessageId(),
      chatId: selected.id,
      senderUid: uid,
      type: message.deleted ? ChatMessageType.text : message.type,
      text: message.deleted ? '↪' : message.text,
      mediaKey: message.mediaKey,
      mediaMime: message.mediaMime,
      mediaName: message.mediaName,
      mediaSize: message.mediaSize,
      mediaDurationMs: message.mediaDurationMs,
      mediaWidth: message.mediaWidth,
      mediaHeight: message.mediaHeight,
      share: message.share,
      createdAt: DateTime.now(),
      status: ChatMessageStatus.sending,
    );
    try {
      await ref
          .read(chatRepositoryProvider)
          .send(
            chat: selected,
            author: author,
            message: forward,
            peerMuted: selected.mutedFor(selected.peerOf(uid)) == true,
          );
      if (mounted) {
        context.showSnack(
          Tr.of(context, ar: 'تمت إعادة التوجيه.', en: 'Forwarded.'),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        context.showSnack(userFacingError(context, error), isError: true);
      }
    }
  }

  Future<void> _menu(String value, Chat? chat, String uid) async {
    if (chat == null) return;
    switch (value) {
      case 'media':
        await _showMedia(chat);
      case 'mute':
        await ref
            .read(chatRepositoryProvider)
            .setFlag(chat.id, uid, flag: 'muted', value: !chat.mutedFor(uid));
      case 'privacy':
        await context.push(RoutePaths.chatPrivacy);
      case 'report':
        await showReportSheet(
          context,
          ref,
          targetType: 'user',
          targetId: chat.peerOf(uid),
          targetUid: chat.peerOf(uid),
          preview: chat.lastMessageText,
        );
      case 'block':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(Tr.of(context, ar: 'حظر المستخدم؟', en: 'Block user?')),
            content: Text(
              Tr.of(
                context,
                ar: 'لن تستطيع إرسال أو استقبال رسائل من هذا الحساب.',
                en: 'You will not be able to send or receive messages from this account.',
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(context.l10n.commonCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(Tr.of(context, ar: 'حظر', en: 'Block')),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          await ref
              .read(communityRepositoryProvider)
              .block(uid: uid, target: chat.peerOf(uid));
          if (mounted) setState(() => _canMessage = false);
        }
    }
  }

  Future<void> _showMedia(Chat chat) async {
    final messages = ref
        .read(chatMessagesProvider(widget.chatId))
        .messages
        .where(
          (item) =>
              item.type == ChatMessageType.image ||
              item.type == ChatMessageType.video ||
              item.type == ChatMessageType.file,
        )
        .toList(growable: false);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: messages.isEmpty
              ? Center(
                  child: Text(
                    Tr.of(
                      context,
                      ar: 'لا وسائط مشتركة بعد.',
                      en: 'No shared media yet.',
                    ),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(Space.md),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, index) =>
                      _ChatMedia(message: messages[index], compact: true),
                ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.enabled,
    required this.text,
    required this.focus,
    required this.replyTo,
    required this.editing,
    required this.uploading,
    required this.stage,
    required this.onCancelReply,
    required this.onSend,
    required this.onAttach,
  });

  final bool enabled;
  final TextEditingController text;
  final FocusNode focus;
  final ChatMessage? replyTo;
  final ChatMessage? editing;
  final bool uploading;
  final String stage;
  final VoidCallback onCancelReply;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final quoted = editing ?? replyTo;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border(top: BorderSide(color: palette.border)),
        ),
        padding: const EdgeInsets.fromLTRB(
          Space.sm,
          Space.xs,
          Space.sm,
          Space.xs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (quoted != null)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.sm,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: palette.surfaceAlt,
                  borderRadius: BorderRadius.circular(Radii.xs),
                  border: BorderDirectional(
                    start: BorderSide(color: palette.primary, width: 2),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '${editing != null ? Tr.of(context, ar: 'تعديل', en: 'Edit') : Tr.of(context, ar: 'رد', en: 'Reply')} · ${quoted.preview}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                    InkWell(
                      onTap: onCancelReply,
                      child: const Icon(Icons.close_rounded, size: 14),
                    ),
                  ],
                ),
              ),
            if (uploading)
              LinearProgressIndicator(minHeight: 2, color: palette.primary),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                IconButton(
                  onPressed: enabled ? onAttach : null,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  color: palette.primary,
                ),
                Expanded(
                  child: TextField(
                    controller: text,
                    focusNode: focus,
                    enabled: enabled,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 4000,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: uploading
                          ? stage
                          : Tr.of(context, ar: 'اكتب رسالة…', en: 'Message…'),
                      counterText: '',
                      isDense: true,
                      filled: true,
                      fillColor: palette.surfaceAlt,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: Space.md,
                        vertical: Space.sm,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Radii.pill),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: enabled ? onSend : null,
                  icon: Icon(
                    editing != null ? Icons.check_rounded : Icons.send_rounded,
                  ),
                  color: palette.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.chat,
    required this.uid,
    required this.mine,
    required this.peerName,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    required this.onCopy,
    required this.onReact,
    required this.onRetry,
    required this.onForward,
  });

  final ChatMessage message;
  final Chat? chat;
  final String uid;
  final bool mine;
  final String peerName;
  final VoidCallback onReply;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onCopy;
  final ValueChanged<String> onReact;
  final VoidCallback? onRetry;
  final VoidCallback onForward;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final status = chat == null
        ? message.status
        : messageStatus(message, chat: chat!, uid: uid);
    final reactions = message.reactions;
    return Align(
      alignment: mine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          crossAxisAlignment: mine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: <Widget>[
            GestureDetector(
              onLongPress: () => _menu(context),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                ),
                padding: message.type == ChatMessageType.text
                    ? const EdgeInsets.symmetric(
                        horizontal: Space.md,
                        vertical: Space.sm,
                      )
                    : const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: mine ? palette.primary : palette.surface,
                  borderRadius: BorderRadiusDirectional.only(
                    topStart: const Radius.circular(Radii.md),
                    topEnd: const Radius.circular(Radii.md),
                    bottomStart: Radius.circular(mine ? Radii.md : 4),
                    bottomEnd: Radius.circular(mine ? 4 : Radii.md),
                  ),
                  border: mine ? null : Border.all(color: palette.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (!mine && peerName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: 4,
                          top: 2,
                          bottom: 2,
                        ),
                        child: Text(
                          peerName,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: palette.primary,
                          ),
                        ),
                      ),
                    if (message.replyToId.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: (mine ? Colors.white : palette.surfaceAlt)
                              .withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          message.replyToPreview.isEmpty
                              ? Tr.of(context, ar: 'رسالة', en: 'Message')
                              : message.replyToPreview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: mine ? Colors.white70 : palette.textMuted,
                          ),
                        ),
                      ),
                    if (message.deleted)
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          Tr.of(
                            context,
                            ar: 'حُذفت هذه الرسالة',
                            en: 'This message was deleted',
                          ),
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: mine ? Colors.white70 : palette.textMuted,
                          ),
                        ),
                      )
                    else ...<Widget>[
                      if (message.share != null)
                        _ShareBubble(share: message.share!, mine: mine),
                      if (message.hasMedia)
                        _ChatMedia(message: message, mine: mine),
                      if (message.text.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(
                            message.text,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: mine
                                  ? palette.onPrimary
                                  : palette.textPrimary,
                            ),
                          ),
                        ),
                    ],
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(4, 2, 2, 0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (message.editedAt != null)
                            Text(
                              Tr.of(context, ar: 'معدّلة · ', en: 'edited · '),
                              style: TextStyle(
                                fontSize: 8,
                                color: mine
                                    ? Colors.white54
                                    : palette.textMuted,
                              ),
                            ),
                          Text(
                            _time(message.createdAt),
                            style: TextStyle(
                              fontSize: 8,
                              color: mine ? Colors.white60 : palette.textMuted,
                            ),
                          ),
                          if (mine) ...<Widget>[
                            const SizedBox(width: 3),
                            _Ticks(status: status),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (reactions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Wrap(
                  spacing: 3,
                  children: <Widget>[
                    for (final entry in reactions.entries)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: palette.surfaceAlt,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: palette.border),
                        ),
                        child: Text(
                          '${ChatRepositoryEmoji.of(entry.key)} ${entry.value.length}',
                          style: const TextStyle(fontSize: 9),
                        ),
                      ),
                  ],
                ),
              ),
            if (status == ChatMessageStatus.failed)
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.reply_rounded, size: 14),
                label: Text(
                  Tr.of(
                    context,
                    ar: 'فشل الإرسال · إعادة',
                    en: 'Failed · retry',
                  ),
                  style: const TextStyle(fontSize: 9),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _time(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _menu(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.sm),
              child: Wrap(
                spacing: 6,
                children: <Widget>[
                  for (final entry in ChatRepositoryEmoji.all.entries)
                    InkWell(
                      onTap: () =>
                          Navigator.of(context).pop('react:${entry.key}'),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          entry.value,
                          style: const TextStyle(fontSize: 22),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: Text(Tr.of(context, ar: 'رد', en: 'Reply')),
              onTap: () => Navigator.of(context).pop('reply'),
            ),
            ListTile(
              leading: const Icon(Icons.forward_rounded),
              title: Text(Tr.of(context, ar: 'إعادة توجيه', en: 'Forward')),
              onTap: () => Navigator.of(context).pop('forward'),
            ),
            if (message.text.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: Text(Tr.of(context, ar: 'نسخ', en: 'Copy')),
                onTap: () => Navigator.of(context).pop('copy'),
              ),
            if (mine &&
                message.type == ChatMessageType.text &&
                !message.deleted)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(Tr.of(context, ar: 'تعديل', en: 'Edit')),
                onTap: () => Navigator.of(context).pop('edit'),
              ),
            if (mine)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(Tr.of(context, ar: 'حذف', en: 'Delete')),
                onTap: () => Navigator.of(context).pop('delete'),
              ),
          ],
        ),
      ),
    );
    if (action == null) return;
    if (action.startsWith('react:')) {
      onReact(action.substring(6));
    } else {
      switch (action) {
        case 'reply':
          onReply();
        case 'forward':
          onForward();
        case 'copy':
          onCopy();
        case 'edit':
          onEdit();
        case 'delete':
          onDelete();
      }
    }
  }
}

class _Ticks extends StatelessWidget {
  const _Ticks({required this.status});

  final ChatMessageStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return switch (status) {
      ChatMessageStatus.read => const Icon(
        Icons.done_all_rounded,
        size: 12,
        color: Colors.lightBlueAccent,
      ),
      ChatMessageStatus.delivered => Icon(
        Icons.done_all_rounded,
        size: 12,
        color: palette.onPrimary.withValues(alpha: 0.7),
      ),
      ChatMessageStatus.sent => Icon(
        Icons.done_rounded,
        size: 12,
        color: palette.onPrimary.withValues(alpha: 0.7),
      ),
      ChatMessageStatus.sending => Icon(
        Icons.schedule_rounded,
        size: 11,
        color: palette.onPrimary.withValues(alpha: 0.6),
      ),
      ChatMessageStatus.failed => Icon(
        Icons.error_outline_rounded,
        size: 12,
        color: palette.danger,
      ),
    };
  }
}

abstract final class ChatRepositoryEmoji {
  static const Map<String, String> all = <String, String>{
    'heart': '❤️',
    'like': '👍',
    'haha': '😂',
    'wow': '😮',
    'sad': '😢',
  };

  static String of(String key) => all[key] ?? '❤️';
}

class _ChatMedia extends ConsumerWidget {
  const _ChatMedia({
    required this.message,
    this.compact = false,
    this.mine = false,
  });

  final ChatMessage message;
  final bool compact;
  final bool mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(communityMediaProvider);
    return FutureBuilder<Map<String, String>>(
      future: service.downloadUrls(<String>[
        message.mediaKey,
        if (message.thumbKey.isNotEmpty) message.thumbKey,
      ]),
      builder: (context, snapshot) {
        final url = snapshot.data?[message.mediaKey];
        final thumb = snapshot.data?[message.thumbKey] ?? url;
        if (url == null || url.isEmpty) {
          return Container(
            width: compact ? double.infinity : 200,
            height: compact ? 90 : 140,
            color: Colors.black12,
            alignment: Alignment.center,
            child: const Icon(Icons.image_outlined, size: 20),
          );
        }
        switch (message.type) {
          case ChatMessageType.image:
            return ClipRRect(
              borderRadius: BorderRadius.circular(Radii.xs),
              child: Image.network(
                url,
                width: compact ? double.infinity : 210,
                height: compact ? 90 : 180,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(
                  width: 200,
                  height: 120,
                  child: Icon(Icons.broken_image_outlined),
                ),
              ),
            );
          case ChatMessageType.video:
            return SizedBox(
              width: compact ? double.infinity : 230,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.xs),
                child: CommunityVideo(
                  url: url,
                  posterUrl: thumb,
                  active: false,
                  startMuted: true,
                  aspectRatio:
                      (message.mediaWidth > 0 && message.mediaHeight > 0
                              ? message.mediaWidth / message.mediaHeight
                              : 9 / 16)
                          .clamp(0.8, 1.8),
                  showChrome: true,
                  fit: BoxFit.cover,
                ),
              ),
            );
          case ChatMessageType.audio:
            return _VoiceBubble(url: url, mine: mine);
          case ChatMessageType.file:
            return InkWell(
              onTap: () => _save(context, ref, url),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: compact ? double.infinity : 240,
                ),
                padding: const EdgeInsets.all(Space.sm),
                decoration: BoxDecoration(
                  color: mine ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(Radii.xs),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.insert_drive_file_outlined, size: 20),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        message.mediaName.isEmpty
                            ? Tr.of(context, ar: 'ملف', en: 'File')
                            : message.mediaName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                    const Icon(Icons.download_rounded, size: 16),
                  ],
                ),
              ),
            );
          default:
            return const SizedBox.shrink();
        }
      },
    );
  }

  Future<void> _save(BuildContext context, WidgetRef ref, String url) async {
    try {
      final file = await ref
          .read(communityMediaProvider)
          .downloadVideo(
            url,
            fileName: message.mediaName.isEmpty
                ? 'wings-file'
                : message.mediaName,
          );
      await SharePlus.instance.share(
        ShareParams(files: <XFile>[XFile(file.path)]),
      );
    } on Object catch (error) {
      if (context.mounted) {
        context.showSnack(userFacingError(context, error), isError: true);
      }
    }
  }
}

class _VoiceBubble extends StatefulWidget {
  const _VoiceBubble({required this.url, required this.mine});

  final String url;
  final bool mine;

  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble> {
  late final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _position;
  Duration _duration = Duration.zero;
  Duration _positionValue = Duration.zero;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onDurationChanged.listen((value) {
      if (mounted) setState(() => _duration = value);
    });
    _position = _player.onPositionChanged.listen((value) {
      if (mounted) setState(() => _positionValue = value);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _positionValue = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    unawaited(_position?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final progress = _duration.inMilliseconds <= 0
        ? 0.0
        : (_positionValue.inMilliseconds / _duration.inMilliseconds).clamp(
            0.0,
            1.0,
          );
    return Container(
      padding: const EdgeInsets.all(Space.sm),
      width: 210,
      child: Row(
        children: <Widget>[
          InkWell(
            onTap: () async {
              if (_playing) {
                await _player.pause();
              } else {
                await _player.play(UrlSource(widget.url));
              }
              if (mounted) setState(() => _playing = !_playing);
            },
            child: Icon(
              _playing ? Icons.pause_circle_rounded : Icons.play_circle_rounded,
              size: 30,
              color: widget.mine ? palette.onPrimary : palette.primary,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  backgroundColor: (widget.mine ? Colors.white : palette.border)
                      .withValues(alpha: 0.3),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_positionValue.inSeconds}s / ${_duration.inSeconds}s',
                  style: TextStyle(
                    fontSize: 9,
                    color: widget.mine ? Colors.white70 : palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareBubble extends ConsumerWidget {
  const _ShareBubble({required this.share, required this.mine});

  final ChatShare share;
  final bool mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final service = ref.watch(communityMediaProvider);
    final hasKey = share.imageKey.isNotEmpty;
    return FutureBuilder<Map<String, String>>(
      future: hasKey
          ? service.downloadUrls(<String>[share.imageKey])
          : Future<Map<String, String>>.value(const <String, String>{}),
      builder: (context, snapshot) {
        final image = share.imageUrl.isNotEmpty
            ? share.imageUrl
            : snapshot.data?[share.imageKey] ?? '';
        return InkWell(
          onTap: () => context.push(share.destination),
          borderRadius: BorderRadius.circular(Radii.xs),
          child: Container(
            width: 250,
            decoration: BoxDecoration(
              color: mine ? Colors.white24 : palette.surfaceAlt,
              borderRadius: BorderRadius.circular(Radii.xs),
              border: Border.all(color: palette.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (image.isNotEmpty)
                  Image.network(
                    image,
                    height: 110,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                Padding(
                  padding: const EdgeInsets.all(Space.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        share.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: mine ? palette.onPrimary : palette.textPrimary,
                        ),
                      ),
                      if (share.subtitle.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          share.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9,
                            color: mine
                                ? Colors.white70
                                : palette.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.open_in_new_rounded,
                            size: 12,
                            color: mine ? Colors.white : palette.primary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            Tr.of(
                              context,
                              ar: 'فتح المحتوى',
                              en: 'Open content',
                            ),
                            style: TextStyle(
                              fontSize: 9,
                              color: mine ? Colors.white : palette.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
