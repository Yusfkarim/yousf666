import '../../core/services/marketplace_client.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/app_state.dart';
import '../../core/theme/clay_widgets.dart';
import '../../core/theme/marketplace_scaffold.dart';

class OrderChatScreen extends ConsumerStatefulWidget {
  const OrderChatScreen({required this.orderId, super.key});
  final String orderId;

  @override
  ConsumerState<OrderChatScreen> createState() => _OrderChatScreenState();
}

class _OrderChatScreenState extends ConsumerState<OrderChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  LocalChannel? _channel;

  MarketplaceClient get _client => ref.read(apiProvider);

  @override
  void initState() {
    super.initState();
    _load();
    _channel = _client
        .channel('order-chat-${widget.orderId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'order_id', value: widget.orderId),
          callback: (_) => _load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    if (_channel != null) unawaited(_client.removeChannel(_channel!).then((_) {}));
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await _client.from('messages').select().eq('order_id', widget.orderId).order('created_at');
      if (!mounted) return;
      setState(() {
        _messages = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      });
    } catch (error) {
      if (mounted) setState(() => _loading = false);
      if (mounted) _message('چات بەردەست نییە: $error');
    }
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    final user = _client.auth.currentUser;
    if (user == null || body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _client.from('messages').insert({'order_id': widget.orderId, 'sender_id': user.id, 'body': body});
      _controller.clear();
      await _load();
    } catch (error) {
      if (mounted) _message('پەیام نەنێردرا: $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _message(String value) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));

  @override
  Widget build(BuildContext context) {
    final userId = _client.auth.currentUser?.id;
    return MarketplaceScaffold(
      body: Column(children: [
        Expanded(
          child: _loading
              ? clayLoading(label: 'پەیامەکان دەهێنرێن...')
              : _messages.isEmpty
                  ? clayEmpty('هێشتا پەیامێک نییە', subtitle: 'پرسیارێکت لەبارەی داواکارییەکە هەیە؟')
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        final mine = message['sender_id'] == userId;
                        return Align(
                          alignment: mine ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: ClayCard(
                                radius: 20,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(message['body'] as String? ?? '', style: const TextStyle(fontSize: 14)),
                                  const SizedBox(height: 3),
                                  Text(mine ? 'تۆ' : 'دوکان / گەیەنەر', style: TextStyle(fontSize: 9, color: context.clayMuted)),
                                ]),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
          child: Row(children: [
            Expanded(
              child: ClayInsetContainer(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                radius: 99,
                child: TextField(controller: _controller, maxLength: 2000, decoration: const InputDecoration(border: InputBorder.none, hintText: 'پەیام بنووسە...', counterText: '')),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: _sending ? null : _send,
              borderRadius: BorderRadius.circular(30),
              child: ClayIconBadge(icon: _sending ? Icons.hourglass_top_rounded : Icons.send_rounded, size: 48, tone: ClayTone.orange),
            ),
          ]),
        ),
      ]),
    );
  }
}
