import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lumii_quest/features/notifications/data/notification_repository.dart';
import 'package:lumii_quest/features/notifications/domain/notification_item.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum _FilterChoice { singleDate, dateRange, clear }

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _repository = NotificationRepository();
  late Future<List<NotificationItem>> _notifications = _repository.getRecent();
  DateTime? _filterStart;
  DateTime? _filterEnd;
  final Set<int> _respondingRequests = {};

  Future<void> _respond(NotificationItem item, {required bool accept}) async {
    final requestId = item.friendRequestId;
    if (requestId == null || _respondingRequests.contains(requestId)) return;
    setState(() => _respondingRequests.add(requestId));
    try {
      await _repository.respondToFriendRequest(
        requestId: requestId,
        accept: accept,
      );
      if (mounted) {
        setState(() => _notifications = _repository.getRecent());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accept ? 'Friend request accepted.' : 'Friend request declined.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not answer request: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _respondingRequests.remove(requestId));
    }
  }

  Future<void> _chooseFilter() async {
    final choice = await showDialog<_FilterChoice>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Filter notifications'),
        children: [
          SimpleDialogOption(
            onPressed: () => context.pop(_FilterChoice.singleDate),
            child: const ListTile(
              leading: Icon(LucideIcons.calendar),
              title: Text('Single date'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => context.pop(_FilterChoice.dateRange),
            child: const ListTile(
              leading: Icon(LucideIcons.calendarRange),
              title: Text('Date range'),
            ),
          ),
          if (_filterStart != null)
            SimpleDialogOption(
              onPressed: () => context.pop(_FilterChoice.clear),
              child: const ListTile(
                leading: Icon(LucideIcons.listX),
                title: Text('Clear filter'),
              ),
            ),
        ],
      ),
    );
    if (!mounted || choice == null) return;

    if (choice == _FilterChoice.clear) {
      setState(() {
        _filterStart = null;
        _filterEnd = null;
      });
      return;
    }

    final now = DateTime.now();
    if (choice == _FilterChoice.singleDate) {
      final date = await showDatePicker(
        context: context,
        initialDate: _filterStart ?? now,
        firstDate: DateTime(2020),
        lastDate: DateTime(now.year + 1, 12, 31),
        helpText: 'Filter by date (dd/mm/yyyy)',
      );
      if (date != null && mounted) {
        setState(() {
          _filterStart = DateTime(date.year, date.month, date.day);
          _filterEnd = _filterStart!.add(const Duration(days: 1));
        });
      }
      return;
    }

    final range = await showDateRangePicker(
      context: context,
      initialDateRange: _filterStart == null || _filterEnd == null
          ? null
          : DateTimeRange(
              start: _filterStart!,
              end: _filterEnd!.subtract(const Duration(days: 1)),
            ),
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Filter by date range',
    );
    if (range != null && mounted) {
      setState(() {
        _filterStart = DateTime(
          range.start.year,
          range.start.month,
          range.start.day,
        );
        _filterEnd = DateTime(
          range.end.year,
          range.end.month,
          range.end.day,
        ).add(const Duration(days: 1));
      });
    }
  }

  List<NotificationItem> _filtered(List<NotificationItem> items) {
    return filterNotificationItems(items, start: _filterStart, end: _filterEnd);
  }

  Future<void> _refresh() async {
    final future = _repository.getRecent();
    setState(() => _notifications = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          icon: const Icon(LucideIcons.chevronLeft),
        ),
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(LucideIcons.refreshCcw),
          ),
          IconButton(
            tooltip: 'Filter',
            onPressed: _chooseFilter,
            icon: const Icon(LucideIcons.listFilter),
          ),
        ],
      ),
      body: FutureBuilder<List<NotificationItem>>(
        future: _notifications,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _NotificationMessage(
              message: 'Notifications could not be loaded.',
              onRetry: () =>
                  setState(() => _notifications = _repository.getRecent()),
            );
          }

          final items = _filtered(snapshot.data ?? const []);
          if (items.isEmpty) {
            return _NotificationMessage(
              message: _filterStart == null
                  ? 'No notifications yet.'
                  : 'No notifications in this period.',
            );
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final requestId = item.friendRequestId;
                  final isResponding =
                      requestId != null &&
                      _respondingRequests.contains(requestId);
                  return Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          leading: const Icon(LucideIcons.bell),
                          title: Text(
                            item.title,
                            style: TextStyle(
                              fontWeight: item.isRead
                                  ? FontWeight.w600
                                  : FontWeight.w800,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text(item.body),
                          ),
                          trailing: Text(
                            formatNotificationDate(item.createdAt),
                          ),
                        ),
                        if (item.canRespond)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.end,
                              children: [
                                OutlinedButton(
                                  onPressed: isResponding
                                      ? null
                                      : () => _respond(item, accept: false),
                                  child: const Text('Decline'),
                                ),
                                FilledButton(
                                  onPressed: isResponding
                                      ? null
                                      : () => _respond(item, accept: true),
                                  child: Text(
                                    isResponding ? 'Saving…' : 'Accept',
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (item.isFriendRequest)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: _RequestStatus(status: item.actionStatus),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RequestStatus extends StatelessWidget {
  const _RequestStatus({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final accepted = status == 'accepted';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          accepted ? LucideIcons.check : LucideIcons.x,
          size: 18,
          color: accepted ? Colors.green : Theme.of(context).colorScheme.error,
        ),
        const SizedBox(width: 5),
        Text(accepted ? 'Accepted' : 'Declined'),
      ],
    );
  }
}

class _NotificationMessage extends StatelessWidget {
  const _NotificationMessage({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.bell, size: 42),
          const SizedBox(height: 12),
          Text(message),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    );
  }
}
