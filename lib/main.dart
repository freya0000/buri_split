import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  await dotenv.load(fileName: ".env"); // Load the file
  runApp(const BuriSplitApp());
}

// If API key was hardcoded :
// void main() {
//   runApp(const BuriSplitApp());
// }

// 1. DATA MODELS
class ReceiptItem {
  final String name;
  final int price;
  final int quantity;
  List<String> assignedPeople = [];

  ReceiptItem({required this.name, required this.price, this.quantity = 1});

  factory ReceiptItem.fromJson(Map<String, dynamic> json) {
    return ReceiptItem(
      name: json['name'] ?? 'Unknown Item',
      price: (json['price'] as num).toInt(),
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
    );
  }
}

class Person {
  String name;
  bool showOrders; // New variable to track visibility
  Person({required this.name, this.showOrders = false});
}

class BuriSplitApp extends StatelessWidget {
  const BuriSplitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BuriSplt',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // 2. STATE VARIABLES
  List<ReceiptItem> items = [];
  List<Person> people = [Person(name: "Me"), Person(name: "Friend 1")];
  bool isScanning = false;
  int scannedTotal = 0;

  int get calculatedSum =>
      items.fold(0, (sum, item) => sum + (item.price * item.quantity));

  bool get isTotalMismatch =>
      // scannedTotal != 0 && calculatedSum != scannedTotal;
      calculatedSum != scannedTotal;

  // Hard code: Replace with your actual Gemini API Key from AI Studio
  //final String _apiKey = "";
  // Environment way
  final String _apiKey = dotenv.env['GEMINI_API_KEY'] ?? 'API_KEY_NOT_FOUND';

  // 3. LOGIC: SCAN RECEIPT
  Future<void> _pickAndScanImage() async {
    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800, // Compress to save quota
      imageQuality: 70,
    );

    if (photo == null) return;
    setState(() => isScanning = true);

    try {
      final model = GenerativeModel(
        model: 'gemini-flash-latest', // Stable 2026 model
        apiKey: _apiKey,
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
        ),
      );

      final bytes = await photo.readAsBytes();
      const prompt =
          "Analyze this Japanese receipt. Return ONLY a JSON object: "
          "{\"items\": [{\"name\": string, \"price\": int, \"quantity\": int}], "
          "\"receipt_total\": int}.";
      final content = [
        Content.multi([TextPart(prompt), DataPart('image/jpeg', bytes)]),
      ];
      final response = await model.generateContent(content);
      final rawText = response.text;

      if (rawText == null || rawText.isEmpty) {
        throw Exception("Empty AI response");
      }

      final cleanedJson = rawText
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      // 1. Decode as a Map (Object), not a List
      final Map<String, dynamic> decoded = jsonDecode(cleanedJson);

      setState(() {
        // 2. Extract the list of items using the "items" key
        final List<dynamic> itemsList = decoded['items'] ?? [];
        items = itemsList.map((item) => ReceiptItem.fromJson(item)).toList();

        // 3. Extract the total using the "receipt_total" key
        scannedTotal = (decoded['receipt_total'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => isScanning = false);
    }
  }

  // 4a. LOGIC : add new person
  void _addNewPerson() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Add New Person"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: "Enter name"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(
                  () => people.add(Person(name: controller.text.trim())),
                );
              }
              Navigator.pop(ctx);
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  // 4b. LOGIC: RENAME & POPUPS
  void _renamePerson(int index) {
    final controller = TextEditingController(text: people[index].name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Rename Friend"),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment
                .spaceBetween, // Pushes items to far left and right
            children: [
              // Left side: Delete button
              IconButton(
                icon: const Icon(
                  Icons.delete,
                  size: 24, // Sized down slightly to look better in a row
                  color: Color.fromARGB(255, 122, 60, 54),
                ),
                onPressed: () {
                  Navigator.pop(ctx); // Close the rename dialog first
                  _deletePerson(index); // Then open the delete confirmation
                },
              ),

              // Right side: Cancel and Save buttons
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Cancel"),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        String oldName = people[index].name;
                        String newName = controller.text.trim();
                        if (newName.isNotEmpty) {
                          people[index].name = newName;
                          for (var item in items) {
                            int i = item.assignedPeople.indexOf(oldName);
                            if (i != -1) item.assignedPeople[i] = newName;
                          }
                        }
                      });
                      Navigator.pop(ctx); // Close dialog
                    },
                    child: const Text("Save"),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 4c. DELETE PERSON
  void _deletePerson(int index) {
    String personName = people[index].name;

    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text("Confirm Deletion"),
          content: Text("Are you sure you want to delete $personName?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(), // Close dialog
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  // 1. Remove the person from the people list
                  people.removeAt(index);

                  // 2. Remove their name from any assigned items
                  for (var item in items) {
                    item.assignedPeople.remove(personName);
                  }
                });
                Navigator.of(ctx).pop(); // Close dialog
              },
              child: const Text(
                "Delete",
                style: TextStyle(color: Color.fromARGB(255, 122, 60, 54)),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showItemAssignment(ReceiptItem item) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        // Vital for updating UI inside popup
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text("Who bought ${item.name}?"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: people
                  .map(
                    (p) => CheckboxListTile(
                      title: Text(p.name),
                      value: item.assignedPeople.contains(p.name),
                      onChanged: (val) {
                        // Use "val == true" to ensure it's a solid boolean check
                        if (val != null) {
                          setDialogState(() {
                            setState(() {
                              if (val) {
                                item.assignedPeople.add(p.name);
                              } else {
                                item.assignedPeople.remove(p.name);
                              }
                            });
                          });
                        }
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Done"),
            ),
          ],
        ),
      ),
    );
  }

  double _calculatePersonTotal(String name) {
    double total = 0.0;
    for (var item in items) {
      if (item.assignedPeople.contains(name)) {
        total += (item.price * item.quantity) / item.assignedPeople.length;
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("BuriSplit 🧾"), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ElevatedButton.icon(
            onPressed: isScanning ? null : _pickAndScanImage,
            icon: isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.camera_alt),
            label: Text(isScanning ? "Processing..." : "Scan Japanese Receipt"),
          ),
          const Divider(height: 30),
          const Text(
            "Items (Tap to assign)",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          ...items.map(
            (item) => Card(
              child: ListTile(
                title: Text(item.name),
                subtitle: Text("${item.price}円 x ${item.quantity}"),
                trailing: Column(
                  mainAxisSize: MainAxisSize.min, // Shrinks to fit content
                  crossAxisAlignment:
                      CrossAxisAlignment.end, // Aligns all text to the right
                  children: [
                    // 1. The Names (Top Row)
                    Wrap(
                      spacing: 4,
                      alignment: WrapAlignment.end,
                      children: item.assignedPeople
                          .take(2)
                          .map(
                            (name) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.teal.withOpacity(0.5),
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                name,
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          )
                          .toList(),
                    ),

                    // 2. The Counter (Bottom Row)
                    if (item.assignedPeople.length > 2)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: 4.0,
                        ), // Space between names and counter
                        child: Text(
                          "+${item.assignedPeople.length - 2} others",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal.shade700,
                          ),
                        ),
                      ),
                  ],
                ),
                onTap: () => _showItemAssignment(item),
              ),
            ),
          ),

          // DISPLAY TOTAL SCANNED AMOUNT HERE
          ListTile(
            title: const Text(
              "Total Amount",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            trailing: Text(
              "$calculatedSum円",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Colors.teal,
              ),
            ),
          ),

          // ... inside your ListView children:
          const Divider(height: 30),
          ListTile(
            title: const Text(
              "Receipt Verification",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Text(
              "Scanned: $scannedTotal 円 | Items: $calculatedSum 円",
            ),
            trailing: Icon(
              isTotalMismatch
                  ? Icons.error_outline
                  : Icons.check_circle_outline,
              color: isTotalMismatch ? Colors.red : Colors.teal,
            ),
          ),

          if (isTotalMismatch)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  "⚠️ Total mismatch! The sum of items doesn't match the receipt total. Please check prices.",
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          const Divider(height: 30),
          const Text(
            "Total to Pay (Tap to rename)",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          ...people.asMap().entries.map((entry) {
            int idx = entry.key;
            Person p = entry.value;

            // Find all items assigned to this person
            List<ReceiptItem> personOrders = items
                .where((item) => item.assignedPeople.contains(p.name))
                .toList();

            return Column(
              children: [
                ListTile(
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // The "Eye" Toggle Button
                      IconButton(
                        icon: Icon(
                          p.showOrders
                              ? Icons.visibility
                              : Icons.visibility_off,
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => p.showOrders = !p.showOrders),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 16),
                        onPressed: () => _renamePerson(idx),
                      ),
                    ],
                  ),
                  title: Text(
                    p.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: Text(
                    "${_calculatePersonTotal(p.name).toStringAsFixed(0)}円",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.teal,
                    ),
                  ),
                ),

                // The "Hidden" Order List
                if (p.showOrders)
                  Container(
                    padding: const EdgeInsets.only(
                      left: 70,
                      right: 16,
                      bottom: 8,
                    ),
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: personOrders.map((item) {
                        // Calculate split price (e.g., 300 if shared by 2)
                        double splitPrice =
                            (item.price * item.quantity) /
                            item.assignedPeople.length;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                item.assignedPeople.length > 1
                                    ? "${item.name} x${item.quantity}/${item.assignedPeople.length}"
                                    : "${item.name} x${item.quantity}",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              Text(
                                "${splitPrice.toStringAsFixed(0)}円",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                const Divider(height: 1),
              ],
            );
          }),
          // NEW CODE
          TextButton(
            onPressed: _addNewPerson, // Calls the dialog method we created
            child: const Text("+ Add Person"),
          ),
        ],
      ),
    );
  }
}
