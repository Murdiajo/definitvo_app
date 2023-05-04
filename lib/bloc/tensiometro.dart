// import 'package:flutter_bloc/flutter_bloc.dart';
// import 'package:definitvo_app/model/bluetooth.dart';

// class TensiometroBloc extends Cubit<TensiometroState> {
//   TensiometroBloc() : super(TensiometroState());

//   void updateData(String data) {
//     // Aquí procesas los datos recibidos y actualizas el estado del BLoC
//     // ...
//     emit(state.copyWith(
//       presSistolica: presSistolicaValue,
//       presDiastolica: presDiastolicaValue,
//       pulMedio: pulMedioValue,
//     ));
//   }
// }

// class TensiometroState {
//   final String presSistolica;
//   final String presDiastolica;
//   final String pulMedio;

//   TensiometroState({
//     this.presSistolica = '',
//     this.presDiastolica = '',
//     this.pulMedio = '',
//   });

//   TensiometroState copyWith({
//     required String presSistolica,
//     required String presDiastolica,
//     required String pulMedio,
//   }) {
//     return TensiometroState(
//       presSistolica: presSistolica ?? this.presSistolica,
//       presDiastolica: presDiastolica ?? this.presDiastolica,
//       pulMedio: pulMedio ?? this.pulMedio,
//     );
//   }
// }
