import 'dart:convert';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:freegram/repositories/user_repository.dart'; // UPDATED
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:meta/meta.dart';

part 'profile_event.dart';
part 'profile_state.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  // UPDATED: Now uses UserRepository
  final UserRepository _userRepository;
  final FirebaseAuth _firebaseAuth;

  ProfileBloc({
    required UserRepository userRepository, // UPDATED
    FirebaseAuth? firebaseAuth,
  })  : _userRepository = userRepository, // UPDATED
        _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        super(ProfileInitial()) {
    on<ProfileUpdateEvent>(_onUpdateProfile);
  }

  /// Handles the logic for updating a user's profile.
  Future<void> _onUpdateProfile(
      ProfileUpdateEvent event,
      Emitter<ProfileState> emit,
      ) async {
    emit(ProfileLoading());
    try {
      Map<String, dynamic> dataToUpdate = Map.from(event.updatedData);

      if (event.imageFile != null) {
        final imageUrl = await _uploadToCloudinary(event.imageFile!);
        if (imageUrl != null) {
          dataToUpdate['photoUrl'] = imageUrl;
        } else {
          throw Exception('Image upload failed');
        }
      }

      // UPDATED: Calls the method on the new repository
      await _userRepository.updateUser(event.userId, dataToUpdate);

      final currentUser = _firebaseAuth.currentUser;
      if (currentUser != null && currentUser.uid == event.userId) {
        if (dataToUpdate.containsKey('username')) {
          await currentUser.updateDisplayName(dataToUpdate['username']);
        }
        if (dataToUpdate.containsKey('photoUrl')) {
          await currentUser.updatePhotoURL(dataToUpdate['photoUrl']);
        }
      }

      emit(ProfileUpdateSuccess());
    } catch (e) {
      emit(ProfileError(e.toString()));
    }
  }

  /// Uploads an image to Cloudinary and returns the secure URL.
  Future<String?> _uploadToCloudinary(XFile image) async {
    final url = Uri.parse('https://api.cloudinary.com/v1_1/dq0mb16fk/image/upload');
    final request = http.MultipartRequest('POST', url)
      ..fields['upload_preset'] = 'Prototype';
    final bytes = await image.readAsBytes();
    final multipartFile = http.MultipartFile.fromBytes('file', bytes, filename: image.name);
    request.files.add(multipartFile);
    final response = await request.send();
    if (response.statusCode == 200) {
      final responseData = await response.stream.toBytes();
      final responseString = String.fromCharCodes(responseData);
      final jsonMap = jsonDecode(responseString);
      return jsonMap['secure_url'];
    }
    return null;
  }
}
