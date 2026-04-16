import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackendConfig.load();
  runApp(const BookMyHospitalAdminApp());
}

const String kDefaultApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8080',
);

class BackendConfig {
  static const _prefsKey = 'bookmyhospital_api_base_url';
  static String baseUrl = kDefaultApiBaseUrl;
  static bool configured = false;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null && saved.trim().isNotEmpty) {
      baseUrl = saved.trim();
      configured = true;
    }
  }

  static Future<void> save(String url) async {
    final cleaned = url.trim();
    if (cleaned.isEmpty) return;
    baseUrl = cleaned;
    configured = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, cleaned);
  }
}

class BookMyHospitalAdminApp extends StatelessWidget {
  const BookMyHospitalAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BookMyHospital Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E3A8A)),
      ),
      home: const AdminLoginScreen(),
    );
  }
}

class PendingHospital {
  PendingHospital({
    required this.id,
    required this.name,
    required this.email,
    required this.location,
  });

  final String id;
  final String name;
  final String email;
  final String location;

  factory PendingHospital.fromJson(Map<String, dynamic> map) => PendingHospital(
    id: map['id']?.toString() ?? '',
    name: map['name']?.toString() ?? '',
    email: map['email']?.toString() ?? '',
    location: map['location']?.toString() ?? '',
  );
}

class Complaint {
  Complaint({
    required this.id,
    required this.hospitalId,
    required this.hospitalName,
    required this.patientId,
    required this.patientName,
    required this.description,
    required this.status,
    required this.proofUrls,
    required this.createdAt,
  });

  final String id;
  final String hospitalId;
  final String hospitalName;
  final String patientId;
  final String patientName;
  final String description;
  final String status;
  final List<String> proofUrls;
  final String createdAt;

  factory Complaint.fromJson(Map<String, dynamic> map) => Complaint(
    id: map['id']?.toString() ?? '',
    hospitalId: map['hospitalId']?.toString() ?? '',
    hospitalName: map['hospitalName']?.toString() ?? 'Unknown Hospital',
    patientId: map['patientId']?.toString() ?? 'not-provided',
    patientName: map['patientName']?.toString() ?? '',
    description: map['description']?.toString() ?? '',
    status: map['status']?.toString() ?? 'open',
    proofUrls: (map['proofUrls'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList(),
    createdAt: map['createdAt']?.toString() ?? '',
  );
}

class HospitalAccount {
  HospitalAccount({
    required this.id,
    required this.name,
    required this.email,
    required this.location,
    required this.status,
  });

  final String id;
  final String name;
  final String email;
  final String location;
  final String status;

  factory HospitalAccount.fromJson(Map<String, dynamic> map) => HospitalAccount(
    id: map['id']?.toString() ?? '',
    name: map['name']?.toString() ?? '',
    email: map['email']?.toString() ?? '',
    location: map['location']?.toString() ?? '',
    status: map['status']?.toString() ?? 'unknown',
  );
}

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _pinController = TextEditingController();
  String? _error;

  Future<void> _setBackendUrl() async {
    final controller = TextEditingController(text: BackendConfig.baseUrl);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backend Server URL'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'http://192.168.1.10:8080',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await BackendConfig.save(controller.text);
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Server set to ${BackendConfig.baseUrl}')),
      );
    }
  }

  void _login() {
    if (_pinController.text.trim() == 'BMH-DEV-2026') {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const AdminDashboardScreen()),
      );
      return;
    }
    setState(() => _error = 'Invalid dev/admin access code');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'BookMyHospital Admin',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _setBackendUrl,
                    icon: const Icon(Icons.link),
                    label: Text('Backend: ${BackendConfig.baseUrl}'),
                  ),
                  const SizedBox(height: 8),
                  const Text('Use demo admin code: BMH-DEV-2026'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pinController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Admin Code',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _login,
                    child: const Text('Secure Login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _loading = true;
  List<PendingHospital> _pending = [];
  List<Complaint> _complaints = [];
  List<HospitalAccount> _deactivatedHospitals = [];
  Map<String, dynamic> _usersByLocation = {};
  int _approvedCount = 0;
  int _bookingCount = 0;
  io.Socket? _socket;

  @override
  void initState() {
    super.initState();
    _load();
    _connectLive();
  }

  void _connectLive() {
    try {
      final socket = io.io(
        BackendConfig.baseUrl,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .build(),
      );
      for (final event in [
        'overview:update',
        'hospital:pending',
        'hospital:approved',
        'hospital:declined',
        'hospital:availability-updated',
        'hospital:status-updated',
        'booking:created',
        'complaint:created',
      ]) {
        socket.on(event, (_) => _load());
      }
      socket.connect();
      _socket = socket;
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final results = await Future.wait([
        http.get(
          Uri.parse('${BackendConfig.baseUrl}/api/hospitals?status=pending'),
        ),
        http.get(Uri.parse('${BackendConfig.baseUrl}/api/admin/overview')),
        http.get(
          Uri.parse(
            '${BackendConfig.baseUrl}/api/hospitals?status=deactivated',
          ),
        ),
      ]);

      final pendingRes = results[0];
      final overviewRes = results[1];
      final deactivatedRes = results[2];

      if (pendingRes.statusCode != 200 ||
          overviewRes.statusCode != 200 ||
          deactivatedRes.statusCode != 200) {
        throw Exception('Failed to load admin dashboard data');
      }

      final pendingJson = jsonDecode(pendingRes.body) as Map<String, dynamic>;
      final pending = (pendingJson['hospitals'] as List<dynamic>? ?? [])
          .map((e) => PendingHospital.fromJson(e as Map<String, dynamic>))
          .toList();

      final overview = jsonDecode(overviewRes.body) as Map<String, dynamic>;
      final deactivatedJson =
          jsonDecode(deactivatedRes.body) as Map<String, dynamic>;
      final deactivatedHospitals =
          (deactivatedJson['hospitals'] as List<dynamic>? ?? [])
              .map((e) => HospitalAccount.fromJson(e as Map<String, dynamic>))
              .toList();

      final deactivatedIds = deactivatedHospitals.map((h) => h.id).toSet();
      final complaints = (overview['complaints'] as List<dynamic>? ?? [])
          .map((e) => Complaint.fromJson(e as Map<String, dynamic>))
          .where((c) => !deactivatedIds.contains(c.hospitalId))
          .toList();

      if (!mounted) return;
      setState(() {
        _pending = pending;
        _complaints = complaints;
        _deactivatedHospitals = deactivatedHospitals;
        _usersByLocation =
            overview['usersByLocation'] as Map<String, dynamic>? ?? {};
        _approvedCount = (overview['hospitalsApproved'] ?? 0) as int;
        _bookingCount = (overview['bookings'] as List<dynamic>? ?? []).length;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Backend not reachable. Start backend service.'),
        ),
      );
    }
  }

  Future<void> _review(PendingHospital hospital, String action) async {
    await http.patch(
      Uri.parse('${BackendConfig.baseUrl}/api/hospitals/${hospital.id}/status'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'action': action}),
    );
    await _load();
  }

  @override
  void dispose() {
    _socket?.dispose();
    super.dispose();
  }

  Future<void> _discipline(String hospitalId, String action) async {
    final response = await http.patch(
      Uri.parse(
        '${BackendConfig.baseUrl}/api/admin/hospitals/$hospitalId/discipline',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'action': action}),
    );
    if (!mounted) return;
    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hospital action applied: $action')),
      );
      await _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not apply action right now.')),
      );
    }
  }

  bool _isImageUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif');
  }

  Future<void> _openComplaintDetails(Complaint complaint) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Complaint • ${complaint.hospitalName}'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Complaint ID: ${complaint.id}'),
                Text('Patient Unique ID: ${complaint.patientId}'),
                Text('Patient Name: ${complaint.patientName}'),
                Text('Hospital ID: ${complaint.hospitalId}'),
                const SizedBox(height: 8),
                Text(complaint.description),
                const SizedBox(height: 12),
                Text('Attached Proofs (${complaint.proofUrls.length})'),
                const SizedBox(height: 8),
                if (complaint.proofUrls.isEmpty)
                  const Text('No media attachment found.')
                else
                  ...complaint.proofUrls.map(
                    (url) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                            url,
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 6),
                          if (_isImageUrl(url))
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                url,
                                height: 140,
                                width: 240,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Text('Preview unavailable'),
                              ),
                            )
                          else
                            const Row(
                              children: [
                                Icon(Icons.videocam_outlined),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Video/file link available above',
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Control Room'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _kpi('Approved Hospitals', _approvedCount.toString()),
                    _kpi('Pending Approvals', _pending.length.toString()),
                    _kpi('Bookings', _bookingCount.toString()),
                    _kpi('Complaints', _complaints.length.toString()),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Hospital Approval Queue',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ..._pending.map(
                  (h) => Card(
                    child: ListTile(
                      title: Text(h.name),
                      subtitle: Text('${h.location} • ${h.email}'),
                      trailing: Wrap(
                        spacing: 6,
                        children: [
                          FilledButton.tonal(
                            onPressed: () => _review(h, 'approve'),
                            child: const Text('Approve'),
                          ),
                          OutlinedButton(
                            onPressed: () => _review(h, 'decline'),
                            child: const Text('Decline'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Deactivated Accounts',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (_deactivatedHospitals.isEmpty)
                  const Card(
                    child: ListTile(
                      title: Text('No deactivated accounts'),
                      subtitle: Text(
                        'Deactivated hospitals will appear here for Reactivate or Ban actions.',
                      ),
                    ),
                  )
                else
                  ..._deactivatedHospitals.map(
                    (h) => Card(
                      child: ListTile(
                        title: Text(h.name),
                        subtitle: Text('${h.location} • ${h.email}'),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.green,
                              ),
                              onPressed: () => _discipline(h.id, 'activate'),
                              child: const Text('Activate'),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                              onPressed: () => _discipline(h.id, 'ban'),
                              child: const Text('Ban'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Users by Location',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: _usersByLocation.entries
                          .map(
                            (e) => ListTile(
                              dense: true,
                              title: Text(e.key),
                              trailing: Text(e.value.toString()),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Complaint Inbox',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ..._complaints.map(
                  (c) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Hospital: ${c.hospitalName} (${c.hospitalId})'),
                          Text(
                            'Patient: ${c.patientName} • ID: ${c.patientId}',
                          ),
                          const SizedBox(height: 4),
                          Text(c.description),
                          if (c.proofUrls.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Media attached: ${c.proofUrls.length} file(s)',
                            ),
                          ],
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              FilledButton.tonal(
                                onPressed: () => _openComplaintDetails(c),
                                child: const Text('Open Complaint'),
                              ),
                              OutlinedButton(
                                onPressed: () =>
                                    _discipline(c.hospitalId, 'deactivate'),
                                child: const Text('Deactivate Hospital'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    _discipline(c.hospitalId, 'ban'),
                                child: const Text('Ban Permanently'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _kpi(String label, String value) {
    return Card(
      child: SizedBox(
        width: 170,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}
