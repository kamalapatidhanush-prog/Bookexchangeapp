import 'package:flutter/material.dart';
import '../../backend.dart';
import '../../models/library_models.dart';
import '../widgets/empty_state.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  bool _isMarkingAllRead = false;
  String? _errorMessage;
  List<ActivityItem> _activities = [];
  List<LibraryNotification> _notifications = [];
  final Set<String> _markingReadIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final actFuture = MySqlApiService.instance.getActivity();
      final notifFuture = MySqlApiService.instance.getNotifications();
      final results = await Future.wait([actFuture, notifFuture]);

      if (mounted) {
        setState(() {
          _activities = results[0] as List<ActivityItem>;
          _notifications = results[1] as List<LibraryNotification>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _markAllRead() async {
    if (_isMarkingAllRead) return;
    setState(() => _isMarkingAllRead = true);
    try {
      await MySqlApiService.instance.markAllNotificationsRead();
      await _loadData();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isMarkingAllRead = false);
    }
  }

  Future<void> _markRead(LibraryNotification notification) async {
    if (!_markingReadIds.add(notification.id)) return;
    setState(() {});
    try {
      await MySqlApiService.instance.markNotificationRead(notification.id);
      await _loadData();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      _markingReadIds.remove(notification.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications.where((n) => !n.isRead).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Community Activity'),
        bottom: TabBar(
          controller: _tabController,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            fontFamily: 'Trebuchet MS',
          ),
          tabs: [
            const Tab(text: 'Live Feed'),
            Tab(
              text: 'Notifications${unreadCount > 0 ? ' ($unreadCount)' : ''}',
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? ErrorStateWidget(message: _errorMessage!, onRetry: _loadData)
          : TabBarView(
              controller: _tabController,
              children: [_buildActivityFeed(), _buildNotificationsList()],
            ),
    );
  }

  Widget _buildActivityFeed() {
    if (_activities.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
            const EmptyStateWidget(
              icon: Icons.history_rounded,
              title: 'No community activity yet',
              subtitle:
                  'New listings, purchases, and sales will appear in this feed.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _activities.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = _activities[index];
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: _actionColor(
                      item.actionType,
                    ).withValues(alpha: 0.15),
                    child: Icon(
                      _actionIcon(item.actionType),
                      color: _actionColor(item.actionType),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              item.userName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              _timeAgo(item.createdAt),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14.5,
                          ),
                        ),
                        if (item.description.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            item.description,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNotificationsList() {
    if (_notifications.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
            const EmptyStateWidget(
              icon: Icons.notifications_none_rounded,
              title: 'No notifications',
              subtitle: 'Order and shipping updates will arrive here.',
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _isMarkingAllRead ? null : _markAllRead,
                child: _isMarkingAllRead
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Mark all as read'),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadData,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              itemCount: _notifications.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final notif = _notifications[index];
                return Card(
                  color: notif.isRead
                      ? null
                      : const Color(0xFFE2EFE7).withValues(alpha: 0.3),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: notif.isRead
                          ? Colors.grey.shade200
                          : const Color(0xFFE2EFE7),
                      child: Icon(
                        notif.isRead
                            ? Icons.notifications_outlined
                            : Icons.notifications_active,
                        color: notif.isRead
                            ? Colors.grey.shade600
                            : const Color(0xFF1B3B2B),
                        size: 20,
                      ),
                    ),
                    title: Text(
                      notif.title,
                      style: TextStyle(
                        fontWeight: notif.isRead
                            ? FontWeight.normal
                            : FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(notif.body),
                    trailing: notif.isRead
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.done, size: 18),
                            tooltip: 'Mark as read',
                            onPressed: _markingReadIds.contains(notif.id)
                                ? null
                                : () => _markRead(notif),
                          ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  IconData _actionIcon(String type) {
    switch (type) {
      case 'book_listed':
        return Icons.publish_rounded;
      case 'marketplace_purchase':
        return Icons.shopping_bag_outlined;
      case 'marketplace_sale':
        return Icons.sell_outlined;
      case 'exchange_requested':
        return Icons.swap_horiz_rounded;
      case 'exchange_accepted':
        return Icons.check_circle_outline;
      case 'book_borrowed':
        return Icons.menu_book_rounded;
      case 'exchange_completed':
        return Icons.verified_rounded;
      case 'wanted_posted':
        return Icons.search_rounded;
      default:
        return Icons.history_rounded;
    }
  }

  Color _actionColor(String type) {
    switch (type) {
      case 'book_listed':
        return const Color(0xFF2D5A40);
      case 'marketplace_purchase':
        return Colors.blue.shade700;
      case 'marketplace_sale':
        return const Color(0xFF2D5A40);
      case 'exchange_requested':
        return const Color(0xFFD4A359);
      case 'exchange_accepted':
        return Colors.blue.shade700;
      case 'book_borrowed':
        return Colors.teal.shade700;
      case 'exchange_completed':
        return const Color(0xFF1B3B2B);
      case 'wanted_posted':
        return Colors.purple.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
