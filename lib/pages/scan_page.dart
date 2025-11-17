import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/equipment_service.dart';
import 'equipment_list_page.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool _isProcessing = false;

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return; // Prevent multiple scans
    _isProcessing = true;

    final barcode = capture.barcodes.first;
    final String? value = barcode.rawValue;

    if (value == null) {
      _isProcessing = false;
      return;
    }

    // Lookup the equipment by QR code
    final equipment = await EquipmentService().getEquipmentByQr(value);

    if (!mounted) return;

    if (equipment == null) {
      // QR code not found in database
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Equipment not found.")),
      );
      _isProcessing = false;
      return;
    }

    // Navigate to equipment page
    // Navigator.push(
    //   context,
    //   MaterialPageRoute(
    //     builder: (_) => EquipmentListPage(equipment: equipment),
    //   ),
    // );

    // Allow scanning again after navigation
    Future.delayed(const Duration(milliseconds: 500), () {
      _isProcessing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Scan Equipment QR"),
      ),
      body: MobileScanner(
              fit: BoxFit.cover,
              onDetect: _onDetect,
      ),
    );
  }
}
