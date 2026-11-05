import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'core.dart';
import 'ai.dart';
import 'package:open_file/open_file.dart';
import 'dart:io';

void main() {
  runApp(const JobBotApp());
}

class JobBotApp extends StatelessWidget {
  const JobBotApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JobBot AI',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final List<Widget> _screens = [
    const SearchScreen(),
    const JobsScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
          BottomNavigationBarItem(icon: Icon(Icons.work), label: 'Jobs'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _queryController = TextEditingController();
  bool _loading = false;
  String _log = "";

  void _search() async {
    setState(() { _loading = true; _log = "Searching Adzuna and AI..."; });
    final settings = await Core.getSettings();
    String province = settings['province']!;
    
    try {
      var jobs = await AI.searchJobs(_queryController.text, province, settings);
      await AI.saveJobsToDb(jobs);
      setState(() { _log = "Found and saved ${jobs.length} jobs!"; });
    } catch (e) {
      setState(() { _log = "Error: $e"; });
    } finally {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("JobBot AI Search")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _queryController,
              decoration: const InputDecoration(labelText: "What job are you looking for?", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loading ? null : _search,
              child: _loading ? const CircularProgressIndicator() : const Text("Run AI Search"),
            ),
            const SizedBox(height: 20),
            Text(_log, style: const TextStyle(fontSize: 16, color: Colors.blue)),
          ],
        ),
      ),
    );
  }
}

class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});
  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  List<Map<String, dynamic>> _jobs = [];

  void _loadJobs() async {
    final db = await Core.getDb();
    final jobs = await db.query('jobs', orderBy: 'matchScore DESC');
    setState(() { _jobs = jobs; });
  }

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  void _sendEmail(Map<String, dynamic> job) async {
    final settings = await Core.getSettings();
    final pdfPath = await Core.generatePdf({'name': 'Applicant', 'summary': 'Hard worker...', 'skills': 'Forklift, Admin'}, job['title']);
    String res = await Core.sendEmail(settings, job['email'], "Application for ${job['title']}", "Dear Hiring Manager,\n\nPlease find my CV attached.", pdfPath);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Found Jobs"), actions: [
        IconButton(onPressed: _loadJobs, icon: const Icon(Icons.refresh))
      ]),
      body: ListView.builder(
        itemCount: _jobs.length,
        itemBuilder: (context, index) {
          final job = _jobs[index];
          return Card(
            child: ListTile(
              title: Text(job['title']),
              subtitle: Text("${job['company']} | Match: ${job['matchScore']}%\n${job['aiReason']}"),
              trailing: IconButton(
                icon: const Icon(Icons.send, color: Colors.green),
                onPressed: () => _sendEmail(job),
              ),
            ),
          );
        },
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _aiKey = TextEditingController();
  final _adzunaId = TextEditingController();
  final _adzunaKey = TextEditingController();
  final _smtpUser = TextEditingController();
  final _smtpPass = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() async {
    final s = await Core.getSettings();
    _aiKey.text = s['ai_key']!;
    _adzunaId.text = s['adzuna_id']!;
    _adzunaKey.text = s['adzuna_key']!;
    _smtpUser.text = s['smtp_user']!;
    _smtpPass.text = s['smtp_pass']!;
  }

  void _save() async {
    await Core.saveSettings({
      'ai_key': _aiKey.text,
      'adzuna_id': _adzunaId.text,
      'adzuna_key': _adzunaKey.text,
      'smtp_user': _smtpUser.text,
      'smtp_pass': _smtpPass.text,
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Settings Saved!")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _aiKey, decoration: const InputDecoration(labelText: "OpenAI API Key (sk-...)")),
          TextField(controller: _adzunaId, decoration: const InputDecoration(labelText: "Adzuna App ID")),
          TextField(controller: _adzunaKey, decoration: const InputDecoration(labelText: "Adzuna App Key")),
          const Divider(),
          TextField(controller: _smtpUser, decoration: const InputDecoration(labelText: "Gmail Address")),
          TextField(controller: _smtpPass, decoration: const InputDecoration(labelText: "Gmail App Password")),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: _save, child: const Text("Save Settings")),
        ],
      ),
    );
  }
}
