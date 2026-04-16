import 'dart:convert';
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackendConfig.load();
  runApp(const BookMyHospitalApp());
}

const String kDefaultApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8080',
);

class BackendConfig {
  static const _prefsKey = 'bookmyhospital_api_base_url';
  static const _patientIdKey = 'bookmyhospital_patient_unique_id';
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

  static Future<String> getOrCreatePatientId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_patientIdKey);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing.trim();
    }
    final random = Random();
    final generated =
        'pat_${DateTime.now().millisecondsSinceEpoch}_${1000 + random.nextInt(9000)}';
    await prefs.setString(_patientIdKey, generated);
    return generated;
  }
}

class BookMyHospitalApp extends StatelessWidget {
  const BookMyHospitalApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0D9488),
        brightness: Brightness.light,
      ),
      useMaterial3: true,
    );

    return MaterialApp(
      title: 'BookMyHospital',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(scaffoldBackgroundColor: const Color(0xFFF0FDFA)),
      home: const EntryScreen(),
    );
  }
}

class HospitalInfo {
  HospitalInfo({
    required this.id,
    required this.name,
    required this.email,
    required this.location,
    required this.bedsAvailable,
    required this.icuAvailable,
    required this.otAvailable,
    required this.doctorsAvailable,
    required this.surgeonsAvailable,
    required this.queueWaitMinutes,
    required this.avgReview,
    required this.specialities,
    required this.status,
  });

  final String id;
  final String name;
  final String email;
  final String location;
  final int bedsAvailable;
  final int icuAvailable;
  final int otAvailable;
  final int doctorsAvailable;
  final int surgeonsAvailable;
  final int queueWaitMinutes;
  final double avgReview;
  final List<String> specialities;
  final String status;

  factory HospitalInfo.fromJson(Map<String, dynamic> json) {
    return HospitalInfo(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown Hospital',
      email: json['email']?.toString() ?? '',
      location: json['location']?.toString() ?? 'Unknown',
      bedsAvailable: (json['bedsAvailable'] ?? 0) as int,
      icuAvailable: (json['icuAvailable'] ?? 0) as int,
      otAvailable: (json['otAvailable'] ?? 0) as int,
      doctorsAvailable: (json['doctorsAvailable'] ?? 0) as int,
      surgeonsAvailable: (json['surgeonsAvailable'] ?? 0) as int,
      queueWaitMinutes: (json['queueWaitMinutes'] ?? 0) as int,
      avgReview: ((json['avgReview'] ?? 0) as num).toDouble(),
      specialities: ((json['specialities'] ?? []) as List)
          .map((item) => item.toString())
          .toList(),
      status: json['status']?.toString() ?? 'approved',
    );
  }
}

class ApiService {
  Future<List<HospitalInfo>> getApprovedHospitals() async {
    try {
      final uri = Uri.parse(
        '${BackendConfig.baseUrl}/api/hospitals?status=approved',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        return _fallbackHospitals;
      }
      final map = jsonDecode(response.body) as Map<String, dynamic>;
      final list = (map['hospitals'] as List<dynamic>? ?? [])
          .map((item) => HospitalInfo.fromJson(item as Map<String, dynamic>))
          .toList();
      return list;
    } catch (_) {
      return _fallbackHospitals;
    }
  }

  Future<bool> submitHospitalRegistration(Map<String, dynamic> payload) async {
    try {
      final uri = Uri.parse('${BackendConfig.baseUrl}/api/hospitals/register');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      return response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  Future<HospitalInfo?> loginHospital(String email) async {
    try {
      final uri = Uri.parse('${BackendConfig.baseUrl}/api/hospitals/auth');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      if (response.statusCode != 200) {
        return null;
      }
      final map = jsonDecode(response.body) as Map<String, dynamic>;
      final hospital = map['hospital'] as Map<String, dynamic>?;
      if (hospital == null) return null;
      return HospitalInfo.fromJson(hospital);
    } catch (_) {
      return null;
    }
  }

  Future<bool> createBooking({
    required String hospitalId,
    required String patientName,
    required String patientId,
    required String type,
  }) async {
    try {
      final uri = Uri.parse('${BackendConfig.baseUrl}/api/bookings');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'hospitalId': hospitalId,
          'patientName': patientName,
          'patientId': patientId,
          'type': type,
        }),
      );
      return response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  Future<bool> submitComplaint({
    required String hospitalId,
    required String patientName,
    required String patientId,
    required String description,
    List<String> proofPaths = const [],
  }) async {
    try {
      final uri = Uri.parse('${BackendConfig.baseUrl}/api/complaints');
      final request = http.MultipartRequest('POST', uri)
        ..fields['hospitalId'] = hospitalId
        ..fields['patientName'] = patientName
        ..fields['patientId'] = patientId
        ..fields['description'] = description;

      for (final proofPath in proofPaths) {
        if (proofPath.trim().isEmpty) continue;
        request.files.add(
          await http.MultipartFile.fromPath('proofs', proofPath),
        );
      }

      final streamed = await request.send();
      return streamed.statusCode == 201;
    } catch (_) {
      return false;
    }
  }
}

final List<HospitalInfo> _fallbackHospitals = [
  HospitalInfo(
    id: 'hosp_1',
    name: 'CityCare Multispeciality Hospital',
    email: 'citycare@bmh.in',
    location: 'Pune',
    bedsAvailable: 11,
    icuAvailable: 3,
    otAvailable: 1,
    doctorsAvailable: 18,
    surgeonsAvailable: 6,
    queueWaitMinutes: 34,
    avgReview: 4.5,
    specialities: ['Cardiology', 'Trauma', 'Critical Care'],
    status: 'approved',
  ),
  HospitalInfo(
    id: 'hosp_2',
    name: 'Sunrise Emergency & Trauma',
    email: 'sunrise@bmh.in',
    location: 'Mumbai',
    bedsAvailable: 8,
    icuAvailable: 2,
    otAvailable: 1,
    doctorsAvailable: 9,
    surgeonsAvailable: 3,
    queueWaitMinutes: 29,
    avgReview: 4.2,
    specialities: ['Emergency', 'Orthopedics'],
    status: 'approved',
  ),
  HospitalInfo(
    id: 'hosp_3',
    name: 'Green Valley Women & Child Hospital',
    email: 'greenvalley@bmh.in',
    location: 'Nashik',
    bedsAvailable: 6,
    icuAvailable: 2,
    otAvailable: 1,
    doctorsAvailable: 7,
    surgeonsAvailable: 2,
    queueWaitMinutes: 21,
    avgReview: 4.6,
    specialities: ['Pediatrics', 'Gynecology'],
    status: 'approved',
  ),
];

class EntryScreen extends StatelessWidget {
  const EntryScreen({super.key});

  Future<void> _setBackendUrl(BuildContext context) async {
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
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Server set to ${BackendConfig.baseUrl}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFCCFBF1), Color(0xFFF0FDFA), Color(0xFFFFFFFF)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                Text(
                  'BookMyHospital',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF134E4A),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Hospitals at your fingertips — fast, calm, and reliable in emergencies.',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _setBackendUrl(context),
                  icon: const Icon(Icons.link),
                  label: Text('Backend: ${BackendConfig.baseUrl}'),
                ),
                const Spacer(),
                _RoleCard(
                  title: 'Join as Patient',
                  subtitle:
                      'Google sign-in, live availability, pre-booking, reviews, complaints.',
                  icon: Icons.favorite,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PatientAuthScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                _RoleCard(
                  title: 'Join as Hospital',
                  subtitle:
                      'Submit registration docs, wait for admin approval, then manage live availability.',
                  icon: Icons.local_hospital,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const HospitalRegistrationScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFF99F6E4),
                child: Icon(icon, color: const Color(0xFF134E4A)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PatientAuthScreen extends StatefulWidget {
  const PatientAuthScreen({super.key});

  @override
  State<PatientAuthScreen> createState() => _PatientAuthScreenState();
}

class _PatientAuthScreenState extends State<PatientAuthScreen> {
  bool _loading = false;
  final _googleSignIn = GoogleSignIn();

  Future<void> _signIn() async {
    setState(() => _loading = true);
    String name = 'Demo Patient';
    String email = 'patient.demo@bmh.in';

    try {
      final account = await _googleSignIn.signIn();
      if (account != null) {
        name = account.displayName ?? name;
        email = account.email;
      }
    } catch (_) {
      // Fall back to demo profile if Google OAuth is not configured yet.
    }

    if (!mounted) return;
    setState(() => _loading = false);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            PatientHomeScreen(patientName: name, patientEmail: email),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Patient Login')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Text('Sign in with Google for quick and secure access.'),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _loading ? null : _signIn,
              icon: const Icon(Icons.login),
              label: Text(_loading ? 'Signing in...' : 'Continue with Google'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Tip: In demo mode, app can continue with a fallback patient account.',
            ),
          ],
        ),
      ),
    );
  }
}

class PatientHomeScreen extends StatefulWidget {
  const PatientHomeScreen({
    super.key,
    required this.patientName,
    required this.patientEmail,
  });

  final String patientName;
  final String patientEmail;

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  final ApiService _api = ApiService();
  List<HospitalInfo> _hospitals = [];
  bool _loading = true;
  String _patientUniqueId = '';
  Timer? _pollTimer;
  io.Socket? _socket;
  DateTime? _lastSync;

  @override
  void initState() {
    super.initState();
    _initPatientId();
    _loadHospitals();
    _connectLive();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _loadHospitals(),
    );
  }

  Future<void> _initPatientId() async {
    final id = await BackendConfig.getOrCreatePatientId();
    if (!mounted) return;
    setState(() => _patientUniqueId = id);
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
      socket.onConnect((_) {});
      socket.on('overview:update', (_) => _loadHospitals());
      socket.on('hospital:availability-updated', (_) => _loadHospitals());
      socket.on('booking:created', (_) => _loadHospitals());
      socket.connect();
      _socket = socket;
    } catch (_) {
      // If sockets fail, polling still keeps the dashboard live.
    }
  }

  Future<void> _loadHospitals() async {
    final data = await _api.getApprovedHospitals();
    if (!mounted) return;
    setState(() {
      _hospitals = data;
      _loading = false;
      _lastSync = DateTime.now();
    });
  }

  Future<void> _book(HospitalInfo hospital, String type) async {
    final ok = await _api.createBooking(
      hospitalId: hospital.id,
      patientName: widget.patientName,
      patientId: _patientUniqueId,
      type: type,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '$type pre-booked at ${hospital.name}'
              : 'Could not place booking right now.',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _socket?.dispose();
    super.dispose();
  }

  Future<void> _complain(HospitalInfo hospital) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    List<String> proofPaths = [];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Complaint for ${hospital.name}'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: controller,
                      maxLines: 3,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Describe the issue'
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final result = await FilePicker.platform.pickFiles(
                          allowMultiple: true,
                          type: FileType.media,
                        );
                        if (result == null) return;
                        setModalState(() {
                          proofPaths = result.files
                              .where((file) => file.path != null)
                              .map((file) => file.path!)
                              .toList();
                        });
                      },
                      icon: const Icon(Icons.attach_file),
                      label: Text(
                        proofPaths.isEmpty
                            ? 'Attach photo/video proof'
                            : '${proofPaths.length} file(s) attached',
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (proofPaths.isNotEmpty)
                      Text(
                        proofPaths
                            .map((path) => path.split('/').last)
                            .join(', '),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) {
                          return;
                        }
                        final ok = await _api.submitComplaint(
                          hospitalId: hospital.id,
                          patientName: widget.patientName,
                          patientId: _patientUniqueId,
                          description: controller.text.trim(),
                          proofPaths: proofPaths,
                        );
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).pop();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? 'Complaint submitted to admin panel.'
                                  : 'Complaint failed. Try again.',
                            ),
                          ),
                        );
                      },
                      child: const Text('Submit Complaint'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Dashboard'),
        actions: [
          IconButton(
            onPressed: _loadHospitals,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: ListTile(
                    title: Text('Welcome, ${widget.patientName}'),
                    subtitle: Text(
                      '${widget.patientEmail}\nUnique Patient ID: ${_patientUniqueId.isEmpty ? 'creating...' : _patientUniqueId}',
                    ),
                  ),
                ),
                Card(
                  color: const Color(0xFFE0F2FE),
                  child: ListTile(
                    title: const Text('Live hospital sync'),
                    subtitle: Text(
                      'Updated ${_lastSync == null ? 'just now' : _lastSync!.toLocal().toString()} • ${_hospitals.length} hospitals visible',
                    ),
                    trailing: FilledButton.tonal(
                      onPressed: _loadHospitals,
                      child: const Text('Refresh'),
                    ),
                  ),
                ),
                ..._hospitals.map(
                  (h) => Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            h.name,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${h.location} • Rating ${h.avgReview.toStringAsFixed(1)}',
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _chip('Beds ${h.bedsAvailable}'),
                              _chip('ICU ${h.icuAvailable}'),
                              _chip('OT ${h.otAvailable}'),
                              _chip('Doctors ${h.doctorsAvailable}'),
                              _chip('Surgeons ${h.surgeonsAvailable}'),
                              _chip('Wait ${h.queueWaitMinutes} min'),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('Specialities: ${h.specialities.join(', ')}'),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.tonal(
                                onPressed: () => _book(h, 'Bed'),
                                child: const Text('Pre-book Bed'),
                              ),
                              FilledButton.tonal(
                                onPressed: () => _book(h, 'Emergency Bed'),
                                child: const Text('Emergency Bed'),
                              ),
                              FilledButton.tonal(
                                onPressed: () => _book(h, 'Appointment'),
                                child: const Text('Book Appointment'),
                              ),
                              OutlinedButton(
                                onPressed: () => _complain(h),
                                child: const Text('Raise Complaint'),
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

  Widget _chip(String label) {
    return Chip(
      label: Text(label),
      backgroundColor: const Color(0xFFCCFBF1),
      side: BorderSide.none,
    );
  }
}

class HospitalRegistrationScreen extends StatefulWidget {
  const HospitalRegistrationScreen({super.key});

  @override
  State<HospitalRegistrationScreen> createState() =>
      _HospitalRegistrationScreenState();
}

class _HospitalRegistrationScreenState
    extends State<HospitalRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _location = TextEditingController();
  final _speciality = TextEditingController();
  final _equipment = TextEditingController();
  final _beds = TextEditingController(text: '30');
  final _icu = TextEditingController(text: '8');
  final _ot = TextEditingController(text: '2');
  final _docs = TextEditingController(
    text: 'https://drive.google.com/your-hospital-docs-folder',
  );
  bool _submitting = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    final ok = await ApiService().submitHospitalRegistration({
      'name': _name.text.trim(),
      'email': _email.text.trim(),
      'location': _location.text.trim(),
      'specialities': _speciality.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      'equipment': _equipment.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      'bedsTotal': int.tryParse(_beds.text.trim()) ?? 0,
      'bedsAvailable': int.tryParse(_beds.text.trim()) ?? 0,
      'icuTotal': int.tryParse(_icu.text.trim()) ?? 0,
      'icuAvailable': int.tryParse(_icu.text.trim()) ?? 0,
      'otTotal': int.tryParse(_ot.text.trim()) ?? 0,
      'otAvailable': int.tryParse(_ot.text.trim()) ?? 0,
      'queueWaitMinutes': 30,
      'docsUrl': _docs.text.trim(),
    });

    if (!mounted) return;
    setState(() => _submitting = false);

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => HospitalWaitingScreen(success: ok),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hospital Registration')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _field(_name, 'Hospital Name'),
              _field(_email, 'Official Email'),
              _field(_location, 'Location'),
              _field(_speciality, 'Specialities (comma separated)'),
              _field(_equipment, 'Equipment (comma separated)'),
              Row(
                children: [
                  Expanded(child: _field(_beds, 'Beds Total')),
                  const SizedBox(width: 8),
                  Expanded(child: _field(_icu, 'ICU Total')),
                  const SizedBox(width: 8),
                  Expanded(child: _field(_ot, 'OT Total')),
                ],
              ),
              _field(_docs, 'Documents Link'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: const Icon(Icons.verified_user),
                label: Text(
                  _submitting ? 'Submitting...' : 'Submit for Verification',
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const HospitalLoginScreen(),
                    ),
                  );
                },
                child: const Text('Hospital Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class HospitalLoginScreen extends StatefulWidget {
  const HospitalLoginScreen({super.key});

  @override
  State<HospitalLoginScreen> createState() => _HospitalLoginScreenState();
}

class _HospitalLoginScreenState extends State<HospitalLoginScreen> {
  final _email = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _email.text.trim();
    if (email.isEmpty) return;
    setState(() => _loading = true);
    final hospital = await ApiService().loginHospital(email);
    if (!mounted) return;
    setState(() => _loading = false);

    if (hospital == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hospital not found or not approved yet.'),
        ),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => HospitalDashboardScreen(hospital: hospital),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hospital Login')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _email,
              decoration: const InputDecoration(
                labelText: 'Approved hospital email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loading ? null : _login,
              child: Text(_loading ? 'Signing in...' : 'Open Dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}

class HospitalWaitingScreen extends StatelessWidget {
  const HospitalWaitingScreen({super.key, required this.success});

  final bool success;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                success ? Icons.schedule : Icons.error_outline,
                size: 60,
                color: success ? Colors.orange : Colors.red,
              ),
              const SizedBox(height: 12),
              Text(
                success
                    ? 'Registration submitted! Admin verification pending.'
                    : 'Could not submit right now. Please retry.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HospitalDashboardScreen extends StatefulWidget {
  const HospitalDashboardScreen({super.key, required this.hospital});

  final HospitalInfo hospital;

  @override
  State<HospitalDashboardScreen> createState() =>
      _HospitalDashboardScreenState();
}

class _HospitalDashboardScreenState extends State<HospitalDashboardScreen> {
  late final TextEditingController _hospitalId;
  late final TextEditingController _beds;
  late final TextEditingController _icu;
  late final TextEditingController _ot;
  late final TextEditingController _doctors;
  late final TextEditingController _surgeons;
  late final TextEditingController _wait;
  List<dynamic> _bookings = [];
  io.Socket? _socket;
  Timer? _pollTimer;
  Timer? _statusTimer;
  bool _loadingBookings = false;
  bool _saving = false;
  String _accountStatus = 'approved';

  @override
  void initState() {
    super.initState();
    _accountStatus = widget.hospital.status;
    _hospitalId = TextEditingController(text: widget.hospital.id);
    _beds = TextEditingController(
      text: widget.hospital.bedsAvailable.toString(),
    );
    _icu = TextEditingController(text: widget.hospital.icuAvailable.toString());
    _ot = TextEditingController(text: widget.hospital.otAvailable.toString());
    _doctors = TextEditingController(
      text: widget.hospital.doctorsAvailable.toString(),
    );
    _surgeons = TextEditingController(
      text: widget.hospital.surgeonsAvailable.toString(),
    );
    _wait = TextEditingController(
      text: widget.hospital.queueWaitMinutes.toString(),
    );
    _loadBookings();
    _loadHospitalStatus();
    _connectLive();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _loadBookings(),
    );
    _statusTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadHospitalStatus(),
    );
  }

  Future<void> _loadHospitalStatus() async {
    try {
      final response = await http.get(
        Uri.parse(
          '${BackendConfig.baseUrl}/api/hospitals/${_hospitalId.text.trim()}',
        ),
      );
      if (response.statusCode != 200) return;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final hospital = body['hospital'] as Map<String, dynamic>?;
      if (hospital == null || !mounted) return;
      setState(() {
        _accountStatus = hospital['status']?.toString() ?? _accountStatus;
      });
    } catch (_) {}
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
      socket.on('booking:created', (_) => _loadBookings());
      socket.on('hospital:availability-updated', (_) => _loadBookings());
      socket.on('hospital:snapshot', (_) => _loadBookings());
      socket.connect();
      _socket = socket;
    } catch (_) {}
  }

  Future<void> _loadBookings() async {
    if (_loadingBookings) return;
    _loadingBookings = true;
    try {
      final response = await http.get(
        Uri.parse(
          '${BackendConfig.baseUrl}/api/hospitals/${_hospitalId.text.trim()}/bookings',
        ),
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          _bookings = (body['bookings'] as List<dynamic>? ?? []);
        });
      }
    } catch (_) {}
    _loadingBookings = false;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _statusTimer?.cancel();
    _socket?.dispose();
    _hospitalId.dispose();
    _beds.dispose();
    _icu.dispose();
    _ot.dispose();
    _doctors.dispose();
    _surgeons.dispose();
    _wait.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_accountStatus != 'approved') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Account is not active. Availability update is locked.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await http.patch(
        Uri.parse(
          '${BackendConfig.baseUrl}/api/hospitals/${_hospitalId.text.trim()}/availability',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'bedsAvailable': int.tryParse(_beds.text) ?? 0,
          'icuAvailable': int.tryParse(_icu.text) ?? 0,
          'otAvailable': int.tryParse(_ot.text) ?? 0,
          'doctorsAvailable': int.tryParse(_doctors.text) ?? 0,
          'surgeonsAvailable': int.tryParse(_surgeons.text) ?? 0,
          'queueWaitMinutes': int.tryParse(_wait.text) ?? 30,
        }),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Availability updated.')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final approvalColor = _accountStatus == 'approved'
        ? const Color(0xFF16A34A)
        : const Color(0xFFF59E0B);
    return Scaffold(
      appBar: AppBar(title: const Text('Hospital Dashboard (Approved)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_accountStatus != 'approved')
            Card(
              color: const Color(0xFFFEE2E2),
              child: const ListTile(
                leading: Icon(Icons.lock_outline, color: Colors.red),
                title: Text('Account is been deactive by admin'),
                subtitle: Text('File requestion with proof for re activation'),
              ),
            ),
          Card(
            color: const Color(0xFFE0F2FE),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.hospital.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.hospital.location} • ${widget.hospital.email}',
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        label: Text(_accountStatus.toUpperCase()),
                        backgroundColor: approvalColor.withValues(alpha: 0.14),
                        side: BorderSide(
                          color: approvalColor.withValues(alpha: 0.35),
                        ),
                      ),
                      Chip(
                        label: Text('Bookings ${_bookings.length}'),
                        backgroundColor: const Color(0xFFCCFBF1),
                        side: BorderSide.none,
                      ),
                      Chip(
                        label: Text('Queue ${_wait.text} min'),
                        backgroundColor: const Color(0xFFFFEDD5),
                        side: BorderSide.none,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _hospitalStatCard('Beds', _beds.text),
              _hospitalStatCard('ICU', _icu.text),
              _hospitalStatCard('OT', _ot.text),
              _hospitalStatCard('Doctors', _doctors.text),
              _hospitalStatCard('Surgeons', _surgeons.text),
              _hospitalStatCard('Bookings', _bookings.length.toString()),
            ],
          ),
          const SizedBox(height: 16),
          _nField(_hospitalId, 'Hospital ID (demo: hosp_1)'),
          _nField(_beds, 'Beds Available'),
          _nField(_icu, 'ICU Available'),
          _nField(_ot, 'OT Available'),
          _nField(_doctors, 'Doctors Available'),
          _nField(_surgeons, 'Surgeons Available'),
          _nField(_wait, 'Estimated Wait (minutes)'),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: (_saving || _accountStatus != 'approved') ? null : _save,
            child: Text(_saving ? 'Saving...' : 'Update Live Availability'),
          ),
          const SizedBox(height: 18),
          Text(
            'Live bookings for ${_hospitalId.text.trim()}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (_bookings.isEmpty)
            const Card(
              child: ListTile(
                title: Text('No bookings yet'),
                subtitle: Text(
                  'When patient books Bed / Emergency Bed / Appointment, it will appear here.',
                ),
              ),
            )
          else
            ..._bookings.map(
              (b) => Card(
                child: ListTile(
                  leading: const Icon(Icons.event_available),
                  title: Text(
                    '${b['type'] ?? 'Booking'} • ${b['patientName'] ?? ''}',
                  ),
                  subtitle: Text(
                    'Priority: ${b['priority'] ?? 'normal'} • ${b['status'] ?? ''}',
                  ),
                  trailing: Text(b['createdAt']?.toString() ?? ''),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _nField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _hospitalStatCard(String label, String value) {
    return SizedBox(
      width: 150,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
