import 'dart:convert';
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await BackendConfig.load();
  runApp(const QLessApp());
}

const String kDefaultApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://bookmyhospital-api.onrender.com',
);
const String kBuildLabel = 'R4 2026-04-16';

class BackendConfig {
  static const _prefsKey = 'bookmyhospital_api_base_url';
  static const _patientIdKey = 'bookmyhospital_patient_unique_id';
  static String baseUrl = kDefaultApiBaseUrl;
  static bool configured = false;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null && saved.contains('loca.lt')) {
      await prefs.remove(_prefsKey);
      baseUrl = kDefaultApiBaseUrl;
      configured = false;
      return;
    }
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

class QLessApp extends StatelessWidget {
  const QLessApp({super.key});

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
      title: 'Q-Less',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(scaffoldBackgroundColor: const Color(0xFFF0FDFA)),
      home: const EntryScreen(),
    );
  }
}

const List<String> kEntryTaglines = [
  'Hospitals at your fingertips — fast, calm, and reliable in emergencies.',
  'Local OPD clinics with real-time queue visibility.',
  'Skip the crowd with smart OPD queue timing.',
  'Check wait times before you leave home.',
  'Book consultations in minutes, not hours.',
  'Emergency flow that keeps families informed.',
  'Simple for patients, efficient for staff.',
  'Q-Less keeps OPDs moving smoothly.',
];

class RotatingTaglines extends StatefulWidget {
  const RotatingTaglines({
    super.key,
    required this.lines,
    this.interval = const Duration(seconds: 7),
    this.transition = const Duration(milliseconds: 600),
  });

  final List<String> lines;
  final Duration interval;
  final Duration transition;

  @override
  State<RotatingTaglines> createState() => _RotatingTaglinesState();
}

class _RotatingTaglinesState extends State<RotatingTaglines>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.lines.length > 1) {
      _timer = Timer.periodic(widget.interval, (_) {
        if (!mounted) return;
        setState(() => _index = (_index + 1) % widget.lines.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyMedium;

    return AnimatedSize(
      duration: widget.transition,
      curve: Curves.easeInOut,
      child: AnimatedSwitcher(
        duration: widget.transition,
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        transitionBuilder: (child, animation) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOut,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.12),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
        child: Text(
          widget.lines[_index],
          key: ValueKey(_index),
          style: textStyle,
        ),
      ),
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
    required this.ratingsCount,
    required this.specialities,
    required this.status,
    required this.facilityType,
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
  final int ratingsCount;
  final List<String> specialities;
  final String status;
  final String facilityType;

  FacilityRole get role => facilityRoleFromString(facilityType);
  bool get isClinic => role == FacilityRole.clinic;

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
      ratingsCount: (json['ratingsCount'] ?? 0) as int,
      specialities: ((json['specialities'] ?? []) as List)
          .map((item) => item.toString())
          .toList(),
      status: json['status']?.toString() ?? 'approved',
      facilityType: json['facilityType']?.toString() ?? 'hospital',
    );
  }
}

class PatientNotification {
  PatientNotification({
    required this.id,
    required this.hospitalId,
    required this.title,
    required this.message,
    required this.type,
    required this.createdAt,
  });

  final String id;
  final String hospitalId;
  final String title;
  final String message;
  final String type;
  final String createdAt;

  factory PatientNotification.fromJson(Map<String, dynamic> json) {
    return PatientNotification(
      id: json['id']?.toString() ?? '',
      hospitalId: json['hospitalId']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Notification',
      message: json['message']?.toString() ?? '',
      type: json['type']?.toString() ?? 'info',
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }
}

enum FacilityRole { hospital, clinic }

extension FacilityRoleX on FacilityRole {
  String get label => this == FacilityRole.hospital ? 'Hospital' : 'Clinic';
}

FacilityRole facilityRoleFromString(String? value) {
  final normalized = (value ?? '').toLowerCase().trim();
  return normalized == 'clinic' ? FacilityRole.clinic : FacilityRole.hospital;
}

class AppointmentRecord {
  AppointmentRecord({
    required this.id,
    required this.displayId,
    required this.hospitalId,
    required this.hospitalName,
    required this.patientId,
    required this.patientName,
    required this.type,
    required this.facilityType,
    required this.status,
    required this.priority,
    required this.createdAt,
    this.assignedDoctor,
    this.assignedTime,
    this.queuePosition,
    this.updatedAt,
  });

  final String id;
  final String displayId;
  final String hospitalId;
  final String hospitalName;
  final String patientId;
  final String patientName;
  final String type;
  final String facilityType;
  final String status;
  final String priority;
  final String createdAt;
  final String? assignedDoctor;
  final String? assignedTime;
  final int? queuePosition;
  final String? updatedAt;

  FacilityRole get facilityRole => facilityRoleFromString(facilityType);
  bool get isClinic => facilityRole == FacilityRole.clinic;

  factory AppointmentRecord.fromBookingJson(Map<String, dynamic> json) {
    final id =
        json['id']?.toString() ??
        'booking_${DateTime.now().millisecondsSinceEpoch}';
    return AppointmentRecord(
      id: id,
      displayId: _toDisplayId(id),
      hospitalId: json['hospitalId']?.toString() ?? '',
      hospitalName: json['hospitalName']?.toString() ?? 'Unknown Facility',
      patientId: json['patientId']?.toString() ?? '',
      patientName: json['patientName']?.toString() ?? 'Unknown Patient',
      type: (json['type']?.toString() ?? 'Appointment').trim(),
      facilityType: facilityRoleFromString(
        json['facilityType']?.toString(),
      ).name,
      status: _normalizeStatus(json['status']?.toString() ?? 'pending'),
      priority: (json['priority']?.toString() ?? 'normal').trim(),
      createdAt:
          json['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
      assignedDoctor: json['assignedDoctor']?.toString(),
      assignedTime: json['assignedTime']?.toString(),
      queuePosition: json['queuePosition'] is int
          ? json['queuePosition'] as int
          : int.tryParse('${json['queuePosition'] ?? ''}'),
      updatedAt: json['updatedAt']?.toString(),
    );
  }

  factory AppointmentRecord.fromJson(Map<String, dynamic> json) {
    return AppointmentRecord(
      id: json['id']?.toString() ?? '',
      displayId:
          json['displayId']?.toString() ??
          _toDisplayId(json['id']?.toString() ?? ''),
      hospitalId: json['hospitalId']?.toString() ?? '',
      hospitalName: json['hospitalName']?.toString() ?? 'Unknown Facility',
      patientId: json['patientId']?.toString() ?? '',
      patientName: json['patientName']?.toString() ?? 'Unknown Patient',
      type: json['type']?.toString() ?? 'Appointment',
      facilityType: facilityRoleFromString(
        json['facilityType']?.toString(),
      ).name,
      status: _normalizeStatus(json['status']?.toString() ?? 'pending'),
      priority: json['priority']?.toString() ?? 'normal',
      createdAt:
          json['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
      assignedDoctor: json['assignedDoctor']?.toString(),
      assignedTime: json['assignedTime']?.toString(),
      queuePosition: json['queuePosition'] is int
          ? json['queuePosition'] as int
          : int.tryParse('${json['queuePosition'] ?? ''}'),
      updatedAt: json['updatedAt']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayId': displayId,
    'hospitalId': hospitalId,
    'hospitalName': hospitalName,
    'patientId': patientId,
    'patientName': patientName,
    'type': type,
    'facilityType': facilityType,
    'status': status,
    'priority': priority,
    'createdAt': createdAt,
    'assignedDoctor': assignedDoctor,
    'assignedTime': assignedTime,
    'queuePosition': queuePosition,
    'updatedAt': updatedAt,
  };

  AppointmentRecord copyWith({
    String? facilityType,
    String? status,
    String? assignedDoctor,
    String? assignedTime,
    int? queuePosition,
    String? updatedAt,
  }) {
    return AppointmentRecord(
      id: id,
      displayId: displayId,
      hospitalId: hospitalId,
      hospitalName: hospitalName,
      patientId: patientId,
      patientName: patientName,
      type: type,
      facilityType: facilityType ?? this.facilityType,
      status: status ?? this.status,
      priority: priority,
      createdAt: createdAt,
      assignedDoctor: assignedDoctor ?? this.assignedDoctor,
      assignedTime: assignedTime ?? this.assignedTime,
      queuePosition: queuePosition ?? this.queuePosition,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String _toDisplayId(String raw) {
    final compact = raw.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
    if (compact.isEmpty) return 'APT_UNKNOWN';
    final suffix = compact.length <= 8
        ? compact
        : compact.substring(compact.length - 8);
    return 'APT_$suffix';
  }

  static String _normalizeStatus(String status) {
    final normalized = status.trim().toLowerCase();
    if (normalized.isEmpty || normalized == 'confirmed') return 'pending';
    if (normalized == 'cancelled') return 'canceled';
    return normalized;
  }
}

class AppointmentFlow {
  static bool canTransition(String from, String to) {
    const transitions = <String, Set<String>>{
      'pending': {'accepted', 'declined', 'canceled', 'reschedule_requested'},
      'accepted': {'assigned', 'declined', 'canceled'},
      'assigned': {'queued', 'reschedule_requested', 'canceled'},
      'queued': {'completed', 'canceled'},
      'reschedule_requested': {'assigned', 'declined', 'canceled'},
    };
    final allowed = transitions[from];
    if (allowed == null) return false;
    return allowed.contains(to);
  }
}

class HqrGenerationResult {
  const HqrGenerationResult({
    required this.token,
    required this.verifyUrl,
    required this.expiresAt,
    required this.expiresInSeconds,
  });

  final String token;
  final String verifyUrl;
  final String expiresAt;
  final int expiresInSeconds;
}

class HqrVerifyResult {
  const HqrVerifyResult({
    required this.verified,
    required this.reason,
    this.bookingId,
  });

  final bool verified;
  final String reason;
  final String? bookingId;
}

class ApiService {
  static const _offlineBoxName = 'bmh_phase3_offline';
  static const _hospitalsCacheKey = 'bookmyhospital_cached_hospitals';
  static String _notificationsCacheKey(String patientId) =>
      'bookmyhospital_cached_notifications_$patientId';
  static String _patientAppointmentsCacheKey(String patientId) =>
      'bookmyhospital_cached_patient_appointments_$patientId';
  static String _facilityAppointmentsCacheKey(
    String facilityId,
    FacilityRole role,
  ) => 'bookmyhospital_cached_${role.name}_appointments_$facilityId';
  static String _facilityAppointmentActionsKey(
    String facilityId,
    FacilityRole role,
  ) => 'bookmyhospital_cached_${role.name}_appointment_actions_$facilityId';

  Future<void> _cacheJson(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(value));
  }

  Future<Map<String, dynamic>?> _readCachedMap(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<Box<String>> _offlineBox() async {
    if (Hive.isBoxOpen(_offlineBoxName)) {
      return Hive.box<String>(_offlineBoxName);
    }
    return Hive.openBox<String>(_offlineBoxName);
  }

  Future<void> _cacheHiveJson(String key, dynamic value) async {
    final box = await _offlineBox();
    await box.put(key, jsonEncode(value));
  }

  Future<Map<String, dynamic>?> _readHiveMap(String key) async {
    final box = await _offlineBox();
    final raw = box.get(key);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<List<HospitalInfo>> getApprovedHospitals() async {
    try {
      final uri = Uri.parse(
        '${BackendConfig.baseUrl}/api/hospitals?status=approved',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        final cached = await _readCachedMap(_hospitalsCacheKey);
        final cachedList = (cached?['hospitals'] as List<dynamic>? ?? [])
            .map((item) => HospitalInfo.fromJson(item as Map<String, dynamic>))
            .toList();
        return cachedList.isNotEmpty ? cachedList : _fallbackHospitals;
      }
      final map = jsonDecode(response.body) as Map<String, dynamic>;
      await _cacheJson(_hospitalsCacheKey, map);
      final list = (map['hospitals'] as List<dynamic>? ?? [])
          .map((item) => HospitalInfo.fromJson(item as Map<String, dynamic>))
          .toList();
      return list;
    } catch (_) {
      final cached = await _readCachedMap(_hospitalsCacheKey);
      final cachedList = (cached?['hospitals'] as List<dynamic>? ?? [])
          .map((item) => HospitalInfo.fromJson(item as Map<String, dynamic>))
          .toList();
      return cachedList.isNotEmpty ? cachedList : _fallbackHospitals;
    }
  }

  Future<bool> submitHospitalRegistration(Map<String, dynamic> payload) async {
    try {
      final uri = Uri.parse('${BackendConfig.baseUrl}/api/hospitals/register');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 12));
      return response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  Future<HospitalInfo?> loginHospital(String email) async {
    try {
      final uri = Uri.parse('${BackendConfig.baseUrl}/api/hospitals/auth');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email}),
          )
          .timeout(const Duration(seconds: 10));
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
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'hospitalId': hospitalId,
              'patientName': patientName,
              'patientId': patientId,
              'type': type,
            }),
          )
          .timeout(const Duration(seconds: 10));
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

      final streamed = await request.send().timeout(
        const Duration(seconds: 20),
      );
      return streamed.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  Future<List<PatientNotification>> getPatientNotifications(
    String patientId,
  ) async {
    try {
      final uri = Uri.parse(
        '${BackendConfig.baseUrl}/api/patients/$patientId/notifications',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        final cached = await _readCachedMap(_notificationsCacheKey(patientId));
        return (cached?['notifications'] as List<dynamic>? ?? [])
            .map(
              (item) =>
                  PatientNotification.fromJson(item as Map<String, dynamic>),
            )
            .toList();
      }
      final map = jsonDecode(response.body) as Map<String, dynamic>;
      await _cacheJson(_notificationsCacheKey(patientId), map);
      return (map['notifications'] as List<dynamic>? ?? [])
          .map(
            (item) =>
                PatientNotification.fromJson(item as Map<String, dynamic>),
          )
          .toList();
    } catch (_) {
      final cached = await _readCachedMap(_notificationsCacheKey(patientId));
      return (cached?['notifications'] as List<dynamic>? ?? [])
          .map(
            (item) =>
                PatientNotification.fromJson(item as Map<String, dynamic>),
          )
          .toList();
    }
  }

  Future<List<AppointmentRecord>> getPatientAppointments(
    String patientId,
  ) async {
    try {
      final uri = Uri.parse(
        '${BackendConfig.baseUrl}/api/patients/$patientId/bookings',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return _readPatientAppointmentsCache(patientId);
      }
      final map = jsonDecode(response.body) as Map<String, dynamic>;
      final appointments =
          (map['bookings'] as List<dynamic>? ?? [])
              .map(
                (item) => AppointmentRecord.fromBookingJson(
                  item as Map<String, dynamic>,
                ),
              )
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      await _cacheHiveJson(_patientAppointmentsCacheKey(patientId), {
        'appointments': appointments.map((item) => item.toJson()).toList(),
      });
      return appointments;
    } catch (_) {
      return _readPatientAppointmentsCache(patientId);
    }
  }

  Future<List<AppointmentRecord>> getFacilityAppointments({
    required String facilityId,
    required FacilityRole role,
  }) async {
    try {
      final uri = Uri.parse(
        '${BackendConfig.baseUrl}/api/hospitals/$facilityId/bookings',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return _readFacilityAppointmentsCache(facilityId, role);
      }
      final map = jsonDecode(response.body) as Map<String, dynamic>;
      final appointments =
          (map['bookings'] as List<dynamic>? ?? [])
              .map(
                (item) => AppointmentRecord.fromBookingJson(
                  item as Map<String, dynamic>,
                ),
              )
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      await _cacheHiveJson(_facilityAppointmentsCacheKey(facilityId, role), {
        'appointments': appointments.map((item) => item.toJson()).toList(),
      });
      return appointments;
    } catch (_) {
      return _readFacilityAppointmentsCache(facilityId, role);
    }
  }

  Future<AppointmentRecord?> updateAppointment({
    required String appointmentId,
    String? status,
    String? assignedDoctor,
    String? assignedTime,
    int? queuePosition,
  }) async {
    try {
      final payload = <String, dynamic>{};
      if (status != null) payload['status'] = status;
      if (assignedDoctor != null) payload['assignedDoctor'] = assignedDoctor;
      if (assignedTime != null) payload['assignedTime'] = assignedTime;
      if (queuePosition != null) payload['queuePosition'] = queuePosition;
      if (payload.isEmpty) return null;
      final uri = Uri.parse(
        '${BackendConfig.baseUrl}/api/bookings/$appointmentId',
      );
      final response = await http
          .patch(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final map = jsonDecode(response.body) as Map<String, dynamic>;
      final booking = map['booking'] as Map<String, dynamic>?;
      if (booking == null) return null;
      return AppointmentRecord.fromBookingJson(booking);
    } catch (_) {
      return null;
    }
  }

  Future<HqrGenerationResult?> generateHqr({
    required String bookingId,
    required String facilityId,
  }) async {
    try {
      final uri = Uri.parse('${BackendConfig.baseUrl}/api/hqr/generate');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'bookingId': bookingId,
              'hospitalId': facilityId,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final map = jsonDecode(response.body) as Map<String, dynamic>;
      return HqrGenerationResult(
        token: map['token']?.toString() ?? '',
        verifyUrl: map['verifyUrl']?.toString() ?? '',
        expiresAt: map['expiresAt']?.toString() ?? '',
        expiresInSeconds: (map['expiresInSeconds'] as num?)?.toInt() ?? 900,
      );
    } catch (_) {
      return null;
    }
  }

  Future<HqrVerifyResult> verifyHqr({
    required String token,
    required String patientId,
  }) async {
    try {
      final uri = Uri.parse('${BackendConfig.baseUrl}/api/hqr/verify');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'token': token, 'patientId': patientId}),
          )
          .timeout(const Duration(seconds: 10));
      final map = jsonDecode(response.body) as Map<String, dynamic>;
      return HqrVerifyResult(
        verified: map['verified'] == true,
        reason:
            map['message']?.toString() ??
            map['reason']?.toString() ??
            map['error']?.toString() ??
            (response.statusCode == 200 ? 'Verified' : 'Verification failed'),
        bookingId: map['bookingId']?.toString(),
      );
    } catch (_) {
      return const HqrVerifyResult(
        verified: false,
        reason: 'Verification service unavailable',
      );
    }
  }

  Future<Map<String, AppointmentRecord>> readFacilityAppointmentActions({
    required String facilityId,
    required FacilityRole role,
  }) async {
    final cached = await _readHiveMap(
      _facilityAppointmentActionsKey(facilityId, role),
    );
    final actions = (cached?['actions'] as Map<String, dynamic>? ?? {});
    final result = <String, AppointmentRecord>{};
    for (final entry in actions.entries) {
      if (entry.value is Map<String, dynamic>) {
        result[entry.key] = AppointmentRecord.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
    }
    return result;
  }

  Future<void> saveFacilityAppointmentAction({
    required String facilityId,
    required FacilityRole role,
    required AppointmentRecord appointment,
  }) async {
    final current = await readFacilityAppointmentActions(
      facilityId: facilityId,
      role: role,
    );
    current[appointment.id] = appointment;
    await _cacheHiveJson(_facilityAppointmentActionsKey(facilityId, role), {
      'actions': current.map((key, value) => MapEntry(key, value.toJson())),
    });
  }

  Future<List<AppointmentRecord>> _readPatientAppointmentsCache(
    String patientId,
  ) async {
    final cached = await _readHiveMap(_patientAppointmentsCacheKey(patientId));
    return (cached?['appointments'] as List<dynamic>? ?? [])
        .map((item) => AppointmentRecord.fromJson(item as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<List<AppointmentRecord>> _readFacilityAppointmentsCache(
    String facilityId,
    FacilityRole role,
  ) async {
    final cached = await _readHiveMap(
      _facilityAppointmentsCacheKey(facilityId, role),
    );
    return (cached?['appointments'] as List<dynamic>? ?? [])
        .map((item) => AppointmentRecord.fromJson(item as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<String> askAiHelp(String message, {required bool lowDataMode}) async {
    try {
      await http
          .get(Uri.parse('${BackendConfig.baseUrl}/health'))
          .timeout(const Duration(seconds: 70));

      final uri = Uri.parse('${BackendConfig.baseUrl}/api/ai/help');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'message': message, 'lowDataMode': lowDataMode}),
          )
          .timeout(const Duration(seconds: 25));
      if (response.statusCode == 200) {
        final map = jsonDecode(response.body) as Map<String, dynamic>;
        return map['reply']?.toString() ?? 'No response from assistant.';
      }
    } catch (_) {}

    return lowDataMode
        ? 'Low-network fallback:\n• Retry in a few seconds\n• Use refresh button\n• For emergency: call local emergency now'
        : 'Assistant is temporarily offline due to low network. Please retry, or use manual booking/complaint actions from dashboard.';
  }

  Future<HospitalInfo?> submitHospitalRating({
    required String hospitalId,
    required int rating,
  }) async {
    try {
      final uri = Uri.parse(
        '${BackendConfig.baseUrl}/api/hospitals/$hospitalId/rate',
      );
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'rating': rating}),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final map = jsonDecode(response.body) as Map<String, dynamic>;
      final hospital = map['hospital'] as Map<String, dynamic>?;
      if (hospital == null) return null;
      return HospitalInfo.fromJson(hospital);
    } catch (_) {
      return null;
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
    ratingsCount: 132,
    specialities: ['Cardiology', 'Trauma', 'Critical Care'],
    status: 'approved',
    facilityType: 'hospital',
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
    ratingsCount: 91,
    specialities: ['Emergency', 'Orthopedics'],
    status: 'approved',
    facilityType: 'hospital',
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
    ratingsCount: 76,
    specialities: ['Pediatrics', 'Gynecology'],
    status: 'approved',
    facilityType: 'hospital',
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
                  'Q-Less',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF134E4A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Build $kBuildLabel',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                const RotatingTaglines(lines: kEntryTaglines),
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
                  title: 'Join as Hospitals or Clinics',
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
  List<AppointmentRecord> _appointments = [];
  List<PatientNotification> _notifications = [];
  bool _loading = true;
  bool _loadingAppointments = true;
  int _selectedTabIndex = 0;
  FacilityRole _homeFilter = FacilityRole.hospital;
  String? _highlightedAppointmentId;
  String _patientUniqueId = '';
  Timer? _pollTimer;
  Timer? _notificationPollTimer;
  Timer? _appointmentPollTimer;
  io.Socket? _socket;
  DateTime? _lastSync;
  Set<String> _seenNotificationIds = <String>{};
  Set<String> _starredNotificationIds = <String>{};

  @override
  void initState() {
    super.initState();
    _initPatientId();
    _loadHospitals();
    _connectLive();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 12),
      (_) => _loadHospitals(),
    );
    _notificationPollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadNotifications(),
    );
    _appointmentPollTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _loadAppointments(),
    );
  }

  Future<void> _initPatientId() async {
    final id = await BackendConfig.getOrCreatePatientId();
    if (!mounted) return;
    setState(() => _patientUniqueId = id);
    await _loadNotificationState();
    await _loadNotifications();
    await _loadAppointments();
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
      socket.on('booking:created', (_) => _loadAppointments());
      socket.on('booking:updated', (_) => _loadAppointments());
      socket.on('patient:notification', (payload) {
        if (payload is! Map<String, dynamic>) return;
        final targetId = payload['patientId']?.toString() ?? '';
        if (targetId.isEmpty || targetId != _patientUniqueId) return;
        final notification = PatientNotification.fromJson(payload);
        if (!mounted) return;
        setState(() {
          _notifications = [notification, ..._notifications]
              .fold<List<PatientNotification>>([], (acc, item) {
                if (acc.any((existing) => existing.id == item.id)) return acc;
                acc.add(item);
                return acc;
              })
              .take(30)
              .toList();
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(notification.message)));
      });
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

  Future<void> _loadNotifications() async {
    if (_patientUniqueId.trim().isEmpty) return;
    final notifications = await _api.getPatientNotifications(_patientUniqueId);
    if (!mounted) return;
    setState(() {
      _notifications = notifications.take(30).toList();
    });
  }

  String _seenNotificationsPrefsKey() =>
      'qless_seen_notifications_${_patientUniqueId.trim()}';

  String _starredNotificationsPrefsKey() =>
      'qless_starred_notifications_${_patientUniqueId.trim()}';

  Future<void> _loadNotificationState() async {
    if (_patientUniqueId.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final seen =
        prefs.getStringList(_seenNotificationsPrefsKey()) ?? const <String>[];
    final starred =
        prefs.getStringList(_starredNotificationsPrefsKey()) ??
        const <String>[];
    if (!mounted) return;
    setState(() {
      _seenNotificationIds = seen.toSet();
      _starredNotificationIds = starred.toSet();
    });
  }

  Future<void> _saveNotificationState() async {
    if (_patientUniqueId.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _seenNotificationsPrefsKey(),
      _seenNotificationIds.take(250).toList(),
    );
    await prefs.setStringList(
      _starredNotificationsPrefsKey(),
      _starredNotificationIds.take(250).toList(),
    );
  }

  int get _visibleNotificationCount {
    return _notifications
        .where(
          (item) =>
              !_seenNotificationIds.contains(item.id) ||
              _starredNotificationIds.contains(item.id),
        )
        .length;
  }

  Future<void> _openNotificationCenter() async {
    final result = await Navigator.of(context).push<NotificationCenterResult>(
      MaterialPageRoute(
        builder: (_) => NotificationCenterScreen(
          notifications: _notifications,
          initialSeenIds: _seenNotificationIds,
          initialStarredIds: _starredNotificationIds,
          facilityRoleByHospitalId: {
            for (final hospital in _hospitals) hospital.id: hospital.role,
          },
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _seenNotificationIds = result.seenIds;
      _starredNotificationIds = result.starredIds;
    });
    await _saveNotificationState();
  }

  Future<void> _loadAppointments() async {
    if (_patientUniqueId.trim().isEmpty) return;
    final appointments = await _api.getPatientAppointments(_patientUniqueId);
    if (!mounted) return;
    setState(() {
      _appointments = appointments;
      _loadingAppointments = false;
    });
  }

  void _openAiAssistant() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            AiHelpScreen(apiService: _api, patientName: widget.patientName),
      ),
    );
  }

  Future<void> _book(HospitalInfo hospital, String type) async {
    final ok = await _api.createBooking(
      hospitalId: hospital.id,
      patientName: widget.patientName,
      patientId: _patientUniqueId,
      type: type,
    );
    if (!mounted) return;
    final entityLabel = hospital.role.label;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '$type pre-booked at ${hospital.name} ($entityLabel)'
              : 'Could not place booking right now.',
        ),
      ),
    );
    if (ok) {
      _loadAppointments();
      _loadHospitals();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _notificationPollTimer?.cancel();
    _appointmentPollTimer?.cancel();
    _socket?.dispose();
    super.dispose();
  }

  Future<void> _openQrEntryPoint() async {
    final match = await Navigator.of(context).push<AppointmentRecord>(
      MaterialPageRoute(
        builder: (_) => AppointmentQrScannerScreen(
          appointments: _appointments,
          api: _api,
          patientId: _patientUniqueId,
        ),
      ),
    );
    if (!mounted || match == null) return;
    setState(() {
      _selectedTabIndex = 1;
      _highlightedAppointmentId = match.id;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Scanned ${match.displayId} for ${match.hospitalName}.'),
      ),
    );
  }

  Future<void> _updatePatientAppointmentStatus(
    AppointmentRecord appointment,
    String targetStatus,
  ) async {
    final allowedStatuses = {'pending', 'accepted', 'assigned', 'queued'};
    if (!allowedStatuses.contains(appointment.status)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Action not allowed for current status.')),
      );
      return;
    }

    final remote = await _api.updateAppointment(
      appointmentId: appointment.id,
      status: targetStatus,
    );
    final next =
        remote ??
        appointment.copyWith(
          status: targetStatus,
          updatedAt: DateTime.now().toIso8601String(),
        );
    if (!mounted) return;
    setState(() {
      _appointments = _appointments.map((item) {
        if (item.id != appointment.id) return item;
        return next;
      }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          remote == null
              ? '${appointment.displayId} updated locally. Sync pending.'
              : '${appointment.displayId} marked $targetStatus',
        ),
      ),
    );
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

  Future<void> _rateHospital(HospitalInfo hospital) async {
    double selected = 5;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text('Rate ${hospital.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current rating: ${hospital.avgReview.toStringAsFixed(1)} (${hospital.ratingsCount})',
              ),
              const SizedBox(height: 12),
              Text('Your rating: ${selected.toStringAsFixed(0)} / 5'),
              Slider(
                value: selected,
                min: 1,
                max: 5,
                divisions: 4,
                label: selected.toStringAsFixed(0),
                onChanged: (value) => setModalState(() => selected = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Submit Rating'),
            ),
          ],
        ),
      ),
    );

    if (submitted != true) return;
    final updated = await _api.submitHospitalRating(
      hospitalId: hospital.id,
      rating: selected.round(),
    );

    if (!mounted) return;
    if (updated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rating could not be submitted right now.'),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Thanks! ${updated.name} is now rated ${updated.avgReview.toStringAsFixed(1)}',
        ),
      ),
    );
    await _loadHospitals();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectedTabIndex == 0
              ? 'Patient Home'
              : _selectedTabIndex == 1
              ? 'My Appointments'
              : 'Patient Profile',
        ),
        actions: [
          IconButton(
            tooltip: 'AI Help',
            onPressed: _openAiAssistant,
            icon: const Icon(Icons.smart_toy_outlined),
          ),
          IconButton(
            tooltip: 'Notifications',
            onPressed: _openNotificationCenter,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_none_rounded),
                if (_visibleNotificationCount > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D9488),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _visibleNotificationCount > 99
                            ? '99+'
                            : _visibleNotificationCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: _loadHospitals,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedTabIndex,
        children: [
          _buildHomeTab(),
          _buildAppointmentsTab(),
          _buildProfileTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTabIndex,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: 'Appointments',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
        onDestinationSelected: (index) {
          setState(() => _selectedTabIndex = index);
        },
      ),
    );
  }

  Widget _buildHomeTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final filtered = _hospitals.where((h) => h.role == _homeFilter).toList();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: ListTile(
            title: Text('Welcome, ${widget.patientName}'),
            subtitle: Text(
              '${widget.patientEmail}\nPatient ID: ${_patientUniqueId.isEmpty ? 'creating...' : _patientUniqueId}',
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SegmentedButton<FacilityRole>(
            style: ButtonStyle(
              visualDensity: VisualDensity.comfortable,
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            segments: const [
              ButtonSegment<FacilityRole>(
                value: FacilityRole.hospital,
                label: Text('Hospitals'),
                icon: Icon(Icons.local_hospital),
              ),
              ButtonSegment<FacilityRole>(
                value: FacilityRole.clinic,
                label: Text('Clinics'),
                icon: Icon(Icons.medical_services),
              ),
            ],
            selected: {_homeFilter},
            onSelectionChanged: (selection) {
              setState(() => _homeFilter = selection.first);
            },
          ),
        ),
        Card(
          color: const Color(0xFFE0F2FE),
          child: ListTile(
            title: Text(
              _homeFilter == FacilityRole.hospital
                  ? 'Live hospital sync'
                  : 'Live clinic sync',
            ),
            subtitle: Text(
              'Updated ${_lastSync == null ? 'just now' : _lastSync!.toLocal().toString()} • ${filtered.length} ${_homeFilter.label.toLowerCase()}${filtered.length == 1 ? '' : 's'} visible',
            ),
            trailing: FilledButton.tonal(
              onPressed: _loadHospitals,
              child: const Text('Refresh'),
            ),
          ),
        ),
        if (filtered.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    _homeFilter == FacilityRole.hospital
                        ? Icons.local_hospital_outlined
                        : Icons.medical_services_outlined,
                    size: 48,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No ${_homeFilter.label.toLowerCase()}s available right now',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ...filtered.map(
          (h) => Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: h.isClinic
                              ? const Color(0xFFE0F2FE)
                              : const Color(0xFFCCFBF1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              h.isClinic
                                  ? Icons.medical_services
                                  : Icons.local_hospital,
                              size: 14,
                              color: h.isClinic
                                  ? const Color(0xFF1E40AF)
                                  : const Color(0xFF0D9488),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              h.isClinic ? 'Clinic' : 'Hospital',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: h.isClinic
                                    ? const Color(0xFF1E40AF)
                                    : const Color(0xFF0D9488),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    h.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${h.location} • Rating ${h.avgReview.toStringAsFixed(1)} (${h.ratingsCount})',
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _metricChip('Beds ${h.bedsAvailable}'),
                      _metricChip('ICU ${h.icuAvailable}'),
                      _metricChip('OT ${h.otAvailable}'),
                      _metricChip('Doctors ${h.doctorsAvailable}'),
                      _metricChip('Wait ${h.queueWaitMinutes}m'),
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
                        onPressed: () => _book(h, 'Appointment'),
                        child: const Text('Book Appointment'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => _book(h, 'Emergency'),
                        child: const Text('Emergency'),
                      ),
                      OutlinedButton(
                        onPressed: _openQrEntryPoint,
                        child: const Text('QR Scanner'),
                      ),
                      OutlinedButton(
                        onPressed: () => _complain(h),
                        child: const Text('Raise Complaint'),
                      ),
                      OutlinedButton(
                        onPressed: () => _rateHospital(h),
                        child: const Text('Rate Facility'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAppointmentsTab() {
    if (_loadingAppointments) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_appointments.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Card(
            child: ListTile(
              title: Text('No appointments yet'),
              subtitle: Text(
                'Book from Home tab. Offline cache will keep your last synced appointments.',
              ),
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ..._appointments.map((appointment) {
          final canEdit = {
            'pending',
            'accepted',
            'assigned',
            'queued',
          }.contains(appointment.status);
          return AppointmentCard(
            appointment: appointment,
            highlighted: _highlightedAppointmentId == appointment.id,
            showHospitalName: true,
            actions: canEdit
                ? [
                    AppointmentCardAction(
                      label: 'Cancel',
                      semanticLabel:
                          'Cancel appointment ${appointment.displayId}',
                      onPressed: () => _updatePatientAppointmentStatus(
                        appointment,
                        'canceled',
                      ),
                    ),
                    AppointmentCardAction(
                      label: 'Reschedule',
                      semanticLabel:
                          'Request reschedule for appointment ${appointment.displayId}',
                      onPressed: () => _updatePatientAppointmentStatus(
                        appointment,
                        'reschedule_requested',
                      ),
                    ),
                  ]
                : const [],
          );
        }),
      ],
    );
  }

  Widget _buildProfileTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.person),
            title: Text(widget.patientName),
            subtitle: Text(widget.patientEmail),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Patient Unique ID'),
            subtitle: Text(
              _patientUniqueId.isEmpty ? 'creating...' : _patientUniqueId,
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Sync health'),
            subtitle: Text(
              _lastSync == null
                  ? 'Waiting for first sync'
                  : 'Last sync: ${_lastSync!.toLocal()}',
            ),
          ),
        ),
        FilledButton.tonal(
          onPressed: _openQrEntryPoint,
          child: const Text('Open QR Scanner Entry Point'),
        ),
      ],
    );
  }

  Widget _metricChip(String label) {
    return Chip(
      label: Text(label),
      backgroundColor: const Color(0xFFCCFBF1),
      side: BorderSide.none,
    );
  }
}

class AiHelpScreen extends StatefulWidget {
  const AiHelpScreen({
    super.key,
    required this.apiService,
    required this.patientName,
  });

  final ApiService apiService;
  final String patientName;

  @override
  State<AiHelpScreen> createState() => _AiHelpScreenState();
}

class _AiHelpScreenState extends State<AiHelpScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, String>> _messages = [
    {
      'role': 'ai',
      'text':
          'Hi! I am your Q-Less AI helper. Ask for emergency flow, booking help, or complaint guidance.',
    },
  ];

  bool _sending = false;
  bool _lowDataMode = true;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _messages.add({'role': 'user', 'text': text});
      _messageController.clear();
    });

    final reply = await widget.apiService.askAiHelp(
      text,
      lowDataMode: _lowDataMode,
    );

    if (!mounted) return;
    setState(() {
      _messages.add({'role': 'ai', 'text': reply});
      _sending = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Help Assistant'),
        actions: [
          Row(
            children: [
              const Text('Low-data'),
              Switch(
                value: _lowDataMode,
                onChanged: (value) => setState(() => _lowDataMode = value),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            color: const Color(0xFFE0F2FE),
            child: Text(
              'Hello ${widget.patientName}. In low network zone this assistant auto-falls back to compact guidance.',
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final item = _messages[index];
                final isUser = item['role'] == 'user';
                return Align(
                  alignment: isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(maxWidth: 320),
                    decoration: BoxDecoration(
                      color: isUser
                          ? const Color(0xFFCCFBF1)
                          : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(item['text'] ?? ''),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Ask AI: emergency, booking, complaint... ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _sending ? null : _send,
                    child: Text(_sending ? '...' : 'Send'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
  FacilityRole _selectedRole = FacilityRole.hospital;
  bool _submitting = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    final ok = await ApiService().submitHospitalRegistration({
      'name': _name.text.trim(),
      'email': _email.text.trim(),
      'location': _location.text.trim(),
      'facilityType': _selectedRole.name,
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
      appBar: AppBar(title: const Text('Registration')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              SegmentedButton<FacilityRole>(
                segments: const [
                  ButtonSegment<FacilityRole>(
                    value: FacilityRole.hospital,
                    label: Text('Hospital'),
                    icon: Icon(Icons.local_hospital_outlined),
                  ),
                  ButtonSegment<FacilityRole>(
                    value: FacilityRole.clinic,
                    label: Text('Clinic'),
                    icon: Icon(Icons.medical_information_outlined),
                  ),
                ],
                selected: {_selectedRole},
                onSelectionChanged: (selection) {
                  setState(() => _selectedRole = selection.first);
                },
              ),
              const SizedBox(height: 12),
              _field(_name, '${_selectedRole.label} Name'),
              _field(_email, 'Official ${_selectedRole.label} Email'),
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
                child: const Text('Facility Login'),
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
          content: Text('Facility not found or not approved yet.'),
        ),
      );
      return;
    }

    final role = hospital.role;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => HospitalDashboardScreen(hospital: hospital, role: role),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Facility Login')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _email,
              decoration: const InputDecoration(
                labelText: 'Approved facility email',
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
  const HospitalDashboardScreen({
    super.key,
    required this.hospital,
    this.role = FacilityRole.hospital,
  });

  final HospitalInfo hospital;
  final FacilityRole role;

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
  List<AppointmentRecord> _appointments = [];
  int _selectedTabIndex = 0;
  String _statusFilter = 'all';
  io.Socket? _socket;
  Timer? _pollTimer;
  Timer? _statusTimer;
  Timer? _banExitTimer;
  bool _loadingAppointments = false;
  bool _saving = false;
  String _accountStatus = 'approved';

  @override
  void initState() {
    super.initState();
    _accountStatus = widget.hospital.status;
    if (_accountStatus == 'banned') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _startBanCountdown();
      });
    }
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
    _loadAppointments();
    _loadHospitalStatus();
    _connectLive();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadAppointments(),
    );
    _statusTimer = Timer.periodic(
      const Duration(seconds: 20),
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
      _applyAccountStatus(hospital['status']?.toString() ?? _accountStatus);
    } catch (_) {}
  }

  void _applyAccountStatus(String status) {
    final next = status.trim().isEmpty ? _accountStatus : status.trim();
    final previous = _accountStatus;
    if (!mounted) return;
    setState(() => _accountStatus = next);

    if (next == 'banned' && previous != 'banned') {
      _startBanCountdown();
    }
  }

  void _startBanCountdown() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Justice is been provided kiddo--Batman')),
    );
    _banExitTimer?.cancel();
    _banExitTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const HospitalLoginScreen()),
        (route) => false,
      );
    });
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
      socket.on('booking:created', (_) => _loadAppointments());
      socket.on('booking:updated', (_) => _loadAppointments());
      socket.on('hospital:availability-updated', (_) => _loadAppointments());
      socket.on('hospital:snapshot', (_) => _loadAppointments());
      socket.on('hospital:status-updated', (payload) {
        if (payload is! Map<String, dynamic>) return;
        final payloadId =
            payload['id']?.toString() ??
            payload['hospitalId']?.toString() ??
            '';
        if (payloadId != _hospitalId.text.trim()) return;
        _applyAccountStatus(payload['status']?.toString() ?? _accountStatus);
      });
      socket.connect();
      _socket = socket;
    } catch (_) {}
  }

  Future<void> _loadAppointments() async {
    if (_loadingAppointments) return;
    _loadingAppointments = true;
    try {
      final facilityId = _hospitalId.text.trim();
      final remote = await _api.getFacilityAppointments(
        facilityId: facilityId,
        role: widget.role,
      );
      final localActions = await _api.readFacilityAppointmentActions(
        facilityId: facilityId,
        role: widget.role,
      );
      final merged =
          remote.map((item) => localActions[item.id] ?? item).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() => _appointments = merged);
    } catch (_) {}
    _loadingAppointments = false;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _statusTimer?.cancel();
    _banExitTimer?.cancel();
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

  final ApiService _api = ApiService();

  Future<void> _transitionAppointment(
    AppointmentRecord appointment,
    String nextStatus, {
    String? assignedDoctor,
    String? assignedTime,
    int? queuePosition,
  }) async {
    if (!AppointmentFlow.canTransition(appointment.status, nextStatus)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot move ${appointment.displayId} from ${appointment.status} to $nextStatus.',
          ),
        ),
      );
      return;
    }

    final remote = await _api.updateAppointment(
      appointmentId: appointment.id,
      status: nextStatus,
      assignedDoctor: assignedDoctor,
      assignedTime: assignedTime,
      queuePosition: queuePosition,
    );
    final updated =
        remote ??
        appointment.copyWith(
          status: nextStatus,
          assignedDoctor: assignedDoctor,
          assignedTime: assignedTime,
          queuePosition: queuePosition,
          updatedAt: DateTime.now().toIso8601String(),
        );
    final facilityId = _hospitalId.text.trim();
    if (remote == null) {
      await _api.saveFacilityAppointmentAction(
        facilityId: facilityId,
        role: widget.role,
        appointment: updated,
      );
    }
    if (!mounted) return;
    setState(() {
      _appointments = _appointments.map((item) {
        if (item.id != updated.id) return item;
        return updated;
      }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          remote == null
              ? '${appointment.displayId} updated locally. Sync pending.'
              : '${appointment.displayId} moved to $nextStatus.',
        ),
      ),
    );
  }

  Future<void> _openAssignDialog(AppointmentRecord appointment) async {
    final selected = await showDialog<SlotSelection>(
      context: context,
      builder: (ctx) => TimeSlotPickerDialog(
        title: 'Assign doctor & time',
        initialDoctor: appointment.assignedDoctor,
        initialTime: appointment.assignedTime,
      ),
    );
    if (selected == null) return;
    await _transitionAppointment(
      appointment,
      'assigned',
      assignedDoctor: selected.doctor,
      assignedTime: selected.time,
    );
  }

  Future<void> _openQueueDialog(AppointmentRecord appointment) async {
    final controller = TextEditingController(
      text: '${appointment.queuePosition ?? 1}',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set queue position'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Queue position',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final queue = int.tryParse(controller.text.trim()) ?? 1;
    await _transitionAppointment(
      appointment,
      'queued',
      queuePosition: queue < 1 ? 1 : queue,
    );
  }

  Future<void> _openHqrForAppointment(AppointmentRecord appointment) async {
    final facilityId = _hospitalId.text.trim();
    final hqr = await _api.generateHqr(
      bookingId: appointment.id,
      facilityId: facilityId,
    );
    if (!mounted) return;
    if (hqr == null || hqr.verifyUrl.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate HQR for ${appointment.displayId}.'),
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('HQR Check-in'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: hqr.verifyUrl,
                size: 220,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF0F172A),
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Expires in ${hqr.expiresInSeconds ~/ 60} minutes',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              SelectableText(
                hqr.verifyUrl,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  List<AppointmentRecord> _filteredAppointments() {
    if (_statusFilter == 'all') return _appointments;
    return _appointments.where((item) => item.status == _statusFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isClinic = widget.role == FacilityRole.clinic;
    final approvalColor = _accountStatus == 'approved'
        ? const Color(0xFF16A34A)
        : const Color(0xFFF59E0B);
    final appBarTitle = isClinic ? 'Clinic Dashboard' : 'Hospital Dashboard';
    final destinations = isClinic
        ? const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.event_note_outlined),
              selectedIcon: Icon(Icons.event_note),
              label: 'Appointments',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ]
        : const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.event_note_outlined),
              selectedIcon: Icon(Icons.event_note),
              label: 'Appointments',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ];
    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        actions: [
          IconButton(
            tooltip: 'Refresh now',
            onPressed: () {
              _loadHospitalStatus();
              _loadAppointments();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _accountStatus == 'deactivated'
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                Card(
                  color: Color(0xFFFEE2E2),
                  child: ListTile(
                    leading: Icon(Icons.lock_outline, color: Colors.red),
                    title: Text('Account is deactivated by admin'),
                    subtitle: Text(
                      'Please request admin for re-activation of account with proof.',
                    ),
                  ),
                ),
              ],
            )
          : _accountStatus == 'banned'
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                Card(
                  color: Color(0xFF111827),
                  child: ListTile(
                    leading: Icon(Icons.gavel, color: Colors.white),
                    title: Text(
                      'Justice is been provided kiddo--Batman',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      'Account has been banned permanently. Redirecting to login in 30 seconds.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ],
            )
          : IndexedStack(
              index: _selectedTabIndex,
              children: [
                _buildFacilityDashboardHome(approvalColor, isClinic),
                _buildFacilityAppointmentsTab(),
                _buildFacilitySettingsOrProfile(isClinic),
              ],
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTabIndex,
        destinations: destinations,
        onDestinationSelected: (value) {
          setState(() => _selectedTabIndex = value);
        },
      ),
    );
  }

  Widget _buildFacilityDashboardHome(Color approvalColor, bool isClinic) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: const Color(0xFFE0F2FE),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.hospital.name,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text('${widget.hospital.location} • ${widget.hospital.email}'),
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
                      label: Text('Appointments ${_appointments.length}'),
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
        if (isClinic) ...[
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('OPD Calendar'),
              subtitle: Text(
                'Today • ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Doctor Slot Management'),
              subtitle: Text(
                'Doctors available: ${_doctors.text} • Avg wait: ${_wait.text} min',
              ),
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _hospitalStatCard('Doctors', _doctors.text),
              _hospitalStatCard('Queue Min', _wait.text),
              _hospitalStatCard('Appointments', '${_appointments.length}'),
            ],
          ),
        ] else ...[
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _hospitalStatCard('Beds', _beds.text),
              _hospitalStatCard('ICU', _icu.text),
              _hospitalStatCard('OT', _ot.text),
              _hospitalStatCard('Doctors', _doctors.text),
              _hospitalStatCard('Surgeons', _surgeons.text),
              _hospitalStatCard('Appointments', '${_appointments.length}'),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildFacilityAppointmentsTab() {
    if (_loadingAppointments) {
      return const Center(child: CircularProgressIndicator());
    }
    final filtered = _filteredAppointments();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final status in const [
              'all',
              'pending',
              'accepted',
              'assigned',
              'queued',
              'completed',
              'declined',
            ])
              ChoiceChip(
                label: Text(status.toUpperCase()),
                selected: _statusFilter == status,
                onSelected: (_) => setState(() => _statusFilter = status),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          const Card(
            child: ListTile(title: Text('No appointments for selected filter')),
          )
        else
          ...filtered.map((appointment) {
            final actions = <AppointmentCardAction>[];
            if (appointment.status == 'pending') {
              actions.add(
                AppointmentCardAction(
                  label: 'Accept',
                  semanticLabel: 'Accept appointment ${appointment.displayId}',
                  onPressed: () =>
                      _transitionAppointment(appointment, 'accepted'),
                ),
              );
              actions.add(
                AppointmentCardAction(
                  label: 'Decline',
                  semanticLabel: 'Decline appointment ${appointment.displayId}',
                  onPressed: () =>
                      _transitionAppointment(appointment, 'declined'),
                ),
              );
            } else if (appointment.status == 'accepted' ||
                appointment.status == 'reschedule_requested') {
              actions.add(
                AppointmentCardAction(
                  label: 'Assign',
                  semanticLabel:
                      'Assign doctor and time for ${appointment.displayId}',
                  onPressed: () => _openAssignDialog(appointment),
                ),
              );
              actions.add(
                AppointmentCardAction(
                  label: 'HQR',
                  semanticLabel: 'Generate HQR for ${appointment.displayId}',
                  onPressed: () => _openHqrForAppointment(appointment),
                ),
              );
            } else if (appointment.status == 'assigned') {
              actions.add(
                AppointmentCardAction(
                  label: 'Queue',
                  semanticLabel:
                      'Set queue position for ${appointment.displayId}',
                  onPressed: () => _openQueueDialog(appointment),
                ),
              );
              actions.add(
                AppointmentCardAction(
                  label: 'HQR',
                  semanticLabel: 'Generate HQR for ${appointment.displayId}',
                  onPressed: () => _openHqrForAppointment(appointment),
                ),
              );
            } else if (appointment.status == 'queued') {
              actions.add(
                AppointmentCardAction(
                  label: 'Complete',
                  semanticLabel:
                      'Mark appointment ${appointment.displayId} complete',
                  onPressed: () =>
                      _transitionAppointment(appointment, 'completed'),
                ),
              );
              actions.add(
                AppointmentCardAction(
                  label: 'HQR',
                  semanticLabel: 'Generate HQR for ${appointment.displayId}',
                  onPressed: () => _openHqrForAppointment(appointment),
                ),
              );
            }
            return AppointmentCard(
              appointment: appointment,
              showHospitalName: false,
              actions: actions,
            );
          }),
      ],
    );
  }

  Widget _buildFacilitySettingsOrProfile(bool isClinic) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _nField(_hospitalId, '${widget.role.label} ID'),
        _nField(_doctors, 'Doctors Available'),
        _nField(_wait, 'Estimated Wait (minutes)'),
        if (!isClinic) ...[
          _nField(_beds, 'Beds Available'),
          _nField(_icu, 'ICU Available'),
          _nField(_ot, 'OT Available'),
          _nField(_surgeons, 'Surgeons Available'),
        ],
        const SizedBox(height: 10),
        FilledButton(
          onPressed: (_saving || _accountStatus != 'approved') ? null : _save,
          child: Text(_saving ? 'Saving...' : 'Update Live Availability'),
        ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text('${widget.role.label} profile'),
            subtitle: Text(
              '${widget.hospital.name}\n${widget.hospital.location} • ${widget.hospital.email}',
            ),
          ),
        ),
      ],
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardWidth = ((screenWidth - 48) / 2).clamp(150.0, 220.0);
    return SizedBox(
      width: cardWidth,
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

class AppointmentCardAction {
  const AppointmentCardAction({
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback onPressed;
}

class AppointmentCard extends StatelessWidget {
  const AppointmentCard({
    super.key,
    required this.appointment,
    required this.showHospitalName,
    this.highlighted = false,
    this.actions = const [],
  });

  final AppointmentRecord appointment;
  final bool showHospitalName;
  final bool highlighted;
  final List<AppointmentCardAction> actions;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: highlighted ? const Color(0xFF0F766E) : Colors.transparent,
          width: highlighted ? 2 : 0,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  appointment.displayId,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                StatusBadge(status: appointment.status),
                _TypeBadge(type: appointment.type),
                _FacilityEntityBadge(facilityType: appointment.facilityType),
              ],
            ),
            const SizedBox(height: 8),
            if (showHospitalName)
              Text(
                'Facility: ${appointment.hospitalName} • ${appointment.facilityRole.label}',
              ),
            Text('Patient: ${appointment.patientName}'),
            Text('Created: ${appointment.createdAt}'),
            if ((appointment.assignedDoctor ?? '').isNotEmpty)
              Text('Doctor: ${appointment.assignedDoctor}'),
            if ((appointment.assignedTime ?? '').isNotEmpty)
              Text('Time: ${appointment.assignedTime}'),
            if (appointment.queuePosition != null)
              Text('Queue position: ${appointment.queuePosition}'),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: actions
                    .map(
                      (action) => Semantics(
                        button: true,
                        label: action.semanticLabel,
                        child: FilledButton.tonal(
                          onPressed: action.onPressed,
                          child: Text(action.label),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final color = switch (normalized) {
      'pending' => const Color(0xFFB45309),
      'accepted' => const Color(0xFF0369A1),
      'assigned' => const Color(0xFF4338CA),
      'queued' => const Color(0xFF0F766E),
      'completed' => const Color(0xFF15803D),
      'declined' || 'canceled' => const Color(0xFFB91C1C),
      'reschedule_requested' => const Color(0xFF7C2D12),
      _ => const Color(0xFF374151),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        normalized.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2FE),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        type.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF0C4A6E),
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _FacilityEntityBadge extends StatelessWidget {
  const _FacilityEntityBadge({required this.facilityType});

  final String facilityType;

  @override
  Widget build(BuildContext context) {
    final role = facilityRoleFromString(facilityType);
    final isClinic = role == FacilityRole.clinic;
    final bg = isClinic ? const Color(0xFFE0F2FE) : const Color(0xFFCCFBF1);
    final fg = isClinic ? const Color(0xFF1E40AF) : const Color(0xFF0D9488);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isClinic ? Icons.medical_services : Icons.local_hospital,
            size: 12,
            color: fg,
          ),
          const SizedBox(width: 4),
          Text(
            isClinic ? 'CLINIC' : 'HOSPITAL',
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class NotificationCenterResult {
  NotificationCenterResult({required this.seenIds, required this.starredIds});

  final Set<String> seenIds;
  final Set<String> starredIds;
}

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({
    super.key,
    required this.notifications,
    required this.initialSeenIds,
    required this.initialStarredIds,
    required this.facilityRoleByHospitalId,
  });

  final List<PatientNotification> notifications;
  final Set<String> initialSeenIds;
  final Set<String> initialStarredIds;
  final Map<String, FacilityRole> facilityRoleByHospitalId;

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  late Set<String> _seenIds;
  late Set<String> _starredIds;

  @override
  void initState() {
    super.initState();
    _seenIds = {...widget.initialSeenIds};
    _starredIds = {...widget.initialStarredIds};
  }

  List<PatientNotification> get _visibleNotifications {
    return widget.notifications.where((notification) {
      return !_seenIds.contains(notification.id) ||
          _starredIds.contains(notification.id);
    }).toList();
  }

  NotificationCenterResult _buildResult() {
    final autoSeen = _visibleNotifications
        .where((item) => !_starredIds.contains(item.id))
        .map((item) => item.id);
    return NotificationCenterResult(
      seenIds: {..._seenIds, ...autoSeen},
      starredIds: {..._starredIds},
    );
  }

  void _closeWithResult() {
    Navigator.of(context).pop(_buildResult());
  }

  void _toggleStar(String id) {
    setState(() {
      if (_starredIds.contains(id)) {
        _starredIds.remove(id);
      } else {
        _starredIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleNotifications;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        _closeWithResult();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: _closeWithResult,
            icon: const Icon(Icons.arrow_back),
          ),
          title: const Text('Notifications'),
        ),
        body: visible.isEmpty
            ? const Center(
                child: Text('No unseen notifications. Starred ones stay here.'),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final item = visible[index];
                  final isStarred = _starredIds.contains(item.id);
                  final role = widget.facilityRoleByHospitalId[item.hospitalId];
                  return Card(
                    color: const Color(0xFFFFF7ED),
                    child: ListTile(
                      onTap: () => setState(() => _seenIds.add(item.id)),
                      leading: const Icon(Icons.notifications_active_outlined),
                      title: Text(item.title),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 2),
                          Text(item.message),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (role != null)
                                _FacilityEntityBadge(facilityType: role.name),
                              if (item.createdAt.trim().isNotEmpty)
                                Text(
                                  item.createdAt,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ],
                      ),
                      trailing: IconButton(
                        tooltip: isStarred
                            ? 'Unstar notification'
                            : 'Star notification',
                        onPressed: () => _toggleStar(item.id),
                        style: IconButton.styleFrom(
                          backgroundColor: isStarred
                              ? const Color(0xFFCCFBF1)
                              : const Color(0xFF94A3B8),
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(34, 34),
                        ),
                        icon: Icon(
                          isStarred
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: isStarred
                              ? const Color(0xFF0D9488)
                              : Colors.white,
                          size: 19,
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class AppointmentQrScannerScreen extends StatefulWidget {
  const AppointmentQrScannerScreen({
    super.key,
    required this.appointments,
    required this.api,
    required this.patientId,
  });

  final List<AppointmentRecord> appointments;
  final ApiService api;
  final String patientId;

  @override
  State<AppointmentQrScannerScreen> createState() =>
      _AppointmentQrScannerScreenState();
}

class _AppointmentQrScannerScreenState
    extends State<AppointmentQrScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final TextEditingController _manualCodeController = TextEditingController();
  bool _handledScan = false;
  String? _scanError;

  @override
  void dispose() {
    _scannerController.dispose();
    _manualCodeController.dispose();
    super.dispose();
  }

  String _extractToken(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return '';
    final uri = Uri.tryParse(cleaned);
    if (uri != null) {
      final qpToken = uri.queryParameters['token'];
      if (qpToken != null && qpToken.trim().isNotEmpty) {
        return qpToken.trim();
      }
    }
    return cleaned;
  }

  Future<void> _handleScannedValue(String raw) async {
    if (_handledScan) return;
    final token = _extractToken(raw);
    if (token.isEmpty) {
      setState(() {
        _scanError = 'Missing token in scanned content.';
      });
      return;
    }
    final result = await widget.api.verifyHqr(
      token: token,
      patientId: widget.patientId,
    );
    if (!mounted) return;
    if (!result.verified) {
      setState(() {
        _scanError = result.reason;
      });
      return;
    }
    AppointmentRecord? appointment;
    for (final item in widget.appointments) {
      if (item.id == result.bookingId) {
        appointment = item;
        break;
      }
    }
    if (appointment == null) {
      setState(() {
        _scanError =
            'Verified, but appointment is not loaded locally. Pull to refresh.';
      });
      return;
    }
    _handledScan = true;
    Navigator.of(context).pop(appointment);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Appointment QR')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _scannerController,
                    onDetect: (capture) {
                      if (capture.barcodes.isEmpty) return;
                      final code = capture.barcodes.first.rawValue;
                      if (code == null) return;
                      _handleScannedValue(code);
                    },
                    errorBuilder: (context, error, child) {
                      return Container(
                        color: const Color(0xFF0F172A),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Camera unavailable.\nUse manual code entry below.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: Colors.white),
                        ),
                      );
                    },
                  ),
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 220,
                        height: 220,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: const Color(0xFF99F6E4),
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Scan HQR token (or verify URL), or paste token manually.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _manualCodeController,
            decoration: const InputDecoration(
              labelText: 'Manual token / URL',
              hintText: 'https://.../api/hqr/verify?token=...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () => _handleScannedValue(_manualCodeController.text),
            child: const Text('Open Appointment'),
          ),
          if (_scanError != null) ...[
            const SizedBox(height: 12),
            Text(_scanError!, style: const TextStyle(color: Color(0xFFB91C1C))),
          ],
          const SizedBox(height: 16),
          if (widget.appointments.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recent appointment codes',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ...widget.appointments
                        .take(3)
                        .map(
                          (appointment) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(appointment.displayId),
                            subtitle: Text(
                              '${appointment.hospitalName} • ${appointment.status}',
                            ),
                            trailing: IconButton(
                              onPressed: () =>
                                  _handleScannedValue(appointment.displayId),
                              icon: const Icon(Icons.open_in_new),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SlotSelection {
  const SlotSelection({required this.doctor, required this.time});

  final String doctor;
  final String time;
}

class TimeSlotPickerDialog extends StatefulWidget {
  const TimeSlotPickerDialog({
    super.key,
    required this.title,
    this.initialDoctor,
    this.initialTime,
  });

  final String title;
  final String? initialDoctor;
  final String? initialTime;

  @override
  State<TimeSlotPickerDialog> createState() => _TimeSlotPickerDialogState();
}

class _TimeSlotPickerDialogState extends State<TimeSlotPickerDialog> {
  late final TextEditingController _doctorController;
  late String _selectedTime;
  static const _slots = [
    '09:00 AM',
    '10:30 AM',
    '12:00 PM',
    '02:30 PM',
    '04:00 PM',
    '06:30 PM',
  ];

  @override
  void initState() {
    super.initState();
    _doctorController = TextEditingController(text: widget.initialDoctor ?? '');
    _selectedTime = _slots.contains(widget.initialTime)
        ? widget.initialTime!
        : _slots.first;
  }

  @override
  void dispose() {
    _doctorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _doctorController,
            decoration: const InputDecoration(
              labelText: 'Doctor name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedTime,
            decoration: const InputDecoration(
              labelText: 'Time slot',
              border: OutlineInputBorder(),
            ),
            items: _slots
                .map((slot) => DropdownMenuItem(value: slot, child: Text(slot)))
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selectedTime = value);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final doctor = _doctorController.text.trim();
            if (doctor.isEmpty) return;
            Navigator.of(
              context,
            ).pop(SlotSelection(doctor: doctor, time: _selectedTime));
          },
          child: const Text('Assign'),
        ),
      ],
    );
  }
}
