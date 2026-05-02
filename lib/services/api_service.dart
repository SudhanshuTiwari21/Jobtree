import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

/// API Configuration
class ApiConfig {
  // Change this to your backend URL
  // Development: http://localhost:3000/api or http://10.0.2.2:3000/api (Android emulator)
  // Production: https://your-api-domain.com/api
  static const String baseUrl = 'http://13.201.127.250:3000/api';
  
  // Timeout durations
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
}

/// API Response wrapper
class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? message;
  final String? errorCode;
  final int? attemptsRemaining;
  final int? waitSeconds;

  ApiResponse({
    required this.success,
    this.data,
    this.message,
    this.errorCode,
    this.attemptsRemaining,
    this.waitSeconds,
  });

  factory ApiResponse.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic>)? fromJsonT) {
    return ApiResponse(
      success: json['success'] ?? false,
      data: json['data'] != null && fromJsonT != null ? fromJsonT(json['data']) : json['data'],
      message: json['message'],
      errorCode: json['errorCode'],
      attemptsRemaining: json['attemptsRemaining'],
      waitSeconds: json['waitSeconds'],
    );
  }

  factory ApiResponse.error(String message, {String? errorCode}) {
    return ApiResponse(
      success: false,
      message: message,
      errorCode: errorCode,
    );
  }
}

/// Main API Service
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final AuthService _authService = AuthService();

  /// Get headers for API requests
  Future<Map<String, String>> _getHeaders({bool requireAuth = false}) async {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (requireAuth) {
      final token = await _authService.getAccessToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

  /// Make GET request
  Future<ApiResponse<T>> get<T>(
    String endpoint, {
    bool requireAuth = false,
    T Function(Map<String, dynamic>)? fromJson,
    Map<String, String>? queryParams,
  }) async {
    try {
      final headers = await _getHeaders(requireAuth: requireAuth);
      
      // Build URI with query parameters
      final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint');
      final uriWithParams = queryParams != null && queryParams.isNotEmpty
          ? uri.replace(queryParameters: queryParams)
          : uri;
      
      final response = await http
          .get(
            uriWithParams,
            headers: headers,
          )
          .timeout(ApiConfig.connectionTimeout);

      return _handleResponse(response, fromJson);
    } on SocketException {
      return ApiResponse.error('No internet connection', errorCode: 'NETWORK_ERROR');
    } on HttpException {
      return ApiResponse.error('Server error', errorCode: 'HTTP_ERROR');
    } catch (e) {
      return ApiResponse.error('Something went wrong: ${e.toString()}', errorCode: 'UNKNOWN_ERROR');
    }
  }

  /// Make POST request
  Future<ApiResponse<T>> post<T>(
    String endpoint, {
    Map<String, dynamic>? body,
    bool requireAuth = false,
    T Function(Map<String, dynamic>)? fromJson,
  }) async {
    try {
      final headers = await _getHeaders(requireAuth: requireAuth);
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}$endpoint'),
            headers: headers,
            body: body != null ? json.encode(body) : null,
          )
          .timeout(ApiConfig.connectionTimeout);

      return _handleResponse(response, fromJson);
    } on SocketException {
      return ApiResponse.error('No internet connection', errorCode: 'NETWORK_ERROR');
    } on HttpException {
      return ApiResponse.error('Server error', errorCode: 'HTTP_ERROR');
    } catch (e) {
      return ApiResponse.error('Something went wrong: ${e.toString()}', errorCode: 'UNKNOWN_ERROR');
    }
  }

  /// Make PATCH request
  Future<ApiResponse<T>> patch<T>(
    String endpoint, {
    Map<String, dynamic>? body,
    bool requireAuth = true,
    T Function(Map<String, dynamic>)? fromJson,
  }) async {
    try {
      final headers = await _getHeaders(requireAuth: requireAuth);
      final response = await http
          .patch(
            Uri.parse('${ApiConfig.baseUrl}$endpoint'),
            headers: headers,
            body: body != null ? json.encode(body) : null,
          )
          .timeout(ApiConfig.connectionTimeout);

      return _handleResponse(response, fromJson);
    } on SocketException {
      return ApiResponse.error('No internet connection', errorCode: 'NETWORK_ERROR');
    } on HttpException {
      return ApiResponse.error('Server error', errorCode: 'HTTP_ERROR');
    } catch (e) {
      return ApiResponse.error('Something went wrong: ${e.toString()}', errorCode: 'UNKNOWN_ERROR');
    }
  }

  /// Make DELETE request
  Future<ApiResponse<T>> delete<T>(
    String endpoint, {
    bool requireAuth = true,
    T Function(Map<String, dynamic>)? fromJson,
  }) async {
    try {
      final headers = await _getHeaders(requireAuth: requireAuth);
      final response = await http
          .delete(
            Uri.parse('${ApiConfig.baseUrl}$endpoint'),
            headers: headers,
          )
          .timeout(ApiConfig.connectionTimeout);

      return _handleResponse(response, fromJson);
    } on SocketException {
      return ApiResponse.error('No internet connection', errorCode: 'NETWORK_ERROR');
    } on HttpException {
      return ApiResponse.error('Server error', errorCode: 'HTTP_ERROR');
    } catch (e) {
      return ApiResponse.error('Something went wrong: ${e.toString()}', errorCode: 'UNKNOWN_ERROR');
    }
  }

  /// Handle HTTP response
  ApiResponse<T> _handleResponse<T>(
    http.Response response,
    T Function(Map<String, dynamic>)? fromJson,
  ) {
    final Map<String, dynamic> responseBody;
    
    try {
      responseBody = json.decode(response.body);
    } catch (e) {
      return ApiResponse.error('Invalid response from server', errorCode: 'PARSE_ERROR');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Determine the data source: use 'data' field if present, otherwise use root response
      T? parsedData;
      if (fromJson != null) {
        // If there's a 'data' field, use it; otherwise parse from root
        final dataSource = responseBody['data'] != null 
            ? (responseBody['data'] is Map<String, dynamic> ? responseBody['data'] : responseBody)
            : responseBody;
        try {
          parsedData = fromJson(dataSource as Map<String, dynamic>);
        } catch (e) {
          // If parsing fails, return error
          return ApiResponse.error('Failed to parse response: ${e.toString()}', errorCode: 'PARSE_ERROR');
        }
      } else if (responseBody['data'] != null) {
        parsedData = responseBody['data'] as T?;
      }
      
      return ApiResponse(
        success: responseBody['success'] ?? true,
        data: parsedData,
        message: responseBody['message'],
      );
    } else if (response.statusCode == 401) {
      // Token expired - try to refresh
      _authService.clearTokens();
      return ApiResponse.error(
        responseBody['message'] ?? 'Session expired. Please login again.',
        errorCode: 'UNAUTHORIZED',
      );
    } else if (response.statusCode == 429) {
      // Rate limited
      return ApiResponse(
        success: false,
        message: responseBody['message'] ?? 'Too many requests. Please try again later.',
        errorCode: 'RATE_LIMITED',
        waitSeconds: responseBody['waitSeconds'],
      );
    } else {
      return ApiResponse(
        success: false,
        message: responseBody['message'] ?? responseBody['error']?['message'] ?? 'Request failed',
        errorCode: responseBody['errorCode'] ?? 'API_ERROR',
        attemptsRemaining: responseBody['attemptsRemaining'],
      );
    }
  }

  // ============== AUTH ENDPOINTS ==============

  /// Send OTP to phone number
  Future<ApiResponse> sendOtp(String phoneNumber, {String countryCode = '+91'}) async {
    return post(
      '/auth/send-otp',
      body: {
        'phoneNumber': phoneNumber,
        'countryCode': countryCode,
      },
    );
  }

  /// Resend OTP
  Future<ApiResponse> resendOtp(String phoneNumber, {String countryCode = '+91'}) async {
    return post(
      '/auth/resend-otp',
      body: {
        'phoneNumber': phoneNumber,
        'countryCode': countryCode,
      },
    );
  }

  /// Verify OTP and login/signup
  Future<ApiResponse<AuthResult>> verifyOtp(
    String phoneNumber,
    String otp, {
    String countryCode = '+91',
  }) async {
    final response = await post<AuthResult>(
      '/auth/verify-otp',
      body: {
        'phoneNumber': phoneNumber,
        'otp': otp,
        'countryCode': countryCode,
      },
      fromJson: AuthResult.fromJson,
    );

    // Save tokens on successful verification
    if (response.success && response.data != null) {
      await _authService.saveTokens(
        response.data!.accessToken,
        response.data!.refreshToken,
      );
      await _authService.saveSalonData(response.data!.salon);
      // Save role based on existing profiles
      if (response.data!.ownerExists) {
        await _authService.saveUserRole('salon');
      } else if (response.data!.seekerExists) {
        await _authService.saveUserRole('seeker');
      }
      // Default role will be set when user picks a role on RoleSelectionScreen
    }

    return response;
  }

  /// Refresh access token
  Future<ApiResponse> refreshToken() async {
    final refreshToken = await _authService.getRefreshToken();
    if (refreshToken == null) {
      return ApiResponse.error('No refresh token', errorCode: 'NO_TOKEN');
    }

    final response = await post(
      '/auth/refresh',
      body: {'refreshToken': refreshToken},
    );

    if (response.success && response.data != null) {
      await _authService.saveAccessToken(response.data['accessToken']);
    }

    return response;
  }

  /// Switch role to seeker - gets a seeker JWT using existing salon auth
  Future<ApiResponse<SeekerAuthResult>> switchToSeeker() async {
    try {
      final headers = await _getHeaders(requireAuth: true);
      final httpResponse = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/auth/switch-role'),
            headers: headers,
            body: json.encode({'role': 'seeker'}),
          )
          .timeout(ApiConfig.connectionTimeout);

      final responseBody = json.decode(httpResponse.body);
      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        final result = SeekerAuthResult.fromJson(responseBody);
        // Save seeker tokens (replace salon tokens)
        await _authService.saveTokens(result.accessToken, result.refreshToken);
        await _authService.saveSeekerData(result.seeker);
        await _authService.saveUserRole('seeker');
        return ApiResponse(success: true, data: result);
      }
      return ApiResponse.error(responseBody['message'] ?? 'Failed to switch role');
    } catch (e) {
      return ApiResponse.error('Something went wrong: ${e.toString()}');
    }
  }

  /// Logout
  Future<ApiResponse> logout() async {
    final response = await post('/auth/logout', requireAuth: true);
    await _authService.clearTokens();
    return response;
  }

  // ============== SALON ENDPOINTS ==============

  /// Get current salon profile
  Future<ApiResponse<SalonProfile>> getSalonProfile() async {
    return get<SalonProfile>(
      '/salon/me',
      requireAuth: true,
      fromJson: SalonProfile.fromJson,
    );
  }

  /// Update salon profile (partial update)
  Future<ApiResponse<SalonProfile>> updateSalonProfile(Map<String, dynamic> updates) async {
    // Only send non-null values
    final cleanUpdates = Map<String, dynamic>.from(updates)
      ..removeWhere((key, value) => value == null);

    if (cleanUpdates.isEmpty) {
      return ApiResponse.error('No fields to update');
    }

    return patch<SalonProfile>(
      '/salon/profile',
      body: cleanUpdates,
      requireAuth: true,
      fromJson: SalonProfile.fromJson,
    );
  }

  /// Get profile completion status
  Future<ApiResponse<ProfileCompletion>> getProfileCompletion() async {
    return get<ProfileCompletion>(
      '/salon/completion',
      requireAuth: true,
      fromJson: ProfileCompletion.fromJson,
    );
  }

  // ============== MEDIA ENDPOINTS ==============

  /// Get presigned URL for media upload
  Future<ApiResponse<PresignedUrl>> getMediaPresignedUrl({
    required String mediaType,
    required String contentType,
    String? filename,
  }) async {
    return post<PresignedUrl>(
      '/salon/media/presign',
      body: {
        'mediaType': mediaType,
        'contentType': contentType,
        if (filename != null) 'filename': filename,
      },
      requireAuth: true,
      fromJson: PresignedUrl.fromJson,
    );
  }

  /// Save media record after upload
  Future<ApiResponse> saveMediaRecord({
    required String mediaType,
    required String mediaUrl,
    bool isPrimary = false,
  }) async {
    return post(
      '/salon/media',
      body: {
        'mediaType': mediaType,
        'mediaUrl': mediaUrl,
        'isPrimary': isPrimary,
      },
      requireAuth: true,
    );
  }

  /// Delete media
  Future<ApiResponse> deleteMedia(String mediaId) async {
    return delete('/salon/media/$mediaId', requireAuth: true);
  }

  // ============== JOB ENDPOINTS ==============

  /// Create a new job posting
  Future<ApiResponse<Job>> createJob({
    required String jobRole,
    String? otherCategory,
    String? customRoleName,
    List<String>? skills,
    required String location,
    int numberOfStaff = 1,
    required double salaryMin,
    required double salaryMax,
    required String workType,
    required String experience,
    String? accommodation,
    String? preferredGender,
  }) async {
    try {
      final headers = await _getHeaders(requireAuth: true);
      
      final body = {
        'jobRole': jobRole,
        if (otherCategory != null) 'otherCategory': otherCategory,
        if (customRoleName != null && customRoleName.isNotEmpty) 'customRoleName': customRoleName,
        if (skills != null && skills.isNotEmpty) 'skills': skills,
        'location': location,
        'numberOfStaff': numberOfStaff,
        'salaryMin': salaryMin,
        'salaryMax': salaryMax,
        'workType': workType,
        'experience': experience,
        if (accommodation != null) 'accommodation': accommodation,
        if (preferredGender != null) 'preferredGender': preferredGender,
      };
      
      print('Creating job with data: $body');
      
      final httpResponse = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/jobs'),
            headers: headers,
            body: json.encode(body),
          )
          .timeout(ApiConfig.connectionTimeout);

      // Parse response body
      final Map<String, dynamic> responseBody;
      try {
        responseBody = json.decode(httpResponse.body);
        print('Create job API raw response: ${httpResponse.body}');
      } catch (e) {
        print('Failed to parse create job response: $e');
        return ApiResponse.error('Invalid response from server', errorCode: 'PARSE_ERROR');
      }

      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        // Backend returns: { success: true, message: '...', job: {...} }
        final jobData = responseBody['job'] as Map<String, dynamic>?;
        
        if (jobData != null) {
          try {
            final job = Job.fromJson(jobData);
            print('Successfully created job: ${job.id}');
            return ApiResponse(
              success: true,
              data: job,
              message: responseBody['message'] ?? 'Job created successfully',
            );
          } catch (e) {
            print('Error parsing created job: $e');
            return ApiResponse.error('Failed to parse created job: ${e.toString()}', errorCode: 'PARSE_ERROR');
          }
        } else {
          print('No job field in response');
          return ApiResponse.error('Invalid response format', errorCode: 'PARSE_ERROR');
        }
      } else {
        final errorMsg = responseBody['message'] ?? 'Failed to create job';
        print('Create job API error: ${httpResponse.statusCode} - $errorMsg');
        return ApiResponse.error(errorMsg, errorCode: 'HTTP_ERROR');
      }
    } on SocketException {
      print('Network error creating job');
      return ApiResponse.error('No internet connection', errorCode: 'NETWORK_ERROR');
    } on HttpException catch (e) {
      print('HTTP error creating job: $e');
      return ApiResponse.error('Server error', errorCode: 'HTTP_ERROR');
    } catch (e, stackTrace) {
      print('Unexpected error creating job: $e');
      print('Stack trace: $stackTrace');
      return ApiResponse.error('Something went wrong: ${e.toString()}', errorCode: 'UNKNOWN_ERROR');
    }
  }

  /// Get all jobs for current salon
  Future<ApiResponse<List<Job>>> getJobs() async {
    try {
      final headers = await _getHeaders(requireAuth: true);
      final httpResponse = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/jobs/my-jobs'),
            headers: headers,
          )
          .timeout(ApiConfig.connectionTimeout);

      // Parse response body
      final Map<String, dynamic> responseBody;
      try {
        responseBody = json.decode(httpResponse.body);
        print('Jobs API raw response: ${httpResponse.body}');
      } catch (e) {
        print('Failed to parse jobs response: $e');
        return ApiResponse.error('Invalid response from server', errorCode: 'PARSE_ERROR');
      }

      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        // Backend returns: { success: true, jobs: [...], total: ..., ... }
        final success = responseBody['success'] ?? true;
        final jobsList = responseBody['jobs'] as List<dynamic>?;
        
        if (jobsList != null) {
          try {
            final jobs = jobsList
                .map((item) {
                  try {
                    return Job.fromJson(item as Map<String, dynamic>);
                  } catch (e) {
                    print('Error parsing job item: $e');
                    print('Job item: $item');
                    return null;
                  }
                })
                .whereType<Job>()
                .toList();
            
            print('Successfully parsed ${jobs.length} jobs');
            return ApiResponse(
              success: true,
              data: jobs,
              message: 'Jobs loaded successfully',
            );
          } catch (e) {
            print('Error parsing jobs list: $e');
            return ApiResponse.error('Failed to parse jobs: ${e.toString()}', errorCode: 'PARSE_ERROR');
          }
        } else {
          print('No jobs field in response, returning empty list');
          return ApiResponse(
            success: true,
            data: [],
            message: 'No jobs found',
          );
        }
      } else {
        final errorMsg = responseBody['message'] ?? 'Failed to load jobs';
        print('Jobs API error: ${httpResponse.statusCode} - $errorMsg');
        return ApiResponse.error(errorMsg, errorCode: 'HTTP_ERROR');
      }
    } on SocketException {
      print('Network error loading jobs');
      return ApiResponse.error('No internet connection', errorCode: 'NETWORK_ERROR');
    } on HttpException catch (e) {
      print('HTTP error loading jobs: $e');
      return ApiResponse.error('Server error', errorCode: 'HTTP_ERROR');
    } catch (e, stackTrace) {
      print('Unexpected error loading jobs: $e');
      print('Stack trace: $stackTrace');
      return ApiResponse.error('Something went wrong: ${e.toString()}', errorCode: 'UNKNOWN_ERROR');
    }
  }

  /// Get single job by ID
  Future<ApiResponse<Job>> getJobById(String jobId) async {
    return get<Job>(
      '/jobs/$jobId',
      requireAuth: true,
      fromJson: Job.fromJson,
    );
  }

  /// Update a job posting
  Future<ApiResponse<Job>> updateJob({
    required String jobId,
    Map<String, dynamic>? updates,
  }) async {
    return patch<Job>(
      '/jobs/$jobId',
      body: updates,
      requireAuth: true,
      fromJson: Job.fromJson,
    );
  }

  // ============== NOTIFICATIONS ==============

  /// Get notifications for authenticated salon
  Future<ApiResponse<List<AppNotification>>> getNotifications({
    int limit = 50,
    int offset = 0,
    bool unreadOnly = false,
  }) async {
    final queryParams = {
      'limit': limit.toString(),
      'offset': offset.toString(),
      'unreadOnly': unreadOnly.toString(),
    };
    
    final response = await get<Map<String, dynamic>>(
      '/notifications',
      requireAuth: true,
      queryParams: queryParams,
    );

    if (response.success && response.data != null) {
      final notificationsData = response.data!['notifications'] as List?;
      final notifications = notificationsData != null
          ? notificationsData.map((json) => AppNotification.fromJson(json)).toList()
          : <AppNotification>[];
      
      return ApiResponse(
        success: true,
        data: notifications,
      );
    }

    return ApiResponse(
      success: false,
      message: response.message ?? 'Failed to fetch notifications',
      data: [],
    );
  }

  /// Get unread notification count
  Future<ApiResponse<int>> getUnreadNotificationCount() async {
    final response = await get<Map<String, dynamic>>(
      '/notifications/unread-count',
      requireAuth: true,
    );

    if (response.success && response.data != null) {
      final count = response.data!['count'] as int? ?? 0;
      return ApiResponse(success: true, data: count);
    }

    return ApiResponse(success: false, data: 0);
  }

  /// Mark notification as read
  Future<ApiResponse<AppNotification>> markNotificationAsRead(String notificationId) async {
    return patch<AppNotification>(
      '/notifications/$notificationId/read',
      requireAuth: true,
      fromJson: AppNotification.fromJson,
    );
  }

  /// Mark all notifications as read
  Future<ApiResponse> markAllNotificationsAsRead() async {
    return patch(
      '/notifications/read-all',
      requireAuth: true,
    );
  }

  /// Get notification preferences
  Future<ApiResponse<NotificationPreferences>> getNotificationPreferences() async {
    return get<NotificationPreferences>(
      '/notifications/preferences',
      requireAuth: true,
      fromJson: NotificationPreferences.fromJson,
    );
  }

  /// Update notification preferences
  Future<ApiResponse<NotificationPreferences>> updateNotificationPreferences({
    bool? jobTips,
    bool? profileImprovements,
    bool? accountAlerts,
    bool? promotions,
  }) async {
    final body = <String, dynamic>{};
    if (jobTips != null) body['job_tips'] = jobTips;
    if (profileImprovements != null) body['profile_improvements'] = profileImprovements;
    if (accountAlerts != null) body['account_alerts'] = accountAlerts;
    if (promotions != null) body['promotions'] = promotions;

    return patch<NotificationPreferences>(
      '/notifications/preferences',
      body: body,
      requireAuth: true,
      fromJson: NotificationPreferences.fromJson,
    );
  }

  /// Register push token (legacy owner-only endpoint)
  Future<ApiResponse> registerPushToken({
    required String deviceType,
    required String pushToken,
  }) async {
    return post(
      '/notifications/push-token',
      body: {
        'device_type': deviceType,
        'push_token': pushToken,
      },
      requireAuth: true,
    );
  }

  /// Register FCM device token (owner or seeker). Use after login for push notifications.
  Future<ApiResponse> registerFcmDevice({
    required String fcmToken,
    required String platform,
  }) async {
    return post(
      '/device/register',
      body: {
        'fcmToken': fcmToken,
        'platform': platform,
      },
      requireAuth: true,
    );
  }

  /// Unregister FCM device (e.g. on logout). Optionally pass current fcmToken.
  Future<ApiResponse> unregisterFcmDevice({String? fcmToken}) async {
    return post(
      '/device/unregister',
      body: fcmToken != null ? {'fcmToken': fcmToken} : null,
      requireAuth: true,
    );
  }

  /// Send a test push notification to the current user's device(s). For debugging FCM.
  Future<ApiResponse> sendTestPush() async {
    return post(
      '/device/test-push',
      requireAuth: true,
    );
  }

  // ============== SUPPORT ==============

  /// Create a support ticket
  Future<ApiResponse> createSupportTicket({
    required String issueType,
    String? description,
    String? appVersion,
    String? deviceInfo,
  }) async {
    return post(
      '/support/ticket',
      body: {
        'issue_type': issueType,
        'description': description,
        'app_version': appVersion,
        'device_info': deviceInfo,
      },
      requireAuth: true,
    );
  }

  /// Get support configuration (phone, WhatsApp)
  Future<ApiResponse<Map<String, dynamic>>> getSupportConfig() async {
    return get<Map<String, dynamic>>(
      '/support/config',
      requireAuth: true,
    );
  }

  // ============== SEEKER ENDPOINTS ==============

  /// Verify OTP as a job seeker (role='seeker')
  Future<ApiResponse<SeekerAuthResult>> verifySeekerOtp(
    String phoneNumber,
    String otp, {
    String countryCode = '+91',
  }) async {
    try {
      final headers = await _getHeaders();
      final httpResponse = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/auth/verify-otp'),
            headers: headers,
            body: json.encode({
              'phoneNumber': phoneNumber,
              'otp': otp,
              'countryCode': countryCode,
              'role': 'seeker',
            }),
          )
          .timeout(ApiConfig.connectionTimeout);

      final Map<String, dynamic> responseBody;
      try {
        responseBody = json.decode(httpResponse.body);
      } catch (e) {
        return ApiResponse.error('Invalid response from server', errorCode: 'PARSE_ERROR');
      }

      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        final result = SeekerAuthResult.fromJson(responseBody);
        // Save tokens
        await _authService.saveTokens(result.accessToken, result.refreshToken);
        await _authService.saveSeekerData(result.seeker);
        return ApiResponse(success: true, data: result, message: responseBody['message']);
      } else {
        return ApiResponse(
          success: false,
          message: responseBody['message'] ?? 'Verification failed',
          attemptsRemaining: responseBody['attemptsRemaining'],
        );
      }
    } on SocketException {
      return ApiResponse.error('No internet connection', errorCode: 'NETWORK_ERROR');
    } catch (e) {
      return ApiResponse.error('Something went wrong: ${e.toString()}', errorCode: 'UNKNOWN_ERROR');
    }
  }

  /// Get seeker profile
  Future<ApiResponse<SeekerProfile>> getSeekerProfile() async {
    try {
      final headers = await _getHeaders(requireAuth: true);
      final httpResponse = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/seeker/profile'), headers: headers)
          .timeout(ApiConfig.connectionTimeout);

      final responseBody = json.decode(httpResponse.body);
      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        final seekerData = responseBody['seeker'] as Map<String, dynamic>?;
        if (seekerData != null) {
          return ApiResponse(success: true, data: SeekerProfile.fromJson(seekerData));
        }
        return ApiResponse.error('No seeker data');
      }
      return ApiResponse.error(responseBody['message'] ?? 'Failed to load profile');
    } catch (e) {
      return ApiResponse.error('Something went wrong: ${e.toString()}');
    }
  }

  /// Create / update seeker profile
  Future<ApiResponse<SeekerProfile>> updateSeekerProfile(Map<String, dynamic> data) async {
    try {
      final headers = await _getHeaders(requireAuth: true);
      final httpResponse = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/seeker/profile'),
            headers: headers,
            body: json.encode(data),
          )
          .timeout(ApiConfig.connectionTimeout);

      final responseBody = json.decode(httpResponse.body);
      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        final seekerData = responseBody['seeker'] as Map<String, dynamic>?;
        if (seekerData != null) {
          return ApiResponse(success: true, data: SeekerProfile.fromJson(seekerData), message: responseBody['message']);
        }
        return ApiResponse.error('No seeker data in response');
      }
      return ApiResponse.error(responseBody['message'] ?? 'Failed to update profile');
    } catch (e) {
      return ApiResponse.error('Something went wrong: ${e.toString()}');
    }
  }

  /// Patch seeker profile (partial update)
  Future<ApiResponse<SeekerProfile>> patchSeekerProfile(Map<String, dynamic> data) async {
    try {
      final headers = await _getHeaders(requireAuth: true);
      final httpResponse = await http
          .patch(
            Uri.parse('${ApiConfig.baseUrl}/seeker/profile'),
            headers: headers,
            body: json.encode(data),
          )
          .timeout(ApiConfig.connectionTimeout);

      final responseBody = json.decode(httpResponse.body);
      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        final seekerData = responseBody['seeker'] as Map<String, dynamic>?;
        if (seekerData != null) {
          return ApiResponse(success: true, data: SeekerProfile.fromJson(seekerData));
        }
        return ApiResponse.error('No seeker data in response');
      }
      return ApiResponse.error(responseBody['message'] ?? 'Failed to update profile');
    } catch (e) {
      return ApiResponse.error('Something went wrong: ${e.toString()}');
    }
  }

  /// Get seeker profile completion
  Future<ApiResponse<Map<String, dynamic>>> getSeekerCompletion() async {
    return get<Map<String, dynamic>>('/seeker/completion', requireAuth: true);
  }

  /// Get job feed for seekers
  Future<ApiResponse<List<SeekerJobItem>>> getSeekerJobs({String? city, String? role, int limit = 20, int offset = 0}) async {
    try {
      final headers = await _getHeaders(requireAuth: true);
      final queryParams = <String, String>{
        'limit': limit.toString(),
        'offset': offset.toString(),
      };
      if (city != null && city.isNotEmpty) queryParams['city'] = city;
      if (role != null && role.isNotEmpty) queryParams['role'] = role;

      final uri = Uri.parse('${ApiConfig.baseUrl}/seeker/jobs').replace(queryParameters: queryParams);
      final httpResponse = await http.get(uri, headers: headers).timeout(ApiConfig.connectionTimeout);
      final responseBody = json.decode(httpResponse.body);

      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        final jobsList = responseBody['jobs'] as List<dynamic>? ?? [];
        final jobs = jobsList.map((j) => SeekerJobItem.fromJson(j as Map<String, dynamic>)).toList();
        return ApiResponse(success: true, data: jobs, message: '${jobs.length} jobs found');
      }
      return ApiResponse.error(responseBody['message'] ?? 'Failed to load jobs');
    } catch (e) {
      return ApiResponse.error('Something went wrong: ${e.toString()}');
    }
  }

  /// Apply to a job
  Future<ApiResponse> applyToJob(String jobId) async {
    return post('/seeker/apply', body: {'jobId': jobId}, requireAuth: true);
  }

  /// Get seeker's applications
  Future<ApiResponse<List<Map<String, dynamic>>>> getSeekerApplications({int limit = 20, int offset = 0}) async {
    try {
      final headers = await _getHeaders(requireAuth: true);
      final uri = Uri.parse('${ApiConfig.baseUrl}/seeker/applications')
          .replace(queryParameters: {'limit': limit.toString(), 'offset': offset.toString()});
      final httpResponse = await http.get(uri, headers: headers).timeout(ApiConfig.connectionTimeout);
      final responseBody = json.decode(httpResponse.body);

      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        final apps = (responseBody['applications'] as List<dynamic>? ?? [])
            .map((a) => Map<String, dynamic>.from(a as Map))
            .toList();
        return ApiResponse(success: true, data: apps);
      }
      return ApiResponse.error(responseBody['message'] ?? 'Failed to load applications');
    } catch (e) {
      return ApiResponse.error('Something went wrong: ${e.toString()}');
    }
  }

  /// Update seeker preferences
  Future<ApiResponse> updateSeekerPreferences(Map<String, dynamic> data) async {
    return patch('/seeker/preferences', body: data, requireAuth: true);
  }

  // ============== OWNER CANDIDATE MANAGEMENT ==============

  /// Get candidates (applications) for a specific job owned by the salon owner
  Future<ApiResponse<Map<String, dynamic>>> getJobCandidates(String jobId, {String? status, int limit = 50, int offset = 0}) async {
    try {
      final headers = await _getHeaders(requireAuth: true);
      final queryParams = <String, String>{
        'limit': limit.toString(),
        'offset': offset.toString(),
      };
      if (status != null && status.isNotEmpty) {
        queryParams['status'] = status;
      }

      final uri = Uri.parse('${ApiConfig.baseUrl}/owner/jobs/$jobId/applications')
          .replace(queryParameters: queryParams);
      final httpResponse = await http.get(uri, headers: headers).timeout(ApiConfig.connectionTimeout);
      final responseBody = json.decode(httpResponse.body);

      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        return ApiResponse(success: true, data: Map<String, dynamic>.from(responseBody));
      }
      return ApiResponse.error(responseBody['message'] ?? 'Failed to load candidates');
    } on SocketException {
      return ApiResponse.error('No internet connection', errorCode: 'NETWORK_ERROR');
    } catch (e) {
      return ApiResponse.error('Something went wrong: ${e.toString()}', errorCode: 'UNKNOWN_ERROR');
    }
  }

  /// Update candidate application status
  Future<ApiResponse<Map<String, dynamic>>> updateCandidateStatus(String applicationId, String status) async {
    try {
      final headers = await _getHeaders(requireAuth: true);
      final httpResponse = await http
          .patch(
            Uri.parse('${ApiConfig.baseUrl}/owner/applications/$applicationId/status'),
            headers: headers,
            body: json.encode({'status': status}),
          )
          .timeout(ApiConfig.connectionTimeout);
      final responseBody = json.decode(httpResponse.body);

      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        return ApiResponse(success: true, data: Map<String, dynamic>.from(responseBody), message: responseBody['message']);
      }
      return ApiResponse.error(responseBody['message'] ?? 'Failed to update status');
    } on SocketException {
      return ApiResponse.error('No internet connection', errorCode: 'NETWORK_ERROR');
    } catch (e) {
      return ApiResponse.error('Something went wrong: ${e.toString()}', errorCode: 'UNKNOWN_ERROR');
    }
  }

  // ============== INTERVIEW SCHEDULING ==============

  /// Schedule interview for a shortlisted candidate
  Future<ApiResponse<Map<String, dynamic>>> scheduleInterview(
    String applicationId, {
    required String interviewAt,
    String? mode,
    String? notes,
  }) async {
    return post<Map<String, dynamic>>(
      '/owner/applications/$applicationId/schedule-interview',
      body: {
        'interviewAt': interviewAt,
        if (mode != null) 'mode': mode,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
      requireAuth: true,
    );
  }

  /// Reschedule an existing interview
  Future<ApiResponse<Map<String, dynamic>>> rescheduleInterview(
    String applicationId, {
    required String interviewAt,
    String? mode,
    String? notes,
  }) async {
    return patch<Map<String, dynamic>>(
      '/owner/applications/$applicationId/reschedule-interview',
      body: {
        'interviewAt': interviewAt,
        if (mode != null) 'mode': mode,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
      requireAuth: true,
    );
  }

  /// Mark interview as completed
  Future<ApiResponse<Map<String, dynamic>>> completeInterview(String applicationId) async {
    return patch<Map<String, dynamic>>(
      '/owner/applications/$applicationId/complete-interview',
      requireAuth: true,
    );
  }

  // ============== CALL MASKING ==============

  /// Initiate a masked call to a candidate
  /// Only works for shortlisted/interview candidates.
  /// Rate limited to 3 calls/candidate/day.
  Future<ApiResponse<Map<String, dynamic>>> initiateSecureCall(String applicationId) async {
    try {
      final headers = await _getHeaders(requireAuth: true);
      final httpResponse = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/calls/initiate/$applicationId'),
            headers: headers,
          )
          .timeout(ApiConfig.connectionTimeout);
      final responseBody = json.decode(httpResponse.body);

      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        return ApiResponse(
          success: true,
          data: Map<String, dynamic>.from(responseBody),
          message: responseBody['message'],
        );
      }
      return ApiResponse.error(
        responseBody['message'] ?? 'Failed to initiate call',
        errorCode: responseBody['error']?['code'] ?? 'CALL_ERROR',
      );
    } on SocketException {
      return ApiResponse.error('No internet connection', errorCode: 'NETWORK_ERROR');
    } catch (e) {
      return ApiResponse.error('Something went wrong: ${e.toString()}', errorCode: 'UNKNOWN_ERROR');
    }
  }

  // ============== HEALTH CHECK ==============

  /// Check API health
  Future<ApiResponse> healthCheck() async {
    return get('/health');
  }
}

// ============== DATA MODELS ==============

/// Auth result from verify-otp
class AuthResult {
  final bool isNewUser;
  final bool ownerExists;
  final bool seekerExists;
  final String accessToken;
  final String refreshToken;
  final String expiresIn;
  final SalonProfile salon;

  AuthResult({
    required this.isNewUser,
    this.ownerExists = false,
    this.seekerExists = false,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.salon,
  });

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      isNewUser: json['isNewUser'] ?? false,
      ownerExists: json['ownerExists'] ?? false,
      seekerExists: json['seekerExists'] ?? false,
      accessToken: json['accessToken'] ?? '',
      refreshToken: json['refreshToken'] ?? '',
      expiresIn: json['expiresIn'] ?? '7d',
      salon: SalonProfile.fromJson(json['salon'] ?? {}),
    );
  }
}

/// Salon profile data
class SalonProfile {
  final String id;
  final String phoneNumber;
  final String? countryCode;
  final String? salonName;
  final String? ownerName;
  final String? city;
  final String? area;
  final String? fullAddress;
  final double? latitude;
  final double? longitude;
  final String verificationStatus;
  final int profileCompletionPercent;
  final bool isProfileComplete;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  SalonProfile({
    required this.id,
    required this.phoneNumber,
    this.countryCode,
    this.salonName,
    this.ownerName,
    this.city,
    this.area,
    this.fullAddress,
    this.latitude,
    this.longitude,
    this.verificationStatus = 'unverified',
    this.profileCompletionPercent = 0,
    this.isProfileComplete = false,
    this.createdAt,
    this.updatedAt,
  });

  factory SalonProfile.fromJson(Map<String, dynamic> json) {
    return SalonProfile(
      id: json['id'] ?? '',
      phoneNumber: json['phoneNumber'] ?? '',
      countryCode: json['countryCode'],
      salonName: json['salonName'],
      ownerName: json['ownerName'],
      city: json['city'],
      area: json['area'],
      fullAddress: json['fullAddress'],
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
      verificationStatus: json['verificationStatus'] ?? 'unverified',
      profileCompletionPercent: json['profileCompletionPercent'] ?? 0,
      isProfileComplete: json['isProfileComplete'] ?? false,
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phoneNumber': phoneNumber,
      'countryCode': countryCode,
      'salonName': salonName,
      'ownerName': ownerName,
      'city': city,
      'area': area,
      'fullAddress': fullAddress,
      'latitude': latitude,
      'longitude': longitude,
      'verificationStatus': verificationStatus,
      'profileCompletionPercent': profileCompletionPercent,
      'isProfileComplete': isProfileComplete,
    };
  }
}

/// Profile completion status
class ProfileCompletion {
  final int completionPercent;
  final bool isComplete;
  final List<String> missing; // Missing field keys
  final String upsellStage; // 'early' | 'activation' | 'trust' | 'ready'
  
  // Legacy fields (for backward compatibility)
  final Map<String, bool> fields;
  final List<NextStep> nextSteps;

  ProfileCompletion({
    required this.completionPercent,
    required this.isComplete,
    required this.missing,
    required this.upsellStage,
    this.fields = const {},
    this.nextSteps = const [],
  });

  factory ProfileCompletion.fromJson(Map<String, dynamic> json) {
    final fieldsMap = <String, bool>{};
    if (json['fields'] != null) {
      (json['fields'] as Map<String, dynamic>).forEach((key, value) {
        fieldsMap[key] = value == true;
      });
    }

    return ProfileCompletion(
      completionPercent: json['completionPercent'] ?? 0,
      isComplete: json['isComplete'] ?? false,
      missing: (json['missing'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      upsellStage: json['upsellStage'] ?? 'early',
      fields: fieldsMap,
      nextSteps: (json['nextSteps'] as List<dynamic>?)
              ?.map((e) => NextStep.fromJson(e))
              .toList() ??
          [],
    );
  }
}

/// Next step suggestion
class NextStep {
  final String field;
  final String label;

  NextStep({required this.field, required this.label});

  factory NextStep.fromJson(Map<String, dynamic> json) {
    return NextStep(
      field: json['field'] ?? '',
      label: json['label'] ?? '',
    );
  }
}

/// Presigned URL for S3 upload
class PresignedUrl {
  final String uploadUrl;
  final String fileUrl;
  final String fileKey;
  final int expiresIn;
  final String method;
  final String contentType;

  PresignedUrl({
    required this.uploadUrl,
    required this.fileUrl,
    required this.fileKey,
    required this.expiresIn,
    required this.method,
    required this.contentType,
  });

  factory PresignedUrl.fromJson(Map<String, dynamic> json) {
    return PresignedUrl(
      uploadUrl: json['uploadUrl'] ?? '',
      fileUrl: json['fileUrl'] ?? '',
      fileKey: json['fileKey'] ?? '',
      expiresIn: json['expiresIn'] ?? 3600,
      method: json['method'] ?? 'PUT',
      contentType: json['contentType'] ?? 'application/octet-stream',
    );
  }
}

/// Job data model
class Job {
  final String id;
  final String salonId;
  final String jobRole;
  final String? otherCategory;
  final String? customRoleName;
  final List<String> skills;
  final String location;
  final int numberOfStaff;
  final double salaryMin;
  final double salaryMax;
  final String workType;
  final String experience;
  final String? accommodation;
  final String? preferredGender;
  final String status;
  final bool isFeatured;
  final int viewsCount;
  final int applicationsCount;
  final String? description;
  final String? shiftType;
  final List<String> weeklyOff;
  final List<String> facilities;
  final int completionPercent;
  final int vacancyCount;
  final int totalApplications;
  final int shortlistedCount;
  final int interviewCount;
  final int hiredCount;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Job({
    required this.id,
    required this.salonId,
    required this.jobRole,
    this.otherCategory,
    this.customRoleName,
    this.skills = const [],
    required this.location,
    this.numberOfStaff = 1,
    required this.salaryMin,
    required this.salaryMax,
    required this.workType,
    required this.experience,
    this.accommodation,
    this.preferredGender,
    this.status = 'active',
    this.isFeatured = false,
    this.viewsCount = 0,
    this.applicationsCount = 0,
    this.description,
    this.shiftType,
    this.weeklyOff = const [],
    this.facilities = const [],
    this.completionPercent = 40,
    this.vacancyCount = 1,
    this.totalApplications = 0,
    this.shortlistedCount = 0,
    this.interviewCount = 0,
    this.hiredCount = 0,
    this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Job.fromJson(Map<String, dynamic> json) {
    return Job(
      id: json['id'] ?? '',
      salonId: json['salonId'] ?? '',
      jobRole: json['jobRole'] ?? '',
      otherCategory: json['otherCategory'],
      customRoleName: json['customRoleName'],
      skills: json['skills'] != null 
          ? List<String>.from(json['skills']) 
          : [],
      location: json['location'] ?? '',
      numberOfStaff: json['numberOfStaff'] ?? 1,
      salaryMin: (json['salaryMin'] ?? 0).toDouble(),
      salaryMax: (json['salaryMax'] ?? 0).toDouble(),
      workType: json['workType'] ?? 'full_time',
      experience: json['experience'] ?? 'fresher_ok',
      accommodation: json['accommodation'],
      preferredGender: json['preferredGender'],
      status: json['status'] ?? 'active',
      isFeatured: json['isFeatured'] ?? false,
      viewsCount: json['viewsCount'] ?? 0,
      applicationsCount: json['applicationsCount'] ?? 0,
      description: json['description'],
      shiftType: json['shiftType'],
      weeklyOff: json['weeklyOff'] != null 
          ? List<String>.from(json['weeklyOff']) 
          : [],
      facilities: json['facilities'] != null 
          ? List<String>.from(json['facilities']) 
          : [],
      completionPercent: json['completionPercent'] ?? 40,
      vacancyCount: json['vacancyCount'] ?? json['numberOfStaff'] ?? 1,
      totalApplications: json['totalApplications'] ?? json['applicationsCount'] ?? 0,
      shortlistedCount: json['shortlistedCount'] ?? 0,
      interviewCount: json['interviewCount'] ?? 0,
      hiredCount: json['hiredCount'] ?? 0,
      expiresAt: json['expiresAt'] != null 
          ? DateTime.parse(json['expiresAt']) 
          : null,
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt']) 
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null 
          ? DateTime.parse(json['updatedAt']) 
          : DateTime.now(),
    );
  }

  String get displayRole {
    if (customRoleName != null && customRoleName!.isNotEmpty) {
      return customRoleName!;
    }
    return jobRole;
  }
}

/// Notification Model (renamed to avoid conflict with Flutter's Notification)
class AppNotification {
  final String id;
  final String salonId;
  final String type;
  final String title;
  final String message;
  final String? deepLink;
  final bool isRead;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.salonId,
    required this.type,
    required this.title,
    required this.message,
    this.deepLink,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map ? json['data'] as Map<String, dynamic> : null;
    return AppNotification(
      id: json['id'] ?? '',
      salonId: json['salon_id'] ?? json['user_id'] ?? '',
      type: json['type'] ?? '',
      title: json['title'] ?? '',
      message: json['message'] ?? json['body'] ?? '',
      deepLink: json['deep_link'] ?? data?['deepLink'],
      isRead: json['is_read'] ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }
}

/// Notification Preferences Model
class NotificationPreferences {
  final String salonId;
  final bool hiringUpdates;
  final bool jobTips;
  final bool profileImprovements;
  final bool accountAlerts;
  final bool promotions;
  final DateTime updatedAt;

  NotificationPreferences({
    required this.salonId,
    required this.hiringUpdates,
    required this.jobTips,
    required this.profileImprovements,
    required this.accountAlerts,
    required this.promotions,
    required this.updatedAt,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      salonId: json['salon_id'] ?? '',
      hiringUpdates: json['hiring_updates'] ?? true,
      jobTips: json['job_tips'] ?? true,
      profileImprovements: json['profile_improvements'] ?? true,
      accountAlerts: json['account_alerts'] ?? true,
      promotions: json['promotions'] ?? false,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : DateTime.now(),
    );
  }
}

// ============== SEEKER DATA MODELS ==============

/// Auth result from verify-otp for seekers
class SeekerAuthResult {
  final bool isNewUser;
  final bool seekerProfileExists;
  final String accessToken;
  final String refreshToken;
  final String expiresIn;
  final SeekerProfile seeker;

  SeekerAuthResult({
    required this.isNewUser,
    required this.seekerProfileExists,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.seeker,
  });

  factory SeekerAuthResult.fromJson(Map<String, dynamic> json) {
    return SeekerAuthResult(
      isNewUser: json['isNewUser'] ?? false,
      seekerProfileExists: json['seekerProfileExists'] ?? false,
      accessToken: json['accessToken'] ?? '',
      refreshToken: json['refreshToken'] ?? '',
      expiresIn: json['expiresIn'] ?? '7d',
      seeker: SeekerProfile.fromJson(json['seeker'] ?? {}),
    );
  }
}

/// Seeker profile model
class SeekerProfile {
  final String id;
  final String phoneNumber;
  final String? fullName;
  final String? gender;
  final String? city;
  final String? preferredRole;
  final String? experience;
  final double? expectedSalary;
  final List<String> skills;
  final String? profilePhotoUrl;
  final int profileCompletionPercent;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  SeekerProfile({
    required this.id,
    required this.phoneNumber,
    this.fullName,
    this.gender,
    this.city,
    this.preferredRole,
    this.experience,
    this.expectedSalary,
    this.skills = const [],
    this.profilePhotoUrl,
    this.profileCompletionPercent = 0,
    this.createdAt,
    this.updatedAt,
  });

  bool get hasBasicProfile => fullName != null && city != null && preferredRole != null;

  factory SeekerProfile.fromJson(Map<String, dynamic> json) {
    return SeekerProfile(
      id: json['id'] ?? '',
      phoneNumber: json['phoneNumber'] ?? '',
      fullName: json['fullName'],
      gender: json['gender'],
      city: json['city'],
      preferredRole: json['preferredRole'],
      experience: json['experience'],
      expectedSalary: json['expectedSalary']?.toDouble(),
      skills: json['skills'] != null ? List<String>.from(json['skills']) : [],
      profilePhotoUrl: json['profilePhotoUrl'],
      profileCompletionPercent: json['profileCompletionPercent'] ?? 0,
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phoneNumber': phoneNumber,
      'fullName': fullName,
      'gender': gender,
      'city': city,
      'preferredRole': preferredRole,
      'experience': experience,
      'expectedSalary': expectedSalary,
      'skills': skills,
      'profilePhotoUrl': profilePhotoUrl,
      'profileCompletionPercent': profileCompletionPercent,
    };
  }
}

/// Job item as seen by a seeker (includes hasApplied flag + salon name)
class SeekerJobItem {
  final String id;
  final String jobRole;
  final String? customRoleName;
  final String location;
  final double salaryMin;
  final double salaryMax;
  final String workType;
  final String experience;
  final String? salonName;
  final String? description;
  final String status;
  final bool hasApplied;
  final DateTime createdAt;

  SeekerJobItem({
    required this.id,
    required this.jobRole,
    this.customRoleName,
    required this.location,
    required this.salaryMin,
    required this.salaryMax,
    required this.workType,
    required this.experience,
    this.salonName,
    this.description,
    this.status = 'active',
    this.hasApplied = false,
    required this.createdAt,
  });

  String get displayRole {
    if (customRoleName != null && customRoleName!.isNotEmpty) return customRoleName!;
    return jobRole.replaceAll('_', ' ').split(' ').map((w) =>
      w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}'
    ).join(' ');
  }

  String get postedAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  factory SeekerJobItem.fromJson(Map<String, dynamic> json) {
    return SeekerJobItem(
      id: json['id'] ?? '',
      jobRole: json['jobRole'] ?? json['job_role'] ?? '',
      customRoleName: json['customRoleName'] ?? json['custom_role_name'],
      location: json['location'] ?? '',
      salaryMin: (json['salaryMin'] ?? json['salary_min'] ?? 0).toDouble(),
      salaryMax: (json['salaryMax'] ?? json['salary_max'] ?? 0).toDouble(),
      workType: json['workType'] ?? json['work_type'] ?? 'full_time',
      experience: json['experience'] ?? 'fresher_ok',
      salonName: json['salonName'] ?? json['salon_name'],
      description: json['description'],
      status: json['status'] ?? 'active',
      hasApplied: json['hasApplied'] ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : (json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now()),
    );
  }
}


