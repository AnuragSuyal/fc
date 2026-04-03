import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import '../../widgets/rounded_scaffold.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return RoundedScaffold(
      title: 'Help & Support',
      body: ListView(
        children: [
          const SizedBox(height: 16),

          // FAQ Section
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Frequently Asked Questions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          _buildFaqTile(
            question: 'How do I set up my room?',
            answer:
                'Open My Room from the Rooms tab or your profile. On first use we allocate your permanent room, and after that you can keep editing the same room anytime.',
          ),
          _buildFaqTile(
            question: 'How do I send gifts?',
            answer:
                'Use the gift button inside a voice or game room, or inside a one-to-one friend chat, then pick the gift and send it.',
          ),
          _buildFaqTile(
            question: 'How do I earn coins?',
            answer:
                'You can earn coins by daily login, completing quests, winning games, and hosting rooms.',
          ),
          _buildFaqTile(
            question: 'What is VIP membership?',
            answer:
                'VIP membership gives you exclusive benefits like colored name, chat backup, and daily bonuses.',
          ),
          _buildFaqTile(
            question: 'How do I report a user?',
            answer:
                'Tap the three dots on a user\'s profile and select Report.',
          ),

          const Divider(height: 32),

          // Contact Support
          const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Still need help?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Contact our support team and we\'ll get back to you within 24 hours.',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),

          Card(
            margin: const EdgeInsets.all(16),
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.email, color: AppColors.primaryBlue),
                  ),
                  title: const Text('Email Support'),
                  subtitle: const Text('support@friendcircle.app'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () {
                    // TODO: Open email client
                  },
                ),
                const Divider(height: 0),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.chat, color: Colors.green),
                  ),
                  title: const Text('Live Chat'),
                  subtitle: const Text('Chat with support team'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () {
                    // TODO: Open live chat
                  },
                ),
                const Divider(height: 0),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.discord, color: Colors.purple),
                  ),
                  title: const Text('Discord'),
                  subtitle: const Text('Join our community'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () {
                    // TODO: Open Discord link
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // App Info
          Center(
            child: Column(
              children: [
                const Text(
                  'Friend Circle',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Version 1.2.0 (Build 42)',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),
                Text(
                  'Â© 2024 Friend Circle. All rights reserved.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildFaqTile({required String question, required String answer}) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ExpansionTile(
        title: Text(
          question,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              answer,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }
}
