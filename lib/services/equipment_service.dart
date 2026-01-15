import 'package:supabase_flutter/supabase_flutter.dart';

class EquipmentService {
  final supabase = Supabase.instance.client;

  Future<List<dynamic>> getAllEquipment() async {
    return await supabase.from('equipment').select().order('name');
  }

  /// ✅ Insert equipment and return the inserted row (including id)
  Future<Map<String, dynamic>> insertEquipment(String name) async {
    final res = await supabase
        .from('equipment')
        .insert({'name': name})
        .select()
        .single();

    return Map<String, dynamic>.from(res);
  }

  Future<Map<String, dynamic>?> getEquipmentByQr(String qrValue) async {
    final res = await supabase
        .from('equipment')
        .select()
        .eq('qr_code', qrValue)
        .maybeSingle();

    return res;
  }
}
