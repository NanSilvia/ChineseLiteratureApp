import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'pages/camera-page.dart';
import 'pages/repository_page.dart';
import 'pages/review_history_page.dart';
import 'pages/settings_page.dart';
import 'pages/shared_text_page.dart';
import 'services/connectivity_service.dart';
import 'services/auth_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: SystemUiOverlay.values,
  );
  // Initialize services
  ConnectivityService();
  AuthService().init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chinese Learning',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  static const _sharingChannel = MethodChannel('com.example.zhapp/sharing');

  // Key to refresh repository page when card is saved
  final GlobalKey<State<RepositoryPage>> _repositoryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Handle text shared while the app is already running
    _sharingChannel.setMethodCallHandler((call) async {
      if (call.method == 'sharedText' && mounted) {
        _openSharedTextPage(call.arguments as String);
      }
    });
    // Handle text shared that launched / resumed the app cold
    _sharingChannel.invokeMethod<String>('getSharedText').then((text) {
      if (text != null && text.isNotEmpty && mounted) {
        _openSharedTextPage(text);
      }
    });
  }

  void _openSharedTextPage(String text) {
    final nav = Navigator.of(context);
    nav.push(
      MaterialPageRoute(builder: (_) => SharedTextPage(sharedText: text)),
    );
  }

  void _onCardSaved() {
    // Switch to repository tab and refresh
    setState(() => _currentIndex = 0);
  }

  void _goToSettings() {
    setState(() => _currentIndex = 3);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_getTitle()), elevation: 0),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          AuthGate(
            message: 'Please log in to view your saved cards.',
            onGoToSettings: _goToSettings,
            child: RepositoryPage(key: _repositoryKey),
          ),
          AuthGate(
            message: 'Please log in to use the OCR camera.',
            onGoToSettings: _goToSettings,
            child: CameraPage(onCardSaved: _onCardSaved),
          ),
          AuthGate(
            message: 'Please log in to view your study progress.',
            onGoToSettings: _goToSettings,
            child: const ReviewHistoryPage(),
          ),
          const SettingsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_box_outlined),
            selectedIcon: Icon(Icons.add_box),
            label: 'Add Card',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Progress',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  String _getTitle() {
    switch (_currentIndex) {
      case 0:
        return 'Library';
      case 1:
        return 'Add Card';
      case 2:
        return 'Study Progress';
      case 3:
        return 'Settings';
      default:
        return 'Chinese Learning';
    }
  }
}
