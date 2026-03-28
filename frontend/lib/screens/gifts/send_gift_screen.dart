import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/gift_service.dart';
import '../../services/user_service.dart';
import '../../models/gift_model.dart';
import '../../models/user_model.dart';
import '../../utils/constants.dart';
import '../../widgets/app_search_icon.dart';
import '../../widgets/currency_icon.dart';
import '../../widgets/user_avatar.dart';

class SendGiftScreen extends StatefulWidget {
  final GiftModel gift;
  final String? initialRecipientId;

  const SendGiftScreen({
    super.key,
    required this.gift,
    this.initialRecipientId,
  });

  @override
  State<SendGiftScreen> createState() => _SendGiftScreenState();
}

class _SendGiftScreenState extends State<SendGiftScreen> {
  final _messageController = TextEditingController();
  UserModel? _selectedUser;
  List<UserModel> _searchResults = [];
  bool _isSearching = false;
  bool _isLoading = false;
  String? _errorMessage;

  // Send options
  bool _isPrivate = true; // true = private, false = broadcast
  bool _isDisposed = false;

  void _safeSetState(VoidCallback fn) {
    if (!_isDisposed && mounted) {
      setState(fn);
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialRecipientId != null) {
      _loadRecipient(widget.initialRecipientId!);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadRecipient(String userId) async {
    _safeSetState(() => _isLoading = true);

    final user = await UserService.getUserById(userId);

    if (mounted) {
      _safeSetState(() {
        _selectedUser = user;
        _isLoading = false;
      });
    }
  }

  Future<void> _searchUsers(String query) async {
    if (query.length < 3) return;

    _safeSetState(() {
      _isSearching = true;
      _searchResults = [];
    });

    final results = await UserService.searchUsers(query);

    if (mounted) {
      _safeSetState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  Future<void> _sendGift() async {
    if (_selectedUser == null) {
      _safeSetState(() {
        _errorMessage = 'Please select a recipient';
      });
      return;
    }

    _safeSetState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await GiftService.sendGift(
        toUserId: _selectedUser!.id,
        giftId: widget.gift.id,
        message:
            _messageController.text.isNotEmpty ? _messageController.text : null,
        broadcast: !_isPrivate,
      );

      if (!mounted) return;

      // Show success dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Gift Sent! ðŸŽ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.gift.icon,
                style: const TextStyle(fontSize: 64),
              ),
              const SizedBox(height: 16),
              Text(
                'You sent ${widget.gift.name} to ${_selectedUser!.username}!',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              if (result['newBalance'] != null) ...[
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CurrencyIcon.coins(size: 18),
                    const SizedBox(width: 4),
                    Text(
                      '${result['newBalance']['coins']}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 16),
                    const CurrencyIcon.gems(size: 18),
                    const SizedBox(width: 4),
                    Text(
                      '${result['newBalance']['gems']}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context, true); // Return to previous screen
              },
              child: const Text('Done'),
            ),
          ],
        ),
      );

      // Update auth provider balance
      if (result['newBalance'] != null) {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        authProvider.updateBalance(
          coins: result['newBalance']['coins'],
          gems: result['newBalance']['gems'],
        );

        if (mounted) {
          _safeSetState(() {});
        }
      }
    } catch (e) {
      _safeSetState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final canAfford = widget.gift.canAfford(user?.coins ?? 0, user?.gems ?? 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Gift'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Gift preview
                  Center(
                    child: Container(
                      width: 200,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        children: [
                          Text(
                            widget.gift.icon,
                            style: const TextStyle(fontSize: 80),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            widget.gift.name,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (widget.gift.coinsPrice > 0)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const CurrencyIcon.coins(size: 20),
                                const SizedBox(width: 4),
                                Text(
                                  '${widget.gift.coinsPrice}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          if (widget.gift.gemsPrice > 0)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const CurrencyIcon.gems(size: 20),
                                const SizedBox(width: 4),
                                Text(
                                  '${widget.gift.gemsPrice}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Balance check
                  if (!canAfford) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 32,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Insufficient funds',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'You need ${widget.gift.coinsPrice} coins and ${widget.gift.gemsPrice} gems',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pushNamed(context, '/wallet');
                            },
                            child: const Text('Get Coins'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Recipient selection
                  const Text(
                    'Select Recipient',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),

                  if (_selectedUser != null) ...[
                    // Selected user display
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          UserAvatar(
                            imageUrl: _selectedUser!.avatar,
                            username: _selectedUser!.username,
                            radius: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedUser!.username,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Level ${_selectedUser!.level}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _safeSetState(() {
                                _selectedUser = null;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // User search
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Search by username...',
                        prefixIcon: const AppSearchIcon(size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (value) {
                        _searchUsers(value);
                      },
                    ),

                    const SizedBox(height: 8),

                    // Search results
                    if (_isSearching)
                      const Center(child: CircularProgressIndicator())
                    else if (_searchResults.isNotEmpty)
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final result = _searchResults[index];
                            return ListTile(
                              leading: UserAvatar(
                                imageUrl: result.avatar,
                                username: result.username,
                                radius: 20,
                              ),
                              title: Text(result.username),
                              subtitle: Text('Level ${result.level}'),
                              onTap: () {
                                _safeSetState(() {
                                  _selectedUser = result;
                                  _searchResults = [];
                                });
                              },
                            );
                          },
                        ),
                      ),
                  ],

                  const SizedBox(height: 16),

                  // Personal message
                  const Text(
                    'Personal Message (Optional)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _messageController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Write a nice message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Send options
                  const Text(
                    'Send As',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Private'),
                          selected: _isPrivate,
                          onSelected: (selected) {
                            _safeSetState(() {
                              _isPrivate = true;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Broadcast'),
                          selected: !_isPrivate,
                          onSelected: (selected) {
                            _safeSetState(() {
                              _isPrivate = false;
                            });
                          },
                        ),
                      ),
                    ],
                  ),

                  if (!_isPrivate)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Broadcast gifts will be shown to everyone in the room',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue,
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Error message
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Colors.red.shade700,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: (canAfford && _selectedUser != null && !_isLoading)
                  ? _sendGift
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Send Gift',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
