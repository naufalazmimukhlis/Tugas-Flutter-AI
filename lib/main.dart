import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const ProviderScope(child: ResepAIApp()));
}

/* ===================== STATE ===================== */

class RecipeState {
  final String hasil;
  final bool loading;

  RecipeState({
    required this.hasil,
    this.loading = false,
  });
}

/* ===================== NOTIFIER ===================== */

class RecipeNotifier extends StateNotifier<RecipeState> {
  RecipeNotifier() : super(RecipeState(hasil: "Mau masak apa hari ini?"));

  String? _modelName;

  Future<void> _loadAvailableModel() async {
    final apiKey = dotenv.env['GEMINI_API_KEY'];

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1/models?key=$apiKey',
    );

    final response = await http.get(url);
    final data = jsonDecode(response.body);

    if (data['models'] == null) {
      throw Exception("Gagal mengambil daftar model");
    }

    // Ambil model yang support generateContent
    for (final model in data['models']) {
      final methods = model['supportedGenerationMethods'] ?? [];
      if (methods.contains('generateContent')) {
        _modelName = model['name']; 
        break;
      }
    }

    if (_modelName == null) {
      throw Exception("Tidak ada model yang mendukung generateContent");
    }
  }

  Future<void> cariResep(String menu) async {
    if (menu.trim().isEmpty) return;

    state = RecipeState(hasil: "", loading: true);

    try {
      final apiKey = dotenv.env['GEMINI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception("API Key tidak ditemukan");
      }

      _modelName ??= await (() async {
        await _loadAvailableModel();
        return _modelName!;
      })();

      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1/$_modelName:generateContent?key=$apiKey',
      );

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {
                  "text":
                      "Berikan resep masakan $menu dalam bahasa Indonesia.\n"
                      "Format:\n1. Bahan-bahan\n2. Cara membuat\n"
                      "Gunakan bahasa sederhana."
                }
              ]
            }
          ]
        }),
      );

      final data = jsonDecode(response.body);

      if (data['candidates'] == null) {
        throw Exception(data['error']?['message'] ?? "API Error");
      }

      final text =
          data['candidates'][0]['content']['parts'][0]['text'];

      state = RecipeState(hasil: text, loading: false);
    } catch (e) {
      state = RecipeState(
        hasil: "Terjadi kesalahan:\n$e",
        loading: false,
      );
    }
  }
}

/* ===================== PROVIDER ===================== */

final recipeProvider =
    StateNotifierProvider<RecipeNotifier, RecipeState>(
        (ref) => RecipeNotifier());

/* ===================== UI ===================== */

class ResepAIApp extends StatelessWidget {
  const ResepAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recipeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "🍳 Koki AI: Resep Kilat",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.orange,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: "Masukkan Nama Masakan",
                hintText: "Contoh: Ayam Goreng",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.restaurant_menu),
              ),
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: state.loading
                    ? null
                    : () {
                        ref
                            .read(recipeProvider.notifier)
                            .cariResep(controller.text);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                child: state.loading
                    ? const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      )
                    : const Text(
                        "Dapatkan Resep",
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    state.hasil,
                    style: const TextStyle(fontSize: 15, height: 1.6),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
