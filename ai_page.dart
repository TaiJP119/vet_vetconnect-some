import 'dart:convert';
import 'dart:io';
import 'package:VetApp/features/user_auth/presentation/pages/home_page.dart';
// import your Vet Finder and Pet Profile pages as needed
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';

class AIPage extends StatefulWidget {
  const AIPage({super.key});

  @override
  State<AIPage> createState() => _AIPageState();
}

class _AIPageState extends State<AIPage> {
  final TextEditingController textController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final List<_ChatMessage> messages = [];
  bool isTyping = false;
  XFile? selectedImage;
  String? selectedPetId;
  Map<String, String> petNameMap = {};
  final model = GenerativeModel(
    model: 'gemini-1.5-flash', // < -- can choose other model ya
    apiKey: 'YOUR-API-KEY',
  );
  final List<String> faqQuestions = [
    "My cat is vomiting. What should I do?",
    "Is this rash on my dog's skin normal?",
    "What vaccine does a puppy need?",
    "Can I feed human food to my rabbit?",
    "How to treat fleas on my cat?",
  ];
  late stt.SpeechToText speech;
  bool _isListening = false;
  Set<String> _favourites = {};

  @override
  void initState() {
    super.initState();
    _loadPets();
    _loadFavouritesFromFirebase();
    speech = stt.SpeechToText();
  }

// Remove markdown bold markers, render as real bold via TextSpan
  TextSpan boldParserAndStripLinks(String input, List<String> extractedUrls) {
    // Remove all extracted URLs (shown as buttons) from main text
    for (final url in extractedUrls) {
      input = input.replaceAll(url, '');
    }
    // Replace **bold** with bold spans
    final pattern = RegExp(r'\*\*(.*?)\*\*');
    final spans = <TextSpan>[];
    int current = 0;
    for (final match in pattern.allMatches(input)) {
      if (match.start > current) {
        spans.add(TextSpan(text: input.substring(current, match.start)));
      }
      spans.add(TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.bold)));
      current = match.end;
    }
    if (current < input.length) {
      spans.add(TextSpan(text: input.substring(current)));
    }
    return TextSpan(children: spans);
  }

  // Load user's pets from Firestore
  Future<void> _loadPets() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final query = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('pets')
        .get();
    if (query.docs.isNotEmpty) {
      setState(() {
        petNameMap = {
          for (final doc in query.docs)
            doc.id: (doc.data()['name'] ?? "Unnamed")
        };
        selectedPetId = query.docs.first.id;
      });
    }
  }

  // --- FAVOURITES: Store/Load in Firebase ---
  Future<void> _loadFavouritesFromFirebase() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final query = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('ai_saved_answers')
        .get();
    setState(() {
      _favourites = query.docs.map((d) => d.id).toSet();
    });
  }

  Future<void> _toggleFavourite(_ChatMessage msg) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('ai_saved_answers');

    if (_favourites.contains(msg.firebaseId)) {
      // Remove from Firestore
      await ref.doc(msg.firebaseId).delete();
      setState(() {
        _favourites.remove(msg.firebaseId);
      });
    } else {
      // Save to Firestore
      final docRef = await ref.add({
        "text": msg.text,
        "timestamp": msg.timestamp,
        "petId": selectedPetId,
      });
      setState(() {
        msg.firebaseId = docRef.id;
        _favourites.add(docRef.id);
      });
    }
  }

  // --- VOICE INPUT ---
  Future<void> startListening() async {
    bool available = await speech.initialize();
    if (!available) return;
    setState(() => _isListening = true);
    speech.listen(
      onResult: (result) {
        textController.text = result.recognizedWords;
      },
      listenFor: const Duration(seconds: 15),
    );
  }

  void stopListening() {
    speech.stop();
    setState(() => _isListening = false);
  }

  // --- SENDING MESSAGE ---
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    setState(() {
      messages.add(_ChatMessage(
        text: text.trim(),
        isUser: true,
        timestamp: DateTime.now(),
        id: UniqueKey().toString(),
      ));
      isTyping = true;
    });
    textController.clear(); // Immediately clear input

    scrollToBottom();

    // (Prompt building as before)
    final contextHistory = _buildContextHistory();
    final petDesc = selectedPetId != null && petNameMap[selectedPetId!] != null
        ? "Pet details: ${petNameMap[selectedPetId!]}"
        : "";

    String prompt = """
$petDesc
Chat history:
$contextHistory
Pet issue: $text

Please:
- Give a summary, helpful, friendly, and medically sound answer suitable for pet owners.
- List possible causes and home care tips if relevant.
- Show "red flag" symptoms when the user should urgently see a vet.
- If urgent/critical, mention this and recommend finding a vet, using the words 'EMERGENCY' or 'urgent' in your reply.
- Render **bold** in text as actual bold, not with stars.
""";

    // List<Content> aiInputs = [Content.text(prompt)];
    final List<Content> aiInputs = [];

    if (selectedImage != null) {
      final imageBytes = await selectedImage!.readAsBytes();
      final mimetype = selectedImage!.mimeType ?? 'image/jpeg';

      aiInputs.add(
        Content.multi([
          TextPart(prompt),
          DataPart(mimetype, imageBytes),
        ]),
      );
    } else {
      aiInputs.add(Content.text(prompt));
    }

    String aiResponse = '';

    final response = model.generateContentStream(aiInputs);
    await for (final chunk in response) {
      if (chunk.text != null) {
        setState(() {
          aiResponse += chunk.text!;
        });
        scrollToBottom();
      }
    }

    // 1. Remove all **bold** markers for display (handled by parser below)
    // 2. Remove all URLs and images (no need for any parsing here)
    String cleanText = aiResponse;

    setState(() {
      messages.add(_ChatMessage(
        text: cleanText.trim(),
        isUser: false,
        timestamp: DateTime.now(),
        id: UniqueKey().toString(),
        // sources: [], images: [], --> Not needed anymore!
        isUrgent: aiResponse.toLowerCase().contains("emergency") ||
            aiResponse.toLowerCase().contains("urgent"),
      ));
      isTyping = false;
    });
    scrollToBottom();
  }

  // For AI follow-up: Use last 4 (user+AI) messages for context
  String _buildContextHistory() {
    final recent =
        messages.length > 7 ? messages.sublist(messages.length - 7) : messages;
    return recent
        .map((m) => (m.isUser ? "User: " : "AI: ") + m.text)
        .join("\n");
  }

  void scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source);
    if (picked != null) {
      setState(() {
        selectedImage = picked;
      });
    }
  }

  // --- UI ---
  Widget buildMessageBubble(_ChatMessage message) {
    final isAI = !message.isUser;
    return Container(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      child: Column(
        crossAxisAlignment:
            message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: message.isUser ? Colors.yellow[700] : Colors.grey[200],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: message.isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: message.isUser
                      ? MainAxisAlignment.end
                      : MainAxisAlignment.start,
                  children: [
                    if (!message.isUser) ...[
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.teal,
                        child: Icon(Icons.pets, color: Colors.white, size: 16),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: isAI
                          ? Text.rich(
                              _boldParser(message.text),
                              style: const TextStyle(fontSize: 16),
                            )
                          : Text(
                              message.text,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ],
                ),
                if (isAI)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // FAVOURITE (STAR) BUTTON
                      IconButton(
                        icon: Icon(
                          _favourites.contains(message.id)
                              ? Icons.star
                              : Icons.star_border,
                          color: _favourites.contains(message.id)
                              ? Colors.orange
                              : Colors.grey,
                        ),
                        onPressed: () => _toggleFavourite(message),
                        tooltip: _favourites.contains(message.id)
                            ? "Saved"
                            : "Save as Favourite",
                      ),
                      // FIND VET BUTTON (EMERGENCY/URGENT)
                      if (message.isUrgent)
                        TextButton.icon(
                          icon: Icon(Icons.local_hospital, color: Colors.red),
                          label: Text("Find Nearby Vet",
                              style: TextStyle(color: Colors.red)),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => /* Your Vet Finder Page Widget */
                                        HomePage(),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                Text(
                  "${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}",
                  style: TextStyle(fontSize: 10, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

// Bold parser (no link/image handling needed anymore)
  TextSpan _boldParser(String input) {
    final pattern = RegExp(r'\*\*(.*?)\*\*');
    final spans = <TextSpan>[];
    int current = 0;
    for (final match in pattern.allMatches(input)) {
      if (match.start > current) {
        spans.add(TextSpan(text: input.substring(current, match.start)));
      }
      spans.add(TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.bold)));
      current = match.end;
    }
    if (current < input.length) {
      spans.add(TextSpan(text: input.substring(current)));
    }
    return TextSpan(children: spans);
  }

  // --- Saved Answers Page ---
  void openSavedAnswers() {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => SavedAnswersFirebasePage(petNameMap: petNameMap)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Vet AI Assist',
          style: GoogleFonts.notoSans(
              fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
        ),
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => HomePage()),
            );
          },
        ),
        backgroundColor: const Color.fromRGBO(255, 238, 47, 1),
        actions: [
          IconButton(
            icon: Icon(Icons.star, color: Colors.orange),
            onPressed: openSavedAnswers,
            tooltip: "Saved Answers",
          ),
          IconButton(
            icon: Icon(Icons.photo_camera),
            onPressed: () => pickImage(ImageSource.camera),
          ),
          IconButton(
            icon: Icon(Icons.photo_library),
            onPressed: () => pickImage(ImageSource.gallery),
          ),
          IconButton(
            icon: Icon(Icons.mic,
                color: _isListening ? Colors.red : Colors.black),
            onPressed: _isListening ? stopListening : startListening,
            tooltip: "Voice Input",
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (petNameMap.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
                child: Row(
                  children: [
                    const Icon(Icons.pets, size: 20, color: Colors.teal),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButton<String>(
                        value: selectedPetId,
                        isExpanded: true,
                        icon: Icon(Icons.arrow_drop_down),
                        items: petNameMap.entries
                            .map((e) => DropdownMenuItem<String>(
                                  value: e.key,
                                  child: Text(e.value),
                                ))
                            .toList(),
                        onChanged: (id) => setState(() => selectedPetId = id),
                      ),
                    ),
                  ],
                ),
              ),
            if (selectedImage != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Image.file(File(selectedImage!.path), height: 150),
              ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: faqQuestions
                    .map((q) => Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ActionChip(
                            label: Text(q),
                            onPressed: () => sendMessage(q),
                            backgroundColor: Colors.yellow[100],
                          ),
                        ))
                    .toList(),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: messages.length + (isTyping ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index < messages.length) {
                    return buildMessageBubble(messages[index]);
                  } else {
                    return const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Center(
                        child: SpinKitThreeBounce(
                          color: Colors.grey,
                          size: 20.0,
                        ),
                      ),
                    );
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: textController,
                      onSubmitted: sendMessage,
                      decoration: InputDecoration(
                        hintText: "Describe your pet issue...",
                        filled: true,
                        fillColor: Colors.grey[200],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => sendMessage(textController.text),
                    icon: const Icon(Icons.send, color: Colors.black),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Chat Message Data Class ---
class _ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final String id;
  final bool isUrgent;
  String firebaseId; // For firestore doc id if saved

  _ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    required this.id,
    this.isUrgent = false,
    this.firebaseId = '',
  });
}

// --- Saved Answers Page (from Firebase) ---
class SavedAnswersFirebasePage extends StatelessWidget {
  final Map<String, String> petNameMap;
  const SavedAnswersFirebasePage({super.key, required this.petNameMap});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null)
      return Scaffold(body: Center(child: Text("Not logged in")));
    return Scaffold(
      appBar: AppBar(
        title: Text("Saved Answers"),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('ai_saved_answers')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return Center(child: Text("No saved answers."));
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final petName = petNameMap[data['petId']] ?? '';
              final List images = data['images'] ?? [];
              return Card(
                margin: EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                child: ListTile(
                  title: Text(
                    _firstLine(data['text'] ?? ''),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: petName.isNotEmpty ? Text("Pet: $petName") : null,
                  trailing: IconButton(
                    icon: Icon(Icons.delete, color: Colors.red),
                    onPressed: () async {
                      final confirm = await showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text("Delete Saved Answer"),
                          content: Text(
                              "Are you sure you want to delete this saved answer?"),
                          actions: [
                            TextButton(
                              child: Text("Cancel"),
                              onPressed: () => Navigator.pop(ctx, false),
                            ),
                            TextButton(
                              child: Text("Delete"),
                              onPressed: () => Navigator.pop(ctx, true),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await snapshot.data!.docs[i].reference.delete();
                      }
                    },
                  ),
                  onTap: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => SavedAnswerDetailPage(
                                answerData: data,
                                petName: petName,
                                petId: data['petId'] ?? '')));
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _firstLine(String text) {
    return text.split('\n').first;
  }
}

class SavedAnswerDetailPage extends StatefulWidget {
  final Map<String, dynamic> answerData;
  final String petName;
  final String petId;

  const SavedAnswerDetailPage(
      {super.key,
      required this.answerData,
      required this.petName,
      required this.petId});

  @override
  State<SavedAnswerDetailPage> createState() => _SavedAnswerDetailPageState();
}

class _SavedAnswerDetailPageState extends State<SavedAnswerDetailPage> {
  List<Map<String, dynamic>> _records = [];
  Map<String, dynamic>? _petInfo;

  @override
  void initState() {
    super.initState();
    _fetchPetAndRecords();
  }

  Future<void> _fetchPetAndRecords() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || widget.petId.isEmpty) return;

    final petDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('pets')
        .doc(widget.petId)
        .get();
    setState(() {
      _petInfo = petDoc.data();
    });

    final recordsQuery = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('pets')
        .doc(widget.petId)
        .collection('records')
        .orderBy('date', descending: true)
        .limit(3) // Latest 3
        .get();
    setState(() {
      _records = recordsQuery.docs.map((d) => d.data()).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = _stripLinks(widget.answerData['text'] ?? '');
    final List images = widget.answerData['images'] ?? [];

    return Scaffold(
      appBar: AppBar(title: Text("Saved Answer")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.petName.isNotEmpty) ...[
              Text("Pet: ${widget.petName}",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              if (_petInfo != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    "Species: ${_petInfo?['species'] ?? ''}\n"
                    "Breed: ${_petInfo?['breed'] ?? ''}\n"
                    "Gender: ${_petInfo?['gender'] ?? ''}\n"
                    "Birthday: ${_petInfo?['birthday'] ?? ''}",
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ),
              Divider(),
            ],
            Text.rich(_boldParser(text),
                style: TextStyle(fontSize: 16, height: 1.5)),
            if (images.isNotEmpty) ...[
              SizedBox(height: 16),
              Text("Related Images:",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(
                height: 110,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: images.length,
                  itemBuilder: (ctx, i) {
                    final url = images[i];
                    return Padding(
                      padding: const EdgeInsets.all(6.0),
                      child: _isValidImageUrl(url)
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                url,
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                                errorBuilder: (ctx, error, stack) =>
                                    Icon(Icons.broken_image, size: 50),
                              ),
                            )
                          : Icon(Icons.broken_image, size: 50),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Remove links from output (urls, clickable or not)
  String _stripLinks(String text) {
    final urlReg = RegExp(r'https?://[^\s]+');
    return text.replaceAll(urlReg, '');
  }

  // Render **bold** as real bold text
  TextSpan _boldParser(String input) {
    final pattern = RegExp(r'\*\*(.*?)\*\*');
    final spans = <TextSpan>[];
    int current = 0;

    for (final match in pattern.allMatches(input)) {
      if (match.start > current) {
        spans.add(TextSpan(text: input.substring(current, match.start)));
      }
      spans.add(TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.bold)));
      current = match.end;
    }
    if (current < input.length) {
      spans.add(TextSpan(text: input.substring(current)));
    }
    return TextSpan(children: spans);
  }

  bool _isValidImageUrl(String url) {
    return url.startsWith('http') &&
        (url.endsWith('.jpg') ||
            url.endsWith('.png') ||
            url.endsWith('.jpeg') ||
            url.contains("googleusercontent") ||
            url.contains("imgur.com"));
  }
}
