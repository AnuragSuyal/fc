import 'package:flutter/material.dart';
import '../../services/friend_service.dart';
import '../../widgets/user_avatar.dart';
import '../../services/location_service.dart';
import '../../utils/constants.dart';
import '../messages/chat_screen.dart';
import '../profile/enhanced_profile_screen.dart';

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  List<dynamic> _nearbyUsers = [];
  bool _isLoading = true;
  bool _hasPermission = false;
  double _maxDistance = 10.0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkPermissionAndLoad();
  }

  Future<void> _checkPermissionAndLoad() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Check permission
      final hasPerm = await LocationService.hasPermission();

      if (!hasPerm) {
        setState(() {
          _hasPermission = false;
          _isLoading = false;
        });
        return;
      }

      setState(() => _hasPermission = true);

      // Get current location
      final location = await LocationService.getCurrentLocation();

      if (location == null) {
        setState(() {
          _error = 'Could not get location';
          _isLoading = false;
        });
        return;
      }

      // Removed _currentLocation storage

      // Update location on server
      await LocationService.updateLocation(
        latitude: location.latitude,
        longitude: location.longitude,
        sharing: true,
        radius: _maxDistance.toInt(),
      );

      // Get nearby users
      await _loadNearbyUsers();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadNearbyUsers() async {
    setState(() => _isLoading = true);

    final users = await LocationService.getNearbyUsers(
      maxDistance: _maxDistance.toInt(),
    );

    if (!mounted) return;

    setState(() {
      _nearbyUsers = users;
      _isLoading = false;
    });
  }

  Future<void> _requestPermission() async {
    final granted = await LocationService.requestPermission();

    if (granted && mounted) {
      _checkPermissionAndLoad();
    } else {
      setState(() => _hasPermission = false);
    }
  }

  Future<void> _sendFriendRequest(Map<String, dynamic> user) async {
    final userId = user['_id']?.toString();
    final username = user['username']?.toString() ?? 'User';
    if (userId == null || userId.isEmpty) return;

    final success = await FriendService.sendFriendRequest(userId);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Friend request sent to $username'
              : 'Could not send a friend request right now',
        ),
        backgroundColor: success ? AppColors.successGreen : AppColors.errorRed,
      ),
    );
  }

  Future<void> _openChat(Map<String, dynamic> user) async {
    final userId = user['_id']?.toString();
    final username = user['username']?.toString() ?? 'Unknown';
    if (userId == null || userId.isEmpty) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          userId: userId,
          username: username,
          avatar: user['avatar']?.toString(),
        ),
      ),
    );
  }

  Future<void> _openProfile(Map<String, dynamic> user) async {
    final userId = user['_id']?.toString();
    if (userId == null || userId.isEmpty) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EnhancedProfileScreen(userId: userId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby'),
        actions: [
          // Distance filter
          PopupMenuButton<double>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() => _maxDistance = value);
              _loadNearbyUsers();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 5, child: Text('5 km')),
              const PopupMenuItem(value: 10, child: Text('10 km')),
              const PopupMenuItem(value: 25, child: Text('25 km')),
              const PopupMenuItem(value: 50, child: Text('50 km')),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_hasPermission
              ? _buildPermissionRequest()
              : _error != null
                  ? _buildError()
                  : _nearbyUsers.isEmpty
                      ? _buildEmptyState()
                      : _buildNearbyList(),
    );
  }

  Widget _buildPermissionRequest() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.location_off,
              size: 80,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 24),
            const Text(
              'Location Access Required',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Enable location to see users nearby',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _requestPermission,
              icon: const Icon(Icons.location_on),
              label: const Text('Enable Location'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _checkPermissionAndLoad,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'No users nearby',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Check back later or increase your search radius',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadNearbyUsers,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildNearbyList() {
    return RefreshIndicator(
      onRefresh: _loadNearbyUsers,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _nearbyUsers.length,
        itemBuilder: (context, index) {
          final user = _nearbyUsers[index];
          final isOnline = user['status']?['isOnline'] ?? false;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: Stack(
                children: [
                  UserAvatar(
                    imageUrl: user['avatar'],
                    username: user['username'] ?? '',
                    radius: 24,
                  ),
                  if (isOnline)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              title: Text(
                user['username'] ?? 'Unknown',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Level ${user['level'] ?? 1}'),
                  Text(
                    '${user['distance']} km away',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.person_add),
                    onPressed: () => _sendFriendRequest(user),
                  ),
                  IconButton(
                    icon: const Icon(Icons.message),
                    onPressed: () => _openChat(user),
                  ),
                ],
              ),
              onTap: () => _openProfile(user),
            ),
          );
        },
      ),
    );
  }
}
