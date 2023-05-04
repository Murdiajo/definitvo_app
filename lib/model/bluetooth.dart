import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/flutter_blue.dart';

class FlutterBleApp extends StatefulWidget {
  const FlutterBleApp({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  // ignore: library_private_types_in_public_api
  _FlutterBleAppState createState() => _FlutterBleAppState();
}

class _FlutterBleAppState extends State<FlutterBleApp> {
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  /// Device
  BluetoothDevice? device;
  FlutterBluePlus flutterBlue = FlutterBluePlus.instance;

  /// Scanning
  StreamSubscription? _scanSubscription;
  Map<DeviceIdentifier, ScanResult> scanResults = {};
  bool isScanning = false;

  /// State
  StreamSubscription? _stateSubscription;
  BluetoothState state = BluetoothState.unknown;

  // inicializa el campo "device" con un valor predeterminado

  bool get isConnected => (device != null);
  StreamSubscription? deviceConnection;
  StreamSubscription? deviceStateSubscription;
  List<BluetoothService> services = [];
  Map<Guid, StreamSubscription> valueChangedSubscriptions = {};
  BluetoothDeviceState deviceState = BluetoothDeviceState.disconnected;

  static const String CHARACTERISTIC_UUID =
      '00002A35-0000-1000-8000-00805f9b34fb';
  static const String SYSTOLIC_PRESSURE_CHARACTERISTIC_UUID =
      '00002A7A-0000-1000-8000-00805f9b34fb';
  static const String DIASTOLIC_PRESSURE_CHARACTERISTIC_UUID =
      '00002A7B-0000-1000-8000-00805f9b34fb';
  static const String HEART_RATE_SERVICE_UUID =
      '0000180D-0000-1000-8000-00805f9b34fb';
  static const String HEART_RATE_MEASUREMENT_CHARACTERISTIC_UUID =
      '00002A37-0000-1000-8000-00805f9b34fb';

  static const String kMYDEVICE = 'myDevice';
  String? _myDeviceId;
  int? _presSistolica;
  int? _presDiastolica;
  int? _pulMedio;

  @override
  void initState() {
    super.initState();
    //Obtener inmediatamente el estado de FlutterBle
    flutterBlue.state.listen((s) {
      setState(() {
        state = s;
      });
    });
    // Subscribe to state changes
    _stateSubscription = flutterBlue.state.listen((s) {
      setState(() {
        state = s;
      });
      //print('State updated: $state');
    });

    _loadMyDeviceId();
  }

  //Para cargar el ID de un dispositivo
  _loadMyDeviceId() async {
    SharedPreferences prefs = await _prefs;
    _myDeviceId = prefs.getString(kMYDEVICE) ?? '';

    if (_myDeviceId!.isNotEmpty) {
      _startScan();
    }
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _scanSubscription?.cancel();
    deviceConnection?.cancel();
    super.dispose();
  }

  _startScan() {
    _scanSubscription = flutterBlue
        .scan(
      timeout: const Duration(seconds: 5),
    )
        .listen((scanResult) {
      // print('localName: ${scanResult.advertisementData.localName}');
      // print(
      //     'manufacturerData: ${scanResult.advertisementData.manufacturerData}');
      // print('serviceData: ${scanResult.advertisementData.serviceData}');

      if (_myDeviceId == scanResult.device.id.toString()) {
        _stopScan();
        _connect(scanResult.device);
      }

      setState(() {
        scanResults[scanResult.device.id] = scanResult;
      });
    }, onDone: _stopScan);

    setState(() {
      isScanning = true;
    });
  }

  _stopScan() {
    _scanSubscription?.cancel();
    //_scanSubscription = null;
    setState(() {
      isScanning = false;
    });
  }

  //CONECTAR AL DISPOSITIVO
  _connect(BluetoothDevice d) async {
    device = d;
    // Connect to device
    //ESTABELCIENDO EL TIEMPO DE ESPERA DE 4 SEGUNDOS PARA CONECTAR AL DISPOSITIVO
    await device!.connect(timeout: const Duration(seconds: 4));

    deviceConnection = device!.state.listen(null, onDone: _disconnect);

    // Update the connection state immediately
    device!.state.listen((s) {
      setState(() {
        deviceState = s;
      });
    });

    // Subscribe to connection changes
    deviceStateSubscription = device!.state.listen((s) async {
      setState(() {
        deviceState = s;
      });
      if (s == BluetoothDeviceState.connected) {
        services = await device!.discoverServices();
        setState(() {
          print('*** device.id : ${device!.id.toString()}');
          _restoreDeviceId(device!.id.toString());
          turnOnCharacterService();
        });
      }
    });
  }

  //DESCONECTAR AL DISPOSITIVO
  _disconnect() {
    // Remove all value changed listeners
    valueChangedSubscriptions.forEach((uuid, sub) => sub.cancel());
    valueChangedSubscriptions.clear();
    deviceStateSubscription?.cancel();
    deviceConnection?.cancel();
    setState(() {
      device;
    });
  }

  //LECTURA Y ESCRITURA DEL DISPOSITIVO
  _readCharacteristic(BluetoothCharacteristic c) async {
    List<int> value = await c.read();
    print('Value: $value');
    setState(() {});
  }

  _writeCharacteristic(BluetoothCharacteristic c) async {
    await c.write([0x12, 0x34]);
    setState(() {});
  }

  _readDescriptor(BluetoothDescriptor d) async {
    List<int> value = await d.read();
    print('Value: $value');
    setState(() {});
  }

  _writeDescriptor(BluetoothDescriptor d) async {
    await d.write([0x12, 0x34]);
    setState(() {});
  }

  //DEFINIENDO EL _setNotification
  _setNotification(BluetoothCharacteristic c) async {
    if (c.isNotifying) {
      await c.setNotifyValue(false);
      // Cancel subscription
      valueChangedSubscriptions[c.uuid]?.cancel();
      valueChangedSubscriptions.remove(c.uuid);
    } else {
      await c.setNotifyValue(true);
      // ignore: cancel_subscriptions
      final sub = c.value.listen((d) {
        final decoded = utf8.decode(d);
        dataParser(decoded as Uint8List);
      });

      // Add to map
      valueChangedSubscriptions[c.uuid] = sub;
    }
    setState(() {});
  }

  // DEFINE EL METODO _readPressureValues
  _readPressureValues(BluetoothCharacteristic characteristic) async {
    if (characteristic.properties.read) {
      final List<int> value = await characteristic.read();
      if (value.isNotEmpty) {
        final int pressureValue = value[0] + (value[1] << 8);
        print('Presión arterial: $pressureValue');
      }
    }
  }

  //DEFINE EL METODO _readheartratemeasurement
  _readHeartRateMeasurement(BluetoothCharacteristic characteristic) async {
    if (characteristic.properties.read) {
      final List<int> value = await characteristic.read();
      if (value.isNotEmpty) {
        final int heartRate = value[1];
        print('Heart Rate: $heartRate');
      }
    }
  }

  _refreshDeviceState(BluetoothDevice d) async {
    var state = await d.state.first;
    setState(() {
      deviceState = state;
      print('State refreshed: $deviceState');
    });
  }

  _buildScanningButton() {
    if (isConnected || state != BluetoothState.on) {
      return null;
    }
    if (isScanning) {
      return FloatingActionButton(
        onPressed: _stopScan,
        backgroundColor: Colors.red,
        child: const Icon(Icons.stop),
      );
    } else {
      return FloatingActionButton(
          onPressed: _startScan, child: const Icon(Icons.search));
    }
  }

  _buildScanResultTiles() {
    return scanResults.values
        .map(
          (r) => ScanResultTile(
            result: r,
            onTap: () => _connect(r.device),
          ),
        )
        .toList();
  }

  List<Widget> _buildServiceTiles() {
    return services
        .map(
          (s) => ServiceTile(
            service: s,
            characteristicTiles: s.characteristics
                .map(
                  (c) => CharacteristicTile(
                    characteristic: c,
                    onReadPressed: () => _readCharacteristic(c),
                    onWritePressed: () => _writeCharacteristic(c),
                    onNotificationPressed: () => _setNotification(c),
                    descriptorTiles: c.descriptors
                        .map(
                          (d) => DescriptorTile(
                            descriptor: d,
                            onReadPressed: () => _readDescriptor(d),
                            onWritePressed: () => _writeDescriptor(d),
                          ),
                        )
                        .toList(),
                  ),
                )
                .toList(),
          ),
        )
        .toList();
  }

  _buildActionButtons() {
    if (isConnected) {
      return <Widget>[
        IconButton(
          icon: const Icon(Icons.cancel),
          onPressed: () => _disconnect(),
        ),
      ];
    }
  }

  _buildAlertTile() {
    return Container(
      color: Colors.redAccent,
      child: ListTile(
        title: Text(
          'Bluetooth adapter is ${state.toString().substring(15)}',
          style: Theme.of(context).primaryTextTheme.titleMedium,
        ),
        trailing: Icon(
          Icons.error,
          color: Theme.of(context).primaryTextTheme.titleMedium?.color,
        ),
      ),
    );
  }

  _buildDeviceStateTile() {
    return ListTile(
        leading: (deviceState == BluetoothDeviceState.connected)
            ? const Icon(Icons.bluetooth_connected)
            : const Icon(Icons.bluetooth_disabled),
        title: Text('Device is ${deviceState.toString().split('.')[1]}.'),
        subtitle: Text('${device!.id}'),
        trailing: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => _refreshDeviceState(device!),
          color: Theme.of(context).iconTheme.color?.withOpacity(0.5),
        ));
  }

  _buildProgressBarTile() {
    return const LinearProgressIndicator();
  }

  @override
  Widget build(BuildContext context) {
    var tiles = <Widget>[];
    if (state != BluetoothState.on) {
      tiles.add(_buildAlertTile());
    }
    if (isConnected) {
      // tiles.add(_buildDeviceStateTile());
      // tiles.addAll(_buildServiceTiles());
    } else {
      tiles.addAll(_buildScanResultTiles());
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Dispositivo BEURER APP'),
          actions: _buildActionButtons(),
          backgroundColor: Colors.blueGrey,
          centerTitle: true,
        ),
        backgroundColor: Colors.greenAccent.shade100,
        floatingActionButton: _buildScanningButton(),
        body: Stack(
          children: <Widget>[
            (isScanning) ? _buildProgressBarTile() : Container(),
            isConnected
                ? _buildMyWidget()
                : ListView(
                    children: tiles,
                  )
          ],
        ),
      ),
    );
  }

  Future<void> _restoreDeviceId(String id) async {
    final SharedPreferences prefs = await _prefs;
    prefs.setString(kMYDEVICE, id);
  }

  // Define el método _TurnOnCharacterService actualizado
  turnOnCharacterService() {
    for (var service in services) {
      for (var character in service.characteristics) {
        if (character.uuid.toString() == CHARACTERISTIC_UUID) {
          _setNotification(character);
        } else if (character.uuid.toString() ==
            HEART_RATE_MEASUREMENT_CHARACTERISTIC_UUID) {
          _readHeartRateMeasurement(character);
        } else if (character.uuid.toString() ==
            SYSTOLIC_PRESSURE_CHARACTERISTIC_UUID) {
          _setNotification(character);
          _readPressureValues(character);
        } else if (character.uuid.toString() ==
            DIASTOLIC_PRESSURE_CHARACTERISTIC_UUID) {
          _setNotification(character);
          _readPressureValues(character);
        }
      }
    }
  }

  void dataParser(Uint8List data) {
    if (data.isNotEmpty) {
      final parsedData = utf8.decode(data); // decode the data to a string
      var presSistolicaValue = int.parse(parsedData.split(',')[0]);
      var presDiastolicaValue = int.parse(parsedData.split(',')[1]);
      var pulMedioValue = int.parse(parsedData.split(',')[2]);

      // print('presSistolicaValue: $presSistolicaValue');
      // print('presDiastolicaValue: $presDiastolicaValue');
      // print('pulMedioValue: $pulMedioValue');

      setState(() {
        _presSistolica = presSistolicaValue.toString() as int?;
        _presDiastolica = presDiastolicaValue.toString() as int?;
        _pulMedio = pulMedioValue.toString() as int?;
      });
    }
  }

  _buildMyWidget() {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Card(
            child: SizedBox(
              height: 200, // Establece la altura fija del Card
              child: SingleChildScrollView(
                // Agrega un desplazamiento vertical
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    const SizedBox(
                      height: 15,
                    ),
                    Image.asset(
                      'assets/sistolica.png',
                      height: 100, // Establece la altura fija de la imagen
                      fit: BoxFit
                          .contain, // Escala la imagen para ajustarla al tamaño de la caja
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    const Text(
                      'Presion Sistolica',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    Text(
                      _presSistolica.toString(),
                      style: const TextStyle(fontSize: 30),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Card(
            child: SizedBox(
              height: 200, // Establece la altura fija del Card
              child: SingleChildScrollView(
                // Agrega un desplazamiento vertical
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    const SizedBox(
                      height: 15,
                    ),
                    Image.asset(
                      'assets/diastolica.png',
                      height: 100, // Establece la altura fija de la imagen
                      fit: BoxFit
                          .contain, // Escala la imagen para ajustarla al tamaño de la caja
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    const Text(
                      'Presion Diastolica',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    Text(
                      _presDiastolica.toString(),
                      style: const TextStyle(fontSize: 30),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Card(
            child: SizedBox(
              height: 200, // Establece la altura fija del Card
              child: SingleChildScrollView(
                // Agrega un desplazamiento vertical
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    const SizedBox(
                      height: 15,
                    ),
                    Image.asset(
                      'assets/pulsomedio.png',
                      height: 100, // Establece la altura fija de la imagen
                      fit: BoxFit
                          .contain, // Escala la imagen para ajustarla al tamaño de la caja
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    const Text(
                      'Pulso Medio',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    Text(
                      _pulMedio.toString(),
                      style: const TextStyle(fontSize: 30),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
