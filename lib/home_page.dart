import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final supabase = Supabase.instance.client;
  final TextEditingController _controller = TextEditingController();
  List<dynamic> _items = [];

  Future<void> _insertItem() async {
    final user = supabase.auth.currentUser;
    await supabase.from('items').insert({'name': _controller.text,'user_id': user!.id});
    _controller.clear();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final data = await supabase.from('items').select();
    setState(() => _items = data);
  }

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Supabase Flutter Demo')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(controller: _controller),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _insertItem, child: const Text('Add Item')),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _items.length,
                itemBuilder: (_, i) => ListTile(title: Text(_items[i]['name'] ?? '')),
              ),
            )
          ],
        ),
      ),
    );
  }
}