// lib/bloc/profile_bloc.dart

import 'dart:convert';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../services/firestore_service.dart';

// --- EVENTS ---
abstract class ProfileEvent extends Equatable {
  const ProfileEvent();
  @override
  List<Object?> get props => [];
}

class UpdateProfile extends ProfileEvent {
  final String userId;
  final Map<String, dynamic> updatedData;
  final XFile? imageFile;

  const UpdateProfile({required this.userId, required this.updatedData, this.imageFile});

  @override
  List<Object?> get props => [userId, updatedData, imageFile];
}

// --- STATES ---
abstract class ProfileState extends Equatable {
  const ProfileState();
  @override
  List<Object> get props => [];
}

class ProfileInitial extends ProfileState {}
class ProfileLoading extends ProfileState {}
class ProfileSuccess extends ProfileState {}
class ProfileError extends ProfileState {
  final String message;
  const ProfileError(this.message);
  @override
  List<Object> get props => [message];
}

// --- BLoC ---
class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final FirestoreService _firestoreService;

  ProfileBloc(this._firestoreService) : super(ProfileInitial()) {
    on<UpdateProfile>(_onUpdateProfile);
  }

  Future<void> _onUpdateProfile(UpdateProfile event, Emitter<ProfileState> emit) async {
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
      await _firestoreService.updateUser(event.userId, dataToUpdate);
      emit(ProfileSuccess());
    } catch (e) {
      emit(ProfileError(e.toString()));
    }
  }

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
