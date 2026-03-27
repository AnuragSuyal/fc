import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/group_service.dart';
import '../../models/group_model.dart';
import '../../utils/constants.dart';

class GroupDetailScreen extends StatefulWidget {
  final String groupId;

  const GroupDetailScreen({super.key, required this.groupId});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  GroupModel? _group;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadGroup();
  }

  Future<void> _loadGroup() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final group = await GroupService.getGroupById(widget.groupId);

      if (!mounted) return;

      setState(() {
        _group = group;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _handleClaimTreasure() async {
    if (_group == null) return;

    final result = await GroupService.claimTreasure(_group!.id);

    if (!mounted) return;

    if (result != null) {
      await _loadGroup();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Treasure claimed! +${result['coins']} coins'),
          backgroundColor: Colors.amber,
        ),
      );
    }
  }

  Future<void> _handleLeaveGroup() async {
    if (_group == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Group'),
        content: Text('Are you sure you want to leave ${_group!.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await GroupService.leaveGroup(_group!.id);
      if (success && mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Left group successfully'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_group?.name ?? 'Group Details'),
        actions: [
          if (_group?.hasTreasure == true)
            IconButton(
              icon: const Icon(Icons.card_giftcard, color: Colors.amber),
              onPressed: _handleClaimTreasure,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          size: 64, color: Colors.red.shade300),
                      const SizedBox(height: 16),
                      const Text('Failed to load group'),
                      const SizedBox(height: 8),
                      Text(_error!,
                          style: TextStyle(color: Colors.grey.shade600)),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _loadGroup,
                        child: const Text('Try Again'),
                      ),
                    ],
                  ),
                )
              : _group == null
                  ? const Center(child: Text('Group not found'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  AppColors.primaryBlue,
                                  AppColors.secondaryBlue
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 30,
                                  backgroundImage: _group!.avatar.isNotEmpty
                                      ? NetworkImage(_group!.avatar)
                                      : null,
                                  child: _group!.avatar.isEmpty
                                      ? Text(
                                          _group!.name[0].toUpperCase(),
                                          style: const TextStyle(fontSize: 24),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _group!.name,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      Text(
                                        _group!.tag,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.white
                                              .withValues(alpha: 0.8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Stats cards
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  'Members',
                                  '${_group!.memberCount}/${_group!.maxMembers}',
                                  Icons.people,
                                  Colors.blue,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  'Rank',
                                  '#${_group!.stats['rank'] ?? '?'}',
                                  Icons.emoji_events,
                                  Colors.amber,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // Description
                          if (_group!.description.isNotEmpty) ...[
                            const Text(
                              'Description',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(_group!.description),
                            const SizedBox(height: 16),
                          ],

                          // Motto
                          if (_group!.motto.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.format_quote,
                                      color: Colors.blue),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _group!.motto,
                                      style: const TextStyle(
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Leader
                          const Text(
                            'Group Leader',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ListTile(
                            leading: CircleAvatar(
                              backgroundImage: NetworkImage(
                                _group!.leaderAvatar.isNotEmpty
                                    ? _group!.leaderAvatar
                                    : 'https://via.placeholder.com/40',
                              ),
                            ),
                            title: Text(_group!.leaderName),
                            subtitle: const Text('Leader'),
                          ),

                          const SizedBox(height: 16),

                          // Members
                          const Text(
                            'Members',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...(_group!.members.take(5).map((member) {
                            final user = member['userId'] is Map
                                ? member['userId'] as Map<String, dynamic>
                                : null;
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: NetworkImage(
                                  user?['avatar'] ??
                                      'https://via.placeholder.com/40',
                                ),
                              ),
                              title: Text(user?['username'] ?? 'Unknown'),
                              subtitle: Text(member['role']),
                            );
                          })),

                          if (_group!.members.length > 5)
                            TextButton(
                              onPressed: () {
                                // TODO: Show all members
                              },
                              child:
                                  Text('+ ${_group!.members.length - 5} more'),
                            ),

                          const SizedBox(height: 24),

                          // Leave button (if not leader)
                          Consumer<AuthProvider>(
                            builder: (context, auth, _) {
                              final isLeader =
                                  _group!.leaderId == auth.user?.id;
                              if (isLeader) return const SizedBox.shrink();

                              return SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _handleLeaveGroup,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Leave Group'),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}






