import 'dart:convert';
import 'package:http/http.dart' as http;
import 'core.dart';

class AI {
  static Future<List<Map<String, dynamic>>> searchJobs(String query, String province, Map<String, String> settings) async {
    List<Map<String, dynamic>> jobs = [];
    
    if (settings['adzuna_id']!.isNotEmpty && settings['adzuna_key']!.isNotEmpty) {
      final url = Uri.parse('https://api.adzuna.com/v1/api/jobs/za/search/1?app_id=${settings['adzuna_id']}&app_key=${settings['adzuna_key']}&what=$query&where=$province');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        var data = jsonDecode(res.body);
        for (var item in data['results']) {
          jobs.add({
            'uid': item['id'].toString(),
            'title': item['title'],
            'company': item['company']['display_name'] ?? 'Unknown',
            'location': item['location']['display_name'] ?? province,
            'url': item['redirect_url'],
            'description': item['description'],
            'provider': 'Adzuna',
          });
        }
      }
    }

    if (settings['ai_key']!.isNotEmpty && jobs.isNotEmpty) {
      jobs = await _rankJobs(jobs, settings['ai_key']!);
    }

    return jobs;
  }

  static Future<List<Map<String, dynamic>>> _rankJobs(List<Map<String, dynamic>> jobs, String apiKey) async {
    final url = Uri.parse('https://api.openai.com/v1/chat/completions');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };
    
    String jobList = jobs.map((j) => "UID: ${j['uid']} | TITLE: ${j['title']} | DESC: ${j['description'].toString().substring(0, 200)}").join("\n\n");
    
    final body = jsonEncode({
      "model": "gpt-4o-mini",
      "messages": [
        {"role": "system", "content": "You are a job matcher. Score these jobs 0-100 based on fit and scam risk. Reply JSON: {\"results\": [{\"uid\": \"\", \"fit\": 0, \"reason\": \"\"}]}"},
        {"role": "user", "content": jobList}
      ],
      "response_format": {"type": "json_object"}
    });

    try {
      final res = await http.post(url, headers: headers, body: body);
      if (res.statusCode == 200) {
        var data = jsonDecode(jsonDecode(res.body)['choices'][0]['message']['content']);
        for (var result in data['results']) {
          var job = jobs.firstWhere((j) => j['uid'] == result['uid'], orElse: () => null);
          if (job != null) {
            job['matchScore'] = result['fit'];
            job['aiReason'] = result['reason'];
          }
        }
      }
    } catch (e) {
      print("AI Ranking failed: $e");
    }
    return jobs;
  }

  static Future<void> saveJobsToDb(List<Map<String, dynamic>> jobs) async {
    final db = await Core.getDb();
    for (var j in jobs) {
      await db.insert('jobs', {
        'uid': j['uid'],
        'title': j['title'],
        'company': j['company'],
        'location': j['location'],
        'url': j['url'],
        'description': j['description'],
        'email': '',
        'matchScore': j['matchScore'] ?? Core.calculateMatchScore(j['description']),
        'scamScore': Core.calculateScamScore(j['description']),
        'selected': 0,
        'cvMode': 'custom',
        'provider': j['provider'],
        'aiReason': j['aiReason'] ?? 'Keyword Matched',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }
}
