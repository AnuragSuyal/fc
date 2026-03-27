import 'package:flutter/material.dart';
import '../../services/group_service.dart';
import '../../models/group_model.dart';
import '../../utils/constants.dart';
import '../../widgets/user_avatar.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<GroupModel> _myGroups = [];
  List<GroupModel> _discoverGroups = [];
  List<GroupModel> _leaderboard = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final myGroups = await GroupService.getMyGroups();
      final discover = await GroupService.getDiscoverGroups();
      final leaderboard = await GroupService.getLeaderboard();

      if (!mounted) return;

      setState(() {
        _myGroups = myGroups;
        _discoverGroups = discover;
        _leaderboard = leaderboard;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading groups: $e');
      setState(() => _isLoading = false);
    }
  }

  void _showCreateGroupDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final mottoController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Group'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Group Name',
                  hintText: 'e.g., Gaming Squad',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'What is your group about?',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: mottoController,
                decoration: const InputDecoration(
                  labelText: 'Motto (Optional)',
                  hintText: 'A short slogan',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _isLoading = true);

              final group = await GroupService.createGroup(
                name: nameController.text,
                description: descController.text,
                motto: mottoController.text,
              );

              if (group != null && mounted) {
                await _loadData();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Group "${group.name}" created!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleJoinGroup(String groupId, String groupName) async {
    final success = await GroupService.joinGroup(groupId);

    if (!mounted) return;

    if (success) {
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Joined $groupName!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to join group'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleClaimTreasure(String groupId) async {
    final result = await GroupService.claimTreasure(groupId);

    if (!mounted) return;

    if (result != null) {
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Treasure claimed! +${result['coins'] ?? 0} coins'),
          backgroundColor: Colors.amber,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.primaryBlue,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.primaryBlue,
            tabs: const [
              Tab(text: 'My Groups'),
              Tab(text: 'Discover'),
              Tab(text: 'Leaderboard'),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    // My Groups Tab
                    _buildMyGroups(),

                    // Discover Tab
                    _buildDiscoverGroups(),

                    // Leaderboard Tab
                    _buildLeaderboard(),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildMyGroups() {
    if (_myGroups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.group_off,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No groups yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create or join a group to get started',
              style: TextStyle(color: Colors.grey.shade500),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showCreateGroupDialog,
              icon: const Icon(Icons.add),
              label: const Text('Create Group'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _myGroups.length,
      itemBuilder: (context, index) {
        final group = _myGroups[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(
            children: [
              ListTile(
                leading: UserAvatar(
                  imageUrl: group.avatar,
                  username: group.name,
                  radius: 20,
                ),
                title: Text(group.name),
                subtitle: Text(
                  '${group.memberCount}/${group.maxMembers} members â€¢ ${group.type}',
                ),
                trailing: group.hasTreasure
                    ? IconButton(
                        icon: const Icon(Icons.card_giftcard,
                            color: Colors.amber),
                        onPressed: () => _handleClaimTreasure(group.id),
                      )
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.pushNamed(
                          context,
                          '/groups/detail',
                          arguments: group.id,
                        );
                      },
                      child: const Text('View'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Leave Group'),
                            content: Text(
                                'Are you sure you want to leave ${group.name}?'),
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
                          await GroupService.leaveGroup(group.id);
                          await _loadData();
                        }
                      },
                      child: const Text('Leave'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDiscoverGroups() {
    if (_discoverGroups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.explore,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No groups to discover',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check back later for new groups',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _discoverGroups.length,
      itemBuilder: (context, index) {
        final group = _discoverGroups[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            onTap: () {
              Navigator.pushNamed(
                context,
                '/groups/detail',
                arguments: group.id,
              );
            },
            leading: UserAvatar(
              imageUrl: group.avatar,
              username: group.name,
              radius: 18,
            ),
            title: Text(group.name),
            subtitle: Text(
              '${group.memberCount}/${group.maxMembers} members â€¢ ${group.motto.isNotEmpty ? group.motto : group.type}',
            ),
            trailing: ElevatedButton(
              onPressed: () => _handleJoinGroup(group.id, group.name),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Join'),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLeaderboard() {
    if (_leaderboard.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.emoji_events_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No groups on leaderboard yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _leaderboard.length,
      itemBuilder: (context, index) {
        final group = _leaderboard[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            onTap: () {
              Navigator.pushNamed(
                context,
                '/groups/detail',
                arguments: group.id,
              );
            },
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: index == 0
                    ? Colors.amber
                    : index == 1
                        ? Colors.grey.shade400
                        : index == 2
                            ? Colors.brown.shade400
                            : Colors.grey.shade200,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '#${index + 1}',
                  style: TextStyle(
                    color: index < 3 ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            title: Text(group.name),
            subtitle: Text(
                '${group.memberCount} members â€¢ ${group.stats['totalXp'] ?? 0} XP'),
            trailing: Text('ðŸŽ¯ ${group.stats['rank'] ?? 0}'),
          ),
        );
      },
    );
  }
}






