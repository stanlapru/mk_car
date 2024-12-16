import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_joystick/flutter_joystick.dart';

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
      ),
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

  double xCoordinate = 0;
  double yCoordinate = 0;
  bool whiteLedState = false; 
  bool yellowLedState = false; 

  @override
  void initState() {
    super.initState();
    startScan();
  }

  void startScan() async {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

    FlutterBluePlus.scanResults.listen((results) {
      print('listening...');
      for (ScanResult result in results) {
        if (!devicesList
            .any((device) => device.remoteId == result.device.remoteId)) {
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

  @override
  void dispose() {
    connectedDevice?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Панель управления'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 100,
              child: ListView.builder(
                itemCount: devicesList.length,
                itemBuilder: (context, index) {
                  final device = devicesList[index];
                  final deviceName = device.platformName.isNotEmpty
                      ? device.platformName
                      : "Неизвестное устройство";

                  // Filter Arduino
                  // if (!deviceName.toLowerCase().contains("hc-06") ||
                  //     !deviceName.toLowerCase().contains("arduino")) {
                  //   return Container();
                  // }

                  return ListTile(
                    title: Text(deviceName),
                    subtitle: Text(device.remoteId.toString()),
                    onTap: () => connectToDevice(device),
                  );
                },
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
                    const Text('Белый LED', style: TextStyle(fontSize: 16)),
                    Switch(
                      value: whiteLedState,
                      onChanged: (value) {
                        setState(() {
                          whiteLedState = value;
                        });
                        sendLedState("LED_WHITE", value);
                      },
                    ),
                  ],
                ),
                const SizedBox(width: 40),
                Column(
                  children: [
                    const Text('Жёлтый LED', style: TextStyle(fontSize: 16)),
                    Switch(
                      value: yellowLedState,
                      onChanged: (value) {
                        setState(() {
                          yellowLedState = value;
                        });
                        sendLedState("LED_YELLOW", value);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
