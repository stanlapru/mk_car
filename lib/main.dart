import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_joystick/flutter_joystick.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bluetooth Joystick',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ).copyWith(
          colorScheme: Theme.of(context)
              .colorScheme
              .copyWith(outline: Colors.blue, primary: Colors.blue)),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ).copyWith(
          colorScheme: Theme.of(context)
              .colorScheme
              .copyWith(outline: Colors.blue, primary: Colors.blue)),
      home: const BluetoothJoystickPage(),
    );
  }
}

class BluetoothJoystickPage extends StatefulWidget {
  const BluetoothJoystickPage({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _BluetoothJoystickPageState createState() => _BluetoothJoystickPageState();
}

class _BluetoothJoystickPageState extends State<BluetoothJoystickPage> {
  FlutterBluePlus flutterBlue = FlutterBluePlus();
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? writeCharacteristic;
  List<BluetoothDevice> devicesList = [];
  Timer? refreshTimer;
  Timer? emergencyFlashTimer;

  double xCoordinate = 0;
  double yCoordinate = 0;
  bool isBluetoothOn = false;
  bool isLocationOn = false;
  bool whiteLedState = false;
  bool leftYellowLedState = false;
  bool rightYellowLedState = false;
  bool emergencyFlashing = false;

  @override
  void initState() {
    super.initState();
    checkAndRequestPermissions();
    checkLocationServices();
    startAutoRefresh();
  }

  Future<void> checkAndRequestPermissions() async {
    var bluetoothScanStatus = await Permission.bluetoothScan.request();
    var bluetoothConnectStatus = await Permission.bluetoothConnect.request();
    var locationStatus = await Permission.location.request();

    if (bluetoothScanStatus.isGranted && bluetoothConnectStatus.isGranted) {
      checkBluetoothState();
    }

    if (locationStatus.isGranted) {
      checkLocationServices();
    }
  }

  void checkBluetoothState() {
    FlutterBluePlus.adapterState.listen((state) {
      setState(() {
        isBluetoothOn = (state == BluetoothAdapterState.on);
      });

      if (isBluetoothOn) {
        startScan();
      }
    });
  }

  Future<void> checkLocationServices() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    setState(() {
      isLocationOn = serviceEnabled;
    });
    if (!serviceEnabled) {
      // Prompt the user to enable location services
      await Geolocator.openLocationSettings();
    }
  }

  void refreshDeviceList() {
    setState(() {
      devicesList.clear();
    });
    startScan();
  }

  void startAutoRefresh() {
    refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (isBluetoothOn && isLocationOn && mounted) {
        refreshDeviceList();
      }
    });
  }

  void startScan() async {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    FlutterBluePlus.scanResults.listen((results) {
      print('listening...');
      for (ScanResult result in results) {
        if (!devicesList
            .any((device) => device.remoteId == result.device.remoteId)) {
          print(
              'Found device: ${result.device.platformName} (${result.device.remoteId})');
          setState(() {
            devicesList.add(result.device);
          });
        }
      }
    });
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    await FlutterBluePlus.stopScan();

    try {
      await device.connect();
    } catch (e) {
      if (e.toString() != "already_connected") {
        rethrow;
      }
    }

    setState(() {
      connectedDevice = device;
    });

    List<BluetoothService> services = await device.discoverServices();
    for (BluetoothService service in services) {
      for (BluetoothCharacteristic characteristic in service.characteristics) {
        if (characteristic.properties.write) {
          setState(() {
            writeCharacteristic = characteristic;
          });
          break;
        }
      }
    }
  }

  void sendJoystickCoordinates(double x, double y) async {
    if (writeCharacteristic != null) {
      String message = "${x.toInt()},${y.toInt()}\n";
      print(message);
      await writeCharacteristic!.write(message.codeUnits);
    }
  }

  void sendLedState(String led, bool state) async {
    if (writeCharacteristic != null) {
      String message = "$led:${state ? 1 : 0}\n";
      print(message);
      await writeCharacteristic!.write(message.codeUnits);
    }
  }

  void toggleEmergencyFlashing(bool state) {
    if (state) {
      emergencyFlashTimer =
          Timer.periodic(const Duration(milliseconds: 500), (timer) {
        setState(() {
          leftYellowLedState = !leftYellowLedState;
          rightYellowLedState = !rightYellowLedState;
        });

        sendLedState("LEFT_YELLOW_LED", leftYellowLedState);
        sendLedState("RIGHT_YELLOW_LED", rightYellowLedState);
      });
    } else {
      emergencyFlashTimer?.cancel();
      setState(() {
        leftYellowLedState = false;
        rightYellowLedState = false;
      });

      sendLedState("LEFT_YELLOW_LED", false);
      sendLedState("RIGHT_YELLOW_LED", false);
    }
  }

  void sendSoundCommand(bool state) async {
    if (writeCharacteristic != null) {
      String message = "SOUND:${state ? 1 : 0}\n";
      await writeCharacteristic!.write(message.codeUnits);
    }
  }

  @override
  void dispose() {
    connectedDevice?.disconnect();
    refreshTimer?.cancel();
    emergencyFlashTimer?.cancel();
    super.dispose();
  }

  final WidgetStateProperty<Icon?> thumbIconRight =
      WidgetStateProperty.resolveWith<Icon?>(
    (Set<WidgetState> states) {
      return const Icon(Icons.turn_right);
    },
  );

  final WidgetStateProperty<Icon?> thumbIconLeft =
      WidgetStateProperty.resolveWith<Icon?>(
    (Set<WidgetState> states) {
      return const Icon(Icons.turn_left);
    },
  );

  final WidgetStateProperty<Icon?> thumbIconEmergency =
      WidgetStateProperty.resolveWith<Icon?>(
    (Set<WidgetState> states) {
      return const Icon(Icons.warning_amber_rounded);
    },
  );

  final WidgetStateProperty<Icon?> thumbIconHeadlights =
      WidgetStateProperty.resolveWith<Icon?>(
    (Set<WidgetState> states) {
      return const Icon(Icons.lightbulb);
    },
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        title: const Text('Панель управления'),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            height: 290,
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                connectedDevice == null
                    ? (!isBluetoothOn || !isLocationOn)
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (!isBluetoothOn)
                                  Text(
                                    'Bluetooth не включен.',
                                    style: TextStyle(
                                        fontSize: 18,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error),
                                  ),
                                if (!isLocationOn)
                                  Text(
                                    'Геолокация не включена.',
                                    style: TextStyle(
                                        fontSize: 18,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error),
                                  ),
                              ],
                            ),
                          )
                        : Column(
                            children: [
                              const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      height: 16.0,
                                      width: 16.0,
                                      child: Center(
                                          child: CircularProgressIndicator()),
                                    ),
                                    SizedBox(
                                      width: 16,
                                    ),
                                    Text(
                                      'Список устройств',
                                      style: TextStyle(fontSize: 20),
                                    ),
                                    // const SizedBox(
                                    //   width: 8,
                                    // ),
                                    // TextButton(
                                    //     onPressed: () {
                                    //       setState(() {
                                    //         devicesList.clear();
                                    //       });
                                    //       startScan();
                                    //     },
                                    //     child: const Text("Обновить")),
                                  ]),
                              const SizedBox(height: 20),
                              SizedBox(
                                height: 200,
                                child: ListView.builder(
                                  itemCount: devicesList.length,
                                  itemBuilder: (context, index) {
                                    final device = devicesList[index];
                                    final deviceName =
                                        device.platformName.isNotEmpty
                                            ? device.platformName
                                            : "Неизвестное устройство";

                                    // Filter Arduino
                                    // if (!deviceName.toLowerCase().contains("hc-06") ||
                                    //     !deviceName.toLowerCase().contains("arduino")) {
                                    //   return Container();
                                    // }

                                    return ListTile(
                                      title: Text(
                                        deviceName,
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onPrimary,
                                        ),
                                      ),
                                      subtitle: Text(
                                        device.remoteId.toString(),
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                      onTap: () => connectToDevice(device),
                                    );
                                  },
                                ),
                              ),
                            ],
                          )
                    : Container()
              ],
            ),
          ),
          if (connectedDevice != null)
            Text(
              'Подключен к ${connectedDevice!.platformName}',
              style: const TextStyle(fontSize: 18),
            ),
          const SizedBox(height: 20),
          Joystick(
            listener: (details) {
              double x = details.x * 100; // [-100, 100]
              double y = details.y * -100; // [-100, 100]
              setState(() {
                xCoordinate = x;
                yCoordinate = y;
              });
              sendJoystickCoordinates(x, y);
            },
            mode: JoystickMode.all,
          ),
          const SizedBox(height: 20),
          Text(
            'X: ${xCoordinate.toStringAsFixed(1)}, Y: ${yCoordinate.toStringAsFixed(1)}',
            style: const TextStyle(fontSize: 16, color: Colors.black),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(
                children: [
                  const Text('Фары', style: TextStyle(fontSize: 16)),
                  Switch(
                    value: whiteLedState,
                    thumbIcon: thumbIconHeadlights,
                    onChanged: (value) {
                      setState(() {
                        whiteLedState = value;
                      });
                      sendLedState("LED_WHITE", value);
                    },
                  ),
                ],
              ),
              const SizedBox(width: 20),
              Column(
                children: [
                  const Text('Влево', style: TextStyle(fontSize: 16)),
                  Switch(
                    value: leftYellowLedState,
                    thumbIcon: thumbIconLeft,
                    onChanged: (value) {
                      setState(() {
                        leftYellowLedState = value;
                      });
                      sendLedState("LEFT_YELLOW_LED", value);
                    },
                  ),
                ],
              ),
              const SizedBox(width: 20),
              Column(
                children: [
                  const Text('Вправо', style: TextStyle(fontSize: 16)),
                  Switch(
                    thumbIcon: thumbIconRight,
                    value: rightYellowLedState,
                    onChanged: (value) {
                      setState(() {
                        rightYellowLedState = value;
                      });
                      sendLedState("RIGHT_YELLOW_LED", value);
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(width: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(
                children: [
                  const Text('Аварийка', style: TextStyle(fontSize: 16)),
                  Switch(
                    thumbIcon: thumbIconEmergency,
                    value: emergencyFlashing,
                    onChanged: (value) {
                      setState(() {
                        emergencyFlashing = value;
                      });
                      toggleEmergencyFlashing(value);
                    },
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Column(
                children: [
                  const Text('Сигнал', style: TextStyle(fontSize: 16)),
                  ElevatedButton(
                    onPressed: null,
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.all(Colors.blue),
                    ),
                    child: GestureDetector(
                      onTapDown: (_) {
                        sendSoundCommand(true);
                      },
                      onTapUp: (_) {
                        sendSoundCommand(false);
                      },
                      child: const Text("Держите"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
