import 'package:flutter/material.dart';

import 'pages/camera-page.dart';
import 'pages/db_page.dart';
import 'pages/user-page.dart';
import 'services/db_service.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 1; // middle page is main
  List<String> _texts = [];
  final DbService _dbService = DbService();

  @override
  void initState() {
    super.initState();
    _loadTexts();
  }

  Future<void> _loadTexts() async {
    final texts = await _dbService.loadTexts();
    setState(() {
      _texts = texts;
    });
  }

  Future<void> _onTextExtracted(String text) async {
    await _dbService.saveText(text);
    await _loadTexts();
  }

  Future<void> _onDeleteText(int index) async {
    await _dbService.deleteText(index, _texts);
    await _loadTexts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: IndexedStack(
        index: _index,
        children: [
          CameraPage(onTextExtracted: _onTextExtracted), // page 0
          DbPage(texts: _texts, onDelete: _onDeleteText), // page 1
          const UserPage(), // page 2
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.camera_alt),
            label: 'Camera',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Saved'),
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Welcome'),
        ],
      ),
    );
  }
}
