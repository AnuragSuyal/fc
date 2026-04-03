import 'package:flutter/material.dart';
import '../../models/room_model.dart';
import '../user_avatar.dart';
import '../level_badge.dart';
import '../vip/vip_badge.dart';
import '../vip/vip_name_text.dart';

class RoomMemberListBottomSheet extends StatefulWidget {
  final RoomModel room;
  final ValueChanged<Participant>? onParticipantTap;

  const RoomMemberListBottomSheet({
    super.key,
    required this.room,
    this.onParticipantTap,
  });

  @override
  State<RoomMemberListBottomSheet> createState() =>
      _RoomMemberListBottomSheetState();
}

class _RoomMemberListBottomSheetState extends State<RoomMemberListBottomSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onlineMembers = widget.room.participants
        .where(
            (participant) => participant.isOnline || participant.seatIndex >= 0)
        .toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFF0F0E13),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Audience Hub',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF7A45).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFFFF7A45).withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '${widget.room.onlineCount} LIVE',
                    style: const TextStyle(
                      color: Color(0xFFFF7A45),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF16151B),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TabBar(
                controller: _tabController,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: const Color(0xFFFF7A45),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF7A45).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                labelColor: Colors.black,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                unselectedLabelColor: Colors.white54,
                unselectedLabelStyle:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                tabs: const [
                  Tab(text: 'Active Now'),
                  Tab(text: 'Inner Circle'),
                  Tab(text: 'Top Tributes'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black12),
              ),
              child: TextField(
                controller: _searchController,
                cursorColor: Colors.black87,
                style: const TextStyle(color: Colors.black87),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  filled: true,
                  fillColor: Colors.transparent,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  hintText: 'Search by name or UID',
                  hintStyle: const TextStyle(color: Colors.black45),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Colors.black87,
                    size: 20,
                  ),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          onPressed: _searchController.clear,
                          icon: const Icon(Icons.close_rounded,
                              color: Colors.black54, size: 20),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildActiveNowTab(onlineMembers),
                _buildMemberList(widget.room.participants),
                _buildContributionList(widget.room.participants),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveNowTab(List<Participant> members) {
    Participant? featuredHost;
    try {
      featuredHost = widget.room.participants.firstWhere(
          (p) => p.role == 'host' || p.userId == widget.room.hostId);
    } catch (_) {}

    final others = members
        .where((p) => featuredHost == null || p.userId != featuredHost.userId)
        .where(_matchesQuery)
        .toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        if (featuredHost != null && _matchesQuery(featuredHost)) ...[
          const Text(
            'FEATURED SPIRIT',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),
          _buildFeaturedCard(featuredHost),
          const SizedBox(height: 24),
        ],
        const Text(
          'NEARBY AURAS',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 16),
        if (others.isEmpty)
          const _MembersEmptyState(
            title: 'No nearby auras found',
            subtitle: 'Try searching for someone else.',
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: others.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              return _MemberTile(
                participant: others[index],
                onTap: widget.onParticipantTap == null
                    ? null
                    : () => widget.onParticipantTap!(others[index]),
              );
            },
          ),
      ],
    );
  }

  Widget _buildFeaturedCard(Participant member) {
    return GestureDetector(
      onTap: widget.onParticipantTap == null
          ? null
          : () => widget.onParticipantTap!(member),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF16151B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFF00D19B), Color(0xFF52A1FF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: UserAvatar(
                    username: member.username,
                    imageUrl: member.avatar,
                    radius: 30,
                    shopProfile: member.user?.shopProfile,
                    vipMembership: member.user?.vipMembership,
                    vipLevel: member.vipLevel,
                  ),
                ),
                if (member.isOnline)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00D19B),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xFF16151B), width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: VipNameText(
                          member.username,
                          membership: member.user?.vipMembership,
                          fallbackVipLevel: member.vipLevel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (member.vipLevel > 0) ...[
                        const SizedBox(width: 8),
                        VipBadge(
                          membership: member.user?.vipMembership,
                          fallbackVipLevel: member.vipLevel,
                          size: VipBadgeSize.small,
                        ),
                      ],
                      const SizedBox(width: 8),
                      const Icon(Icons.bolt_rounded,
                          color: Color(0xFF52A1FF), size: 18),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildTag('stars', const Color(0xFFFF9F69)),
                      const SizedBox(width: 8),
                      _buildTag('verified_user', const Color(0xFF00D19B)),
                      const SizedBox(width: 8),
                      _buildTag('token', const Color(0xFF74B886)),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              width: 16,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildMemberList(List<Participant> members) {
    final filtered = members.where(_matchesQuery).toList();

    if (filtered.isEmpty) {
      return const _MembersEmptyState(
        title: 'No members found',
        subtitle: 'Try another name or wait for the room to fill up.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final member = filtered[index];
        return _MemberTile(
          participant: member,
          onTap: widget.onParticipantTap == null
              ? null
              : () => widget.onParticipantTap!(member),
        );
      },
    );
  }

  Widget _buildContributionList(List<Participant> members) {
    final sorted = List<Participant>.from(members)
      ..sort((a, b) => b.contribution.compareTo(a.contribution));
    final filtered = sorted.where(_matchesQuery).toList();

    if (filtered.isEmpty) {
      return const _MembersEmptyState(
        title: 'No supporter data yet',
        subtitle: 'Gifts and room activity will show up here.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final member = filtered[index];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF16151B),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              _RankBadge(index + 1),
              const SizedBox(width: 12),
              UserAvatar(
                username: member.username,
                imageUrl: member.avatar,
                radius: 22,
                shopProfile: member.user?.shopProfile,
                vipMembership: member.user?.vipMembership,
                vipLevel: member.vipLevel,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: VipNameText(
                            member.username,
                            membership: member.user?.vipMembership,
                            fallbackVipLevel: member.vipLevel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (member.vipLevel > 0) ...[
                          const SizedBox(width: 6),
                          VipBadge(
                            membership: member.user?.vipMembership,
                            fallbackVipLevel: member.vipLevel,
                            size: VipBadgeSize.small,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Seat ${member.seatIndex >= 0 ? member.seatIndex : 'Audience'}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${member.contribution}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Text(
                    'Contribution',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  bool _matchesQuery(Participant participant) {
    if (_query.isEmpty) return true;
    final username = participant.username.toLowerCase();
    final userId = participant.userId.toLowerCase();
    return username.contains(_query) || userId.contains(_query);
  }
}

class _MemberTile extends StatelessWidget {
  final Participant participant;
  final VoidCallback? onTap;

  const _MemberTile({
    required this.participant,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = _roleColor(participant.role);
    final seatLabel = participant.seatIndex >= 0
        ? 'Seat ${participant.seatIndex}'
        : 'Audience';
    final shortUserId = participant.userId.length > 12
        ? '${participant.userId.substring(0, 12)}...'
        : participant.userId;

    return Material(
      color: const Color(0xFF16151B),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Stack(
                children: [
                  UserAvatar(
                    username: participant.username,
                    imageUrl: participant.avatar,
                    radius: 24,
                    shopProfile: participant.user?.shopProfile,
                    vipMembership: participant.user?.vipMembership,
                    vipLevel: participant.vipLevel,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: participant.isOnline
                            ? const Color(0xFF00D19B)
                            : const Color(0xFF4A4D57),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xFF16151B), width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: VipNameText(
                            participant.username,
                            membership: participant.user?.vipMembership,
                            fallbackVipLevel: participant.vipLevel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (participant.vipLevel > 0) ...[
                          const SizedBox(width: 6),
                          VipBadge(
                            membership: participant.user?.vipMembership,
                            fallbackVipLevel: participant.vipLevel,
                            size: VipBadgeSize.small,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'UID: $shortUserId',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        LevelBadge(
                          level: participant.level,
                          levelInfo: participant.user?.levelInfo,
                          size: LevelBadgeSize.small,
                        ),
                        _InfoBadge(_roleLabel(participant.role), accent),
                        _InfoBadge(seatLabel, const Color(0xFF52A1FF)),
                        if (participant.isMuted)
                          const _InfoBadge('Muted', Colors.redAccent),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _InfoBadge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  final int rank;

  const _RankBadge(this.rank);

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (rank) {
      case 1:
        color = Colors.amber;
        break;
      case 2:
        color = Colors.blueGrey;
        break;
      case 3:
        color = Colors.deepOrange;
        break;
      default:
        color = Colors.white54;
    }

    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        '$rank',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MembersEmptyState extends StatelessWidget {
  final String title;
  final String subtitle;

  const _MembersEmptyState({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.groups_outlined, size: 46, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _roleLabel(String role) {
  switch (role) {
    case 'host':
      return 'Host';
    case 'cohost':
      return 'Co-host';
    case 'moderator':
      return 'Admin';
    case 'speaker':
      return 'Speaker';
    default:
      return 'Listener';
  }
}

Color _roleColor(String role) {
  switch (role) {
    case 'host':
      return const Color(0xFFFF7A45);
    case 'cohost':
      return const Color(0xFF8C52FF);
    case 'moderator':
      return const Color(0xFF52A1FF);
    case 'speaker':
      return const Color(0xFF00D19B);
    default:
      return Colors.white54;
  }
}
