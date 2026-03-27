import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/socket_service.dart';
import '../../utils/constants.dart';
import '../../widgets/error_boundary.dart';

class YouTubeTogetherScreen extends StatefulWidget {
  final String roomId;
  final String roomName;

  const YouTubeTogetherScreen({
    super.key,
    required this.roomId,
    required this.roomName,
  });

  @override
  State<YouTubeTogetherScreen> createState() => _YouTubeTogetherScreenState();
}

class _YouTubeTogetherScreenState extends State<YouTubeTogetherScreen> {
  late YoutubePlayerController _controller;
  final TextEditingController _urlController = TextEditingController();
  final List<String> _queue = [];
  bool _isPlayerReady = false;
  String? _currentVideoId;
  List<Map<String, dynamic>> _participants = [];

  @override
  void initState() {
    super.initState();
    _initYouTube();
    _setupSocketListeners();
  }

  void _initYouTube() {
    _controller = YoutubePlayerController(
      initialVideoId: '',
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        disableDragSeek: false,
        loop: false,
        isLive: false,
        forceHD: false,
        enableCaption: false,
      ),
    )..addListener(_listener);
  }

  void _listener() {
    if (_controller.value.isReady && !_isPlayerReady) {
      setState(() => _isPlayerReady = true);
    }
  }

  void _setupSocketListeners() {
    final socket = SocketService.socket;

    socket?.on('youtube:sync', (data) {
      if (!mounted) return;
      final videoId = data['videoId'];
      final timestamp = data['timestamp'];
      final action = data['action'];

      if (videoId != _currentVideoId) {
        _controller.load(videoId);
        setState(() => _currentVideoId = videoId);
      }

      if (action == 'play') {
        _controller.seekTo(Duration(seconds: timestamp));
        _controller.play();
      } else if (action == 'pause') {
        _controller.pause();
      } else if (action == 'seek') {
        _controller.seekTo(Duration(seconds: timestamp));
      }
    });

    socket?.on('youtube:queue', (data) {
      setState(() {
        _queue.add(data['url']);
      });
    });

    socket?.on('room:participants', (data) {
      setState(() {
        _participants =
            List<Map<String, dynamic>>.from(data['participants'] ?? []);
      });
    });
  }

  void _playVideo(String videoId) {
    if (!_isPlayerReady) return;

    final socket = SocketService.socket;
    final currentTime = _controller.value.position.inSeconds;

    _controller.load(videoId);
    setState(() => _currentVideoId = videoId);

    socket?.emit('youtube:play', {
      'roomId': widget.roomId,
      'videoId': videoId,
      'timestamp': currentTime,
    });
  }

  void _pauseVideo() {
    if (!_isPlayerReady) return;

    final socket = SocketService.socket;
    final currentTime = _controller.value.position.inSeconds;

    _controller.pause();

    socket?.emit('youtube:pause', {
      'roomId': widget.roomId,
      'timestamp': currentTime,
    });
  }

  void _seekVideo(int seconds) {
    if (!_isPlayerReady) return;

    final socket = SocketService.socket;

    _controller.seekTo(Duration(seconds: seconds));

    socket?.emit('youtube:seek', {
      'roomId': widget.roomId,
      'timestamp': seconds,
    });
  }

  void _addToQueue() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    final videoId = YoutubePlayer.convertUrlToId(url);
    if (videoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid YouTube URL'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final socket = SocketService.socket;
    socket?.emit('youtube:queue', {
      'roomId': widget.roomId,
      'url': url,
      'videoId': videoId,
    });

    _urlController.clear();
  }

  @override
  void dispose() {
    final socket = SocketService.socket;
    socket?.off('youtube:sync');
    socket?.off('youtube:queue');
    socket?.off('room:participants');

    _controller.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('YouTube Together - ${widget.roomName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.people),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                builder: (context) => Container(
                  padding: const EdgeInsets.all(16),
                  height: 300,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Participants',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _participants.length,
                          itemBuilder: (context, index) {
                            final p = _participants[index];
                            final user = p['userId'] is Map
                                ? p['userId'] as Map<String, dynamic>
                                : null;
                            return ListTile(
                              leading: CircleAvatar(
                                child: Text(user?['username']?[0] ?? '?'),
                              ),
                              title: Text(user?['username'] ?? 'Unknown'),
                              trailing: p['userId'] == authProvider.user?.id
                                  ? const Text('You')
                                  : null,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Video player
          if (_currentVideoId != null)
            ErrorBoundary(
              child: YoutubePlayer(
                controller: _controller,
                showVideoProgressIndicator: true,
                progressIndicatorColor: AppColors.primaryBlue,
                topActions: <Widget>[
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Text(
                      _controller.metadata.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18.0,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
                onReady: () => _isPlayerReady = true,
              ),
            )
          else
            Container(
              height: 200,
              color: Colors.black,
              child: const Center(
                child: Text(
                  'No video playing',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),

          // Controls
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.replay_10),
                  onPressed: () {
                    final newTime = _controller.value.position.inSeconds - 10;
                    _seekVideo(newTime > 0 ? newTime : 0);
                  },
                ),
                IconButton(
                  icon: Icon(
                    _controller.value.isPlaying
                        ? Icons.pause
                        : Icons.play_arrow,
                    size: 32,
                  ),
                  onPressed: _controller.value.isPlaying
                      ? _pauseVideo
                      : () {
                          if (_currentVideoId != null) {
                            _playVideo(_currentVideoId!);
                          }
                        },
                ),
                IconButton(
                  icon: const Icon(Icons.forward_10),
                  onPressed: () {
                    final newTime = _controller.value.position.inSeconds + 10;
                    _seekVideo(newTime);
                  },
                ),
              ],
            ),
          ),

          // Add to queue
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: InputDecoration(
                      hintText: 'Paste YouTube URL...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _addToQueue,
                  child: const Text('Add'),
                ),
              ],
            ),
          ),

          // Queue
          Expanded(
            child: _queue.isEmpty
                ? Center(
                    child: Column(
                      children: [
                        Icon(Icons.queue_music,
                            size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'Queue is empty',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add videos for everyone to watch',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _queue.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        leading: const Icon(Icons.movie),
                        title: Text('Video ${index + 1}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.play_arrow),
                          onPressed: () {
                            final videoId =
                                YoutubePlayer.convertUrlToId(_queue[index]);
                            if (videoId != null) {
                              _playVideo(videoId);
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}






