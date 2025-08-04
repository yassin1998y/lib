import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freegram/blocs/profile_bloc.dart';
// No longer importing event and state directly, as they are part of profile_bloc.dart
// import 'package:freegram/blocs/profile_event.dart';
// import 'package:freegram/blocs/profile_state.dart';
import 'package:image_picker/image_picker.dart';

/// A predefined list of interests for users to choose from.
/// This keeps the available options consistent across the app.
const List<String> _possibleInterests = [
  'Photography', 'Traveling', 'Hiking', 'Reading', 'Gaming', 'Cooking',
  'Movies', 'Music', 'Art', 'Sports', 'Yoga', 'Coding', 'Writing',
  'Dancing', 'Gardening', 'Fashion', 'Fitness', 'History',
];

class EditProfileScreen extends StatefulWidget {
  /// The user's current profile data, passed from the profile screen or wrapper.
  final Map<String, dynamic> currentUserData;

  /// A flag to indicate if the user is completing their profile for the first time.
  /// This changes the UI text and behavior slightly (e.g., hiding the back button).
  final bool isCompletingProfile;

  const EditProfileScreen({
    super.key,
    required this.currentUserData,
    this.isCompletingProfile = false,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  // Form key for validation
  final _formKey = GlobalKey<FormState>();

  // Controllers for text fields
  late TextEditingController _usernameController;
  late TextEditingController _bioController;

  // State variables for dropdowns and multi-select chips
  int? _selectedAge;
  String? _selectedCountry;
  String? _selectedGender;
  List<String> _selectedInterests = [];

  // State variable for the selected profile image file
  XFile? _imageFile;
  final ImagePicker _picker = ImagePicker();

  // Predefined lists for dropdown menus to ensure valid data.
  final List<String> _countries = ['USA', 'Canada', 'UK', 'Germany', 'France', 'Tunisia', 'Egypt', 'Algeria', 'Morocco'];
  final List<String> _genders = ['Male', 'Female', 'Other'];
  final List<int> _ages = List<int>.generate(83, (i) => i + 18); // Ages 18-100

  @override
  void initState() {
    super.initState();
    // Initialize form fields with the user's existing data from the widget.
    _usernameController = TextEditingController(text: widget.currentUserData['username']);
    _bioController = TextEditingController(text: widget.currentUserData['bio']);
    // Handle cases where numeric or string data might be null or empty from Firestore.
    _selectedAge = widget.currentUserData['age'] == 0 ? null : widget.currentUserData['age'];
    _selectedCountry = widget.currentUserData['country']?.isEmpty ?? true ? null : widget.currentUserData['country'];
    _selectedGender = widget.currentUserData['gender']?.isEmpty ?? true ? null : widget.currentUserData['gender'];
    _selectedInterests = List<String>.from(widget.currentUserData['interests'] ?? []);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  /// Shows a bottom sheet for the user to pick an image from the camera or gallery.
  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source != null) {
      final XFile? pickedFile = await _picker.pickImage(source: source, imageQuality: 80);
      if (pickedFile != null) {
        setState(() {
          _imageFile = pickedFile;
        });
      }
    }
  }

  /// Validates the form and dispatches an update event to the ProfileBloc.
  void _updateProfile() {
    // First, validate the form. If it's not valid, do nothing.
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: You are not logged in.')));
      return;
    }

    // Consolidate all the updated data into a map.
    final Map<String, dynamic> updatedData = {
      'username': _usernameController.text.trim(),
      'bio': _bioController.text.trim(),
      'age': _selectedAge,
      'country': _selectedCountry,
      'gender': _selectedGender,
      'interests': _selectedInterests,
    };

    // Dispatch the correct event to the ProfileBloc with the required data.
    context.read<ProfileBloc>().add(ProfileUpdateEvent(
      userId: currentUser.uid,
      updatedData: updatedData,
      imageFile: _imageFile,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isCompletingProfile ? 'Complete Your Profile' : 'Edit Profile'),
        // Prevent the user from going back if they are in the profile completion flow.
        automaticallyImplyLeading: !widget.isCompletingProfile,
        actions: [
          // The save button shows a loading indicator while the profile is updating.
          BlocBuilder<ProfileBloc, ProfileState>(
            builder: (context, state) {
              if (state is ProfileLoading) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue),
                  ),
                );
              }
              return IconButton(
                icon: const Icon(Icons.check, color: Colors.blue),
                onPressed: _updateProfile,
                tooltip: 'Save Changes',
              );
            },
          ),
        ],
      ),
      // The body listens for state changes from the BLoC to show feedback (e.g., success/error SnackBars).
      body: BlocListener<ProfileBloc, ProfileState>(
        listener: (context, state) {
          if (state is ProfileUpdateSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Profile updated successfully!'),
                backgroundColor: Colors.green,
              ),
            );
            // If not in the completion flow, pop the screen to return to the profile.
            if (!widget.isCompletingProfile && Navigator.canPop(context)) {
              Navigator.of(context).pop();
            }
            // If completing profile, the AuthWrapper will rebuild and navigate automatically.
          }
          if (state is ProfileError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: ${state.message}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Informational text shown only during initial profile setup.
                if (widget.isCompletingProfile)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24.0),
                    child: Text(
                      'Welcome! Please provide a few more details to get started.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.black54),
                    ),
                  ),

                // --- Profile Image Picker ---
                GestureDetector(
                  onTap: _pickImage,
                  child: CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: _imageFile != null
                        ? (kIsWeb ? NetworkImage(_imageFile!.path) : FileImage(File(_imageFile!.path))) as ImageProvider
                        : (widget.currentUserData['photoUrl'] != null && widget.currentUserData['photoUrl'].isNotEmpty
                        ? NetworkImage(widget.currentUserData['photoUrl'])
                        : null),
                    child: _imageFile == null && (widget.currentUserData['photoUrl'] == null || widget.currentUserData['photoUrl'].isEmpty)
                        ? Icon(Icons.camera_alt, size: 60, color: Colors.grey[400])
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                const Text("Tap to change photo", style: TextStyle(color: Colors.blue)),
                const SizedBox(height: 24),

                // --- Form Fields ---
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder()),
                  validator: (value) => value == null || value.trim().isEmpty ? 'Please enter a username' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _bioController,
                  decoration: const InputDecoration(labelText: 'Bio', border: OutlineInputBorder()),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: _selectedAge,
                  decoration: const InputDecoration(labelText: 'Age', border: OutlineInputBorder()),
                  items: _ages.map((int value) => DropdownMenuItem<int>(value: value, child: Text(value.toString()))).toList(),
                  onChanged: (newValue) => setState(() => _selectedAge = newValue),
                  validator: (value) => value == null ? 'Please select your age' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedCountry,
                  decoration: const InputDecoration(labelText: 'Country', border: OutlineInputBorder()),
                  items: _countries.map((String value) => DropdownMenuItem<String>(value: value, child: Text(value))).toList(),
                  onChanged: (newValue) => setState(() => _selectedCountry = newValue),
                  validator: (value) => value == null ? 'Please select your country' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedGender,
                  decoration: const InputDecoration(labelText: 'Gender', border: OutlineInputBorder()),
                  items: _genders.map((String value) => DropdownMenuItem<String>(value: value, child: Text(value))).toList(),
                  onChanged: (newValue) => setState(() => _selectedGender = newValue),
                  validator: (value) => value == null ? 'Please select your gender' : null,
                ),
                const SizedBox(height: 24),

                // --- Interests Section ---
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text("Your Interests", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 8),
                // The multi-select chip group for interests.
                Wrap(
                  spacing: 8.0,
                  runSpacing: 4.0,
                  children: _possibleInterests.map((interest) {
                    final isSelected = _selectedInterests.contains(interest);
                    return FilterChip(
                      label: Text(interest),
                      selected: isSelected,
                      selectedColor: const Color.fromARGB(255, 199, 226, 248),
                      checkmarkColor: Colors.blue,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedInterests.add(interest);
                          } else {
                            _selectedInterests.remove(interest);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
