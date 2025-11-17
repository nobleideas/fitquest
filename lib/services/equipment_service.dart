import 'package:supabase_flutter/supabase_flutter.dart';

class EquipmentService {
  final supabase = Supabase.instance.client;


  Future<List<dynamic>> getAllEquipment() async {
    return await supabase.from('equipment').select().order('name');
  }

   Future<void> insertEquipment(String name) async {
    await supabase.from('equipment').insert({'name': name});
    print('Inserted equipment: $name');
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
