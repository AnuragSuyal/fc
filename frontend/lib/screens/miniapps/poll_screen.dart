import 'package:flutter/material.dart';
import '../../models/poll_model.dart';
import '../../utils/constants.dart';

class PollScreen extends StatefulWidget {
  final String roomId;

  const PollScreen({super.key, required this.roomId});

  @override
  State<PollScreen> createState() => _PollScreenState();
}

class _PollScreenState extends State<PollScreen> {
  final List<PollModel> _polls = [];
  final TextEditingController _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _isMultipleChoice = false;
  bool _isCreating = false;

  @override
  void dispose() {
    _questionController.dispose();
    for (var c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    setState(() {
      _optionControllers.add(TextEditingController());
    });
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) return;
    setState(() {
      _optionControllers[index].dispose();
      _optionControllers.removeAt(index);
    });
  }

  void _createPoll() {
    if (_questionController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a question'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final options = _optionControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (options.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least 2 options'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // TODO: Send to backend
    final mockPoll = PollModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      question: _questionController.text,
      options: options
          .map((text) => PollOption(
                id: DateTime.now().millisecondsSinceEpoch.toString() + text,
                text: text,
              ))
          .toList(),
      isMultipleChoice: _isMultipleChoice,
      totalVotes: 0,
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      createdBy: 'current_user',
      createdAt: DateTime.now(),
    );

    setState(() {
      _polls.insert(0, mockPoll);
      _isCreating = false;
      _questionController.clear();
      for (var c in _optionControllers) {
        c.clear();
      }
    });
  }

  void _vote(PollModel poll, PollOption option) {
    // TODO: Send to backend
    setState(() {
      option.votes++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Polls'),
        actions: [
          IconButton(
            icon: Icon(_isCreating ? Icons.close : Icons.add),
            onPressed: () {
              setState(() => _isCreating = !_isCreating);
            },
          ),
        ],
      ),
      body: _isCreating
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Create Poll',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _questionController,
                    decoration: InputDecoration(
                      labelText: 'Question',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ..._optionControllers.asMap().entries.map((entry) {
                    final index = entry.key;
                    final controller = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: controller,
                              decoration: InputDecoration(
                                labelText: 'Option ${index + 1}',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          if (_optionControllers.length > 2)
                            IconButton(
                              icon: const Icon(Icons.remove_circle,
                                  color: Colors.red),
                              onPressed: () => _removeOption(index),
                            ),
                        ],
                      ),
                    );
                  }),
                  TextButton.icon(
                    onPressed: _addOption,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Option'),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Multiple Choice'),
                    value: _isMultipleChoice,
                    onChanged: (value) {
                      setState(() => _isMultipleChoice = value);
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _createPoll,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Create Poll'),
                    ),
                  ),
                ],
              ),
            )
          : _polls.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.poll, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'No polls yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Create a poll to get started',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _polls.length,
                  itemBuilder: (context, index) {
                    final poll = _polls[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              poll.question,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...poll.options.map((option) {
                              final percentage = poll.totalVotes > 0
                                  ? (option.votes / poll.totalVotes * 100)
                                  : 0.0;
                              return GestureDetector(
                                onTap: () => _vote(poll, option),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    border:
                                        Border.all(color: Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(option.text),
                                      ),
                                      const SizedBox(width: 8),
                                      Text('${option.votes} votes'),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${percentage.toStringAsFixed(1)}%',
                                        style: const TextStyle(
                                          color: AppColors.primaryBlue,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}






