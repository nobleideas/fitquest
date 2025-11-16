import 'package:supabase_flutter/supabase_flutter.dart';

class EquipmentService {
  final supabase = Supabase.instance.client;

  Future<Map<String, dynamic>?> getEquipmentByQr(String qrValue) async {
    final res = await supabase
        .from('equipment')
        .select()
        .eq('qr_code', qrValue)
        .maybeSingle();

    return res;
  }
}
