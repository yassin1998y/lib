import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:freegram/screens/edit_profile_screen.dart';
import 'package:freegram/screens/profile_screen.dart';
import 'package:freegram/services/firestore_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

// A predefined list of interests for the filter sheet.
const List<String> _possibleInterests = [
  'Photography', 'Traveling', 'Hiking', 'Reading', 'Gaming', 'Cooking',
  'Movies', 'Music', 'Art', 'Sports', 'Yoga', 'Coding', 'Writing',
  'Dancing', 'Gardening', 'Fashion', 'Fitness', 'History',
];

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});
  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 0,
        backgroundColor: Colors.white,
        elevation: 1,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.black,
          tabs: const [Tab(text: 'For You'), Tab(text: 'Explore')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [ForYouTab(), ExploreTab()],
      ),
    );
  }
}

// --- Explore Tab ---
class ExploreTab extends StatefulWidget {
  const ExploreTab({super.key});
  @override
  State<ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends State<ExploreTab> {
  final _scrollController = ScrollController();
  List<DocumentSnapshot> _allUsers = [];
  List<DocumentSnapshot> _filteredUsers = [];
  bool _isLoading = false;
  bool _isFetchingMore = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  final int _documentLimit = 25; // Increased limit for 5 columns

  // State for filters
  String _searchQuery = '';
  String? _selectedCountry;
  RangeValues _ageRange = const RangeValues(18, 80);
  String _genderFilter = 'All';
  List<String> _selectedInterests = [];
  bool _showNearbyOnly = false;

  final List<String> _countries = ['All', 'USA', 'Canada', 'UK', 'Germany', 'France', 'Tunisia', 'Egypt', 'Algeria', 'Morocco'];

  @override
  void initState() {
    super.initState();
    _getUsers();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 300 && !_isFetchingMore) {
        _getUsers();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Fetches a paginated list of users from the FirestoreService.
  Future<void> _getUsers({bool isRefresh = false}) async {
    if (_isFetchingMore || _showNearbyOnly) return;
    if (isRefresh) {
      _allUsers = [];
      _lastDocument = null;
      _hasMore = true;
    }
    if (!_hasMore) return;

    setState(() {
      _isFetchingMore = true;
      if (_allUsers.isEmpty) _isLoading = true;
    });

    try {
      final querySnapshot = await context.read<FirestoreService>().getPaginatedUsers(
        limit: _documentLimit,
        lastDocument: _lastDocument,
      );

      if (querySnapshot.docs.length < _documentLimit) _hasMore = false;
      if (querySnapshot.docs.isNotEmpty) {
        _lastDocument = querySnapshot.docs.last;
        _allUsers.addAll(querySnapshot.docs);
      }
      _applyFilters();
    } catch (e) {
      debugPrint("Error fetching users: $e");
    }

    if (mounted) setState(() { _isFetchingMore = false; _isLoading = false; });
  }

  /// Fetches users found via Bluetooth from the local Hive cache.
  Future<void> _getNearbyUsers() async {
    setState(() => _isLoading = true);
    final nearbyBox = Hive.box('nearby_contacts');
    final profileBox = Hive.box('user_profiles');
    List<DocumentSnapshot> nearbyUsers = [];

    for (var key in nearbyBox.keys) {
      final profileData = profileBox.get(key);
      if (profileData != null) {
        nearbyUsers.add(MockDocumentSnapshot(key, Map<String, dynamic>.from(profileData)));
      } else {
        try {
          final doc = await context.read<FirestoreService>().getUser(key);
          if (doc.exists) {
            profileBox.put(key, doc.data());
            nearbyUsers.add(doc);
          }
        } catch (e) {
          debugPrint("Could not fetch nearby user profile: $e");
        }
      }
    }

    _allUsers = nearbyUsers;
    _applyFilters();
    setState(() => _isLoading = false);
  }

  /// Applies the current filter criteria to the list of users.
  void _applyFilters() {
    List<DocumentSnapshot> tempFiltered = List.from(_allUsers);
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    tempFiltered = tempFiltered.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      if (doc.id == currentUserId) return false;

      final userAge = data['age'] as int? ?? 0;
      final userGender = data['gender'] as String? ?? '';
      final userCountry = data['country'] as String? ?? '';
      final username = data['username'] as String? ?? '';
      final userInterests = List<String>.from(data['interests'] ?? []);

      if (_searchQuery.isNotEmpty && !username.toLowerCase().contains(_searchQuery.toLowerCase())) return false;
      if (_selectedCountry != null && _selectedCountry != 'All' && userCountry != _selectedCountry) return false;
      if (userAge < _ageRange.start || userAge > _ageRange.end) return false;
      if (_genderFilter != 'All' && userGender != _genderFilter) return false;
      if (_selectedInterests.isNotEmpty && !_selectedInterests.any((interest) => userInterests.contains(interest))) return false;
      return true;
    }).toList();

    // Sort by online status
    tempFiltered.sort((a, b) {
      final aPresence = (a.data() as Map<String, dynamic>)['presence'] ?? false;
      final bPresence = (b.data() as Map<String, dynamic>)['presence'] ?? false;
      if (aPresence && !bPresence) return -1;
      if (!aPresence && bPresence) return 1;
      return 0;
    });

    if (mounted) setState(() => _filteredUsers = tempFiltered);
  }

  /// Reloads user data when filters are changed.
  void _onFilterChanged() {
    if (_showNearbyOnly) {
      _getNearbyUsers();
    } else {
      _getUsers(isRefresh: true);
    }
  }

  /// Shows the filter selection bottom sheet.
  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.8,
              builder: (_, scrollController) => Container(
                padding: const EdgeInsets.all(16.0),
                child: ListView(
                  controller: scrollController,
                  children: [
                    Text('Filters', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    SwitchListTile(title: const Text('Show only nearby users'), value: _showNearbyOnly, onChanged: (val) => setModalState(() => _showNearbyOnly = val)),
                    const Divider(),
                    DropdownButtonFormField<String>(
                      value: _selectedCountry ?? 'All',
                      decoration: const InputDecoration(labelText: 'Country', border: OutlineInputBorder()),
                      items: _countries.map((String value) => DropdownMenuItem<String>(value: value, child: Text(value))).toList(),
                      onChanged: (newValue) => setModalState(() => _selectedCountry = newValue == 'All' ? null : newValue),
                    ),
                    const SizedBox(height: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Age Range: ${_ageRange.start.round()} - ${_ageRange.end.round()}'),
                        RangeSlider(
                          values: _ageRange, min: 13, max: 100, divisions: 87,
                          labels: RangeLabels(_ageRange.start.round().toString(), _ageRange.end.round().toString()),
                          onChanged: (RangeValues values) => setModalState(() => _ageRange = values),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Gender'),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: ['All', 'Male', 'Female'].map((gender) => ChoiceChip(
                        label: Text(gender),
                        selected: _genderFilter == gender,
                        onSelected: (selected) { if (selected) setModalState(() => _genderFilter = gender); },
                      )).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text('Interests'),
                    Wrap(
                      spacing: 8.0, runSpacing: 4.0,
                      children: _possibleInterests.map((interest) {
                        final isSelected = _selectedInterests.contains(interest);
                        return FilterChip(
                          label: Text(interest), selected: isSelected,
                          onSelected: (selected) => setModalState(() => selected ? _selectedInterests.add(interest) : _selectedInterests.remove(interest)),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        child: const Text('Apply Filters'),
                        onPressed: () { _onFilterChanged(); Navigator.pop(context); },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(hintText: 'Search by username...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  onChanged: (value) { _searchQuery = value; _applyFilters(); },
                ),
              ),
              IconButton(icon: const Icon(Icons.filter_list), onPressed: _showFilterSheet),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const UserGridSkeleton(crossAxisCount: 5)
              : RefreshIndicator(
            onRefresh: () => _getUsers(isRefresh: true),
            child: _filteredUsers.isEmpty
                ? const Center(child: Text("No users found. Try adjusting your filters."))
                : GridView.builder(
              controller: _scrollController,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, childAspectRatio: 0.8, crossAxisSpacing: 2, mainAxisSpacing: 2),
              itemCount: _filteredUsers.length + (_hasMore && !_showNearbyOnly ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _filteredUsers.length) return const Center(child: CircularProgressIndicator());
                final user = _filteredUsers[index];
                return CompactUserCard(userDoc: user);
              },
            ),
          ),
        ),
      ],
    );
  }
}

// --- For You Tab ---
class ForYouTab extends StatefulWidget {
  const ForYouTab({super.key});
  @override
  State<ForYouTab> createState() => _ForYouTabState();
}

class _ForYouTabState extends State<ForYouTab> {
  List<DocumentSnapshot>? _recommendedUsers;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRecommendedUsers();
  }

  /// Fetches a list of recommended users based on shared interests.
  Future<void> _fetchRecommendedUsers() async {
    setState(() => _isLoading = true);
    final currentUser = FirebaseAuth.instance.currentUser!;
    try {
      final userDoc = await context.read<FirestoreService>().getUser(currentUser.uid);
      final userData = userDoc.data() as Map<String, dynamic>;
      final List<String> myInterests = List<String>.from(userData['interests'] ?? []);

      if (myInterests.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final users = await context.read<FirestoreService>().getRecommendedUsers(myInterests, currentUser.uid);
      // Sort by number of shared interests
      users.sort((a, b) {
        final aInterests = List<String>.from((a.data() as Map<String, dynamic>)['interests'] ?? []);
        final bInterests = List<String>.from((b.data() as Map<String, dynamic>)['interests'] ?? []);
        final aShared = aInterests.where((i) => myInterests.contains(i)).length;
        final bShared = bInterests.where((i) => myInterests.contains(i)).length;
        return bShared.compareTo(aShared);
      });

      if (mounted) setState(() { _recommendedUsers = users; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint("Error fetching recommendations: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const UserGridSkeleton(crossAxisCount: 5);
    }

    if (_recommendedUsers == null || _recommendedUsers!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Add interests to your profile to get personalized recommendations!", textAlign: TextAlign.center),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () async {
                  final currentUser = FirebaseAuth.instance.currentUser!;
                  final userDoc = await context.read<FirestoreService>().getUser(currentUser.uid);
                  if (userDoc.exists && mounted) {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => EditProfileScreen(currentUserData: userDoc.data() as Map<String, dynamic>),
                    ));
                  }
                },
                child: const Text('Edit Profile'),
              )
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchRecommendedUsers,
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, childAspectRatio: 0.8, crossAxisSpacing: 2, mainAxisSpacing: 2),
        itemCount: _recommendedUsers!.length,
        itemBuilder: (context, index) {
          final user = _recommendedUsers![index];
          return CompactUserCard(userDoc: user);
        },
      ),
    );
  }
}

/// A compact card for displaying a user in a grid.
class CompactUserCard extends StatelessWidget {
  final DocumentSnapshot userDoc;
  const CompactUserCard({super.key, required this.userDoc});

  @override
  Widget build(BuildContext context) {
    final userData = userDoc.data() as Map<String, dynamic>;
    final userId = userDoc.id;
    final photoUrl = userData['photoUrl'];
    final username = userData['username'] ?? 'User';
    final isOnline = userData['presence'] ?? false;

    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          isScrollControlled: true,
          builder: (_) => UserInfoPopup(userId: userId),
        );
      },
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: GridTile(
          footer: Container(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            color: Colors.black.withOpacity(0.5),
            child: Text(
              username,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (photoUrl != null && photoUrl.isNotEmpty)
                Image.network(
                  photoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.person, size: 40, color: Colors.grey),
                )
              else
                const Icon(Icons.person, size: 40, color: Colors.grey),
              if (isOnline)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    height: 8,
                    width: 8,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A skeleton loader for the user grids.
class UserGridSkeleton extends StatelessWidget {
  final int crossAxisCount;
  const UserGridSkeleton({super.key, this.crossAxisCount = 3});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: crossAxisCount, crossAxisSpacing: 4, mainAxisSpacing: 4),
        itemCount: 15,
        itemBuilder: (context, index) => Card(clipBehavior: Clip.antiAlias, child: Container(color: Colors.white)),
      ),
    );
  }
}

/// A popup that shows a summary of a user's profile.
class UserInfoPopup extends StatelessWidget {
  final String userId;
  const UserInfoPopup({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, scrollController) => StreamBuilder<DocumentSnapshot>(
        stream: context.read<FirestoreService>().getUserStream(userId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final userData = snapshot.data!.data() as Map<String, dynamic>;
          final username = userData['username'] ?? 'User';
          final photoUrl = userData['photoUrl'] ?? '';
          final country = userData['country'] ?? 'Not specified';
          final age = userData['age'] ?? 0;
          final bio = userData['bio'] ?? 'No bio yet.';
          final interests = List<String>.from(userData['interests'] ?? []);

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            child: ListView(
              controller: scrollController,
              children: [
                const SizedBox(height: 12),
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),
                CircleAvatar(
                  radius: 40,
                  backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                  child: photoUrl.isEmpty ? Text(username.isNotEmpty ? username[0].toUpperCase() : '?', style: const TextStyle(fontSize: 40)) : null,
                ),
                const SizedBox(height: 12),
                Text('$username, $age', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                Text(country, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.grey)),
                const SizedBox(height: 16),
                Text(bio, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 16),
                if (interests.isNotEmpty)
                  Wrap(
                    spacing: 8.0, runSpacing: 4.0, alignment: WrapAlignment.center,
                    children: interests.map((interest) => Chip(label: Text(interest), backgroundColor: Colors.blue.withOpacity(0.1), labelStyle: const TextStyle(color: Colors.blue))).toList(),
                  ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () { Navigator.pop(context); Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId))); },
                        child: const Text('View Profile'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => context.read<FirestoreService>().startChat(context, userId, username),
                        child: const Text('Message'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Mock DocumentSnapshot for displaying Hive data in the same UI as Firestore data.
class MockDocumentSnapshot implements DocumentSnapshot {
  final String _id;
  final Map<String, dynamic> _data;
  MockDocumentSnapshot(this._id, this._data);
  @override
  dynamic operator [](Object field) => _data[field];
  @override
  dynamic get(Object field) {
    if (_data.containsKey(field)) return _data[field];
    throw StateError('Field does not exist in mock snapshot');
  }
  @override
  Map<String, dynamic> data() => _data;
  @override
  String get id => _id;
  @override
  bool get exists => true;
  @override
  SnapshotMetadata get metadata => throw UnimplementedError();
  @override
  DocumentReference<Object?> get reference => throw UnimplementedError();
}
