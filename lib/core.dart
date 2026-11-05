import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:path_provider/path_provider.dart';

class Core {
  static Database? _db;

  static Future<Database> getDb() async {
    if (_db != null) return _db!;
    _db = await openDatabase(
      join(await getDatabasesPath(), 'jobbot.db'),
      onCreate: (db, version) {
        db.execute('''CREATE TABLE jobs(uid TEXT PRIMARY KEY, title TEXT, company TEXT, location TEXT, url TEXT, description TEXT, email TEXT, matchScore INTEGER, scamScore INTEGER, selected INTEGER, cvMode TEXT, provider TEXT, aiReason TEXT)''');
        db.execute('''CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT)''');
      },
      version: 1,
    );
    return _db!;
  }

  static Future<Map<String, String>> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'ai_key': prefs.getString('ai_key') ?? '',
      'smtp_user': prefs.getString('smtp_user') ?? '',
      'smtp_pass': prefs.getString('smtp_pass') ?? '',
      'adzuna_id': prefs.getString('adzuna_id') ?? '',
      'adzuna_key': prefs.getString('adzuna_key') ?? '',
      'province': prefs.getString('province') ?? 'gauteng',
    };
  }

  static Future<void> saveSettings(Map<String, String> s) async {
    final prefs = await SharedPreferences.getInstance();
    for (var e in s.entries) {
      await prefs.setString(e.key, e.value);
    }
  }

  static int calculateScamScore(String text) {
    int score = 0;
    String t = text.toLowerCase();
    if (t.contains('telegram') || t.contains('registration fee') || t.contains('whatsapp only')) score += 40;
    return score;
  }

  static int calculateMatchScore(String text) {
    int score = 30;
    String t = text.toLowerCase();
    List<String> kw = ['customer service', 'admin', 'office', 'assistant', 'driver', 'warehouse'];
    for (String k in kw) {
      if (t.contains(k)) score += 10;
    }
    return score > 100 ? 100 : score;
  }

  static Future<String> generatePdf(Map<String, String> cvData, String jobTitle) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(cvData['name'] ?? 'Applicant', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Text('Application for: $jobTitle', style: pw.TextStyle(fontSize: 14, fontStyle: pw.FontStyle.italic)),
            pw.Divider(),
            pw.Text('Summary', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text(cvData['summary'] ?? ''),
            pw.SizedBox(height: 10),
            pw.Text('Skills', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text(cvData['skills'] ?? ''),
          ],
        ),
      ),
    );
    final output = await getTemporaryDirectory();
    final file = File("${output.path}/CV_${jobTitle.replaceAll(' ', '_')}.pdf");
    await file.writeAsBytes(await pdf.save());
    return file.path;
  }

  static Future<String> sendEmail(Map<String, String> settings, String to, String subject, String body, String attachmentPath) async {
    try {
      String username = settings['smtp_user']!;
      String password = settings['smtp_pass']!;
      if (password.isEmpty) return "No SMTP password saved.";

      final smtpServer = gmail(username, password);
      final message = Message()
        ..from = Address(username, 'JobBot Applicant')
        ..recipients.add(to)
        ..subject = subject
        ..text = body
        ..attachments.add(FileAttachment(File(attachmentPath)));

      await send(message, smtpServer);
      return "Sent successfully!";
    } catch (e) {
      return "Failed to send: $e";
    }
  }
}
