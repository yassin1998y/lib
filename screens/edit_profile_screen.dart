import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freegram/main.dart'; // For ProfileBloc
import 'package:image_picker/image_picker.dart';

// A predefined list of interests for users to choose from.
const List<String> _possibleInterests = [
  'Photography', 'Traveling', 'Hiking', 'Reading', 'Gaming', 'Cooking',
  'Movies', 'Music', 'Art', 'Sports', 'Yoga', 'Coding', 'Writing',
  'Dancing', 'Gardening', 'Fashion', 'Fitness', 'History',
];

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> currentUserData;
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
  late TextEditingController _usernameController;
  late TextEditingController _bioController;
  int? _selectedAge;
  String? _selectedCountry;
  String? _selectedGender;
  List<String> _selectedInterests = [];
  XFile? _imageFile;
  final ImagePicker _picker = ImagePicker();
  final _formKey = GlobalKey<FormState>();

  // Predefined lists for dropdown menus.
  final List<String> _countries = ['USA', 'Canada', 'UK', 'Germany', 'France', 'Tunisia', 'Egypt', 'Algeria', 'Morocco'];
  final List<String> _genders = ['Male', 'Female'];
  final List<int> _ages = List<int>.generate(83, (i) => i + 18); // Ages 18-100

  @override
  void initState() {
    super.initState();
    // Initialize form fields with the user's current data.
    _usernameController = TextEditingController(text: widget.currentUserData['username']);
    _bioController = TextEditingController(text: widget.currentUserData['bio']);
    _selectedAge = widget.currentUserData['age'] == 0 ? null : widget.currentUserData['age'];
    _selectedCountry = widget.currentUserData['country'].isEmpty ? null : widget.currentUserData['country'];
    _selectedGender = widget.currentUserData['gender'].isEmpty ? null : widget.currentUserData['gender'];
    _selectedInterests = List<String>.from(widget.currentUserData['interests'] ?? []);
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
      final XFile? pickedFile = await _picker.pickImage(source: source);
      if (pickedFile != null) {
        setState(() {
          _imageFile = pickedFile;
        });
      }
    }
  }

  /// Validates the form and dispatches an update event to the ProfileBloc.
  void _updateProfile() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Consolidate updated data into a map.
    final Map<String, dynamic> updatedData = {
      'username': _usernameController.text,
      'bio': _bioController.text,
      'age': _selectedAge,
      'country': _selectedCountry,
      'gender': _selectedGender,
      'interests': _selectedInterests,
    };

    // Dispatch the event to the BLoC.
    context.read<ProfileBloc>().add(UpdateProfile(
      userId: widget.currentUserData['uid'], // Assuming uid is passed in currentUserData
      data: updatedData,
      imageFile: _imageFile,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isCompletingProfile ? 'Complete Your Profile' : 'Edit Profile'),
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
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              return IconButton(
                icon: const Icon(Icons.check),
                onPressed: _updateProfile,
              );
            },
          ),
        ],
      ),
      // The body listens for state changes from the BLoC to show feedback.
      body: BlocListener<ProfileBloc, ProfileState>(
        listener: (context, state) {
          if (state is ProfileUpdateSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated successfully!')));
            if (!widget.isCompletingProfile) {
              Navigator.of(context).pop();
            }
          }
          if (state is ProfileError) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                if (widget.isCompletingProfile)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(
                      'Please complete your profile to continue.',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                GestureDetector(
                  onTap: _pickImage,
                  child: CircleAvatar(
                    radius: 50,
                    backgroundImage: _imageFile != null
                        ? (kIsWeb ? NetworkImage(_imageFile!.path) : FileImage(File(_imageFile!.path))) as ImageProvider?
                        : (widget.currentUserData['photoUrl'] != null && widget.currentUserData['photoUrl'].isNotEmpty
                        ? NetworkImage(widget.currentUserData['photoUrl'])
                        : null),
                    child: (_imageFile == null && (widget.currentUserData['photoUrl'] == null || widget.currentUserData['photoUrl'].isEmpty))
                        ? const Icon(Icons.camera_alt, size: 50)
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(labelText: 'Username'),
                  validator: (value) => value!.isEmpty ? 'Please enter a username' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _bioController,
                  decoration: const InputDecoration(labelText: 'Bio'),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: _selectedAge,
                  decoration: const InputDecoration(labelText: 'Age'),
                  items: _ages.map((int value) {
                    return DropdownMenuItem<int>(value: value, child: Text(value.toString()));
                  }).toList(),
                  onChanged: (newValue) {
                    setState(() {
                      _selectedAge = newValue;
                    });
                  },
                  validator: (value) => value == null ? 'Please select your age' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedCountry,
                  decoration: const InputDecoration(labelText: 'Country'),
                  items: _countries.map((String value) {
                    return DropdownMenuItem<String>(value: value, child: Text(value));
                  }).toList(),
                  onChanged: (newValue) {
                    setState(() {
                      _selectedCountry = newValue;
                    });
                  },
                  validator: (value) => value == null ? 'Please select your country' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedGender,
                  decoration: const InputDecoration(labelText: 'Gender'),
                  items: _genders.map((String value) {
                    return DropdownMenuItem<String>(value: value, child: Text(value));
                  }).toList(),
                  onChanged: (newValue) {
                    setState(() {
                      _selectedGender = newValue;
                    });
                  },
                  validator: (value) => value == null ? 'Please select your gender' : null,
                ),
                const SizedBox(height: 24),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text("Interests", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
