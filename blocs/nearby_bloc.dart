// **FIX**: Corrected the import from 'dart.async' to 'dart:async'.
import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:freegram/services/bluetooth_service.dart';
import 'package:hive/hive.dart';
import 'package:meta/meta.dart';

part 'nearby_event.dart';
part 'nearby_state.dart';

class NearbyBloc extends Bloc<NearbyEvent, NearbyState> {
  final BluetoothService _bluetoothService;
  StreamSubscription? _statusSubscription;
  final Box _contactsBox;

  bool _servicesShouldBeActive = false;

  NearbyBloc({required BluetoothService bluetoothService})
      : _bluetoothService = bluetoothService,
        _contactsBox = Hive.box('nearby_contacts'),
        super(NearbyInitial()) {
    _bluetoothService.start();
    _statusSubscription = BluetoothStatusService().statusStream.listen((status) {
      add(_NearbyStatusUpdated(status));
    });

    on<StartNearbyServices>(_onStartServices);
    on<StopNearbyServices>(_onStopServices);
    on<_NearbyStatusUpdated>(_onStatusUpdated);
  }

  void _onStartServices(StartNearbyServices event, Emitter<NearbyState> emit) {
    _servicesShouldBeActive = true;
    _bluetoothService.startScanning();
    _bluetoothService.startAdvertising();
    emit(NearbyActive(
      foundUserIds: _contactsBox.keys.cast<String>().toList(),
      status: NearbyStatus.scanning,
    ));
  }

  void _onStopServices(StopNearbyServices event, Emitter<NearbyState> emit) {
    _servicesShouldBeActive = false;
    _bluetoothService.stopScanning();
    _bluetoothService.stopAdvertising();
    emit(NearbyInitial());
  }

  void _onStatusUpdated(_NearbyStatusUpdated event, Emitter<NearbyState> emit) {
    if (event.status == NearbyStatus.adapterOff) {
      add(StopNearbyServices());
      return;
    }

    if (event.status == NearbyStatus.idle && _servicesShouldBeActive) {
      add(StartNearbyServices());
      return;
    }

    if (state is NearbyActive) {
      emit(NearbyActive(foundUserIds: _lastKnownUserIds(), status: event.status));
    }

    if (event.status == NearbyStatus.error) {
      emit(const NearbyError("A Bluetooth error occurred."));
    }
  }

  List<String> _lastKnownUserIds() {
    if (state is NearbyActive) {
      return (state as NearbyActive).foundUserIds;
    }
    return _contactsBox.keys.cast<String>().toList();
  }

  @override
  Future<void> close() {
    _statusSubscription?.cancel();
    _bluetoothService.dispose();
    return super.close();
  }
}
