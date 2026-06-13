import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:sms_autofill/sms_autofill.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:image_picker/image_picker.dart';
import 'firebase_options.dart';
import 'app_responsive.dart';
import 'application_chat_screen.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/india_city_service.dart';
import 'services/push_notification_service.dart';
import 'widgets/india_city_picker_sheet.dart';
import 'data/job_taxonomy_catalog.dart';
import 'screens/job_taxonomy_selection_screen.dart';
import 'widgets/shift_timing_picker.dart';

/// Android SMS Retriever: 11-char app hash for `/auth/send-otp` body field `smsAppHash`.
Future<String?> androidSmsRetrieverHash() async {
  if (!Platform.isAndroid) return null;
  try {
    final h = await SmsAutoFill().getAppSignature;
    if (h.length == 11) return h;
  } catch (_) {}
  return null;
}

void showJobtreeImagePreview(BuildContext context, String url) {
  if (url.isEmpty) return;
  showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, prog) {
                    if (prog == null) return child;
                    return const Padding(
                      padding: EdgeInsets.all(48),
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  },
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      );
    },
  );
}

/// Content-Type for direct API upload (prefer picker MIME, then extension).
String jobtreeInferImageContentType(String path, [String? mimeType]) {
  if (mimeType != null && mimeType.isNotEmpty) {
    if (mimeType == 'image/jpg') return 'image/jpeg';
    if (mimeType.startsWith('image/')) return mimeType;
  }
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
  return 'image/jpeg';
}

bool jobtreeIsLocalMediaPath(String path) {
  final t = path.trim();
  if (t.isEmpty) return false;
  return t.startsWith('/') && !t.startsWith('//');
}

ImageProvider? jobtreeMediaImageProvider(String? urlOrPath) {
  if (urlOrPath == null || urlOrPath.trim().isEmpty) return null;
  final src = urlOrPath.trim();
  if (jobtreeIsLocalMediaPath(src)) return FileImage(File(src));
  return NetworkImage(src);
}

Widget jobtreeMediaThumbnail({
  required String? urlOrPath,
  double width = 88,
  double height = 88,
  BoxFit fit = BoxFit.cover,
  BorderRadius? borderRadius,
}) {
  final src = urlOrPath?.trim() ?? '';
  final radius = borderRadius ?? BorderRadius.circular(10);
  Widget placeholder() => Container(
        width: width,
        height: height,
        color: Colors.grey.shade200,
        child: Icon(Icons.image_not_supported_outlined, color: Colors.grey.shade500, size: 28),
      );

  if (src.isEmpty) return placeholder();

  Widget image;
  if (jobtreeIsLocalMediaPath(src)) {
    image = Image.file(File(src), width: width, height: height, fit: fit);
  } else {
    image = Image.network(
      src,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          width: width,
          height: height,
          color: Colors.grey.shade200,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
      errorBuilder: (_, __, ___) => placeholder(),
    );
  }

  return ClipRRect(borderRadius: radius, child: image);
}

/// Content-Type for KYC uploads (images + PDF).
String jobtreeInferDocContentType(String filename, [String? ext]) {
  final lower = filename.toLowerCase();
  final e = (ext ?? '').toLowerCase();
  if (lower.endsWith('.pdf') || e == 'pdf') return 'application/pdf';
  return jobtreeInferImageContentType(filename, null);
}

// Helper function to load saved language preference
Future<Language> loadSavedLanguage() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final savedLang = prefs.getString('selected_language');
    if (savedLang == 'en') {
      return Language.english;
    } else if (savedLang == 'hi') {
      return Language.hindi;
    }
  } catch (e) {
    print('Error loading saved language: $e');
  }

  // Default to Hindi for Indian users
  return Language.hindi;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await PushNotificationService().initialize();
  } catch (e) {
    debugPrint('Firebase/push init failed (run: flutterfire configure): $e');
  }
  runApp(const JobtreeApp());
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void openQuickJobFlow(BuildContext context, Language selectedLanguage) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => PostJobStep1Screen(
        selectedLanguage: selectedLanguage,
        phoneNumber: '', // phone is already tied to auth; not needed for flow
      ),
    ),
  );
}

class JobtreeApp extends StatelessWidget {
  const JobtreeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Jobtree',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3D3D7B),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: AppResponsive.clampTextScaler(context)),
          child: child,
        );
      },
      home: const SplashScreen(),
    );
  }
}

// ============== SPLIT LOGO (icon + TM + wordmark) ==============

/// Design sizes from SVG viewBoxes: icon 68×73, wordmark 162×35.
class JobtreeSplashLogoMetrics {
  JobtreeSplashLogoMetrics._();

  /// SVG viewBox includes TM text to the right of the purple mark (82×73).
  static const double iconViewW = 82;
  static const double iconViewH = 73;
  static const double textViewW = 162;
  static const double textViewH = 35;

  static const double baseIconW = 88;
  static double get baseIconH => baseIconW * iconViewH / iconViewW;
  static double get baseTextW => baseIconW * textViewW / iconViewW;
  static double get baseTextH => baseTextW * textViewH / textViewW;
  static const double baseGap = 14;
}

/// Purple split-tree icon with embedded black **TM** (see logo_tm_icon.svg).
class JobtreeSplitLogoIcon extends StatelessWidget {
  final double width;
  final double height;

  JobtreeSplitLogoIcon({
    super.key,
    double? width,
    double? height,
  })  : width = width ?? JobtreeSplashLogoMetrics.baseIconW,
        height = height ??
            (JobtreeSplashLogoMetrics.baseIconW *
                JobtreeSplashLogoMetrics.iconViewH /
                JobtreeSplashLogoMetrics.iconViewW);

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/images/logo_tm_icon.svg',
      width: width,
      height: height,
      fit: BoxFit.contain,
    );
  }
}

/// Icon + TM + Jobtree wordmark — scales proportionally on all screen widths.
class JobtreeSplashLogo extends StatelessWidget {
  /// Optional vertical offsets for splash merge animation (icon up, text down).
  final double iconOffsetY;
  final double textOffsetY;

  const JobtreeSplashLogo({
    super.key,
    this.iconOffsetY = 0,
    this.textOffsetY = 0,
  });

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final blockBaseW = math.max(
      JobtreeSplashLogoMetrics.baseIconW,
      JobtreeSplashLogoMetrics.baseTextW,
    );
    final maxBlockW = screenW * 0.82;
    final scale = maxBlockW >= blockBaseW ? 1.0 : maxBlockW / blockBaseW;

    final iconW = JobtreeSplashLogoMetrics.baseIconW * scale;
    final iconH = JobtreeSplashLogoMetrics.baseIconH * scale;
    final textW = JobtreeSplashLogoMetrics.baseTextW * scale;
    final textH = JobtreeSplashLogoMetrics.baseTextH * scale;
    final gap = JobtreeSplashLogoMetrics.baseGap * scale;

    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Transform.translate(
              offset: Offset(0, iconOffsetY),
              child: JobtreeSplitLogoIcon(width: iconW, height: iconH),
            ),
            SizedBox(height: gap),
            Transform.translate(
              offset: Offset(-textW * 0.06, textOffsetY),
              child: SvgPicture.asset(
                'assets/images/logo_tm_text.svg',
                width: textW,
                height: textH,
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============== SPLASH SCREEN ==============
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _iconAnimation;
  late Animation<double> _textAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );

    _iconAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.75, curve: Curves.bounceOut),
      ),
    );

    _textAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.75, curve: Curves.bounceOut),
      ),
    );

    _controller.forward();

    Future.delayed(const Duration(milliseconds: 3500), () {
      if (mounted) _checkAuthAndNavigate();
    });
  }

  Future<void> _checkAuthAndNavigate() async {
    try {
      final authService = AuthService();
      final token = await authService.getAccessToken();
      final savedLang = await loadSavedLanguage();

      if (token != null && token.isNotEmpty) {
        // User is authenticated — determine where to go
        final role = await authService.getUserRole();

        if (role == 'seeker') {
          // Ensure seeker JWT (stored token may be salon JWT from older builds)
          final api = ApiService();
          await api.switchToSeeker();
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => SeekerHomeScreen(selectedLanguage: savedLang)),
            );
          }
          return;
        }

        // Default: salon/owner returning → go to owner dashboard
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => JobOwnerHomeScreen(selectedLanguage: savedLang)),
          );
        }
        return;
      }
    } catch (e) {
      print('Auth check error: $e');
    }

    // No valid token → show onboarding / login
    if (mounted) {
      Navigator.of(context).pushReplacement(
        DiagonalSplitPageRoute(page: const OnboardingScreen()),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            // Cap merge travel so small phones don't show a huge icon/text gap mid-animation.
            final mergeTravel = math.min(screenHeight * 0.22, 120.0);
            final iconOffset = -mergeTravel * _iconAnimation.value;
            final textOffset = mergeTravel * _textAnimation.value;

            return Center(
              child: JobtreeSplashLogo(
                iconOffsetY: iconOffset,
                textOffsetY: textOffset,
              ),
            );
          },
        ),
      ),
    );
  }
}

// ============== DIAGONAL SPLIT PAGE ROUTE ==============
class DiagonalSplitPageRoute extends PageRouteBuilder {
  final Widget page;

  DiagonalSplitPageRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: const Duration(milliseconds: 400),
          reverseTransitionDuration: const Duration(milliseconds: 400),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return Stack(
              children: [
                FadeTransition(
                  opacity: animation,
                  child: child,
                ),
                SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset.zero,
                    end: const Offset(-1.0, -1.0),
                  ).animate(CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeInOutCubic,
                  )),
                  child: ClipPath(
                    clipper: TopLeftDiagonalClipper(),
                    child: _buildSplashContent(context),
                  ),
                ),
                SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset.zero,
                    end: const Offset(1.0, 1.0),
                  ).animate(CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeInOutCubic,
                  )),
                  child: ClipPath(
                    clipper: BottomRightDiagonalClipper(),
                    child: _buildSplashContent(context),
                  ),
                ),
              ],
            );
          },
        );

  static Widget _buildSplashContent(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.white,
      child: const Center(
        child: JobtreeSplashLogo(),
      ),
    );
  }
}

class TopLeftDiagonalClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class BottomRightDiagonalClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(size.width, 0);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

// ============== ONBOARDING SCREEN ==============
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late PageController _pageController;
  int _currentPage = 0;
  double _pageOffset = 0.0; // Track scroll position for background
  Timer? _autoScrollTimer;
  Language _selectedLanguage = Language.hindi;
  late AppLocalizations _localizations;
  List<OnboardingData>? _cachedPages;

  List<OnboardingData> get _pages {
    // Only recreate if language changed or pages not cached
    if (_cachedPages == null || _localizations.language != _selectedLanguage) {
      _localizations = AppLocalizations(_selectedLanguage);
      _cachedPages = [
        OnboardingData(
          title: _localizations.page1Title,
          subtitle: _localizations.page1Subtitle,
          bgAsset: 'assets/images/onboarding/bg1.svg',
          illustrationType: IllustrationType.map,
        ),
        OnboardingData(
          title: _localizations.page2Title,
          subtitle: _localizations.page2Subtitle,
          bgAsset: 'assets/images/onboarding/bg2.svg',
          illustrationType: IllustrationType.phone,
        ),
        OnboardingData(
          title: _localizations.page3Title,
          subtitle: _localizations.page3Subtitle,
          bgAsset: 'assets/images/onboarding/bg3.svg',
          illustrationType: IllustrationType.profile,
        ),
      ];
    }
    return _cachedPages!;
  }

  @override
  void initState() {
    super.initState();
    _localizations = AppLocalizations(_selectedLanguage);
    _pageController = PageController();
    _pageController.addListener(_onPageScroll);
    _startAutoScroll();
  }

  void _onPageScroll() {
    setState(() {
      _pageOffset = _pageController.page ?? 0.0;
    });
  }

  void _startAutoScroll() {
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_currentPage < _pages.length - 1) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOutCubic,
        );
      } else {
        _pageController.animateToPage(
          0,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
              children: [
                // Language Selector
                Padding(
                  padding: AppResponsive.screenPaddingHV(context, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Theme(
                        data: Theme.of(context).copyWith(
                          highlightColor: Colors.transparent,
                          splashColor: Colors.transparent,
                          hoverColor: Colors.grey.shade100,
                          listTileTheme: ListTileThemeData(
                            selectedColor: Colors.grey.shade700,
                            selectedTileColor: Colors.transparent,
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: DropdownButton<Language>(
                            value: _selectedLanguage,
                            icon: Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.grey.shade600),
                            underline: const SizedBox(),
                            borderRadius: BorderRadius.circular(12),
                            dropdownColor: Colors.white,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                            menuMaxHeight: 150,
                            selectedItemBuilder: (BuildContext context) {
                              return [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.language, size: 18, color: Colors.grey.shade600),
                                    const SizedBox(width: 6),
                                    Text(
                                      'English',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.language, size: 18, color: Colors.grey.shade600),
                                    const SizedBox(width: 6),
                                    Text(
                                      'हिंदी',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ];
                            },
                            items: [
                            DropdownMenuItem<Language>(
                              value: Language.english,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.language, size: 18, color: Colors.grey.shade600),
                                  const SizedBox(width: 6),
                                  Text(
                                    'English',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            DropdownMenuItem<Language>(
                              value: Language.hindi,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.language, size: 18, color: Colors.grey.shade600),
                                  const SizedBox(width: 6),
                                  Text(
                                    'हिंदी',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          onChanged: (Language? newLanguage) {
                            if (newLanguage != null) {
                              setState(() {
                                _selectedLanguage = newLanguage;
                                _cachedPages = null; // Invalidate cache when language changes
                              });
                            }
                          },
                        ),
                        ),
                      ),
                    ],
                  ),
                ),

                // PageView
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() {
                        _currentPage = index;
                      });
                    },
                    itemCount: _pages.length,
                    itemBuilder: (context, index) {
                      return OnboardingPage(
                        data: _pages[index],
                        isActive: _currentPage == index,
                      );
                    },
                  ),
                ),

            // Page Indicators
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _pages.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentPage == index ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _currentPage == index
                          ? const Color(0xFF3D3D7B)
                          : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),

            // Get Started Button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AddPhoneNumberScreen(
                          selectedLanguage: _selectedLanguage,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3D3D7B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Center(
                    child: Text(
                      _localizations.getStartedButton,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
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

// ============== LANGUAGE SUPPORT ==============
enum Language { english, hindi }

class AppLocalizations {
  final Language language;

  AppLocalizations(this.language);

  // Onboarding Page 1
  String get page1Title => language == Language.hindi
      ? 'अपने नज़दीक नौकरियां खोजें'
      : 'Find Jobs Near You';

  String get page1Subtitle => language == Language.hindi
      ? 'अपने क्षेत्र के पास नौकरी देने वाले सैलून और ब्यूटी शॉप्स खोजें।'
      : 'Discover salons and beauty shops hiring close to your area.';

  // Onboarding Page 2
  String get page2Title => language == Language.hindi
      ? 'एक टैप में आवेदन करें'
      : 'Apply in One Tap';

  String get page2Subtitle => language == Language.hindi
      ? 'एक बटन से अपना प्रोफ़ाइल तुरंत भेजें।'
      : 'Send your profile instantly with one button.';

  // Onboarding Page 3
  String get page3Title => language == Language.hindi
      ? 'अपना प्रोफ़ाइल बनाएं'
      : 'Build Your Profile';

  String get page3Subtitle => language == Language.hindi
      ? 'अधिक नौकरी कॉल पाने के लिए अपनी फोटो, कौशल और अनुभव जोड़ें।'
      : 'Add your photo, skills, and experience to get more job calls.';

  // Buttons
  String get getStartedButton => language == Language.hindi ? 'शुरू करें →' : 'Get Started →';
  String get continueButton => language == Language.hindi ? 'जारी रखें' : 'Continue';
  String get continueArrow => language == Language.hindi ? 'आगे बढ़ें →' : 'Continue →';
  String get resendOtp => language == Language.hindi ? 'ओटीपी पुनः भेजें' : 'Resend OTP';

  // Phone Number Screen
  String get addPhoneNumberTitle => language == Language.hindi ? 'फोन नंबर जोड़ें 1 / 2' : 'Add phone number 1 / 2';
  String get phoneNumberLabel => language == Language.hindi ? 'फोन नंबर' : 'Phone Number';
  String get enterPhoneNumberHint => language == Language.hindi ? 'अपना फोन नंबर दर्ज करें' : 'Enter your Phone Number';
  String get helperTextMobile => language == Language.hindi ? '10 अंकों का मोबाइल नंबर डालें' : 'Enter your 10-digit mobile number';
  String get termsPrivacyText => language == Language.hindi 
      ? 'जारी रखने से आप हमारी शर्तें और गोपनीयता नीति से सहमत होते हैं' 
      : 'By continuing, you agree to our Terms and Privacy Policy';

  // OTP Verification Screen
  String get verifyNumberTitle => language == Language.hindi ? 'अपना नंबर सत्यापित करें 2 / 2' : 'Verify your number 2 / 2';
  String get otpSentMessage => language == Language.hindi ? 'हमने आपके नंबर पर ओटीपी भेजा है' : 'We have sent an OTP to your number';
  String get secureLoginText => language == Language.hindi ? '🔒 यह एक सुरक्षित लॉगिन है' : '🔒 This is a secure login';
  String get otpAutoFillText => language == Language.hindi ? 'ओटीपी अपने आप भर जाएगा' : 'OTP will be auto-filled';
  String get codeLabel => language == Language.hindi ? 'कोड' : 'Code';
  String get didNotReceiveOtp => language == Language.hindi ? 'ओटीपी प्राप्त नहीं हुआ?' : 'Did not receive OTP?';
  String get otpTermsText => language == Language.hindi 
      ? 'जॉबट्री का उपयोग करके, आप हमारी शर्तों और गोपनीयता नीति से सहमत होते हैं'
      : 'By using Jobtree, you agree to the Terms and Privacy Policy';
  String get terms => language == Language.hindi ? 'शर्तें' : 'Terms';
  String get privacyPolicy => language == Language.hindi ? 'गोपनीयता नीति' : 'Privacy Policy';

  // Account Created Success Screen
  String get accountCreatedSuccess => language == Language.hindi ? 'आपका खाता सफलतापूर्वक बनाया गया था!' : 'Your account was successfully created!';
  String get welcomeToJobtree => language == Language.hindi ? 'जॉबट्री परिवार में आपका स्वागत है!!!' : 'Welcome to Jobtree family!!!';

  // Role Selection Screen
  String get chooseYourRole => language == Language.hindi ? 'अपनी भूमिका चुनें' : 'Choose your Role';
  String get iWantJob => language == Language.hindi ? 'मुझे नौकरी चाहिए' : 'I want a job';
  String get iWantJobSubtitle => language == Language.hindi ? 'पास की नौकरियाँ देखें' : 'Find nearby jobs';
  String get iWantStaff => language == Language.hindi ? 'मुझे स्टाफ चाहिए' : 'I want to hire staff';
  String get iWantStaffSubtitle => language == Language.hindi ? '2 मिनट में कामगार पाएं' : 'Hire staff in 2 minutes';

  // Choose Your Job Screen
  String get chooseYourJob => language == Language.hindi ? 'अपनी नौकरी चुनें' : 'Choose Your Job';
  String get preferredJobType => language == Language.hindi ? 'पसंदीदा नौकरी प्रकार' : 'Preferred Job Type';
  String get preferredCity => language == Language.hindi ? 'पसंदीदा शहर' : 'Preferred City';
  String get whereDoYouWantJob => language == Language.hindi ? 'आप कहाँ नौकरी चाहते हैं?' : 'Where do you want job?';

  // Post Job Step 1 Screen (Employer Flow)
  String get basicJobDetails =>
      language == Language.hindi ? 'जॉब की बेसिक डिटेल्स' : 'Job basic details';
  String get step1Of3 => language == Language.hindi ? 'चरण 1 / 3' : 'Step 1 / 3';
  String get selectJobRole =>
      language == Language.hindi ? 'जॉब टाइप और स्किल्स चुनें' : 'Choose job type & skills';
  String get chooseJobTypeAndSkills =>
      language == Language.hindi ? 'जॉब टाइप व स्किल्स चुनें' : 'Choose job type & skills';
  String get location => language == Language.hindi ? 'शहर / लोकेशन' : 'City / Location';
  String get selectLocation => language == Language.hindi ? 'शहर चुनें' : 'Select city';
  String get numberOfStaff => language == Language.hindi ? 'कितनी वैकेंसी हैं?' : 'No. of vacancies';
  String get salaryRange => language == Language.hindi ? 'सैलरी रेंज' : 'Salary range';
  String get saveSkills => language == Language.hindi ? 'सेव करें' : 'Save';
  String get shiftFromLabel => language == Language.hindi ? 'से' : 'From';
  String get shiftToLabel => language == Language.hindi ? 'तक' : 'To';
  String get partTimeFreelance =>
      language == Language.hindi ? 'पार्ट टाइम (फ्रीलांसिंग)' : 'Part time (freelancing)';
  String get salonNameOptional => language == Language.hindi
      ? 'सैलून/स्पा/ब्यूटी क्लिनिक का नाम (वैकल्पिक)'
      : 'Salon/Spa/Beauty clinic name (optional)';
  String get salonNamePlaceholder => language == Language.hindi
      ? 'उदाहरण: रॉयल ब्यूटी क्लिनिक'
      : 'e.g. Royal Beauty Clinic';
  String get ownerNameOptional =>
      language == Language.hindi ? 'संपर्क व्यक्ति का नाम (वैकल्पिक)' : 'Contact person name (optional)';
  String get ownerNamePlaceholder => language == Language.hindi ? 'अपना नाम दर्ज करें' : 'Enter your name';
  String get contactVerified => language == Language.hindi ? 'संपर्क नंबर: सत्यापित ✓' : 'Contact number: Verified ✓';
  String get searchLocation => language == Language.hindi ? 'स्थान खोजें...' : 'Search location...';
  
  // Job Roles for employer (Main roles - max 8)
  String get hairStylist => language == Language.hindi ? 'हेयर स्टाइलिस्ट' : 'Hair Stylist';
  String get beautician => language == Language.hindi ? 'ब्यूटीशियन' : 'Beautician';
  String get makeupArtist => language == Language.hindi ? 'मेकअप आर्टिस्ट' : 'Makeup Artist';
  String get massageTherapist => language == Language.hindi ? 'मसाज थेरेपिस्ट' : 'Massage Therapist';
  String get receptionist => language == Language.hindi ? 'रिसेप्शनिस्ट' : 'Receptionist';
  String get helper => language == Language.hindi ? 'हेल्पर' : 'Helper';
  String get manager => language == Language.hindi ? 'मैनेजर' : 'Manager';
  String get other => language == Language.hindi ? 'अन्य' : 'Other';
  
  // "Other" category groups (max 6-8)
  String get academyTraining => language == Language.hindi ? 'अकादमी / ट्रेनिंग' : 'Academy / Training';
  String get managementRole => language == Language.hindi ? 'मैनेजमेंट' : 'Management';
  String get billingCashier => language == Language.hindi ? 'बिलिंग / कैशियर' : 'Billing / Cashier';
  String get supportStaff => language == Language.hindi ? 'सपोर्ट स्टाफ' : 'Support Staff';
  String get specialistRole => language == Language.hindi ? 'स्पेशलिस्ट' : 'Specialist';
  String get educatorTrainer => language == Language.hindi ? 'एजुकेटर / ट्रेनर' : 'Educator / Trainer';
  String get somethingElse => language == Language.hindi ? 'कुछ और' : 'Something Else';
  
  // Custom role input
  String get roleNameOptional => language == Language.hindi ? 'काम का नाम (वैकल्पिक)' : 'Role name (optional)';
  String get roleNamePlaceholder => language == Language.hindi ? 'उदाहरण: अकादमी प्रशिक्षक' : 'e.g. Academy Trainer';
  String get selectCategory => language == Language.hindi ? 'श्रेणी चुनें' : 'Select category';
  
  // Skill bundles
  String get selectSkills => language == Language.hindi ? 'कौशल चुनें (वैकल्पिक)' : 'Select skills (optional)';
  
  // Hair Stylist skill bundles
  String get haircutsStyling => language == Language.hindi ? 'हेयरकट और स्टाइलिंग' : 'Haircuts & Styling';
  String get colorTreatments => language == Language.hindi ? 'कलर और ट्रीटमेंट' : 'Colour & Treatments';
  String get hairSpaCare => language == Language.hindi ? 'हेयर स्पा और केयर' : 'Hair Spa & Care';
  String get beardGrooming => language == Language.hindi ? 'दाढ़ी और ग्रूमिंग' : 'Beard & Grooming';
  
  // Beautician skill bundles
  String get facialsSkincare => language == Language.hindi ? 'फेशियल और स्किनकेयर' : 'Facials & Skincare';
  String get waxingThreading => language == Language.hindi ? 'वैक्सिंग और थ्रेडिंग' : 'Waxing & Threading';
  String get manicurePedicure => language == Language.hindi ? 'मैनीक्योर और पेडीक्योर' : 'Manicure & Pedicure';
  String get bleachCleanup => language == Language.hindi ? 'ब्लीच और क्लीनअप' : 'Bleach & Cleanup';
  
  // Makeup Artist skill bundles
  String get bridalMakeup => language == Language.hindi ? 'ब्राइडल मेकअप' : 'Bridal Makeup';
  String get partyMakeup => language == Language.hindi ? 'पार्टी मेकअप' : 'Party Makeup';
  String get hdAirbrush => language == Language.hindi ? 'एचडी और एयरब्रश' : 'HD & Airbrush';
  String get eyeMakeup => language == Language.hindi ? 'आई मेकअप' : 'Eye Makeup';
  
  // Therapist skill bundles
  String get bodyMassage => language == Language.hindi ? 'बॉडी मसाज' : 'Body Massage';
  String get headShoulder => language == Language.hindi ? 'हेड और शोल्डर' : 'Head & Shoulder';
  String get aromatherapy => language == Language.hindi ? 'अरोमाथेरेपी' : 'Aromatherapy';
  String get footReflexology => language == Language.hindi ? 'फुट रिफ्लेक्सोलॉजी' : 'Foot Reflexology';
  
  // Fallback display name for "Other"
  String get salonStaff => language == Language.hindi ? 'सैलून स्टाफ' : 'Salon Staff';
  
  // Post Job Step 2 Screen
  String get workDetails => language == Language.hindi ? 'काम का प्रकार' : 'Work details';
  String get step2Of3 => language == Language.hindi ? 'चरण 2 / 3' : 'Step 2 / 3';
  
  // Work type
  String get workType => language == Language.hindi ? 'काम का समय' : 'Work type';
  String get fullTime => language == Language.hindi ? 'फुल टाइम' : 'Full-time';
  String get partTime => language == Language.hindi ? 'पार्ट टाइम' : 'Part-time';
  
  // Experience
  String get experience => language == Language.hindi ? 'अनुभव' : 'Experience';
  String get fresherOk => language == Language.hindi ? 'फ्रेशर भी चलेंगे' : 'Fresher OK';
  String get experienceRequired => language == Language.hindi ? 'अनुभवी चाहिए' : 'Experience required';
  
  // Accommodation
  String get accommodation => language == Language.hindi ? 'रहने की सुविधा' : 'Accommodation';
  String get yes => language == Language.hindi ? 'हाँ' : 'Yes';
  String get no => language == Language.hindi ? 'नहीं' : 'No';
  
  // Gender preference (optional)
  String get genderPreferenceOptional => language == Language.hindi
      ? 'उम्मीदवार का जेंडर चुनें'
      : 'Select applicant gender';
  String get male => language == Language.hindi ? 'पुरुष' : 'Male';
  String get female => language == Language.hindi ? 'महिला' : 'Female';
  String get anyGender => language == Language.hindi ? 'कोई भी' : 'Any';
  
  // Post Job Step 3 Screen
  String get postJob => language == Language.hindi ? 'जॉब पोस्ट करें' : 'Post job';
  String get reviewOnce => language == Language.hindi ? 'बस एक बार जांच लें' : 'Review once before posting';
  String get jobSummary => language == Language.hindi ? 'जॉब का विवरण' : 'Job summary';
  String get edit => language == Language.hindi ? 'बदलें' : 'Edit';
  String get editJobDetailsCTA =>
      language == Language.hindi ? 'विवरण बदलें' : 'Edit details';
  String get postJobButton => language == Language.hindi ? 'जॉब पोस्ट करें →' : 'Post Job →';
  String get posting => language == Language.hindi ? 'पोस्ट हो रहा है...' : 'Posting...';
  
  // Job Posted Success
  String get jobLive => language == Language.hindi ? '🎉 आपकी जॉब लाइव हो गई है' : '🎉 Your job is live';
  String get jobPostedSuccess => language == Language.hindi ? 'जॉब सफलतापूर्वक पोस्ट हो गई!' : 'Job posted successfully!';
  String get improveJobNudge => language == Language.hindi
      ? 'ज़्यादा उम्मीदवार पाने के लिए और जॉब डिटेल्स डालें'
      : 'Add more job details to get more applicants';
  String get improveJob => language == Language.hindi ? 'और जॉब डिटेल्स डालें' : 'Add more job details';
  String get viewJob => language == Language.hindi ? 'किसने आवेदन किया – देखें' : 'See applicants';
  String get goToDashboard => language == Language.hindi ? 'डैशबोर्ड पर जाएं' : 'Go to Dashboard';
  String get jobProfileComplete => language == Language.hindi ? 'जॉब प्रोफ़ाइल' : 'Job profile';
  
  // Home Screen
  String get searchCandidates => language == Language.hindi ? 'उम्मीदवार खोजें' : 'Search candidates';
  String get all => language == Language.hindi ? 'सभी' : 'All';
  String get shortlisted => language == Language.hindi ? 'शॉर्टलिस्ट' : 'Shortlisted';
  String get interviewed => language == Language.hindi ? 'इंटरव्यू' : 'Interviewed';
  String get noJobsPosted => language == Language.hindi ? 'अभी तक कोई जॉब पोस्ट नहीं की गई' : 'No jobs posted yet';
  String get postFirstJobSubtext => language == Language.hindi ? 'पहली जॉब पोस्ट करें और एप्लिकेशन प्राप्त करना शुरू करें' : 'Post your first job to start receiving applications';
  String get postYourFirstJob => language == Language.hindi ? 'अपनी पहली जॉब पोस्ट करें' : 'Post Your First Job';
  String get jobStatusLive => language == Language.hindi ? 'लाइव' : 'Live';
  String get jobComplete => language == Language.hindi ? 'जॉब % पूरी' : 'Job % complete';
  String get improveJobCTA => language == Language.hindi ? 'और जॉब डिटेल्स डालें' : 'Add more job details';
  String get viewJobCTA => language == Language.hindi ? 'किसने आवेदन किया – देखें' : 'See applicants';
  String get jobDetailsCheck => language == Language.hindi ? 'विवरण देखें' : 'Check details';
  String get tapAgainToExit => language == Language.hindi ? 'बाहर निकलने के लिए फिर दबाएं' : 'Tap again to exit';

  // ========== OWNER CANDIDATE MANAGEMENT ==========
  String get candidateListTitle => language == Language.hindi ? 'किसने आवेदन किया' : 'See applicants';
  String get totalApplications => language == Language.hindi ? 'कुल आवेदन' : 'Total Applications';
  String get noApplicationsYet => language == Language.hindi ? 'अभी तक कोई आवेदन नहीं आया' : 'No applications received yet';
  String get noApplicationsSubtext => language == Language.hindi ? 'जब कोई इस जॉब के लिए आवेदन करेगा, तो यहाँ दिखेगा' : 'When someone applies for this job, they will appear here';
  String get statusApplied => language == Language.hindi ? 'आवेदित' : 'Applied';
  String get statusShortlisted => language == Language.hindi ? 'शॉर्टलिस्ट' : 'Shortlisted';
  String get statusInterview => language == Language.hindi ? 'इंटरव्यू' : 'Interview';
  String get statusRejected => language == Language.hindi ? 'अस्वीकृत' : 'Rejected';
  String get statusHired => language == Language.hindi ? 'हायर्ड ✓' : 'Hired ✓';
  String get shortlistAction => language == Language.hindi ? 'शॉर्टलिस्ट करें' : 'Shortlist';
  String get rejectAction => language == Language.hindi ? 'अस्वीकार' : 'Reject';
  String get moveToInterviewAction => language == Language.hindi ? 'इंटरव्यू में ले जाएं' : 'Move to Interview';
  String get markHiredAction => language == Language.hindi ? 'हायर करें' : 'Mark Hired';
  String get statusUpdateSuccess => language == Language.hindi ? 'स्टेटस अपडेट हो गया' : 'Status updated successfully';
  String get statusUpdateFailed => language == Language.hindi ? 'स्टेटस अपडेट नहीं हो सका' : 'Failed to update status';
  String get experienceLabel2 => language == Language.hindi ? 'अनुभव' : 'Experience';
  String get expectedSalaryLabel => language == Language.hindi ? 'अपेक्षित वेतन' : 'Expected Salary';
  String get profileCompletionLabel => language == Language.hindi ? 'प्रोफ़ाइल' : 'Profile';
  String get allFilter => language == Language.hindi ? 'सभी' : 'All';
  String get appliedAgo => language == Language.hindi ? 'पहले आवेदन किया' : 'ago';
  String get loadingCandidates => language == Language.hindi ? 'उम्मीदवार लोड हो रहे हैं...' : 'Loading candidates...';
  String get errorLoadingCandidates => language == Language.hindi ? 'उम्मीदवार लोड नहीं हो सके' : 'Failed to load candidates';
  String get retry => language == Language.hindi ? 'फिर कोशिश करें' : 'Retry';
  String get applicantsCountLabel => language == Language.hindi ? 'आवेदक' : 'Applicants';
  String get allPositionsFilled => language == Language.hindi ? 'सभी पद भर गए हैं' : 'All positions filled';
  String get vacancyLimitReached => language == Language.hindi ? 'इस जॉब के सभी पद भर चुके हैं' : 'Vacancy limit reached for this job';
  String get hiredLabel => language == Language.hindi ? 'हायर्ड' : 'Hired';

  // ========== CALL MASKING ==========
  String get callSecure => language == Language.hindi ? 'कॉल (सुरक्षित)' : 'Call (Secure)';
  String get connecting => language == Language.hindi ? 'कनेक्ट हो रहा है...' : 'Connecting...';
  String get callInitiated => language == Language.hindi ? 'कॉल शुरू हो गई — आपका फ़ोन बजेगा' : 'Call initiated — your phone will ring';
  String get callFailed => language == Language.hindi ? 'कॉल नहीं हो सकी' : 'Call could not be connected';
  String get callLimitReached => language == Language.hindi ? 'आज की कॉल सीमा पूरी हो गई' : 'Daily call limit reached';
  String get callOnlyShortlisted => language == Language.hindi ? 'सिर्फ शॉर्टलिस्ट या इंटरव्यू उम्मीदवारों को कॉल कर सकते हैं' : 'Can only call shortlisted or interview candidates';
  String get callsRemainingToday => language == Language.hindi ? 'आज बचे कॉल' : 'calls remaining today';
  String get secureCallInfo => language == Language.hindi ? 'आपका नंबर उम्मीदवार को नहीं दिखेगा' : 'Your number is hidden from the candidate';

  // ========== CONFIRMATION DIALOGS ==========
  String get confirmRejectTitle => language == Language.hindi ? 'उम्मीदवार अस्वीकार करें?' : 'Reject Candidate?';
  String get confirmRejectMessage => language == Language.hindi ? 'इस उम्मीदवार को अस्वीकार करने के बाद यह बदला नहीं जा सकता।' : 'This action cannot be undone. The candidate will be notified.';
  String get confirmHireTitle => language == Language.hindi ? 'उम्मीदवार हायर करें?' : 'Hire Candidate?';
  String get confirmHireMessage => language == Language.hindi ? 'यह उम्मीदवार इस जॉब के लिए हायर हो जाएगा।' : 'This candidate will be marked as hired for this job.';
  String get confirmAction => language == Language.hindi ? 'हाँ, करें' : 'Yes, Confirm';
  String get cancelAction => language == Language.hindi ? 'रद्द करें' : 'Cancel';
  String get positionFilled => language == Language.hindi ? 'पद भर गया' : 'Position Filled';

  // ========== INTERVIEW SCHEDULING ==========
  String get scheduleInterview => language == Language.hindi ? 'इंटरव्यू शेड्यूल करें' : 'Schedule Interview';
  String get rescheduleInterview => language == Language.hindi ? 'रीशेड्यूल करें' : 'Reschedule';
  String get markInterviewComplete => language == Language.hindi ? 'इंटरव्यू पूरा हुआ' : 'Mark Completed';
  String get interviewScheduled => language == Language.hindi ? 'इंटरव्यू शेड्यूल' : 'Interview Scheduled';
  String get interviewCompleted => language == Language.hindi ? 'इंटरव्यू पूरा' : 'Interview Completed';
  String get interviewOn => language == Language.hindi ? 'इंटरव्यू' : 'Interview on';
  String get selectDate => language == Language.hindi ? 'तारीख चुनें *' : 'Select Date *';
  String get selectTime => language == Language.hindi ? 'समय चुनें *' : 'Select Time *';
  String get interviewMode => language == Language.hindi ? 'इंटरव्यू का तरीका' : 'Interview Mode';
  String get inPerson => language == Language.hindi ? 'व्यक्तिगत' : 'In Person';
  String get phoneCall => language == Language.hindi ? 'फ़ोन कॉल' : 'Phone Call';
  String get videoCall => language == Language.hindi ? 'वीडियो कॉल' : 'Video Call';
  String get notesOptional => language == Language.hindi ? 'नोट्स (वैकल्पिक)' : 'Notes (optional)';
  String get notesHint => language == Language.hindi ? 'जैसे: पोर्टफोलियो लाएं' : 'e.g. Bring your portfolio';
  String get scheduleSuccess => language == Language.hindi ? 'इंटरव्यू शेड्यूल हो गया' : 'Interview scheduled successfully';
  String get rescheduleSuccess => language == Language.hindi ? 'इंटरव्यू रीशेड्यूल हो गया' : 'Interview rescheduled';
  String get completeSuccess => language == Language.hindi ? 'इंटरव्यू पूरा हुआ। अब हायर या रिजेक्ट करें।' : 'Interview completed. Now hire or reject.';
  String get hireOrReject => language == Language.hindi ? 'हायर करें या रिजेक्ट करें' : 'Hire or Reject';
  String get mustSelectDateTime => language == Language.hindi ? 'तारीख और समय चुनें' : 'Please select date and time';
  String get interviewDetails => language == Language.hindi ? 'इंटरव्यू विवरण' : 'Interview Details';

  String get editJobTitle =>
      language == Language.hindi ? 'जॉब डिटेल्स सुधारें' : 'Edit job details';
  String get chooseJobTypeTitle =>
      language == Language.hindi ? 'जॉब टाइप चुनें' : 'Choose job type';
  String get chooseSkillSetTitle =>
      language == Language.hindi ? 'स्किल सेट चुनें' : 'Choose skill set';
  String get chooseSkillSetChange =>
      language == Language.hindi ? 'स्किल सेट चुनें / बदलें' : 'Choose / change skill set';
  String get shiftTimeSelectLabel =>
      language == Language.hindi ? 'शिफ्ट टाइम सेलेक्ट करें' : 'Select shift time';
  String get jobDetailsTitle => language == Language.hindi ? 'जॉब की जानकारी' : 'Job details';
  String get saveChanges => language == Language.hindi ? 'सेव करें' : 'Save';
  String get completeJobHelper => language == Language.hindi ? 'जॉब को 70% तक पूरा करें ताकि ज़्यादा कॉल मिलें' : 'Complete job to 70% to get more calls';
  String get profileIncomplete => language == Language.hindi
      ? 'आपकी प्रोफ़ाइल {p}% पूरी है'
      : 'Your profile is {p}% complete';
  String get addMissingDetails =>
      language == Language.hindi
          ? 'बेहतर उम्मीदवार पाने के लिए छूटी हुई जानकारी जोड़ें'
          : 'Add remaining details to get better candidates';
  String get completeNow =>
      language == Language.hindi ? 'प्रोफ़ाइल डिटेल्स पूरी करें' : 'Complete profile details';
  String get home => language == Language.hindi ? 'होम' : 'Home';
  String get candidates => language == Language.hindi ? 'सभी कैंडिडेट देखें' : 'See all candidates';
  String get ownerApplicantsTab =>
      language == Language.hindi ? 'सभी कैंडिडेट देखें' : 'See all candidates';
  String get allApplicantsTitle =>
      language == Language.hindi ? 'सभी कैंडिडेट' : 'All candidates';
  String get filterApplicants => language == Language.hindi ? 'फ़िल्टर' : 'Filter';
  String get applicantFiltersTitle =>
      language == Language.hindi ? 'कैंडिडेट खोजें' : 'Search candidates';
  String get allJobTypesFilter => language == Language.hindi ? 'सभी जॉब टाइप' : 'All job types';
  String get allCitiesFilter => language == Language.hindi ? 'सभी शहर' : 'All cities';
  String get applyFilters => language == Language.hindi ? 'दिखाएँ' : 'Show results';
  String get clearFilters => language == Language.hindi ? 'फ़िल्टर हटाएँ' : 'Clear filters';
  String get noApplicantsFound =>
      language == Language.hindi ? 'इस फ़िल्टर पर कोई कैंडिडेट नहीं' : 'No candidates for this filter';
  String get noCandidatesYet =>
      language == Language.hindi ? 'अभी कोई कैंडिडेट नहीं मिला' : 'No candidates found yet';
  String get browseCandidatesHint =>
      language == Language.hindi
          ? 'जॉब टाइप या शहर से फ़िल्टर लगाकर खोजें।'
          : 'Browse all job seekers on the app — filter by job type or city.';
  String get appliedForJobLabel => language == Language.hindi ? 'जॉब' : 'Job';
  String get chat => language == Language.hindi ? 'चैट' : 'Chat';
  String get profile => language == Language.hindi ? 'प्रोफ़ाइल' : 'Profile';
  /// Bottom tab label — distinct from [editProfile] action on the screen.
  String get ownerSalonTab => language == Language.hindi ? 'मेरा प्रोफ़ाइल' : 'My profile';
  String get tapToEditProfile =>
      language == Language.hindi ? 'बदलने के लिए टैप करें' : 'Tap to edit';
  
  // Summary labels
  String get roleLabel => language == Language.hindi ? 'जॉब टाइप' : 'Job type';
  String get locationLabel => language == Language.hindi ? 'स्थान' : 'Location';
  String get salaryLabel => language == Language.hindi ? 'वेतन सीमा' : 'Salary range';
  String get workTypeLabel => language == Language.hindi ? 'काम का प्रकार' : 'Work Type';
  String get experienceLabel => language == Language.hindi ? 'अनुभव' : 'Experience';
  String get genderLabel => language == Language.hindi ? 'लिंग' : 'Gender';
  String get salonLabel => language == Language.hindi ? 'सैलून/स्पा/ब्यूटी क्लिनिक' : 'Salon/Spa/Beauty clinic';
  String get staffNeeded => language == Language.hindi ? 'वैकेंसी' : 'Vacancies';
  String get perMonth => language == Language.hindi ? 'प्रति माह' : 'per month';
  
  // Improve Job Screen
  String get improveJobTitle => language == Language.hindi ? 'जॉब की जानकारी बढ़ाएं' : 'Improve your job post';
  String get improveJobSubtext => language == Language.hindi ? 'पूरी जानकारी = ज़्यादा कॉल' : 'More details = more responses';
  String get jobProfileProgress => language == Language.hindi ? 'जॉब प्रोफ़ाइल' : 'Job profile';
  String get complete => language == Language.hindi ? 'पूरी' : 'complete';
  String get doneGoBack => language == Language.hindi ? 'हो गया, वापस जाएं' : 'Done, go back';
  String get saved => language == Language.hindi ? '✓ सेव हो गया' : '✓ Saved';
  String get recommended => language == Language.hindi ? 'सुझाया गया' : 'Recommended';
  String get optional => language == Language.hindi ? 'वैकल्पिक' : 'Optional';
  String get addMore => language == Language.hindi ? 'और जोड़ें' : 'Add more';
  
  // Section 1: Skills & Work Details
  String get skillsWorkDetails => language == Language.hindi ? 'कौशल और काम का विवरण' : 'Skills & Work Details';
  String get selectRelevantSkills => language == Language.hindi ? 'संबंधित कौशल चुनें' : 'Select relevant skills';
  
  // Section 2: Work Timings
  String get workTimings => language == Language.hindi ? 'काम का समय' : 'Work Timings';
  String get shiftType => language == Language.hindi ? 'शिफ्ट का समय' : 'Shift timing';
  String get shiftTiming => language == Language.hindi ? 'शिफ्ट का समय' : 'Shift timing';
  String get fullDay => language == Language.hindi ? 'पूरा दिन' : 'Full day';
  String get shiftBased => language == Language.hindi ? 'शिफ्ट के अनुसार' : 'Shift based';
  String get openingTime => language == Language.hindi ? 'खुलने का समय' : 'Opening time';
  String get closingTime => language == Language.hindi ? 'बंद होने का समय' : 'Closing time';
  String get weeklyOff => language == Language.hindi ? 'हफ्ते में छुट्टी का दिन' : 'Weekly day off';
  
  // Section 3: Facilities & Benefits
  String get facilitiesBenefits => language == Language.hindi ? 'सुविधाएं और लाभ' : 'Facilities & Benefits';
  String get foodProvided => language == Language.hindi ? 'खाना मिलता है' : 'Food provided';
  String get incentives => language == Language.hindi ? 'इंसेंटिव' : 'Incentives';
  String get paidLeave => language == Language.hindi ? 'पेड छुट्टी' : 'Paid leave';
  String get training => language == Language.hindi ? 'ट्रेनिंग' : 'Training';
  
  // Section 4: Salon Details
  String get salonDetails => language == Language.hindi
      ? 'सैलून/स्पा/ब्यूटी क्लिनिक विवरण'
      : 'Salon/Spa/Beauty clinic details';
  String get addPhotos => language == Language.hindi ? 'फोटो जोड़ें' : 'Add photos';
  String get shortDescription => language == Language.hindi ? 'संक्षिप्त विवरण' : 'Short description';
  String get descriptionPlaceholder => language == Language.hindi
      ? 'सैलून/स्पा/ब्यूटी क्लिनिक के बारे में कुछ जानकारी दें'
      : 'Share information about your salon/spa/beauty clinic...';
  
  // Days of week
  String get sunday => language == Language.hindi ? 'रवि' : 'Sun';
  String get monday => language == Language.hindi ? 'सोम' : 'Mon';
  String get tuesday => language == Language.hindi ? 'मंगल' : 'Tue';
  String get wednesday => language == Language.hindi ? 'बुध' : 'Wed';
  String get thursday => language == Language.hindi ? 'गुरु' : 'Thu';
  String get friday => language == Language.hindi ? 'शुक्र' : 'Fri';
  String get saturday => language == Language.hindi ? 'शनि' : 'Sat';

  // Profile Tab
  String get editProfile => language == Language.hindi ? 'प्रोफ़ाइल अपडेट करें' : 'Update profile';
  String get uploadPhoto => language == Language.hindi ? 'फोटो अपलोड करें' : 'Upload Photo';
  String get verified => language == Language.hindi ? 'सत्यापित' : 'Verified';
  String get yourProfileIsComplete => language == Language.hindi
      ? 'आपकी प्रोफ़ाइल {p}% पूरी है'
      : 'Your profile is {p}% complete';
  String get loginPhoneLabel => language == Language.hindi ? 'लॉगिन नंबर (ओटीपी)' : 'Login number (OTP)';
  String get contactNumberHint => language == Language.hindi
      ? 'सभी कॉल/संदेश इसी नंबर पर जाएंगे। अगर जॉब पोस्ट करने वाला और संपर्क व्यक्ति अलग हैं तो मालिक/मैनेजर का नाम सही भरें।'
      : 'Calls and messages use this number. If the contact person differs from whoever posts jobs, enter the owner/manager name correctly.';
  String get completeProfileToGetBetterCandidates => language == Language.hindi ? 'अपनी प्रोफ़ाइल पूरी करें ताकि बेहतर उम्मीदवार मिलें' : 'Complete your profile to get better candidates';
  String get salonDetailsProfile => language == Language.hindi
      ? 'सैलून/स्पा/ब्यूटी क्लिनिक विवरण'
      : 'Salon/Spa/Beauty clinic details';
  String get salonName => language == Language.hindi
      ? 'सैलून/स्पा/ब्यूटी क्लिनिक का नाम'
      : 'Salon/Spa/Beauty clinic name';
  String get city => language == Language.hindi ? 'शहर' : 'City';
  String get ownerManagerName => language == Language.hindi ? 'मालिक / मैनेजर का नाम' : 'Owner / Manager Name';
  String get contactNumber => language == Language.hindi ? 'संपर्क नंबर' : 'Contact Number';
  String get notAdded => language == Language.hindi ? 'जोड़ा नहीं गया' : 'Not added';
  String get verificationDocuments => language == Language.hindi ? 'सत्यापन और दस्तावेज़' : 'Verification & Documents';
  String get aadhaarKycStatus => language == Language.hindi ? 'आधार / केवाईसी स्थिति' : 'Aadhaar / KYC Status';
  String get businessProof => language == Language.hindi ? 'व्यापार प्रमाण' : 'Business Proof';
  String get added => language == Language.hindi ? 'जोड़ा गया' : 'Added';
  String get mediaPhotos => language == Language.hindi ? 'मीडिया और फोटो' : 'Media & Photos';
  String get addPhoto => language == Language.hindi ? '+ फोटो जोड़ें' : '+ Add Photo';
  String get salonPhotosSeeker => language == Language.hindi ? 'सैलून / कार्यस्थल की तस्वीरें' : 'Salon & workplace photos';
  String get settings => language == Language.hindi ? 'सेटिंग्स' : 'Settings';
  String get languageLabel => language == Language.hindi ? 'भाषा' : 'Language';
  String get notifications => language == Language.hindi ? 'सूचनाएं' : 'Notifications';
  String get helpSupport => language == Language.hindi ? 'मदद और सहायता' : 'Help & Support';
  String get about => language == Language.hindi ? 'के बारे में' : 'About';
  String get logout => language == Language.hindi ? 'लॉग आउट' : 'Logout';

  // Notifications Screen
  String get notificationsTitle => language == Language.hindi ? 'सूचनाएं' : 'Notifications';
  String get notificationsSubtext => language == Language.hindi ? 'भर्ती अपडेट और महत्वपूर्ण अलर्ट' : 'Hiring updates & important alerts';
  String get hiringUpdates => language == Language.hindi ? 'भर्ती अपडेट' : 'Hiring Updates';
  String get hiringUpdatesDesc => language == Language.hindi ? 'जब उम्मीदवार आवेदन करें या जवाब दें तो सूचना मिलेगी' : 'Get notified when candidates apply or respond';
  String get jobTips => language == Language.hindi ? 'जॉब टिप्स' : 'Job Tips';
  String get jobTipsDesc => language == Language.hindi ? 'जॉब प्रदर्शन में सुधार के लिए सुझाव' : 'Tips to improve job performance';
  String get profileImprovements => language == Language.hindi ? 'प्रोफ़ाइल सुधार' : 'Profile Improvements';
  String get profileImprovementsDesc => language == Language.hindi ? 'अधिक प्रतिक्रियाएं पाने के लिए सुझाव' : 'Suggestions to get more responses';
  String get accountAlerts => language == Language.hindi ? 'खाता अलर्ट' : 'Account Alerts';
  String get accountAlertsDesc => language == Language.hindi ? 'सुरक्षा और खाता संबंधी अपडेट' : 'Security & account related updates';
  String get offersUpdates => language == Language.hindi ? 'ऑफ़र्स और अपडेट' : 'Offers & Updates';
  String get offersUpdatesDesc => language == Language.hindi ? 'छूट और फीचर घोषणाएं' : 'Discounts & feature announcements';
  String get requiredForHiring => language == Language.hindi ? 'भर्ती अपडेट के लिए आवश्यक' : 'Required for hiring updates';
  String get noNotificationsYet => language == Language.hindi ? 'अभी तक कोई सूचना नहीं' : 'No notifications yet';
  String get noNotificationsSubtext => language == Language.hindi ? 'आपको यहां भर्ती अपडेट दिखाई देंगे' : "You'll see hiring updates here";

  // Help & Support
  String get helpSupportTitle => language == Language.hindi ? 'मदद और सहायता' : 'Help & Support';
  String get helpSupportSubtext => language == Language.hindi ? 'हम यहां मदद के लिए हैं' : "We're here to help";
  String get callSupport => language == Language.hindi ? 'सपोर्ट पर कॉल करें' : 'Call Support';
  String get chatWhatsApp => language == Language.hindi ? 'व्हाट्सऐप पर चैट करें' : 'Chat on WhatsApp';
  String get frequentlyAskedQuestions => language == Language.hindi ? 'अक्सर पूछे जाने वाले प्रश्न' : 'Frequently Asked Questions';
  String get reportProblem => language == Language.hindi ? 'समस्या रिपोर्ट करें' : 'Report a Problem';
  String get reportProblemDesc => language == Language.hindi ? 'बताएं कि क्या गलत हुआ' : 'Tell us what went wrong';
  String get issueType => language == Language.hindi ? 'समस्या का प्रकार' : 'Issue Type';
  String get description => language == Language.hindi ? 'विवरण (वैकल्पिक)' : 'Description (Optional)';
  String get submit => language == Language.hindi ? 'सबमिट करें' : 'Submit';
  String get termsConditions => language == Language.hindi ? 'नियम और शर्तें' : 'Terms & Conditions';
  String get appVersion => language == Language.hindi ? 'ऐप संस्करण' : 'App Version';
  
  // FAQ Questions
  String get faqQ1 => language == Language.hindi ? 'मैं जॉब कैसे पोस्ट करूं?' : 'How do I post a job?';
  String get faqA1 => language == Language.hindi ? 'होम स्क्रीन पर "अपनी जॉब पोस्ट करें" पर क्लिक करें और 3 आसान स्टेप्स में जॉब डालें।' : 'Tap "Post your job" on the home screen and complete 3 simple steps.';
  String get faqQ2 => language == Language.hindi ? 'मेरी जॉब पर कैंडिडेट क्यों नहीं आ रहे?' : 'Why am I not getting candidates?';
  String get faqA2 => language == Language.hindi ? 'सैलरी, लोकेशन और फोटो जोड़ने से ज़्यादा कैंडिडेट मिलते हैं।' : 'Adding salary, location, and photos helps you get more responses.';
  String get faqQ3 => language == Language.hindi ? 'मैं अपनी जॉब को कैसे एडिट करूं?' : 'How can I edit my job?';
  String get faqA3 => language == Language.hindi ? 'डैशबोर्ड में जाकर अपनी जॉब पर "जानकारी जोड़ें" पर क्लिक करें।' : 'Go to Dashboard and tap "Add details" on your job card.';
  String get faqQ4 => language == Language.hindi ? 'क्या जॉबट्री इस्तेमाल करने के पैसे लगते हैं?' : 'Is JobTree paid?';
  String get faqA4 => language == Language.hindi ? 'अभी जॉबट्री पर जॉब पोस्ट करना आसान और किफायती है। प्लान की जानकारी बाद में मिलेगी।' : 'JobTree is affordable and easy to use. Plan details will be shown later.';
  String get faqQ5 => language == Language.hindi ? 'भाषा कैसे बदलें?' : 'How do I change language?';
  String get faqA5 => language == Language.hindi ? 'प्रोफ़ाइल में जाकर "भाषा" पर क्लिक करें।' : 'Go to Profile → Language.';
  
  // Issue Types
  String get issueTypeJobPosting => language == Language.hindi ? 'जॉब पोस्टिंग समस्या' : 'Job posting issue';
  String get issueTypeCandidate => language == Language.hindi ? 'कैंडिडेट समस्या' : 'Candidate issue';
  String get issueTypeAppIssue => language == Language.hindi ? 'ऐप काम नहीं कर रहा' : 'App not working';
  String get issueTypePayment => language == Language.hindi ? 'भुगतान / प्लान' : 'Payment / plan';
  String get issueTypeOther => language == Language.hindi ? 'अन्य' : 'Other';
  String get ticketSubmitted => language == Language.hindi ? 'आपकी समस्या रिपोर्ट की गई है। हम जल्द ही संपर्क करेंगे।' : 'Your issue has been reported. We will contact you soon.';
  String get cancel => language == Language.hindi ? 'रद्द करें' : 'Cancel';

  // About JobTree Screen
  String get aboutJobTreeTitle => language == Language.hindi ? 'जॉबट्री के बारे में' : 'About JobTree';
  String get aboutJobTreeSubtext => language == Language.hindi ? 'सैलून के लिए सरल भर्ती ऐप' : 'A simple hiring app for salons';
  String get whatIsJobTree => language == Language.hindi ? 'जॉबट्री क्या है?' : 'What is JobTree?';
  String get whatIsJobTreeContent => language == Language.hindi 
      ? 'जॉबट्री एक सरल भर्ती ऐप है,\nजो सैलून को सही कामगार\nजल्दी ढूँढने में मदद करता है।'
      : 'JobTree is a simple hiring app\nthat helps salons find\nthe right staff quickly.';
  String get whyJobTreeExists => language == Language.hindi ? 'जॉबट्री क्यों बना?' : 'Why JobTree exists';
  String get whyJobTreeBullet1 => language == Language.hindi 
      ? 'व्हाट्सऐप पर भर्ती मुश्किल होती है'
      : 'Hiring on WhatsApp is unorganised';
  String get whyJobTreeBullet2 => language == Language.hindi 
      ? 'सही कामगार मिलने में समय लगता है'
      : 'Finding reliable staff takes time';
  String get whyJobTreeBullet3 => language == Language.hindi 
      ? 'जॉबट्री भर्ती को आसान बनाता है'
      : 'JobTree makes hiring simple';
  String get howJobTreeHelps => language == Language.hindi ? 'जॉबट्री कैसे मदद करता है' : 'How JobTree helps';
  String get howJobTreeBullet1 => language == Language.hindi 
      ? '2 मिनट में जॉब पोस्ट करें'
      : 'Post a job in under 2 minutes';
  String get howJobTreeBullet2 => language == Language.hindi 
      ? 'सत्यापित प्रोफ़ाइल देखें'
      : 'View verified profiles';
  String get howJobTreeBullet3 => language == Language.hindi 
      ? 'ऐप के अंदर सुरक्षित बात करें'
      : 'Talk safely inside the app';
  String get trustSafety => language == Language.hindi ? 'सुरक्षा और भरोसा' : 'Trust & Safety';
  String get trustBullet1 => language == Language.hindi 
      ? 'फ़ोन नंबर सत्यापन'
      : 'Phone number verification';
  String get trustBullet2 => language == Language.hindi 
      ? 'ऐप के अंदर चैट'
      : 'In-app communication';
  String get trustBullet3 => language == Language.hindi 
      ? 'आपका निजी नंबर सुरक्षित रहता है'
      : 'Your personal number stays private';
  String get companyDetails => language == Language.hindi ? 'कंपनी विवरण' : 'Company Details';
  String get madeInIndia => 'Made in India 🇮🇳';

  // Language names
  String get englishName => 'English';
  String get hindiName => 'हिंदी';

  // Seeker auth flow shared strings
  String get enterPhone => language == Language.hindi ? 'अपना फोन नंबर दर्ज करें' : 'Enter your Phone Number';
  String get phoneNumber => language == Language.hindi ? 'फोन नंबर' : 'Phone Number';
  String get verifyOtp => language == Language.hindi ? 'ओटीपी सत्यापित करें' : 'Verify OTP';
  String get otpSentTo => language == Language.hindi ? 'ओटीपी भेजा गया' : 'OTP sent to';
  String get resendIn => language == Language.hindi ? 'पुनः भेजें' : 'Resend in';
  String get verify => language == Language.hindi ? 'सत्यापित करें' : 'Verify';

  // ========== SEEKER FLOW STRINGS ==========
  String get createYourProfile => language == Language.hindi ? 'अपनी प्रोफ़ाइल बनाएं' : 'Create your Profile';
  String get createProfileSubtext => language == Language.hindi ? 'तेज़ ऑनबोर्डिंग — सिर्फ ज़रूरी जानकारी' : 'Quick onboarding — only essentials';
  String get yourFullName => language == Language.hindi ? 'पूरा नाम *' : 'Full Name *';
  String get enterFullName => language == Language.hindi ? 'अपना पूरा नाम दर्ज करें' : 'Enter your full name';
  String get selectGender => language == Language.hindi ? 'लिंग *' : 'Gender *';
  String get otherGender => language == Language.hindi ? 'अन्य' : 'Other';
  String get preferredJobRole =>
      language == Language.hindi ? 'अपना job type व skills चुनें *' : 'Choose your job type & skills *';
  String get seekerChooseJobTypeButton =>
      language == Language.hindi ? 'अपना job type व skills चुनें' : 'Choose your job type & skills';
  String get seekerCity => language == Language.hindi ? 'अभी जहाँ पर हैं *' : 'Where you are now *';
  String get seekerPreferredWorkCities => language == Language.hindi
      ? 'शहर जिसमें जॉब चाहिए (आप एक से अधिक शहर चुन सकते हैं)'
      : 'Cities where you want a job (you can pick more than one)';
  String get seekerPreferredCitiesLabel =>
      language == Language.hindi ? 'जॉब चाहिए शहर' : 'Job wanted in';
  String get saveAndContinue => language == Language.hindi ? 'सेव करें और आगे बढ़ें' : 'Save & Continue';
  String get jobFeedTitle => language == Language.hindi ? 'नौकरियां' : 'Jobs';
  String get noJobsInArea => language == Language.hindi ? 'आपके क्षेत्र में अभी कोई नौकरी उपलब्ध नहीं है' : 'No jobs available in your area right now';
  String get noJobsSubtext => language == Language.hindi ? 'बाद में फिर देखें या अपना शहर बदलें' : 'Check back later or change your city';
  String get apply => language == Language.hindi ? 'आवेदन करें' : 'Apply';
  String get applied => language == Language.hindi ? 'आवेदित ✓' : 'Applied ✓';
  String get applicationSuccess => language == Language.hindi ? 'आवेदन सफल' : 'Application submitted';
  String get alreadyApplied => language == Language.hindi ? 'आपने पहले ही आवेदन कर दिया है' : 'You have already applied';
  String get seekerProfileCompletion => language == Language.hindi
      ? 'आपकी प्रोफ़ाइल {p}% पूरी है'
      : 'Your profile is {p}% complete';
  String get seekerProfileNudge => language == Language.hindi
      ? 'बेहतर जॉब पाने के लिए जानकारी जोड़ें'
      : 'Add details to get better job matches';
  String get enhanceProfile => language == Language.hindi ? 'प्रोफ़ाइल सुधारें' : 'Enhance Profile';
  String get experienceField =>
      language == Language.hindi ? 'अपना experience जोड़ें' : 'Add your experience';
  String get seekerMaritalStatus =>
      language == Language.hindi ? 'वैवाहिक status' : 'Marital status';
  String get seekerCurrentSalary => language == Language.hindi
      ? 'अभी कितनी salary ले रहे हैं (महीने में)'
      : 'Current monthly salary';
  String get expectedSalaryField => language == Language.hindi
      ? 'नई job में कितनी salary expect कर रहे हैं – डालें'
      : 'Expected salary in your next job';
  String get seekerWorkPortfolio => language == Language.hindi
      ? 'अपने काम की photo या video डालें'
      : 'Add photos or videos of your work';
  String get browseAllJobs => language == Language.hindi ? 'सभी jobs देखें' : 'Browse all jobs';
  String get browseAllJobsHint => language == Language.hindi
      ? 'सभी employer की job posts — job type और location से filter करें'
      : 'All employer job posts — filter by job type and location';
  String get noJobsForFilter => language == Language.hindi
      ? 'इस filter पर कोई job नहीं मिली'
      : 'No jobs match this filter';
  String get seekerSkills => language == Language.hindi ? 'कौशल' : 'Skills';
  String get fresherSeeker => language == Language.hindi ? 'फ्रेशर' : 'Fresher';
  String get experiencedSeeker => language == Language.hindi ? 'अनुभवी (1+ वर्ष)' : 'Experienced (1+ year)';
  String get seniorSeeker => language == Language.hindi ? 'सीनियर (3+ वर्ष)' : 'Senior (3+ years)';
  String get seekerHome => language == Language.hindi ? 'होम' : 'Home';
  String get seekerApplications =>
      language == Language.hindi ? 'कहाँ apply किया – देखें' : 'Where you applied – view';
  String get seekerProfileTab => language == Language.hindi ? 'प्रोफ़ाइल' : 'Profile';
  String get salary => language == Language.hindi ? 'वेतन' : 'Salary';
  String get postedBy => language == Language.hindi ? 'पोस्ट किया' : 'Posted by';
}

// ============== ONBOARDING DATA ==============
enum IllustrationType { map, phone, profile }

class OnboardingData {
  final String title;
  final String subtitle;
  final String bgAsset;
  final IllustrationType illustrationType;

  OnboardingData({
    required this.title,
    required this.subtitle,
    required this.bgAsset,
    required this.illustrationType,
  });
}

// ============== ONBOARDING PAGE ==============
class OnboardingPage extends StatelessWidget {
  final OnboardingData data;
  final bool isActive;

  const OnboardingPage({
    super.key,
    required this.data,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppResponsive.formScreenPadding(context),
      child: Column(
        children: [
          // Illustration Area
          Expanded(
            flex: 3,
            child: Center(
              child: _buildIllustration(),
            ),
          ),

          // Text Content
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  style: TextStyle(
                    fontSize: context.rHeadingSize,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1A1A2E),
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  data.subtitle,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey.shade500,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIllustration() {
    switch (data.illustrationType) {
      case IllustrationType.map:
        return const MapIllustration();
      case IllustrationType.phone:
        return const PhoneIllustration();
      case IllustrationType.profile:
        return const ProfileIllustration();
    }
  }
}

// ============== MAP ILLUSTRATION ==============
class MapIllustration extends StatefulWidget {
  const MapIllustration({super.key});

  @override
  State<MapIllustration> createState() => _MapIllustrationState();
}

class _MapIllustrationState extends State<MapIllustration>
    with TickerProviderStateMixin {
  late AnimationController _frameController1;
  late AnimationController _frameController2;
  late AnimationController _frameController3;
  late AnimationController _floatController;

  // Frame sequences for each marker - all animate to different profiles
  
  // Marker 1: tiny → pin → glow → spa profile (frame2)
  final List<String> _profile1Frames = [
    'assets/images/onboarding/frame6.png',
    'assets/images/onboarding/frame5.png',
    'assets/images/onboarding/frame4.png',
    'assets/images/onboarding/frame2.png',
  ];
  
  // Marker 2: tiny → pin → glow → partial profile (frame1)
  final List<String> _profile2Frames = [
    'assets/images/onboarding/frame6.png',
    'assets/images/onboarding/frame5.png',
    'assets/images/onboarding/frame4.png',
    'assets/images/onboarding/frame1.png',
  ];
  
  // Marker 3: tiny → pin → glow → hairstylist profile (frame3)
  final List<String> _profile3Frames = [
    'assets/images/onboarding/frame6.png',
    'assets/images/onboarding/frame5.png',
    'assets/images/onboarding/frame4.png',
    'assets/images/onboarding/frame3.png',
  ];

  @override
  void initState() {
    super.initState();
    
    // Float animation for gentle bobbing
    _floatController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    )..repeat(reverse: true);

    // Frame animation controllers - smoother duration
    _frameController1 = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _frameController2 = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _frameController3 = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    // Sequential animation: Marker1 → Marker2 → Marker3 (profile)
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _frameController1.forward();
    });
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) _frameController2.forward();
    });
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) _frameController3.forward();
    });
  }

  @override
  void dispose() {
    _frameController1.dispose();
    _frameController2.dispose();
    _frameController3.dispose();
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Cache the static map container to avoid rebuilding it on every frame
    final staticMapContainer = Container(
      width: 262,
      height: 322,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: CustomPaint(
          painter: MapGridPainter(),
          size: const Size(262, 322),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: Listenable.merge([
        _frameController1,
        _frameController2,
        _frameController3,
        _floatController,
      ]),
      builder: (context, child) {
        return SizedBox(
          width: 290,
          height: 360,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Map Container (cached, doesn't rebuild)
              child!,
              
              // MARKER 1 - Left side (animates to spa profile)
              Positioned(
                bottom: 150 + (_floatController.value * 3 - 1.5),
                left: 30,
                child: _buildFrameAnimatedMarker(
                  _frameController1,
                  _profile1Frames,
                  size: 70,
                  popFromBottom: true,
                ),
              ),
              
              // MARKER 2 - Bottom right (animates to profile)
              Positioned(
                bottom: 80 + (_floatController.value * 4 - 2),
                right: 50,
                child: _buildFrameAnimatedMarker(
                  _frameController2,
                  _profile2Frames,
                  size: 65,
                  popFromBottom: true,
                ),
              ),
              
              // MARKER 3 - Top right (animates to hairstylist profile)
              Positioned(
                bottom: 200 + (_floatController.value * 5 - 2.5),
                right: 25,
                child: _buildFrameAnimatedMarker(
                  _frameController3,
                  _profile3Frames,
                  size: 80,
                  popFromBottom: true,
                ),
              ),
            ],
          ),
        );
      },
      child: staticMapContainer, // Pass static widget as child to cache it
    );
  }

  // Build marker with smooth crossfade animation
  Widget _buildFrameAnimatedMarker(
    AnimationController controller,
    List<String> frames,
    {double size = 60, bool popFromBottom = false}
  ) {
    // Phase 1: Pin appears (0.0 - 0.5)
    // Phase 2: Profile fades in on top (0.5 - 1.0)
    
    final pinProgress = (controller.value * 2).clamp(0.0, 1.0);
    final profileProgress = ((controller.value - 0.5) * 2).clamp(0.0, 1.0);
    
    // Pin frame (frame4 - pin with glow)
    final pinFrame = frames.length > 2 ? frames[2] : frames.last;
    // Profile frame (last frame - full profile)
    final profileFrame = frames.last;
    
    // Pin scale and opacity
    final pinScale = Curves.easeOutBack.transform(pinProgress);
    final pinOpacity = pinProgress;
    
    // Profile scale and opacity (fades in smoothly)
    final profileScale = Curves.easeOutCubic.transform(profileProgress);
    final profileOpacity = Curves.easeInOut.transform(profileProgress);
    
    return SizedBox(
      width: size,
      height: size * 1.5, // Extra height to accommodate profile above pin
      child: Stack(
        alignment: Alignment.bottomCenter, // Align to bottom where pin is
        children: [
          // Pin layer (stays visible, fades out when profile appears)
          Opacity(
            opacity: pinOpacity * (1 - profileOpacity),
            child: Transform.scale(
              scale: pinScale,
              alignment: Alignment.center,
              child: Image.asset(
                pinFrame,
                width: size * 0.5,
                height: size * 0.5,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const SizedBox(),
              ),
            ),
          ),
          // Profile layer (fades in, aligned so pin part matches)
          if (profileProgress > 0)
            Opacity(
              opacity: profileOpacity,
              child: Transform.scale(
                scale: profileScale,
                alignment: Alignment.bottomCenter, // Scale from bottom (where pin is)
                child: Image.asset(
                  profileFrame,
                  width: size,
                  height: size * 1.3,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const SizedBox(),
                ),
              ),
            ),
        ],
      ),
    );
  }

}

class MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Light gray background
    final bgPaint = Paint()..color = const Color(0xFFEEEEEE);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);
    
    // Road paint (white roads)
    final roadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Grid lines (thinner roads)
    final gridPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // Draw main grid
    const spacing = 45.0;
    
    // Vertical roads
    for (double x = spacing; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    
    // Horizontal roads
    for (double y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Main curved diagonal road (top-left to bottom-right style)
    final curvedRoad1 = Path();
    curvedRoad1.moveTo(0, size.height * 0.25);
    curvedRoad1.cubicTo(
      size.width * 0.2, size.height * 0.3,
      size.width * 0.3, size.height * 0.45,
      size.width * 0.35, size.height * 0.55,
    );
    curvedRoad1.cubicTo(
      size.width * 0.4, size.height * 0.7,
      size.width * 0.5, size.height * 0.8,
      size.width * 0.7, size.height,
    );
    canvas.drawPath(curvedRoad1, roadPaint);

    // Second curved road
    final curvedRoad2 = Path();
    curvedRoad2.moveTo(size.width * 0.1, 0);
    curvedRoad2.cubicTo(
      size.width * 0.15, size.height * 0.15,
      size.width * 0.1, size.height * 0.35,
      size.width * 0.2, size.height * 0.5,
    );
    curvedRoad2.cubicTo(
      size.width * 0.3, size.height * 0.65,
      size.width * 0.25, size.height * 0.85,
      size.width * 0.4, size.height,
    );
    canvas.drawPath(curvedRoad2, roadPaint);

    // Third curved road (upper area)
    final curvedRoad3 = Path();
    curvedRoad3.moveTo(0, size.height * 0.6);
    curvedRoad3.cubicTo(
      size.width * 0.25, size.height * 0.55,
      size.width * 0.4, size.height * 0.4,
      size.width * 0.6, size.height * 0.35,
    );
    curvedRoad3.cubicTo(
      size.width * 0.8, size.height * 0.3,
      size.width * 0.9, size.height * 0.2,
      size.width, size.height * 0.15,
    );
    canvas.drawPath(curvedRoad3, roadPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ============== PHONE ILLUSTRATION ==============
class PhoneIllustration extends StatefulWidget {
  const PhoneIllustration({super.key});

  @override
  State<PhoneIllustration> createState() => _PhoneIllustrationState();
}

class _PhoneIllustrationState extends State<PhoneIllustration>
    with TickerProviderStateMixin {
  late AnimationController _floatController;
  late AnimationController _buttonStateController;
  int _currentButtonState = 0;

  // Button state assets
  final List<String> _buttonAssets = [
    'assets/images/onboarding/Property 1=Default.svg',
    'assets/images/onboarding/Property 1=Variant2.svg',
    'assets/images/onboarding/Property 1=Variant3.svg',
    'assets/images/onboarding/Property 1=Variant4.svg',
  ];

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    )..repeat(reverse: true);

    _buttonStateController = AnimationController(
      duration: const Duration(seconds: 6), // Total cycle duration
      vsync: this,
    )..repeat();

    // Update button state based on animation progress
    _buttonStateController.addListener(() {
      final progress = _buttonStateController.value;
      int newState;
      if (progress < 0.25) {
        newState = 0; // Default
      } else if (progress < 0.5) {
        newState = 1; // Variant2
      } else if (progress < 0.75) {
        newState = 2; // Variant3
      } else {
        newState = 3; // Variant4
      }

      if (newState != _currentButtonState) {
    setState(() {
          _currentButtonState = newState;
        });
      }
    });
  }

  @override
  void dispose() {
    _floatController.dispose();
    _buttonStateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_floatController, _buttonStateController]),
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _floatController.value * 8 - 4),
          child: Container(
            width: 220,
            height: 300,
            decoration: BoxDecoration(
              color: const Color(0xFF3D3D7B),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF3D3D7B).withValues(alpha: 0.25),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F0F5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 30),
                    // Placeholder lines
                    _buildPlaceholderLine(0.75),
                    const SizedBox(height: 10),
                    _buildPlaceholderLine(0.55),
                    const Spacer(),
                    // Animated Apply Now Button with SVG states
                    Padding(
                      padding: AppResponsive.formScreenPadding(context),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 500),
                        transitionBuilder: (Widget child, Animation<double> animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(
                              scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                                CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeInOut,
                                ),
                              ),
                              child: child,
                            ),
                          );
                        },
                        child: SvgPicture.asset(
                          _buttonAssets[_currentButtonState],
                          key: ValueKey<int>(_currentButtonState),
                          width: 180,
                          height: 45,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 25),
                    // Small circle indicator
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: const Color(0xFF7DD3C0),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaceholderLine(double widthFactor) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: 14,
        decoration: BoxDecoration(
          color: const Color(0xFF3D3D7B).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(7),
        ),
      ),
    );
  }
}

// ============== PROFILE ILLUSTRATION ==============
class ProfileIllustration extends StatefulWidget {
  const ProfileIllustration({super.key});

  @override
  State<ProfileIllustration> createState() => _ProfileIllustrationState();
}

class _ProfileIllustrationState extends State<ProfileIllustration>
    with SingleTickerProviderStateMixin {
  late AnimationController _scrollController;

  @override
  void initState() {
    super.initState();
    // Animate through all 3 states (0 -> 1 -> 2) then loop
    _scrollController = AnimationController(
      duration: const Duration(milliseconds: 4000),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 290,
      height: 360,
      child: AnimatedBuilder(
        animation: _scrollController,
        builder: (context, child) {
          final progress = _scrollController.value;
          
          // Calculate opacity for each card with smooth transitions
          double card1Opacity = 1.0;
          double card2Opacity = 0.0;
          double card3Opacity = 0.0;
          
          // Card 1 to Card 2 transition (0.28 to 0.38)
          if (progress >= 0.28 && progress <= 0.38) {
            final transitionProgress = (progress - 0.28) / 0.1;
            card1Opacity = 1.0 - transitionProgress;
            card2Opacity = transitionProgress;
          } else if (progress > 0.38 && progress < 0.61) {
            card1Opacity = 0.0;
            card2Opacity = 1.0;
          } 
          // Card 2 to Card 3 transition (0.61 to 0.71)
          else if (progress >= 0.61 && progress <= 0.71) {
            final transitionProgress = (progress - 0.61) / 0.1;
            card2Opacity = 1.0 - transitionProgress;
            card3Opacity = transitionProgress;
          } else if (progress > 0.71 && progress < 0.94) {
            card2Opacity = 0.0;
            card3Opacity = 1.0;
          }
          // Card 3 to Card 1 transition (0.94 to 1.0)
          else if (progress >= 0.94) {
            final transitionProgress = (progress - 0.94) / 0.06;
            card3Opacity = 1.0 - transitionProgress;
            card1Opacity = transitionProgress;
          }
          
          return Stack(
            alignment: Alignment.center,
            children: [
              // Card 1
              if (card1Opacity > 0)
                Opacity(
                  opacity: card1Opacity.clamp(0.0, 1.0),
                  child: SvgPicture.asset(
                    'assets/images/onboarding/profile_card_1.svg',
                    width: 290,
                    height: 360,
                    fit: BoxFit.contain,
                  ),
                ),
              // Card 2
              if (card2Opacity > 0)
                Opacity(
                  opacity: card2Opacity.clamp(0.0, 1.0),
                  child: SvgPicture.asset(
                    'assets/images/onboarding/profile_card_2.svg',
                    width: 290,
                    height: 360,
                    fit: BoxFit.contain,
                  ),
                ),
              // Card 3
              if (card3Opacity > 0)
                Opacity(
                  opacity: card3Opacity.clamp(0.0, 1.0),
                  child: SvgPicture.asset(
                    'assets/images/onboarding/profile_card_3.svg',
                    width: 290,
                    height: 360,
                    fit: BoxFit.contain,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ============== ADD PHONE NUMBER SCREEN ==============
class AddPhoneNumberScreen extends StatefulWidget {
  final Language selectedLanguage;
  
  const AddPhoneNumberScreen({
    super.key,
    required this.selectedLanguage,
  });

  @override
  State<AddPhoneNumberScreen> createState() => _AddPhoneNumberScreenState();
}

class _AddPhoneNumberScreenState extends State<AddPhoneNumberScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final ApiService _apiService = ApiService();
  bool _isButtonEnabled = false;
  bool _isLoading = false;
  String? _errorMessage;
  late AppLocalizations _localizations;

  @override
  void initState() {
    super.initState();
    _localizations = AppLocalizations(widget.selectedLanguage);
    _phoneController.addListener(_onPhoneChanged);
  }

  @override
  void dispose() {
    _phoneController.removeListener(_onPhoneChanged);
    _phoneController.dispose();
    super.dispose();
  }

  void _onPhoneChanged() {
    setState(() {
      final phoneText = _phoneController.text.trim();
      _isButtonEnabled = phoneText.length == 10;
      _errorMessage = null; // Clear error when user types
    });
  }

  Future<void> _sendOtp() async {
    if (_isLoading || !_isButtonEnabled) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final phoneNumber = _phoneController.text.trim();
      final smsHash = await androidSmsRetrieverHash();
      final response = await _apiService.sendOtp(phoneNumber, countryCode: '+91', smsAppHash: smsHash);

      if (!mounted) return;

      if (response.success) {
        // Navigate to OTP screen
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => OtpVerificationScreen(
              phoneNumber: '+91$phoneNumber',
              selectedLanguage: widget.selectedLanguage,
            ),
          ),
        );
      } else {
        setState(() {
          // Handle rate limiting
          if (response.waitSeconds != null) {
            _errorMessage = widget.selectedLanguage == Language.hindi
                ? 'कृपया ${response.waitSeconds} सेकंड बाद पुनः प्रयास करें'
                : 'Please wait ${response.waitSeconds} seconds before trying again';
          } else {
            _errorMessage = response.message ?? 
              (widget.selectedLanguage == Language.hindi 
                ? 'ओटीपी भेजने में समस्या हुई' 
                : 'Failed to send OTP');
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = widget.selectedLanguage == Language.hindi
              ? 'कुछ गलत हो गया। पुनः प्रयास करें।'
              : 'Something went wrong. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: AppResponsive.formScreenPadding(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      
                      // Header with back button and title
                      Row(
                        children: [
                          // Back button
                          InkWell(
                            onTap: () => Navigator.of(context).pop(),
                            child: SvgPicture.asset(
                              'assets/images/screen 2/Frame 1299.svg',
                              width: 40,
                              height: 40,
                            ),
                          ),
                          const Spacer(),
                          // Title text "Add phone number 1 / 2"
                          Text(
                            _localizations.addPhoneNumberTitle,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF121A2C),
                            ),
                          ),
                          const Spacer(),
                          const SizedBox(width: 40), // Balance the back button width
                        ],
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Progress indicator
                      Row(
          mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SvgPicture.asset(
                            'assets/images/screen 2/Step 1.svg',
                            width: 20,
                            height: 4,
                          ),
                          const SizedBox(width: 8),
                          SvgPicture.asset(
                            'assets/images/screen 2/Step 2.svg',
                            width: 20,
                            height: 4,
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 32),
                      
                      // Phone Number label
                      Text(
                        _localizations.phoneNumberLabel,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF121A2C),
                        ),
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // Phone input field - custom container to match Figma design
                      Container(
                        width: double.infinity,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF9EA1A8),
                            width: 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              // Country code
                              const Text(
                                '+91',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                  color: Color(0xFF121A2C),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Dropdown arrow
                              const Icon(
                                Icons.keyboard_arrow_down,
                                size: 20,
                                color: Color(0xFF121A2C),
                              ),
                              const SizedBox(width: 12),
                              // Divider
                              Container(
                                width: 1,
                                height: 24,
                                color: const Color(0xFF9EA1A8),
                              ),
                              const SizedBox(width: 12),
                              // Phone number input
                              Expanded(
                                child: TextField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  maxLength: 10,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w400,
                                    color: Color(0xFF121A2C),
                                  ),
                                  decoration: InputDecoration(
                                    hintText: _localizations.enterPhoneNumberHint,
                                    hintStyle: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w400,
                                      color: Color(0xFF9EA1A8),
                                    ),
                                    border: InputBorder.none,
                                    counterText: '',
                                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
            
            // Error message
            if (_errorMessage != null)
              Padding(
                padding: AppResponsive.formScreenPadding(context),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            
            if (_errorMessage != null) const SizedBox(height: 12),
            
            // Helper text above Continue button
            Padding(
              padding: AppResponsive.formScreenPadding(context),
              child: Center(
                child: Text(
                  _localizations.helperTextMobile,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Continue button at the bottom
            Padding(
              padding: AppResponsive.formScreenPadding(context),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: (_isButtonEnabled && !_isLoading) ? _sendOtp : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (_isButtonEnabled && !_isLoading)
                        ? const Color(0xFF3D3D7B) 
                        : Colors.grey.shade300,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          _localizations.continueButton,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _isButtonEnabled 
                                ? Colors.white 
                                : Colors.grey.shade700,
                          ),
                        ),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Terms and Privacy text at the bottom
            Padding(
              padding: AppResponsive.formScreenPadding(context),
              child: Center(
                child: Text(
                  _localizations.termsPrivacyText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ============== OTP VERIFICATION SCREEN ==============
class OtpVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final Language selectedLanguage;
  
  const OtpVerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.selectedLanguage,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> with CodeAutoFill {
  final List<TextEditingController> _otpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  final ApiService _apiService = ApiService();
  String? _appSignature;
  late AppLocalizations _localizations;
  bool _isVerifying = false;
  bool _isResending = false;
  String? _errorMessage;
  int? _attemptsRemaining;
  int _resendCooldown = 0;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _localizations = AppLocalizations(widget.selectedLanguage);
    listenForCode(smsCodeRegexPattern: r'\d{6}');
    _getAppSignature();
    _startResendCooldown();
  }

  void _startResendCooldown() {
    _resendCooldown = 30; // 30 seconds cooldown
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldown > 0) {
        setState(() {
          _resendCooldown--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _getAppSignature() async {
    try {
      _appSignature = await SmsAutoFill().getAppSignature;
      if (_appSignature != null && _appSignature!.length != 11) {
        _appSignature = null;
      }
    } catch (e) {
      // Handle error silently
    }
  }

  @override
  void codeUpdated() {
    final receivedCode = code;
    if (receivedCode != null && receivedCode.length == 6) {
      if (!mounted) return;
      setState(() {
        for (int i = 0; i < 6; i++) {
          _otpControllers[i].text = receivedCode[i];
        }
      });
      _focusNodes[5].unfocus();
      _verifyOTP();
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    cancel();
    unregisterListener();
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _onOtpChanged(int index, String value) {
    setState(() {
      _errorMessage = null; // Clear error when user types
      if (value.length == 1 && index < 5) {
        _focusNodes[index + 1].requestFocus();
      } else if (value.isEmpty && index > 0) {
        _focusNodes[index - 1].requestFocus();
      }
      
      // Check if all OTP fields are filled
      if (value.length == 1 && index == 5) {
        _verifyOTP();
      }
    });
  }

  String _getPhoneNumberOnly() {
    // Extract just the 10-digit number from +91XXXXXXXXXX
    final phone = widget.phoneNumber;
    if (phone.startsWith('+91')) {
      return phone.substring(3);
    }
    return phone.replaceAll(RegExp(r'[^0-9]'), '');
  }

  Future<void> _verifyOTP() async {
    if (_isVerifying) return;

    // Collect all OTP digits
    String otp = '';
    for (var controller in _otpControllers) {
      otp += controller.text;
    }
    
    // Check if all fields are filled
    if (otp.length != 6) return;

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      final phoneNumber = _getPhoneNumberOnly();
      final response = await _apiService.verifyOtp(phoneNumber, otp, countryCode: '+91');

      if (!mounted) return;

      if (response.success && response.data != null) {
        final result = response.data!;

        // CASE 1: Existing owner → Owner Dashboard
        if (result.ownerExists) {
          await AuthService().saveUserRole('salon');
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => JobOwnerHomeScreen(selectedLanguage: widget.selectedLanguage)),
            (route) => false,
          );
        }
        // CASE 2: Existing seeker → exchange salon JWT for seeker JWT, then dashboard
        else if (result.seekerExists) {
          final switchResult = await _apiService.switchToSeeker();
          if (!mounted) return;
          if (switchResult.success) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => SeekerHomeScreen(selectedLanguage: widget.selectedLanguage)),
              (route) => false,
            );
          } else {
            setState(() => _errorMessage = switchResult.message ?? 'Failed to open seeker account');
          }
          return;
        }
        // CASE 3: New user → Account Created → Role Selection
        else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => AccountCreatedSuccessScreen(
                selectedLanguage: widget.selectedLanguage,
                isNewUser: true,
              ),
            ),
          );
        }
      } else {
        setState(() {
          _attemptsRemaining = response.attemptsRemaining;
          if (_attemptsRemaining != null && _attemptsRemaining! <= 0) {
            _errorMessage = widget.selectedLanguage == Language.hindi
                ? 'बहुत अधिक प्रयास। कृपया नया ओटीपी प्राप्त करें।'
                : 'Too many attempts. Please request a new OTP.';
            // Clear OTP fields
            for (var controller in _otpControllers) {
              controller.clear();
            }
            _focusNodes[0].requestFocus();
          } else {
            _errorMessage = response.message ?? 
              (widget.selectedLanguage == Language.hindi 
                ? 'गलत ओटीपी। पुनः प्रयास करें।' 
                : 'Invalid OTP. Please try again.');
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = widget.selectedLanguage == Language.hindi
              ? 'कुछ गलत हो गया। पुनः प्रयास करें।'
              : 'Something went wrong. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isVerifying = false;
        });
      }
    }
  }

  Future<void> _resendOtp() async {
    if (_isResending || _resendCooldown > 0) return;

    setState(() {
      _isResending = true;
      _errorMessage = null;
    });

    try {
      final phoneNumber = _getPhoneNumberOnly();
      final smsHash = Platform.isAndroid
          ? (_appSignature != null && _appSignature!.length == 11
              ? _appSignature
              : await androidSmsRetrieverHash())
          : null;
      final response = await _apiService.resendOtp(phoneNumber, countryCode: '+91', smsAppHash: smsHash);

      if (!mounted) return;

      if (response.success) {
        // Clear existing OTP
        for (var controller in _otpControllers) {
          controller.clear();
        }
        _focusNodes[0].requestFocus();
        _startResendCooldown();
        
        // Show success message briefly
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.selectedLanguage == Language.hindi
                  ? 'ओटीपी पुनः भेजा गया'
                  : 'OTP sent again',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        setState(() {
          if (response.waitSeconds != null) {
            _resendCooldown = response.waitSeconds!;
            _startResendCooldown();
          }
          _errorMessage = response.message ?? 
            (widget.selectedLanguage == Language.hindi 
              ? 'ओटीपी भेजने में समस्या हुई' 
              : 'Failed to resend OTP');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = widget.selectedLanguage == Language.hindi
              ? 'कुछ गलत हो गया।'
              : 'Something went wrong.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: AppResponsive.formScreenPadding(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      
                      // Header with back button and title
                      Row(
                        children: [
                          // Back button
                          InkWell(
                            onTap: () => Navigator.of(context).pop(),
                            child: SvgPicture.asset(
                              'assets/images/screen 2/Frame 1299.svg',
                              width: 40,
                              height: 40,
                            ),
                          ),
                          const Spacer(),
                          // Title text "Verify your number 2 / 2"
                          Text(
                            _localizations.verifyNumberTitle,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF121A2C),
                            ),
                          ),
                          const Spacer(),
                          const SizedBox(width: 40), // Balance the back button width
                        ],
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Progress indicator - Step 1 (purple), Step 2 (purple - active)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SvgPicture.asset(
                            'assets/images/screen 2/Step 1.svg',
                            width: 20,
                            height: 4,
                          ),
                          const SizedBox(width: 8),
                          SvgPicture.asset(
                            'assets/images/screen 2/Step 2 (1).svg',
                            width: 20,
                            height: 4,
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 32),
                      
                      // Text: "We have sent an OTP to your number" - First line, centered
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                _localizations.otpSentMessage,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                  color: Color(0xFF121A2C),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Edit icon (pencil)
                            GestureDetector(
                              onTap: () {
                                // Navigate back to edit phone number
                                Navigator.of(context).pop();
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                    color: Color(0xFF3D3D7B),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    widget.phoneNumber,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w400,
                                      color: Color(0xFF3D3D7B),
                                      decoration: TextDecoration.underline,
                                      decorationColor: Color(0xFF3D3D7B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Label "Code"
                      Text(
                        _localizations.codeLabel,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF121A2C),
                        ),
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // OTP input fields - 6 boxes
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(6, (index) {
                          return Padding(
                            padding: EdgeInsets.only(left: index == 0 ? 0 : 10),
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: TextField(
                                controller: _otpControllers[index],
                                focusNode: _focusNodes[index],
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                maxLength: 1,
                                autofillHints: const [AutofillHints.oneTimeCode],
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF121A2C),
                                ),
                                decoration: InputDecoration(
                                  counterText: '',
                                  contentPadding: EdgeInsets.zero,
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF9EA1A8),
                                      width: 1,
                                    ),
                                  ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF9EA1A8),
                                    width: 1,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF3D3D7B),
                                    width: 2,
                                  ),
                                ),
                              ),
                              onChanged: (value) => _onOtpChanged(index, value),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              ),
                            ),
                          );
                        }),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Error message
                      if (_errorMessage != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      
                      // Loading indicator
                      if (_isVerifying)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3D3D7B)),
                              ),
                            ),
                          ),
                        ),
                      
                      const SizedBox(height: 32),
                      
                      // Resend OTP section
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _localizations.didNotReceiveOtp,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: (_resendCooldown > 0 || _isResending) ? null : _resendOtp,
                            child: _isResending
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3D3D7B)),
                                    ),
                                  )
                                : Text(
                                    _resendCooldown > 0
                                        ? '${_localizations.resendOtp} (${_resendCooldown}s)'
                                        : _localizations.resendOtp,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w400,
                                      color: _resendCooldown > 0 
                                          ? Colors.grey.shade400 
                                          : const Color(0xFF3D3D7B),
                                      decoration: _resendCooldown > 0 
                                          ? TextDecoration.none 
                                          : TextDecoration.underline,
                                      decorationColor: const Color(0xFF3D3D7B),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
            
            // Terms and Privacy Policy at the bottom
            Padding(
              padding: AppResponsive.screenPaddingAll(context),
              child: Center(
                child: Text(
                  _localizations.termsPrivacyText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: Colors.grey.shade600,
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


// ============== ACCOUNT CREATED SUCCESS SCREEN ==============
class AccountCreatedSuccessScreen extends StatefulWidget {
  final Language selectedLanguage;
  final bool isNewUser;
  
  const AccountCreatedSuccessScreen({
    super.key,
    required this.selectedLanguage,
    this.isNewUser = true,
  });

  @override
  State<AccountCreatedSuccessScreen> createState() => _AccountCreatedSuccessScreenState();
}

class _AccountCreatedSuccessScreenState extends State<AccountCreatedSuccessScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late AppLocalizations _localizations;

  @override
  void initState() {
    super.initState();
    _localizations = AppLocalizations(widget.selectedLanguage);
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    ));

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return Opacity(
                opacity: _fadeAnimation.value,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Green checkmark circle
                    Transform.scale(
                      scale: _scaleAnimation.value,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: const BoxDecoration(
                          color: Color(0xFF8BC34A), // Light green
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 60,
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 40),
                    
                    // "Your account was successfully created!" text
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        _localizations.accountCreatedSuccess,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // "Welcome to Jobtree family!!!" text
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        _localizations.welcomeToJobtree,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 60),
                    
                    // Continue button
                    Padding(
                      padding: AppResponsive.formScreenPadding(context),
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (context) => RoleSelectionScreen(
                                  selectedLanguage: widget.selectedLanguage,
                                ),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3D3D7B),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            _localizations.continueArrow,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ============== ROLE SELECTION SCREEN ==============
enum UserRole {
  jobSeeker,  // "I want job"
  employer,   // "I want staff"
}

class RoleSelectionScreen extends StatefulWidget {
  final Language selectedLanguage;
  
  const RoleSelectionScreen({
    super.key,
    required this.selectedLanguage,
  });

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  UserRole? _selectedRole;
  late AppLocalizations _localizations;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _localizations = AppLocalizations(widget.selectedLanguage);
  }

  /// "I Want Job" — uses existing authenticated session (no new OTP).
  /// Switches to seeker token, checks profile, and routes accordingly.
  Future<void> _handleIWantJob() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final apiService = ApiService();

      // Switch role: gets a seeker JWT using the existing salon auth
      final switchResult = await apiService.switchToSeeker();

      if (!mounted) return;

      if (switchResult.success && switchResult.data != null) {
        final result = switchResult.data!;

        if (result.seekerProfileExists) {
          // Existing seeker profile → go to seeker dashboard
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => SeekerHomeScreen(selectedLanguage: widget.selectedLanguage)),
            (route) => false,
          );
        } else {
          // No seeker profile yet → go to minimal onboarding
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => SeekerCreateProfileScreen(selectedLanguage: widget.selectedLanguage)),
            (route) => false,
          );
        }
      } else {
        // Show error toast
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(switchResult.message ?? 'Failed to switch role')),
        );
      }
    } catch (e) {
      print('Error handling I Want Job: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Something went wrong')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: AppResponsive.formScreenPadding(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 40),
                      
                      // Title: "Choose your Role"
                      Center(
                        child: Text(
                          _localizations.chooseYourRole,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF121A2C),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 40),
                      
                      // "I want job" Card → Use existing auth, route to seeker flow
                      _buildRoleCard(
                        title: _localizations.iWantJob,
                        subtitle: _localizations.iWantJobSubtitle,
                        icon: _buildJobSeekerIcon(),
                        isSelected: _selectedRole == UserRole.jobSeeker,
                        onTap: () => _handleIWantJob(),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // "I want staff" Card
                      _buildRoleCard(
                        title: _localizations.iWantStaff,
                        subtitle: _localizations.iWantStaffSubtitle,
                        icon: _buildEmployerIcon(),
                        isSelected: _selectedRole == UserRole.employer,
                        onTap: () async {
                          // Save role as salon owner and open the job posting flow
                          await AuthService().saveUserRole('salon');
                          if (!mounted) return;
                          openQuickJobFlow(context, widget.selectedLanguage);
                        },
                      ),
                      
                      const SizedBox(height: 40),
          ],
        ),
      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required String title,
    required String subtitle,
    required Widget icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: AppResponsive.cardPaddingInsets(context),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected 
                ? const Color(0xFF3D3D7B) 
                : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF121A2C),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            icon,
          ],
        ),
      ),
    );
  }

  Widget _buildJobSeekerIcon() {
    // Magnifying glass over calendar/map with '1' inside
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Calendar/map icon
          Icon(
            Icons.calendar_month,
            size: 36,
            color: Colors.grey.shade400,
          ),
          // Magnifying glass overlay with '1'
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // '1' inside
                  Text(
                    '1',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Magnifying glass handle
          Positioned(
            right: 18,
            top: 22,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: const BorderRadius.only(
                  bottomRight: Radius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployerIcon() {
    // Barber chair with scissors and plus sign
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Chair icon
          Icon(
            Icons.chair_alt,
            size: 36,
            color: Colors.grey.shade400,
          ),
          // Scissors icon on top
          Positioned(
            top: 10,
            child: Icon(
              Icons.content_cut,
              size: 18,
              color: Colors.grey.shade500,
            ),
          ),
          // Plus sign on the right
          Positioned(
            right: 8,
            bottom: 10,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.add,
                size: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============== CHOOSE YOUR JOB SCREEN ==============
class ChooseYourJobScreen extends StatefulWidget {
  final Language selectedLanguage;
  final UserRole selectedRole;
  
  const ChooseYourJobScreen({
    super.key,
    required this.selectedLanguage,
    required this.selectedRole,
  });

  @override
  State<ChooseYourJobScreen> createState() => _ChooseYourJobScreenState();
}

class _ChooseYourJobScreenState extends State<ChooseYourJobScreen> {
  String? _selectedJobType;
  String? _preferredCity;
  final TextEditingController _preferredCityController = TextEditingController();
  List<String> _allCities = [];
  bool _isLoadingCities = false;
  late AppLocalizations _localizations;

  @override
  void initState() {
    super.initState();
    _localizations = AppLocalizations(widget.selectedLanguage);
    _loadStaticCities();
    Future.microtask(() {
      _loadCitiesFromAPI();
    });
  }

  @override
  void dispose() {
    _preferredCityController.dispose();
    super.dispose();
  }

  bool get _isFormValid {
    return _selectedJobType != null && _preferredCity != null;
  }

  Future<void> _loadCitiesFromAPI() async {
    try {
      http.Response? response;
      
      try {
        response = await http.get(
          Uri.parse('https://raw.githubusercontent.com/thatisuday/indian-cities-database/master/cities.json'),
        ).timeout(const Duration(seconds: 8));
      } catch (e) {
        return;
      }

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        try {
          final dynamic data = json.decode(response.body);
          
          List<String> cities = [];
          
          if (data is List) {
            for (var city in data) {
              try {
                if (city is Map) {
                  final name = city['name'] as String? ?? city['city'] as String? ?? '';
                  if (name.isNotEmpty) cities.add(name);
                } else if (city is String && city.isNotEmpty) {
                  cities.add(city);
                }
              } catch (e) {
                continue;
              }
            }
            cities.sort();
          } else if (data is Map && data['data'] != null) {
            try {
              final List<dynamic> cityList = data['data'] as List;
              for (var city in cityList) {
                try {
                  if (city is Map) {
                    final name = city['name'] as String? ?? city['city'] as String? ?? '';
                    if (name.isNotEmpty) cities.add(name);
                  } else if (city is String && city.isNotEmpty) {
                    cities.add(city);
                  }
                } catch (e) {
                  continue;
                }
              }
              cities.sort();
            } catch (e) {
              return;
            }
          }
          
          if (cities.isNotEmpty && mounted) {
            setState(() {
              _allCities = cities;
            });
          }
        } catch (e) {
          // JSON parsing failed, keep static cities
        }
      }
    } catch (e) {
      // Silently fail
    }
  }

  void _loadStaticCities() {
    final staticCities = [
      'Mumbai', 'Delhi', 'Bangalore', 'Hyderabad', 'Ahmedabad', 'Chennai',
      'Kolkata', 'Surat', 'Pune', 'Jaipur', 'Lucknow', 'Kanpur', 'Nagpur',
      'Indore', 'Thane', 'Bhopal', 'Visakhapatnam', 'Patna', 'Vadodara',
      'Ghaziabad', 'Ludhiana', 'Agra', 'Nashik', 'Faridabad', 'Meerut',
      'Rajkot', 'Varanasi', 'Srinagar', 'Amritsar', 'Aurangabad', 'Dhanbad',
      'Navi Mumbai', 'Allahabad', 'Howrah', 'Gwalior', 'Jabalpur', 'Coimbatore',
      'Vijayawada', 'Jodhpur', 'Madurai', 'Raipur', 'Kota', 'Chandigarh',
      'Guwahati', 'Solapur', 'Hubli-Dharwad', 'Bareilly', 'Moradabad', 'Mysore',
      'Gurgaon', 'Aligarh', 'Jalandhar', 'Tiruchirappalli', 'Bhubaneswar', 'Salem',
      'Warangal', 'Mira-Bhayandar', 'Thiruvananthapuram', 'Bhiwandi', 'Saharanpur',
      'Guntur', 'Amravati', 'Bikaner', 'Noida', 'Jamshedpur', 'Bhilai', 'Cuttack',
      'Firozabad', 'Kochi', 'Nellore', 'Bhavnagar', 'Dehradun', 'Durgapur',
      'Asansol', 'Rourkela', 'Nanded', 'Kolhapur', 'Ajmer', 'Akola', 'Gulbarga',
      'Jamnagar', 'Ujjain', 'Loni', 'Siliguri', 'Jhansi', 'Ulhasnagar', 'Jammu',
      'Sangli-Miraj', 'Mangalore', 'Erode', 'Belgaum', 'Ambattur', 'Tirunelveli',
      'Malegaon', 'Gaya', 'Jalgaon', 'Udaipur', 'Maheshtala', 'Tirupur',
      'Davanagere', 'Kozhikode', 'Kurnool', 'Rajahmundry', 'Bokaro', 'South Dumdum',
      'Bellary', 'Patiala', 'Gopalpur', 'Agartala', 'Bhagalpur', 'Muzaffarnagar',
      'Bhatpara', 'Panihati', 'Latur', 'Dhule', 'Rohtak', 'Korba', 'Bhilwara',
      'Brahmapur', 'Muzaffarpur', 'Ahmednagar', 'Mathura', 'Kollam', 'Avadi',
      'Kadapa', 'Anantapur', 'Kamarhati', 'Sambalpur', 'Bilaspur', 'Shahjahanpur',
      'Satara', 'Bijapur', 'Rampur', 'Shivamogga', 'Chandrapur', 'Junagadh',
      'Thrissur', 'Alwar', 'Bardhaman', 'Kulti', 'Kakinada', 'Nizamabad',
      'Parbhani', 'Tumkur', 'Khammam', 'Ozhukarai', 'Bihar Sharif', 'Panipat',
      'Darbhanga', 'Bally', 'Aizawl', 'Dewas', 'Ichalkaranji', 'Karnal',
      'Bathinda', 'Jalna', 'Eluru', 'Barasat', 'Kirari Suleman Nagar', 'Purnia',
      'Satna', 'Mau', 'Sonipat', 'Farrukhabad', 'Sagar', 'Rourkela', 'Durg',
      'Imphal', 'Ratlam', 'Hapur', 'Arrah', 'Karimnagar', 'Anantapur', 'Etawah',
      'Bharatpur', 'Begusarai', 'New Delhi', 'Gandhidham', 'Baranagar', 'Tiruvottiyur',
      'Pondicherry', 'Sikar', 'Thoothukudi', 'Rewa', 'Mirzapur', 'Raichur',
      'Pali', 'Ramagundam', 'Silchar', 'Haridwar', 'Vijayanagaram', 'Tenali',
      'Nagercoil', 'Sri Ganganagar', 'Karawal Nagar', 'Mango', 'Thanjavur',
      'Bulandshahr', 'Uluberia', 'Katni', 'Sambhal', 'Singrauli', 'Nadiad',
      'Secunderabad', 'Naihati', 'Yamunanagar', 'Bidhannagar', 'Pallavaram',
      'Bidar', 'Munger', 'Panchkula', 'Burhanpur', 'Raurkela Industrial Township',
      'Kharagpur', 'Dindigul', 'Gandhinagar', 'Hospet', 'Nangloi Jat', 'Malda',
      'Ongole', 'Deoghar', 'Chapra', 'Haldia', 'Khandwa', 'Nandyal', 'Chittoor',
      'Morena', 'Amroha', 'Anand', 'Bhind', 'Bhalswa Jahangir Pur', 'Madhyamgram',
      'Bhiwani', 'Berhampore', 'Ambala', 'Fatehpur', 'Raebareli', 'Khora',
      'Chittorgarh', 'Bhusawal', 'Orai', 'Bahraich', 'Phusro', 'Vellore',
      'Mehsana', 'Raiganj', 'Sirsa', 'Danapur', 'Serampore', 'Sultan Pur Majra',
      'Guna', 'Jaunpur', 'Panvel', 'Shivpuri', 'Surendranagar Dudhrej', 'Unnao',
      'Chinsurah', 'Veraval', 'Alappuzha', 'Kottayam', 'Machilipatnam', 'Shimla',
      'Adoni', 'Udupi', 'Vizianagaram', 'Katihar', 'Hardwar', 'Suryapet',
      'Miryalaguda', 'Tadipatri', 'Karaikudi', 'Kishanganj', 'Guntakal', 'Jamalpur',
      'Ballia', 'Kavali', 'Tadepalligudem', 'Amaravati', 'Buxar', 'Tezpur',
      'Jehanabad', 'Aurangabad', 'Gangtok', 'Vasco da Gama', 'Panaji', 'Eluru',
      'Dehradun', 'Haridwar', 'Rishikesh', 'Roorkee', 'Kashipur', 'Rudrapur',
      'Haldwani', 'Ramnagar', 'Pithoragarh', 'Almora', 'Nainital', 'Mussoorie',
      'Chamba', 'Dharamshala', 'Shimla', 'Solan', 'Baddi', 'Parwanoo',
      'Kullu', 'Manali', 'Mandi', 'Hamirpur', 'Una', 'Bilaspur',
    ];

    setState(() {
      _allCities = staticCities..sort();
      _isLoadingCities = false;
    });
  }

  void _showCityPicker() {
    final searchController = TextEditingController();
    List<String> filteredCities = List.from(_allCities);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          void filterCities(String query) {
            setModalState(() {
              if (query.isEmpty) {
                filteredCities = List.from(_allCities);
              } else {
                filteredCities = _allCities
                    .where((city) => city.toLowerCase().contains(query.toLowerCase()))
                    .toList();
              }
            });
          }

          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Text(
                        'Select City',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF121A2C),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          searchController.dispose();
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search cities...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF3D3D7B),
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onChanged: filterCities,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _isLoadingCities && _allCities.isEmpty
                      ? const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3D3D7B)),
                          ),
                        )
                      : filteredCities.isEmpty
                          ? const Center(
                              child: Text(
                                'No cities found',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filteredCities.length,
                              itemBuilder: (context, index) {
                                if (index >= filteredCities.length) {
                                  return const SizedBox.shrink();
                                }
                                final city = filteredCities[index];
                                return ListTile(
                                  title: Text(
                                    city,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Color(0xFF121A2C),
                                    ),
                                  ),
                                  onTap: () {
                                    setState(() {
                                      _preferredCity = city;
                                      _preferredCityController.text = city;
                                    });
                                    searchController.dispose();
                                    Navigator.pop(context);
                                  },
                                );
                              },
                            ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final jobTypes = [
      {'en': 'Gents Stylist', 'hi': 'जेंट्स स्टाइलिस्ट', 'id': 'gents_stylist'},
      {'en': 'Beautician', 'hi': 'ब्यूटीशियन', 'id': 'beautician'},
      {'en': 'Unisex Hairdresser', 'hi': 'यूनिसेक्स हेयरड्रेसर', 'id': 'unisex_hairdresser'},
      {'en': 'Nail Artist', 'hi': 'नेल आर्टिस्ट', 'id': 'nail_artist'},
      {'en': 'Ladies Hairdresser', 'hi': 'लेडीज़ हेयरड्रेसर', 'id': 'ladies_hairdresser'},
      {'en': 'Spa Therapist', 'hi': 'स्पा थेरेपिस्ट', 'id': 'spa_therapist'},
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: AppResponsive.formScreenPadding(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      
                      // Back Button and Progress Indicator
                      Row(
                        children: [
                          // Back Button
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: SvgPicture.asset(
                              'assets/images/screen 2/Frame 1299.svg',
                              width: 24,
                              height: 24,
                            ),
                          ),
                          const Spacer(),
                          // Progress Indicator
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildProgressStep(1, isActive: true),
                              Expanded(child: _buildProgressConnector()),
                              _buildProgressStep(2, isActive: true),
                              Expanded(child: _buildProgressConnector()),
                              _buildProgressStep(3, isActive: false),
                            ],
                          ),
                          const Spacer(),
                          const SizedBox(width: 24),
                        ],
                      ),
                      
                      const SizedBox(height: 32),
                      
                      // Title: "Choose Your Job"
                      Text(
                        _localizations.chooseYourJob,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF121A2C),
                          letterSpacing: -0.5,
                        ),
                      ),
                      
                      const SizedBox(height: 32),
                      
                      // Preferred Job Type Section
                      Text(
                        _localizations.preferredJobType,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF121A2C),
                        ),
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // Job Type Cards Grid (2x3)
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 1.2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: jobTypes.length,
                        itemBuilder: (context, index) {
                          final job = jobTypes[index];
                          final isSelected = _selectedJobType == job['id'];
                          
                          return _buildJobTypeCard(
                            englishTitle: job['en']!,
                            hindiTitle: job['hi']!,
                            isSelected: isSelected,
                            onTap: () {
                              setState(() {
                                _selectedJobType = job['id'];
                              });
                            },
                          );
                        },
                      ),
                      
                      const SizedBox(height: 32),
                      
                      // Preferred City Section
                      Text(
                        _localizations.preferredCity,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF121A2C),
                        ),
                      ),
                      
                      const SizedBox(height: 8),
                      
                      TextField(
                        controller: _preferredCityController,
                        decoration: InputDecoration(
                          hintText: _localizations.whereDoYouWantJob,
                          hintStyle: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade400,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.grey.shade300,
                              width: 1,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.grey.shade300,
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF3D3D7B),
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          suffixIcon: Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFF121A2C),
                        ),
                        readOnly: true,
                        onTap: _showCityPicker,
                      ),
                      
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
            
            // Continue Button
            Padding(
              padding: AppResponsive.formFooterPadding(context),
              child: GestureDetector(
                onTap: _isFormValid ? () {
                  // TODO: Navigate to next step
                } : null,
                child: Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    color: _isFormValid 
                        ? const Color(0xFF3D3D7B) 
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      _localizations.continueButton,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _isFormValid 
                            ? Colors.white 
                            : Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressStep(int stepNumber, {required bool isActive}) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF3D3D7B) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive ? const Color(0xFF3D3D7B) : Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: Center(
        child: Text(
          '$stepNumber',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: isActive ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  Widget _buildProgressConnector() {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.grey.shade300,
    );
  }

  Widget _buildJobTypeCard({
    required String englishTitle,
    required String hindiTitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected 
                ? const Color(0xFF3D3D7B) 
                : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Speaker icon
              Icon(
                Icons.volume_up,
                size: 24,
                color: isSelected 
                    ? const Color(0xFF3D3D7B) 
                    : Colors.grey.shade600,
              ),
              const SizedBox(height: 12),
              // English title
              Text(
                englishTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isSelected 
                      ? const Color(0xFF3D3D7B) 
                      : const Color(0xFF121A2C),
                ),
              ),
              const SizedBox(height: 4),
              // Hindi title
              Text(
                hindiTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

// ============== SEEKER: PHONE NUMBER SCREEN ==============
class SeekerPhoneScreen extends StatefulWidget {
  final Language selectedLanguage;
  const SeekerPhoneScreen({super.key, required this.selectedLanguage});
  @override
  State<SeekerPhoneScreen> createState() => _SeekerPhoneScreenState();
}

class _SeekerPhoneScreenState extends State<SeekerPhoneScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final ApiService _apiService = ApiService();
  late AppLocalizations _localizations;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _localizations = AppLocalizations(widget.selectedLanguage);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  String _cleanPhone(String phone) => phone.replaceAll(RegExp(r'[^0-9]'), '');

  Future<void> _sendOtp() async {
    final phone = _cleanPhone(_phoneController.text);
    if (phone.length != 10) {
      setState(() => _errorMessage = widget.selectedLanguage == Language.hindi
          ? '10 अंकों का फोन नंबर दर्ज करें'
          : 'Enter a 10-digit phone number');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final smsHash = await androidSmsRetrieverHash();
      final response = await _apiService.sendOtp(phone, smsAppHash: smsHash);
      if (!mounted) return;
      if (response.success) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => SeekerOtpScreen(
            selectedLanguage: widget.selectedLanguage,
            phoneNumber: phone,
          ),
        ));
      } else {
        setState(() => _errorMessage = response.message ?? 'Failed to send OTP');
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Color(0xFF121A2C)), onPressed: () => Navigator.pop(context)),
        title: Text(_localizations.iWantJob, style: const TextStyle(color: Color(0xFF121A2C), fontSize: 18, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ResponsiveScreenBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Text(_localizations.enterPhone, style: TextStyle(fontSize: context.rHeadingSize, fontWeight: FontWeight.w700, color: const Color(0xFF121A2C))),
              const SizedBox(height: 8),
              Text(
                widget.selectedLanguage == Language.hindi
                    ? 'ओटीपी से लॉगिन करें'
                    : 'Login with OTP',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 32),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _errorMessage != null ? Colors.red : Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)),
                      ),
                      child: const Text('+91', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF121A2C))),
                    ),
                    Container(width: 1, height: 48, color: Colors.grey.shade300),
                    Expanded(
                      child: TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: 1.2),
                        decoration: InputDecoration(
                          hintText: _localizations.phoneNumber,
                          counterText: '',
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _sendOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3D3D7B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_localizations.continueButton, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============== SEEKER: OTP VERIFICATION SCREEN ==============
class SeekerOtpScreen extends StatefulWidget {
  final Language selectedLanguage;
  final String phoneNumber;
  const SeekerOtpScreen({super.key, required this.selectedLanguage, required this.phoneNumber});
  @override
  State<SeekerOtpScreen> createState() => _SeekerOtpScreenState();
}

class _SeekerOtpScreenState extends State<SeekerOtpScreen> with CodeAutoFill {
  final TextEditingController _otpController = TextEditingController();
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  late AppLocalizations _localizations;
  bool _isLoading = false;
  String? _errorMessage;
  int _resendCooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _localizations = AppLocalizations(widget.selectedLanguage);
    listenForCode(smsCodeRegexPattern: r'\d{6}');
    _startCooldown();
  }

  @override
  void codeUpdated() {
    final receivedCode = code;
    if (receivedCode != null && receivedCode.length == 6 && mounted) {
      setState(() {
        _otpController.text = receivedCode;
      });
      _verifyOtp();
    }
  }

  void _startCooldown() {
    _resendCooldown = 30;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendCooldown <= 0) { t.cancel(); return; }
      if (mounted) setState(() => _resendCooldown--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    cancel();
    unregisterListener();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verifyOtp() async {
    if (_isLoading) return;
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() => _errorMessage = widget.selectedLanguage == Language.hindi ? '6 अंकों का ओटीपी दर्ज करें' : 'Enter 6-digit OTP');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final response = await _apiService.verifySeekerOtp(widget.phoneNumber, otp);
      if (!mounted) return;
      if (response.success && response.data != null) {
        final result = response.data!;
        // Conditional navigation
        if (result.seekerProfileExists) {
          // Existing user → go directly to job feed
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => SeekerHomeScreen(selectedLanguage: widget.selectedLanguage)),
            (route) => false,
          );
        } else {
          // New user → onboarding profile
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => SeekerCreateProfileScreen(selectedLanguage: widget.selectedLanguage)),
            (route) => false,
          );
        }
      } else {
        setState(() => _errorMessage = response.message ?? 'Verification failed');
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendOtp() async {
    if (_resendCooldown > 0) return;
    final smsHash = await androidSmsRetrieverHash();
    await _apiService.resendOtp(widget.phoneNumber, countryCode: '+91', smsAppHash: smsHash);
    _startCooldown();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Color(0xFF121A2C)), onPressed: () => Navigator.pop(context)),
      ),
      body: SafeArea(
        child: ResponsiveScreenBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_localizations.verifyOtp, style: TextStyle(fontSize: context.rHeadingSize, fontWeight: FontWeight.w700, color: const Color(0xFF121A2C))),
              const SizedBox(height: 8),
              Text(
                '${_localizations.otpSentTo} +91 ${widget.phoneNumber}',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppResponsive.otpDigitFontSize(context), fontWeight: FontWeight.w700, letterSpacing: 8),
                autofillHints: const [AutofillHints.oneTimeCode],
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '------',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF3D3D7B), width: 2)),
                ),
              ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ),
              const SizedBox(height: 16),
              Center(
                child: _resendCooldown > 0
                    ? Text('${_localizations.resendIn} ${_resendCooldown}s', style: TextStyle(color: Colors.grey.shade500, fontSize: 14))
                    : GestureDetector(
                        onTap: _resendOtp,
                        child: Text(_localizations.resendOtp, style: const TextStyle(color: Color(0xFF3D3D7B), fontWeight: FontWeight.w600, fontSize: 14)),
                      ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3D3D7B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_localizations.verify, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============== SEEKER: CREATE PROFILE SCREEN (MINIMAL ONBOARDING) ==============
class SeekerCreateProfileScreen extends StatefulWidget {
  final Language selectedLanguage;
  const SeekerCreateProfileScreen({super.key, required this.selectedLanguage});
  @override
  State<SeekerCreateProfileScreen> createState() => _SeekerCreateProfileScreenState();
}

class _SeekerCreateProfileScreenState extends State<SeekerCreateProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final ApiService _apiService = ApiService();
  late AppLocalizations _localizations;
  String? _selectedGender;
  String? _selectedCity;
  String? _selectedRole;
  final Set<String> _selectedSkills = {};
  JobTaxonomyCatalog? _jobTaxonomy;
  bool _isLoading = false;
  String? _errorMessage;
  List<String> _cities = [];
  bool _citiesLoading = true;

  @override
  void initState() {
    super.initState();
    _localizations = AppLocalizations(widget.selectedLanguage);
    _cities = List<String>.from(IndiaCityService.kFallbackCities);
    _loadCitiesIntoState();
    JobTaxonomyCatalog.instance().then((c) {
      if (mounted) setState(() => _jobTaxonomy = c);
    });
  }

  Future<void> _loadCitiesIntoState() async {
    setState(() => _citiesLoading = true);
    final loaded = await IndiaCityService.instance.loadCities();
    if (!mounted) return;
    setState(() {
      _cities = loaded;
      _citiesLoading = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _isValid {
    if (_nameController.text.trim().isEmpty || _selectedGender == null || _selectedCity == null || _selectedRole == null) {
      return false;
    }
    final role = _selectedRole!;
    if (role == 'other') {
      return _selectedSkills.isNotEmpty;
    }
    final cat = _jobTaxonomy?.categoryById(role);
    if (cat != null && cat.subcategories.isNotEmpty) {
      return _selectedSkills.any((s) => s.startsWith('$role/'));
    }
    return true;
  }

  Future<void> _saveProfile() async {
    if (!_isValid) return;
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final response = await _apiService.updateSeekerProfile({
        'fullName': _nameController.text.trim(),
        'gender': _selectedGender,
        'city': _selectedCity,
        'preferredRole': _selectedRole,
        if (_selectedSkills.isNotEmpty) 'skills': _selectedSkills.toList(),
      });
      if (!mounted) return;
      if (response.success) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => SeekerHomeScreen(selectedLanguage: widget.selectedLanguage)),
          (route) => false,
        );
      } else {
        setState(() => _errorMessage = response.message ?? 'Failed to save profile');
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: Text(_localizations.createYourProfile, style: const TextStyle(color: Color(0xFF121A2C), fontSize: 18, fontWeight: FontWeight.w600)),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ResponsiveScrollPage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_localizations.createProfileSubtext, style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
              const SizedBox(height: 28),

              // Full Name
              Text(_localizations.yourFullName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF121A2C))),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: _localizations.enterFullName,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF3D3D7B), width: 2)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  widget.selectedLanguage == Language.hindi
                      ? 'आधार/पहचान पत्र जैसा ही नाम लिखें'
                      : 'Spell your name the same way as on your ID',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
              const SizedBox(height: 24),

              // Gender
              Text(_localizations.selectGender, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF121A2C))),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildGenderChip('male', _localizations.male),
                  const SizedBox(width: 12),
                  _buildGenderChip('female', _localizations.female),
                  const SizedBox(width: 12),
                  _buildGenderChip('other', _localizations.otherGender),
                ],
              ),
              const SizedBox(height: 24),

              // City
              Text(_localizations.seekerCity, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF121A2C))),
              const SizedBox(height: 8),
              InkWell(
                onTap: _citiesLoading
                    ? null
                    : () async {
                        final picked = await showIndiaCityPickerSheet(
                          context,
                          cities: _cities,
                          isLoading: false,
                          selected: _selectedCity,
                          title: _localizations.seekerCity,
                          searchHint: _localizations.searchLocation,
                        );
                        if (picked != null) setState(() => _selectedCity = picked);
                      },
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    suffixIcon: _citiesLoading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : const Icon(Icons.arrow_drop_down),
                  ),
                  child: Text(
                    _selectedCity ??
                        (_citiesLoading
                            ? (widget.selectedLanguage == Language.hindi ? 'शहर लोड हो रहे हैं…' : 'Loading cities…')
                            : _localizations.searchLocation),
                    style: TextStyle(
                      fontSize: 14,
                      color: _selectedCity != null ? const Color(0xFF121A2C) : Colors.grey.shade600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Preferred role (taxonomy)
              Text(_localizations.preferredJobRole, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF121A2C))),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedRole == null
                          ? (widget.selectedLanguage == Language.hindi ? 'अभी तक नहीं चुना' : 'None selected')
                          : (_jobTaxonomy?.categoryLabel(_selectedRole!, widget.selectedLanguage == Language.hindi) ?? _selectedRole!),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Color(0xFF121A2C)),
                    ),
                    if (_selectedSkills.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _selectedSkills.map((s) {
                          final lab = _jobTaxonomy?.compoundLabel(s, widget.selectedLanguage == Language.hindi) ?? s;
                          return Chip(
                            label: Text(lab, style: const TextStyle(fontSize: 11)),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final cat = await JobTaxonomyCatalog.instance();
                    if (!mounted) return;
                    final hi = widget.selectedLanguage == Language.hindi;
                    final res = await Navigator.of(context).push<JobTaxonomyPickResult>(
                      MaterialPageRoute(
                        builder: (_) => JobTaxonomySelectionScreen(
                          hindi: hi,
                          catalog: cat,
                          initialCategoryId: _selectedRole,
                          initialCompoundSkills: _selectedSkills.toList(),
                          forSeekerProfile: true,
                        ),
                      ),
                    );
                    if (res != null && mounted) {
                      setState(() {
                        _selectedRole = res.categoryId;
                        _selectedSkills
                          ..clear()
                          ..addAll(res.compoundSkillIds);
                      });
                    }
                  },
                  icon: const Icon(Icons.category_outlined),
                  label: Text(
                    _localizations.seekerChooseJobTypeButton,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ),

              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: (_isValid && !_isLoading) ? _saveProfile : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3D3D7B),
                    disabledBackgroundColor: Colors.grey.shade300,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_localizations.saveAndContinue, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGenderChip(String value, String label) {
    final isSelected = _selectedGender == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedGender = value),
      child: Container(
        padding: AppResponsive.screenPaddingHV(context, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3D3D7B).withOpacity(0.1) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? const Color(0xFF3D3D7B) : Colors.grey.shade300, width: isSelected ? 1.5 : 1),
        ),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400, color: isSelected ? const Color(0xFF3D3D7B) : Colors.grey.shade700)),
      ),
    );
  }
}

// ============== SEEKER: BROWSE ALL JOBS ==============
class SeekerBrowseAllJobsScreen extends StatefulWidget {
  final Language selectedLanguage;

  const SeekerBrowseAllJobsScreen({super.key, required this.selectedLanguage});

  @override
  State<SeekerBrowseAllJobsScreen> createState() => _SeekerBrowseAllJobsScreenState();
}

class _SeekerBrowseAllJobsScreenState extends State<SeekerBrowseAllJobsScreen> {
  final ApiService _apiService = ApiService();
  late AppLocalizations _localizations;

  List<SeekerJobItem> _jobs = [];
  bool _loading = true;
  String? _filterRole;
  String? _filterCity;
  JobTaxonomyCatalog? _taxonomy;
  List<String> _cities = [];

  @override
  void initState() {
    super.initState();
    _localizations = AppLocalizations(widget.selectedLanguage);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final cat = await JobTaxonomyCatalog.instance();
    final cities = await IndiaCityService.instance.loadCities();
    if (!mounted) return;
    setState(() {
      _taxonomy = cat;
      _cities = cities;
    });
    await _loadJobs();
  }

  Future<void> _loadJobs() async {
    setState(() => _loading = true);
    final res = await _apiService.getSeekerJobs(
      browseAll: true,
      city: _filterCity,
      role: _filterRole,
      limit: 100,
    );
    if (!mounted) return;
    setState(() {
      _jobs = res.success && res.data != null ? res.data! : [];
      _loading = false;
    });
  }

  Future<void> _openFilters() async {
    final result = await Navigator.of(context).push<Map<String, String?>>(
      MaterialPageRoute(
        builder: (context) => OwnerApplicantsFilterScreen(
          selectedLanguage: widget.selectedLanguage,
          jobs: const [],
          taxonomy: _taxonomy,
          cityOptions: _cities,
          initialJobRole: _filterRole,
          initialCity: _filterCity,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _filterRole = result['jobRole'];
      _filterCity = result['city'];
    });
    await _loadJobs();
  }

  Future<void> _applyToJob(SeekerJobItem job, int index) async {
    if (job.hasApplied) return;
    final response = await _apiService.applyToJob(job.id);
    if (!mounted) return;
    if (response.success) {
      setState(() {
        _jobs[index] = SeekerJobItem(
          id: job.id,
          jobRole: job.jobRole,
          customRoleName: job.customRoleName,
          location: job.location,
          salaryMin: job.salaryMin,
          salaryMax: job.salaryMax,
          workType: job.workType,
          experience: job.experience,
          salonName: job.salonName,
          description: job.description,
          status: job.status,
          hasApplied: true,
          createdAt: job.createdAt,
          salonPhotoUrls: job.salonPhotoUrls,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_localizations.applicationSuccess), backgroundColor: Colors.green),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(response.message ?? _localizations.alreadyApplied), backgroundColor: Colors.orange),
      );
    }
  }

  String _formatSalary(double val) {
    if (val >= 1000) return '${(val / 1000).toStringAsFixed(0)}K';
    return val.toStringAsFixed(0);
  }

  Widget _infoChip(IconData icon, String label, {Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildJobCard(SeekerJobItem job, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(job.displayRole, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF121A2C))),
                ),
                Text(job.postedAgo, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.location_on_outlined, size: 16, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(job.location, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _infoChip(Icons.currency_rupee, '${_formatSalary(job.salaryMin)} - ${_formatSalary(job.salaryMax)}'),
                const SizedBox(width: 8),
                _infoChip(Icons.work_outline, job.experience == 'fresher_ok' ? _localizations.fresherSeeker : _localizations.experiencedSeeker),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _infoChip(Icons.access_time, job.workType == 'full_time' ? _localizations.fullTime : _localizations.partTime),
                if (job.salonName != null) ...[
                  const SizedBox(width: 8),
                  _infoChip(Icons.storefront_outlined, job.salonName!),
                ],
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: job.hasApplied ? null : () => _applyToJob(job, index),
                style: ElevatedButton.styleFrom(
                  backgroundColor: job.hasApplied ? Colors.grey.shade200 : const Color(0xFF3D3D7B),
                  disabledBackgroundColor: Colors.grey.shade200,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: Text(
                  job.hasApplied ? _localizations.applied : _localizations.apply,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: job.hasApplied ? Colors.grey.shade600 : Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasFilter = (_filterRole != null && _filterRole!.isNotEmpty) || (_filterCity != null && _filterCity!.isNotEmpty);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF121A2C),
        title: Text(_localizations.browseAllJobs, style: const TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: _localizations.filterApplicants,
            onPressed: _openFilters,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadJobs,
              child: _jobs.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                      children: [
                        Icon(Icons.work_off_outlined, size: 72, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(
                          hasFilter ? _localizations.noJobsForFilter : _localizations.noJobsInArea,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          hasFilter ? _localizations.browseAllJobsHint : _localizations.noJobsSubtext,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                        ),
                        const SizedBox(height: 20),
                        OutlinedButton.icon(
                          onPressed: _openFilters,
                          icon: const Icon(Icons.tune),
                          label: Text(_localizations.filterApplicants),
                        ),
                      ],
                    )
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: AppResponsive.scrollScreenPadding(context, top: 12, bottom: 32),
                      children: [
                        Text(
                          _localizations.browseAllJobsHint,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.35),
                        ),
                        if (hasFilter) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (_filterRole != null && _filterRole!.isNotEmpty)
                                Chip(
                                  label: Text(
                                    _taxonomy?.categoryLabel(_filterRole!, widget.selectedLanguage == Language.hindi) ?? _filterRole!,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              if (_filterCity != null && _filterCity!.isNotEmpty)
                                Chip(label: Text(_filterCity!, style: const TextStyle(fontSize: 12))),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        ...List.generate(_jobs.length, (i) => _buildJobCard(_jobs[i], i)),
                      ],
                    ),
            ),
    );
  }
}

// ============== SEEKER: HOME SCREEN (JOB FEED + PROFILE) ==============
class SeekerHomeScreen extends StatefulWidget {
  final Language selectedLanguage;
  const SeekerHomeScreen({super.key, required this.selectedLanguage});
  @override
  State<SeekerHomeScreen> createState() => _SeekerHomeScreenState();
}

class _SeekerHomeScreenState extends State<SeekerHomeScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  late AppLocalizations _localizations;
  late Language _currentLanguage;

  List<SeekerJobItem> _jobs = [];
  SeekerProfile? _seekerProfile;
  bool _isLoading = true;
  int _selectedTab = 0; // 0: Home/Jobs, 1: Applications, 2: Profile
  int _unreadNotificationCount = 0;
  StreamSubscription<PushDeepLink>? _deepLinkSub;

  @override
  void initState() {
    super.initState();
    _currentLanguage = widget.selectedLanguage;
    _localizations = AppLocalizations(_currentLanguage);
    _loadData();
    PushNotificationService().registerTokenIfLoggedIn();
    _deepLinkSub = PushNotificationService.onDeepLink.listen(_handleDeepLink);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handlePendingDeepLink());
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    super.dispose();
  }

  void _handleDeepLink(PushDeepLink link) {
    if (link.host != 'seeker' || !mounted) return;
    _handleSeekerDeepLink(link);
  }

  void _handlePendingDeepLink() {
    final link = PushNotificationService.getAndClearPendingDeepLink();
    if (link != null && link.host == 'seeker' && mounted) _handleSeekerDeepLink(link);
  }

  void _handleSeekerDeepLink(PushDeepLink link) {
    if (!mounted) return;
    if (link.path == 'applications' || link.path.startsWith('applications/')) {
      setState(() => _selectedTab = 1);
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      // Load profile (retry after role switch if token was salon JWT)
      var profileRes = await _apiService.getSeekerProfile();
      if (!profileRes.success) {
        final switchRes = await _apiService.switchToSeeker();
        if (switchRes.success) {
          profileRes = await _apiService.getSeekerProfile();
        }
      }
      if (mounted && profileRes.success && profileRes.data != null) {
        setState(() => _seekerProfile = profileRes.data);
      }

      // Load jobs
      final jobsRes = await _apiService.getSeekerJobs(
        city: _seekerProfile?.city,
        role: _seekerProfile?.preferredRole,
      );
      if (mounted && jobsRes.success && jobsRes.data != null) {
        setState(() => _jobs = jobsRes.data!);
      }

      final unreadRes = await _apiService.getUnreadNotificationCount();
      if (mounted && unreadRes.success && unreadRes.data != null) {
        setState(() => _unreadNotificationCount = unreadRes.data!);
      }
    } catch (e) {
      print('Error loading seeker data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshUnreadCount() async {
    final res = await _apiService.getUnreadNotificationCount();
    if (mounted && res.success && res.data != null) {
      setState(() => _unreadNotificationCount = res.data!);
    }
  }

  Future<void> _applyToJob(SeekerJobItem job, int index) async {
    if (job.hasApplied) return;
    final response = await _apiService.applyToJob(job.id);
    if (mounted) {
      if (response.success) {
        setState(() {
          _jobs[index] = SeekerJobItem(
            id: job.id, jobRole: job.jobRole, customRoleName: job.customRoleName,
            location: job.location, salaryMin: job.salaryMin, salaryMax: job.salaryMax,
            workType: job.workType, experience: job.experience, salonName: job.salonName,
            description: job.description, status: job.status, hasApplied: true, createdAt: job.createdAt,
            salonPhotoUrls: job.salonPhotoUrls,
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_localizations.applicationSuccess), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response.message ?? _localizations.alreadyApplied), backgroundColor: Colors.orange),
        );
      }
    }
  }

  Future<void> _logout() async {
    await PushNotificationService().unregisterToken();
    await _apiService.logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ResponsiveContent(
                child: _selectedTab == 2
                    ? _buildProfileTab()
                    : _selectedTab == 1
                        ? _buildApplicationsTab()
                        : _buildJobFeedTab(),
              ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedTab,
        selectedItemColor: const Color(0xFF3D3D7B),
        unselectedItemColor: Colors.grey.shade400,
        onTap: (i) => setState(() => _selectedTab = i),
        items: [
          BottomNavigationBarItem(icon: const Icon(Icons.home_outlined), activeIcon: const Icon(Icons.home), label: _localizations.seekerHome),
          BottomNavigationBarItem(icon: const Icon(Icons.description_outlined), activeIcon: const Icon(Icons.description), label: _localizations.seekerApplications),
          BottomNavigationBarItem(icon: const Icon(Icons.person_outline), activeIcon: const Icon(Icons.person), label: _localizations.seekerProfileTab),
        ],
      ),
    );
  }

  // ============ JOB FEED TAB ============
  Widget _buildJobFeedTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _localizations.jobFeedTitle,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF121A2C)),
                        ),
                        if (_seekerProfile?.city != null)
                          Text(_seekerProfile!.city!, style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  // Notification bell → notification center (badge when unread)
                  Badge(
                    isLabelVisible: _unreadNotificationCount > 0,
                    label: Text(
                      _unreadNotificationCount > 99 ? '99+' : '$_unreadNotificationCount',
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.notifications_none, color: Color(0xFF121A2C)),
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => NotificationListScreen(
                              selectedLanguage: _currentLanguage,
                            ),
                          ),
                        );
                        _refreshUnreadCount();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => SeekerBrowseAllJobsScreen(selectedLanguage: _currentLanguage),
                    ),
                  );
                  _loadData();
                },
                icon: const Icon(Icons.work_outline, size: 20),
                label: Text(
                  _localizations.browseAllJobs,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF3D3D7B),
                  side: const BorderSide(color: Color(0xFF3D3D7B)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),

          // Profile completion card
          if (_seekerProfile != null && _seekerProfile!.profileCompletionPercent < 100)
            SliverToBoxAdapter(child: _buildCompletionCard()),

          // Job list or empty state
          if (_jobs.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.work_off_outlined, size: 72, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text(_localizations.noJobsInArea, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                    const SizedBox(height: 8),
                    Text(_localizations.noJobsSubtext, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey.shade400)),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildJobCard(_jobs[index], index),
                childCount: _jobs.length,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompletionCard() {
    final percent = _seekerProfile?.profileCompletionPercent ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppResponsive.ownerHomeCardBorder),
        ),
        child: Row(
          children: [
            ProfilePercentRing(
              size: 48,
              percent: percent,
              strokeWidth: 4,
              valueColor: const Color(0xFFF9A825),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _localizations.seekerProfileCompletion.replaceAll('{p}', '$percent'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF121A2C)),
                  ),
                  const SizedBox(height: 2),
                  Text(_localizations.seekerProfileNudge, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => SeekerEnhanceProfileScreen(selectedLanguage: _currentLanguage, seekerProfile: _seekerProfile!),
                ));
                _loadData();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFFF9A825), borderRadius: BorderRadius.circular(8)),
                child: Text(_localizations.enhanceProfile, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobCard(SeekerJobItem job, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title & posted time
            Row(
              children: [
                Expanded(
                  child: Text(job.displayRole, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF121A2C))),
                ),
                Text(job.postedAgo, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
            const SizedBox(height: 6),
            // Location
            Row(
              children: [
                Icon(Icons.location_on_outlined, size: 16, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(job.location, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(height: 8),
            // Salary & experience chips
            Row(
              children: [
                _infoChip(Icons.currency_rupee, '${_formatSalary(job.salaryMin)} - ${_formatSalary(job.salaryMax)}'),
                const SizedBox(width: 8),
                _infoChip(Icons.work_outline, job.experience == 'fresher_ok' ? _localizations.fresherSeeker : _localizations.experiencedSeeker),
              ],
            ),
            const SizedBox(height: 8),
            // Work type
            Row(
              children: [
                _infoChip(Icons.access_time, job.workType == 'full_time' ? _localizations.fullTime : _localizations.partTime),
                if (job.salonName != null) ...[
                  const SizedBox(width: 8),
                  _infoChip(
                    Icons.storefront_outlined,
                    job.salonName!,
                    trailing: job.isSalonVerified
                        ? const Padding(
                            padding: EdgeInsets.only(left: 2),
                            child: Icon(Icons.verified, size: 14, color: Color(0xFF1565C0)),
                          )
                        : null,
                  ),
                ],
              ],
            ),
            if (job.salonPhotoUrls.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _localizations.salonPhotosSeeker,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 88,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: job.salonPhotoUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final url = job.salonPhotoUrls[i];
                    return Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: () => showJobtreeImagePreview(context, url),
                        borderRadius: BorderRadius.circular(10),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 88,
                            height: 88,
                            child: Image.network(
                              url,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => ColoredBox(
                                color: Colors.grey.shade200,
                                child: Icon(Icons.storefront_outlined, color: Colors.grey.shade500, size: 32),
                              ),
                              loadingBuilder: (ctx, child, prog) {
                                if (prog == null) return child;
                                return const Center(
                                  child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
            // Apply button
            SizedBox(
              width: double.infinity, height: 44,
              child: ElevatedButton(
                onPressed: job.hasApplied ? null : () => _applyToJob(job, index),
                style: ElevatedButton.styleFrom(
                  backgroundColor: job.hasApplied ? Colors.grey.shade200 : const Color(0xFF3D3D7B),
                  disabledBackgroundColor: Colors.grey.shade200,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: Text(
                  job.hasApplied ? _localizations.applied : _localizations.apply,
                  style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600,
                    color: job.hasApplied ? Colors.grey.shade600 : Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, {Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  String _formatSalary(double val) {
    if (val >= 1000) return '${(val / 1000).toStringAsFixed(0)}K';
    return val.toStringAsFixed(0);
  }

  // ============ APPLICATIONS TAB ============
  Widget _buildApplicationsTab() {
    return FutureBuilder<ApiResponse<List<Map<String, dynamic>>>>(
      future: _apiService.getSeekerApplications(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final apps = snapshot.data?.data ?? [];
        if (apps.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.description_outlined, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text(
                  widget.selectedLanguage == Language.hindi ? 'अभी तक कोई आवेदन नहीं' : 'No applications yet',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: AppResponsive.cardPaddingInsets(context),
          itemCount: apps.length,
          itemBuilder: (context, index) {
            final app = apps[index];
            final job = app['job'] as Map<String, dynamic>? ?? {};
            final status = app['status'] ?? 'applied';
            final interviewStatus = app['interviewStatus'] ?? 'not_scheduled';
            final interviewAt = app['interviewScheduledAt']?.toString();
            final interviewMode = app['interviewMode']?.toString();
            final interviewNotes = app['interviewNotes']?.toString();

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (job['customRoleName'] as String?)?.isNotEmpty == true
                                  ? job['customRoleName']
                                  : (job['jobRole'] ?? '').toString().replaceAll('_', ' '),
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF121A2C)),
                            ),
                            const SizedBox(height: 4),
                            Text(job['location'] ?? '', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                            if (job['salonName'] != null)
                              Text(job['salonName'], style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: status == 'applied' ? Colors.grey.shade100
                              : status == 'shortlisted' ? const Color(0xFFE3F2FD)
                              : status == 'interview' ? const Color(0xFFF3E5F5)
                              : status == 'hired' ? const Color(0xFFE8F5E9)
                              : const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          status == 'applied' ? (widget.selectedLanguage == Language.hindi ? 'आवेदित' : 'Applied')
                              : status == 'shortlisted' ? (widget.selectedLanguage == Language.hindi ? 'शॉर्टलिस्ट' : 'Shortlisted')
                              : status == 'interview' ? (widget.selectedLanguage == Language.hindi ? 'इंटरव्यू' : 'Interview')
                              : status == 'hired' ? (widget.selectedLanguage == Language.hindi ? 'हायर्ड ✓' : 'Hired ✓')
                              : (widget.selectedLanguage == Language.hindi ? 'अस्वीकृत' : 'Rejected'),
                          style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600,
                            color: status == 'applied' ? Colors.grey.shade700
                                : status == 'shortlisted' ? const Color(0xFF1565C0)
                                : status == 'interview' ? const Color(0xFF7B1FA2)
                                : status == 'hired' ? const Color(0xFF2E7D32)
                                : const Color(0xFFC62828),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Interview details banner for seeker
                  if (status == 'interview' && interviewStatus == 'scheduled' && interviewAt != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3E5F5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF9C27B0).withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.event, size: 16, color: Color(0xFF7B1FA2)),
                              const SizedBox(width: 6),
                              Text(
                                widget.selectedLanguage == Language.hindi ? 'इंटरव्यू शेड्यूल' : 'Interview Scheduled',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF7B1FA2)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _formatSeekerInterviewDate(interviewAt),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E)),
                          ),
                          if (interviewMode != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '📍 ${interviewMode == 'in_person' ? (widget.selectedLanguage == Language.hindi ? 'व्यक्तिगत' : 'In Person') : interviewMode == 'phone_call' ? (widget.selectedLanguage == Language.hindi ? 'फ़ोन कॉल' : 'Phone Call') : (widget.selectedLanguage == Language.hindi ? 'वीडियो कॉल' : 'Video Call')}',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                              ),
                            ),
                          if (interviewNotes != null && interviewNotes.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('📝 $interviewNotes', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (status != 'rejected' && app['id'] != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          final roleLine = (job['customRoleName'] as String?)?.isNotEmpty == true
                              ? job['customRoleName'].toString()
                              : (job['jobRole'] ?? '').toString().replaceAll('_', ' ');
                          final salon = job['salonName']?.toString() ?? '';
                          final title = salon.isNotEmpty ? '$salon · $roleLine' : roleLine;
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (context) => ApplicationChatScreen(
                                applicationId: app['id'].toString(),
                                languageCode: widget.selectedLanguage == Language.hindi ? 'hi' : 'en',
                                title: title,
                                isSalonOwner: false,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.chat_bubble_outline, size: 18),
                        label: Text(widget.selectedLanguage == Language.hindi ? 'संदेश' : 'Message'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF3D3D7B),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          side: const BorderSide(color: Color(0xFF3D3D7B)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatSeekerInterviewDate(String? isoString) {
    if (isoString == null) return '';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final minute = dt.minute.toString().padLeft(2, '0');
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year} at $hour:$minute $ampm';
    } catch (_) {
      return isoString;
    }
  }

  String _formatSeekerExperienceSummary(SeekerProfile? p) {
    if (p == null) return '-';
    final parts = <String>[];
    if (p.experience == 'fresher') {
      parts.add(_localizations.fresherSeeker);
    } else if (p.experience == 'experienced_1_plus') {
      parts.add(_localizations.experiencedSeeker);
    } else if (p.experience == 'senior_3_plus') {
      parts.add(_localizations.seniorSeeker);
    } else if ((p.experience ?? '').isNotEmpty) {
      parts.add(p.experience!);
    }
    if (p.experienceYears != null) {
      parts.add(_currentLanguage == Language.hindi ? '${p.experienceYears} वर्ष' : '${p.experienceYears} yrs');
    }
    if (parts.isEmpty) return '-';
    return parts.join(' · ');
  }

  String _formatSeekerSalaryRange(SeekerProfile? p) {
    if (p == null) return '-';
    final min = p.expectedSalary;
    final max = p.expectedSalaryMax;
    if (min != null && max != null) return '₹${min.toStringAsFixed(0)} – ₹${max.toStringAsFixed(0)}';
    if (min != null) return '₹${min.toStringAsFixed(0)}';
    if (max != null) return '₹${max.toStringAsFixed(0)}';
    return '-';
  }

  String _seekerJobTypeLabel(String? jt) {
    switch (jt) {
      case 'full_time':
        return _currentLanguage == Language.hindi ? 'फुल टाइम' : 'Full-time';
      case 'part_time':
        return _currentLanguage == Language.hindi ? 'पार्ट टाइम' : 'Part-time';
      case 'any':
      default:
        return _currentLanguage == Language.hindi ? 'कोई भी' : 'Any';
    }
  }

  String _seekerMaritalLabel(String? m) {
    switch (m) {
      case 'single':
        return _currentLanguage == Language.hindi ? 'अविवाहित' : 'Single';
      case 'married':
        return _currentLanguage == Language.hindi ? 'विवाहित' : 'Married';
      case 'widowed':
        return _currentLanguage == Language.hindi ? 'विधवा/विधुर' : 'Widowed';
      case 'divorced':
        return _currentLanguage == Language.hindi ? 'तलाकशुदा' : 'Divorced';
      case 'prefer_not_say':
        return _currentLanguage == Language.hindi ? 'नहीं बताया' : 'Prefer not to say';
      default:
        return m ?? '-';
    }
  }

  // ============ PROFILE TAB ============
  Widget _buildProfileTab() {
    final p = _seekerProfile;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 16),
      child: Column(
        children: [
          // Avatar
          CircleAvatar(
            radius: 40,
            backgroundColor: const Color(0xFF3D3D7B).withOpacity(0.1),
            backgroundImage: jobtreeMediaImageProvider(
              (p?.profilePhotoUrl != null && p!.profilePhotoUrl!.trim().isNotEmpty)
                  ? p.profilePhotoUrl!.trim()
                  : null,
            ),
            child: (p?.profilePhotoUrl == null || p!.profilePhotoUrl!.trim().isEmpty)
                ? Text(
                    (p?.fullName?.isNotEmpty == true) ? p!.fullName![0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: Color(0xFF3D3D7B)),
                  )
                : null,
          ),
          const SizedBox(height: 12),
          Text(p?.fullName ?? '-', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF121A2C))),
          Text(p?.phoneNumber ?? '', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
          const SizedBox(height: 24),

          // Info cards
          _profileRow(Icons.location_on_outlined, _localizations.seekerCity, p?.city ?? '-'),
          if ((p?.preferredCities ?? []).isNotEmpty)
            _profileRow(
              Icons.location_searching_outlined,
              _localizations.seekerPreferredCitiesLabel,
              p!.preferredCities.join(', '),
            ),
          FutureBuilder<JobTaxonomyCatalog>(
            future: JobTaxonomyCatalog.instance(),
            builder: (context, snap) {
              final hi = _currentLanguage == Language.hindi;
              final cat = snap.data;
              final pr = p?.preferredRole;
              final roleText = pr == null || pr.isEmpty ? '-' : (cat?.categoryLabel(pr, hi) ?? pr);
              return _profileRow(Icons.work_outline, _localizations.preferredJobRole, roleText);
            },
          ),
          _profileRow(Icons.schedule_outlined, _currentLanguage == Language.hindi ? 'नौकरी का प्रकार' : 'Job type', _seekerJobTypeLabel(p?.jobType)),
          _profileRow(
            Icons.flash_on_outlined,
            _currentLanguage == Language.hindi ? 'तुरंत जॉइन' : 'Immediate join',
            p == null ? '-' : (p.immediateJoin ? (_currentLanguage == Language.hindi ? 'हाँ' : 'Yes') : (_currentLanguage == Language.hindi ? 'नहीं' : 'No')),
          ),
          _profileRow(Icons.person_outline, _localizations.selectGender, p?.gender ?? '-'),
          _profileRow(Icons.timeline, _localizations.experienceField, _formatSeekerExperienceSummary(p)),
          if ((p?.skills ?? []).isNotEmpty)
            FutureBuilder<JobTaxonomyCatalog>(
              future: JobTaxonomyCatalog.instance(),
              builder: (context, snap) {
                final hi = _currentLanguage == Language.hindi;
                final cat = snap.data;
                final skills = p!.skills;
                final text = skills.map((s) => cat?.compoundLabel(s, hi) ?? s).join(', ');
                return _profileRow(Icons.auto_awesome_outlined, _localizations.selectRelevantSkills, text);
              },
            ),
          if (p?.email != null && p!.email!.trim().isNotEmpty)
            _profileRow(Icons.email_outlined, _currentLanguage == Language.hindi ? 'ईमेल' : 'Email', p.email!.trim()),
          if (p?.maritalStatus != null && p!.maritalStatus!.isNotEmpty)
            _profileRow(Icons.favorite_outline, _localizations.seekerMaritalStatus, _seekerMaritalLabel(p.maritalStatus)),
          if (p?.currentSalary != null)
            _profileRow(
              Icons.payments_outlined,
              _localizations.seekerCurrentSalary,
              '₹${p!.currentSalary!.toStringAsFixed(0)}',
            ),
          _profileRow(Icons.currency_rupee, _localizations.expectedSalaryField, _formatSeekerSalaryRange(p)),
          if (p?.hasProfessionalCourse != null)
            _profileRow(
              Icons.school_outlined,
              _currentLanguage == Language.hindi ? 'प्रोफेशनल कोर्स' : 'Professional course',
              p!.hasProfessionalCourse == true ? (_currentLanguage == Language.hindi ? 'हाँ' : 'Yes') : (_currentLanguage == Language.hindi ? 'नहीं' : 'No'),
            ),
          if (p?.professionalCourseCertificateUrl != null && p!.professionalCourseCertificateUrl!.trim().isNotEmpty)
            _profileRow(Icons.verified_outlined, _currentLanguage == Language.hindi ? 'प्रमाणपत्र' : 'Certificate', _currentLanguage == Language.hindi ? 'अपलोड किया गया' : 'On file'),
          if ((p?.workPortfolioUrls ?? []).isNotEmpty)
            _profileRow(
              Icons.collections_outlined,
              _localizations.seekerWorkPortfolio,
              _currentLanguage == Language.hindi
                  ? '${(p?.workPortfolioUrls ?? []).length} फ़ाइलें'
                  : '${(p?.workPortfolioUrls ?? []).length} items',
            ),

          const SizedBox(height: 24),

          // Edit profile button
          SizedBox(
            width: double.infinity, height: 48,
            child: OutlinedButton(
              onPressed: () async {
                if (p != null) {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => SeekerEnhanceProfileScreen(selectedLanguage: _currentLanguage, seekerProfile: p),
                  ));
                  _loadData();
                }
              },
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF3D3D7B)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(_localizations.enhanceProfile, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF3D3D7B))),
            ),
          ),
          const SizedBox(height: 12),

          // Test push (temporary – for FCM verification)
          SizedBox(
            width: double.infinity, height: 48,
            child: OutlinedButton(
              onPressed: () async {
                final res = await _apiService.sendTestPush();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(res.success ? (_currentLanguage == Language.hindi ? 'टेस्ट नोटिफिकेशन भेजा गया' : 'Test notification sent') : (res.message ?? 'Failed')),
                    backgroundColor: res.success ? Colors.green : Colors.orange,
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.grey.shade400),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(_currentLanguage == Language.hindi ? 'टेस्ट पुश भेजें' : 'Send test push', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey.shade700)),
            ),
          ),
          const SizedBox(height: 12),

          // Logout
          SizedBox(
            width: double.infinity, height: 48,
            child: TextButton(
              onPressed: _logout,
              child: Text(_localizations.logout, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.red)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6)]),
        child: Row(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF3D3D7B)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF121A2C))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============== SEEKER: ENHANCE PROFILE SCREEN ==============
class SeekerEnhanceProfileScreen extends StatefulWidget {
  final Language selectedLanguage;
  final SeekerProfile seekerProfile;
  const SeekerEnhanceProfileScreen({super.key, required this.selectedLanguage, required this.seekerProfile});
  @override
  State<SeekerEnhanceProfileScreen> createState() => _SeekerEnhanceProfileScreenState();
}

class _SeekerEnhanceProfileScreenState extends State<SeekerEnhanceProfileScreen> {
  final ApiService _apiService = ApiService();
  late AppLocalizations _localizations;
  bool _isSaving = false;
  bool _pickingPhoto = false;

  String? _experience;
  final TextEditingController _salaryController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  String? _selectedCity;
  String? _selectedRole;
  String? _selectedGender;
  List<String> _cities = [];
  bool _citiesLoading = true;
  Set<String> _selectedSkills = {};
  JobTaxonomyCatalog? _jobTaxonomy;
  /// Canonical S3 URL saved to the server (no presigned query string).
  String? _profilePhotoStorageUrl;
  /// Local file path or presigned URL for on-screen preview.
  String? _profilePhotoPreview;
  late Map<String, List<Map<String, String>>> _skillBundlesPerRole;

  String? _jobType;
  final Set<String> _preferredCities = {};
  bool _immediateJoin = true;
  final TextEditingController _currentSalaryController = TextEditingController();
  final TextEditingController _expectedSalaryMaxController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  double _experienceYears = 0;
  String? _maritalStatus;
  bool? _hasProfessionalCourse;
  String? _certificateUrl;
  final List<Map<String, String>> _workPortfolio = [];
  bool _uploadingCertificate = false;
  bool _uploadingPortfolio = false;

  static const List<String> _coreServiceRoles = [
    'hair_stylist', 'beautician', 'makeup_artist', 'massage_therapist',
  ];

  static final List<Map<String, String>> _generalSkillDefs = [
    {'id': 'customer_service', 'labelEn': 'Customer service', 'labelHi': 'ग्राहक सेवा'},
    {'id': 'cash_billing', 'labelEn': 'Cash / billing', 'labelHi': 'कैश / बिलिंग'},
    {'id': 'english_basic', 'labelEn': 'Basic English', 'labelHi': 'बेसिक अंग्रेज़ी'},
    {'id': 'hygiene_standards', 'labelEn': 'Hygiene & safety', 'labelHi': 'सफ़ाई व सुरक्षा'},
    {'id': 'teamwork', 'labelEn': 'Teamwork', 'labelHi': 'टीम वर्क'},
  ];

  final List<String> _experienceOptions = ['fresher', 'experienced_1_plus', 'senior_3_plus'];

  @override
  void initState() {
    super.initState();
    _localizations = AppLocalizations(widget.selectedLanguage);
    final p = widget.seekerProfile;
    _nameController.text = p.fullName ?? '';
    _selectedGender = p.gender;
    _selectedCity = p.city;
    _selectedRole = p.preferredRole;
    _experience = p.experience;
    _selectedSkills = p.skills.toSet();
    _profilePhotoPreview = p.profilePhotoUrl;
    if (p.expectedSalary != null) _salaryController.text = p.expectedSalary!.toStringAsFixed(0);
    _jobType = p.jobType ?? 'any';
    _immediateJoin = p.immediateJoin;
    _preferredCities.clear();
    _preferredCities.addAll(p.preferredCities);
    if (_preferredCities.isEmpty && (p.city ?? '').isNotEmpty) {
      _preferredCities.add(p.city!);
    }
    if (p.currentSalary != null) _currentSalaryController.text = p.currentSalary!.toStringAsFixed(0);
    if (p.expectedSalaryMax != null) _expectedSalaryMaxController.text = p.expectedSalaryMax!.toStringAsFixed(0);
    if (p.experienceYears != null) {
      _experienceYears = p.experienceYears!.toDouble().clamp(0, 25);
    } else if (p.experience == 'fresher') {
      _experienceYears = 0;
    } else if (p.experience == 'experienced_1_plus') {
      _experienceYears = 1;
    } else if (p.experience == 'senior_3_plus') {
      _experienceYears = 3;
    }
    _maritalStatus = p.maritalStatus;
    _emailController.text = p.email ?? '';
    _hasProfessionalCourse = p.hasProfessionalCourse;
    _certificateUrl = p.professionalCourseCertificateUrl;
    _workPortfolio.clear();
    for (final item in p.workPortfolioUrls) {
      _workPortfolio.add({
        'displayUrl': item.url,
        'kind': item.kind,
      });
    }
    _initSkillBundles();
    _syncSkillsToRole(_selectedRole);
    _cities = List<String>.from(IndiaCityService.kFallbackCities);
    _loadCitiesIntoState();
    JobTaxonomyCatalog.instance().then((c) {
      if (!mounted) return;
      setState(() {
        _jobTaxonomy = c;
        _syncSkillsToRole(_selectedRole);
      });
    });
  }

  void _initSkillBundles() {
    _skillBundlesPerRole = {
      'hair_stylist': [
        {'id': 'haircuts_styling', 'label': _localizations.haircutsStyling},
        {'id': 'color_treatments', 'label': _localizations.colorTreatments},
        {'id': 'hair_spa_care', 'label': _localizations.hairSpaCare},
        {'id': 'beard_grooming', 'label': _localizations.beardGrooming},
      ],
      'beautician': [
        {'id': 'facials_skincare', 'label': _localizations.facialsSkincare},
        {'id': 'waxing_threading', 'label': _localizations.waxingThreading},
        {'id': 'manicure_pedicure', 'label': _localizations.manicurePedicure},
        {'id': 'bleach_cleanup', 'label': _localizations.bleachCleanup},
      ],
      'makeup_artist': [
        {'id': 'bridal_makeup', 'label': _localizations.bridalMakeup},
        {'id': 'party_makeup', 'label': _localizations.partyMakeup},
        {'id': 'hd_airbrush', 'label': _localizations.hdAirbrush},
        {'id': 'eye_makeup', 'label': _localizations.eyeMakeup},
      ],
      'massage_therapist': [
        {'id': 'body_massage', 'label': _localizations.bodyMassage},
        {'id': 'head_shoulder', 'label': _localizations.headShoulder},
        {'id': 'aromatherapy', 'label': _localizations.aromatherapy},
        {'id': 'foot_reflexology', 'label': _localizations.footReflexology},
      ],
    };
  }

  Future<void> _loadCitiesIntoState() async {
    setState(() => _citiesLoading = true);
    final loaded = await IndiaCityService.instance.loadCities();
    if (!mounted) return;
    setState(() {
      _cities = loaded;
      _citiesLoading = false;
    });
  }

  void _syncSkillsToRole(String? role) {
    if (role == null) {
      _selectedSkills.clear();
      return;
    }
    final cat = _jobTaxonomy?.categoryById(role);
    if (cat != null) {
      _selectedSkills.removeWhere((s) => !s.startsWith('$role/'));
      return;
    }
    if (_coreServiceRoles.contains(role)) {
      final valid = _skillBundlesPerRole[role]?.map((e) => e['id']!).toSet() ?? {};
      _selectedSkills.removeWhere((s) => !valid.contains(s));
    } else {
      final valid = _generalSkillDefs.map((e) => e['id']!).toSet();
      _selectedSkills.removeWhere((s) => !valid.contains(s));
    }
  }

  Future<void> _pickSeekerPhoto() async {
    if (_pickingPhoto) return;
    setState(() => _pickingPhoto = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
      if (picked == null || !mounted) return;
      setState(() => _profilePhotoPreview = picked.path);
      final file = File(picked.path);
      final contentType = jobtreeInferImageContentType(picked.path, picked.mimeType);

      final bytes = await file.readAsBytes();
      final uploadRes = await _apiService.uploadSeekerMediaDirect(
        bodyBytes: bytes,
        contentType: contentType,
        mediaType: 'photo',
        filename: picked.name,
      );
      if (!uploadRes.success || uploadRes.data == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.selectedLanguage == Language.hindi
              ? 'अपलोड असफल: ${uploadRes.message ?? uploadRes.errorCode ?? ''}'
              : 'Upload failed: ${uploadRes.message ?? uploadRes.errorCode ?? ''}'),
          backgroundColor: Colors.redAccent,
        ));
        return;
      }
      final fileUrl = uploadRes.data!['fileUrl'] as String?;
      final displayUrl = (uploadRes.data!['displayUrl'] as String?)?.trim();
      if (fileUrl == null || fileUrl.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.selectedLanguage == Language.hindi ? 'अपलोड असफल' : 'Upload failed'),
          backgroundColor: Colors.redAccent,
        ));
        return;
      }
      final patch = await _apiService.patchSeekerProfile({'profilePhotoUrl': fileUrl});
      if (!mounted) return;
      if (patch.success) {
        setState(() {
          _profilePhotoStorageUrl = fileUrl;
          _profilePhotoPreview = patch.data?.profilePhotoUrl ?? displayUrl ?? fileUrl;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.selectedLanguage == Language.hindi ? 'फोटो सहेजा गया' : 'Photo saved'),
          backgroundColor: const Color(0xFF3D3D7B),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.selectedLanguage == Language.hindi ? 'फोटो में त्रुटि' : 'Photo error'),
          backgroundColor: Colors.redAccent,
        ));
      }
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  @override
  void dispose() {
    _salaryController.dispose();
    _nameController.dispose();
    _currentSalaryController.dispose();
    _expectedSalaryMaxController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  String _localizedExperience(String exp) {
    if (exp == 'fresher') return _localizations.fresherSeeker;
    if (exp == 'experienced_1_plus') return _localizations.experiencedSeeker;
    if (exp == 'senior_3_plus') return _localizations.seniorSeeker;
    return exp;
  }

  String _jobTypeLabel(String code) {
    final hi = widget.selectedLanguage == Language.hindi;
    switch (code) {
      case 'full_time':
        return hi ? 'फुल टाइम' : 'Full-time';
      case 'part_time':
        return hi ? 'पार्ट टाइम' : 'Part-time';
      case 'any':
      default:
        return hi ? 'कोई भी' : 'Any';
    }
  }

  String _maritalLabel(String code) {
    final hi = widget.selectedLanguage == Language.hindi;
    switch (code) {
      case 'single':
        return hi ? 'अविवाहित' : 'Single';
      case 'married':
        return hi ? 'विवाहित' : 'Married';
      case 'widowed':
        return hi ? 'विधवा/विधुर' : 'Widowed';
      case 'divorced':
        return hi ? 'तलाकशुदा' : 'Divorced';
      case 'prefer_not_say':
        return hi ? 'नहीं बताना' : 'Prefer not to say';
      default:
        return code;
    }
  }

  Future<Map<String, String>?> _uploadSeekerFileToPresigned({
    required String mediaType,
    required File file,
    required String contentType,
    String? filename,
  }) async {
    final bytes = await file.readAsBytes();
    final uploadRes = await _apiService.uploadSeekerMediaDirect(
      bodyBytes: bytes,
      contentType: contentType,
      mediaType: mediaType,
      filename: filename,
    );
    if (!uploadRes.success || uploadRes.data == null) return null;
    final url = uploadRes.data!['fileUrl'] as String?;
    if (url == null || url.isEmpty) return null;
    final displayUrl = (uploadRes.data!['displayUrl'] as String?)?.trim();
    return {
      'url': url,
      'displayUrl': (displayUrl != null && displayUrl.isNotEmpty) ? displayUrl : url,
    };
  }

  Future<void> _pickCertificate() async {
    if (_uploadingCertificate) return;
    setState(() => _uploadingCertificate = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 88);
      if (picked == null || !mounted) return;
      final file = File(picked.path);
      final lower = picked.path.toLowerCase();
      String contentType = 'image/jpeg';
      if (lower.endsWith('.png')) contentType = 'image/png';
      if (lower.endsWith('.webp')) contentType = 'image/webp';
      final uploaded = await _uploadSeekerFileToPresigned(
        mediaType: 'photo',
        file: file,
        contentType: contentType,
        filename: picked.name,
      );
      if (!mounted) return;
      if (uploaded != null) {
        setState(() => _certificateUrl = uploaded['url']);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.selectedLanguage == Language.hindi ? 'प्रमाणपत्र अपलोड हुआ' : 'Certificate uploaded'),
          backgroundColor: const Color(0xFF3D3D7B),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.selectedLanguage == Language.hindi ? 'अपलोड असफल' : 'Upload failed'),
          backgroundColor: Colors.redAccent,
        ));
      }
    } finally {
      if (mounted) setState(() => _uploadingCertificate = false);
    }
  }

  Future<void> _pickPortfolioMedia({required bool video}) async {
    if (_uploadingPortfolio || _workPortfolio.length >= 8) return;
    setState(() => _uploadingPortfolio = true);
    try {
      final picker = ImagePicker();
      final XFile? picked = video
          ? await picker.pickVideo(source: ImageSource.gallery)
          : await picker.pickImage(source: ImageSource.gallery, maxWidth: 1400, imageQuality: 85);
      if (picked == null || !mounted) return;
      final file = File(picked.path);
      final lower = picked.path.toLowerCase();
      String contentType;
      String mediaType;
      String kind;
      if (video) {
        contentType = 'video/mp4';
        mediaType = 'video';
        kind = 'video';
        if (lower.endsWith('.mov')) contentType = 'video/quicktime';
      } else {
        kind = 'image';
        mediaType = 'photo';
        contentType = 'image/jpeg';
        if (lower.endsWith('.png')) contentType = 'image/png';
        if (lower.endsWith('.webp')) contentType = 'image/webp';
      }
      if (!video) {
        setState(() => _workPortfolio.add({'localPath': picked.path, 'kind': kind}));
      }
      final uploaded = await _uploadSeekerFileToPresigned(
        mediaType: mediaType,
        file: file,
        contentType: contentType,
        filename: picked.name,
      );
      if (!mounted) return;
      if (uploaded != null) {
        setState(() {
          if (!video) {
            final idx = _workPortfolio.indexWhere(
              (e) => e['localPath'] == picked.path && (e['url'] == null || e['url']!.isEmpty),
            );
            final entry = {
              'url': uploaded['url']!,
              'displayUrl': uploaded['displayUrl']!,
              'localPath': picked.path,
              'kind': kind,
            };
            if (idx >= 0) {
              _workPortfolio[idx] = entry;
            } else {
              _workPortfolio.add(entry);
            }
          } else {
            _workPortfolio.add({
              'url': uploaded['url']!,
              'displayUrl': uploaded['displayUrl']!,
              'kind': kind,
            });
          }
        });
      } else {
        if (!video) {
          setState(() => _workPortfolio.removeWhere((e) => e['localPath'] == picked.path && e['url'] == null));
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.selectedLanguage == Language.hindi ? 'अपलोड असफल' : 'Upload failed'),
          backgroundColor: Colors.redAccent,
        ));
      }
    } finally {
      if (mounted) setState(() => _uploadingPortfolio = false);
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final data = <String, dynamic>{};
      if (_nameController.text.trim().isNotEmpty) data['fullName'] = _nameController.text.trim();
      if (_selectedGender != null) data['gender'] = _selectedGender;
      if (_selectedCity != null) data['city'] = _selectedCity;
      if (_selectedRole != null) data['preferredRole'] = _selectedRole;
      if (_experience != null) data['experience'] = _experience;
      data['experienceYears'] = _experienceYears.round().clamp(0, 50);
      if (_salaryController.text.trim().isNotEmpty) {
        final v = double.tryParse(_salaryController.text.trim());
        if (v != null) data['expectedSalary'] = v;
      }
      if (_expectedSalaryMaxController.text.trim().isNotEmpty) {
        final v = double.tryParse(_expectedSalaryMaxController.text.trim());
        if (v != null) data['expectedSalaryMax'] = v;
      }
      if (_currentSalaryController.text.trim().isNotEmpty) {
        final v = double.tryParse(_currentSalaryController.text.trim());
        if (v != null) data['currentSalary'] = v;
      }
      data['skills'] = _selectedSkills.toList();
      if (_profilePhotoStorageUrl != null && _profilePhotoStorageUrl!.trim().isNotEmpty) {
        data['profilePhotoUrl'] = _profilePhotoStorageUrl!.trim();
      }
      if (_maritalStatus != null) data['maritalStatus'] = _maritalStatus;
      if (_emailController.text.trim().isNotEmpty) {
        data['email'] = _emailController.text.trim();
      }
      if (_hasProfessionalCourse != null) {
        data['hasProfessionalCourse'] = _hasProfessionalCourse;
      }
      if (_certificateUrl != null && _certificateUrl!.trim().isNotEmpty) {
        data['professionalCourseCertificateUrl'] = _certificateUrl!.trim();
      }
      final portfolioToSave = _workPortfolio.where((e) => e['url'] != null && e['url']!.isNotEmpty).toList();
      if (portfolioToSave.isNotEmpty) {
        data['workPortfolioUrls'] = portfolioToSave
            .map((e) => {'url': e['url']!, 'kind': e['kind'] ?? 'image'})
            .toList();
      }

      final patch = await _apiService.patchSeekerProfile(data);
      if (!patch.success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(patch.message ?? (widget.selectedLanguage == Language.hindi ? 'सहेजने में त्रुटि' : 'Could not save')),
            backgroundColor: Colors.redAccent,
          ));
        }
        return;
      }

      final prefRes = await _apiService.updateSeekerPreferences({
        'jobType': _jobType ?? 'any',
        'preferredCities': _preferredCities.toList(),
        'immediateJoin': _immediateJoin,
      });
      if (!prefRes.success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(prefRes.message ?? (widget.selectedLanguage == Language.hindi ? 'प्राथमिकताएँ सहेजी नहीं गईं' : 'Preferences not saved')),
          backgroundColor: Colors.orange,
        ));
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.selectedLanguage == Language.hindi ? 'त्रुटि: $e' : 'Error: $e'),
          backgroundColor: Colors.redAccent,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Color(0xFF121A2C)), onPressed: () => Navigator.pop(context)),
        title: Text(_localizations.enhanceProfile, style: const TextStyle(color: Color(0xFF121A2C), fontSize: 18, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ResponsiveScrollPage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name
              Text(_localizations.yourFullName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              Text(
                widget.selectedLanguage == Language.hindi
                    ? 'आधार/पहचान पत्र जैसा ही नाम लिखें'
                    : 'Spell your name the same way as on your ID',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),

              Text(
                widget.selectedLanguage == Language.hindi ? 'प्रोफाइल फोटो' : 'Profile photo',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickingPhoto ? null : _pickSeekerPhoto,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: const Color(0xFF3D3D7B).withOpacity(0.12),
                      backgroundImage: jobtreeMediaImageProvider(_profilePhotoPreview),
                      child: (_profilePhotoPreview == null || _profilePhotoPreview!.isEmpty)
                          ? Text(
                              _nameController.text.trim().isNotEmpty
                                  ? _nameController.text.trim()[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Color(0xFF3D3D7B)),
                            )
                          : null,
                    ),
                    if (_pickingPhoto)
                      const SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.selectedLanguage == Language.hindi ? 'फोटो बदलने के लिए टैप करें' : 'Tap to add or change photo',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),

              // Gender
              Text(_localizations.selectGender, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: ['male', 'female', 'other'].map((g) {
                  final isSelected = _selectedGender == g;
                  final label = g == 'male' ? _localizations.male : g == 'female' ? _localizations.female : _localizations.otherGender;
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedGender = g),
                      child: Container(
                        padding: AppResponsive.screenPaddingHV(context, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF3D3D7B).withOpacity(0.1) : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: isSelected ? const Color(0xFF3D3D7B) : Colors.grey.shade300),
                        ),
                        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400, color: isSelected ? const Color(0xFF3D3D7B) : Colors.grey.shade700)),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // City
              Text(_localizations.seekerCity, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              InkWell(
                onTap: _citiesLoading
                    ? null
                    : () async {
                        final picked = await showIndiaCityPickerSheet(
                          context,
                          cities: _cities,
                          isLoading: false,
                          selected: _selectedCity,
                          title: _localizations.seekerCity,
                          searchHint: _localizations.searchLocation,
                        );
                        if (picked != null) setState(() => _selectedCity = picked);
                      },
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    suffixIcon: _citiesLoading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : const Icon(Icons.arrow_drop_down),
                  ),
                  child: Text(
                    _selectedCity ??
                        (_citiesLoading
                            ? (widget.selectedLanguage == Language.hindi ? 'शहर लोड हो रहे हैं…' : 'Loading cities…')
                            : _localizations.searchLocation),
                    style: TextStyle(
                      fontSize: 14,
                      color: _selectedCity != null ? const Color(0xFF121A2C) : Colors.grey.shade600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Text(
                _localizations.seekerPreferredWorkCities,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ..._preferredCities.map((c) {
                    return Chip(
                      label: Text(c, style: const TextStyle(fontSize: 13)),
                      onDeleted: () => setState(() => _preferredCities.remove(c)),
                      deleteIconColor: const Color(0xFF3D3D7B),
                    );
                  }),
                  ActionChip(
                    label: Text(widget.selectedLanguage == Language.hindi ? '+ शहर' : '+ Add city'),
                    onPressed: _citiesLoading
                        ? null
                        : () async {
                            final picked = await showIndiaCityPickerSheet(
                              context,
                              cities: _cities,
                              isLoading: false,
                              selected: null,
                              title: widget.selectedLanguage == Language.hindi ? 'शहर चुनें' : 'Pick a city',
                              searchHint: _localizations.searchLocation,
                            );
                            if (picked != null && picked.isNotEmpty) {
                              setState(() => _preferredCities.add(picked));
                            }
                          },
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Role + skills (taxonomy)
              Text(_localizations.preferredJobRole, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedRole == null
                          ? (widget.selectedLanguage == Language.hindi ? 'अभी तक नहीं चुना' : 'None selected')
                          : (_jobTaxonomy?.categoryLabel(_selectedRole!, widget.selectedLanguage == Language.hindi) ?? _selectedRole!),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Color(0xFF121A2C)),
                    ),
                    if (_selectedSkills.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _selectedSkills.map((s) {
                          final lab = _jobTaxonomy?.compoundLabel(s, widget.selectedLanguage == Language.hindi) ?? s;
                          return Chip(
                            label: Text(lab, style: const TextStyle(fontSize: 11)),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final cat = await JobTaxonomyCatalog.instance();
                    if (!mounted) return;
                    final hi = widget.selectedLanguage == Language.hindi;
                    final res = await Navigator.of(context).push<JobTaxonomyPickResult>(
                      MaterialPageRoute(
                        builder: (_) => JobTaxonomySelectionScreen(
                          hindi: hi,
                          catalog: cat,
                          initialCategoryId: _selectedRole,
                          initialCompoundSkills: _selectedSkills.toList(),
                          forSeekerProfile: true,
                        ),
                      ),
                    );
                    if (res != null && mounted) {
                      setState(() {
                        _selectedRole = res.categoryId;
                        _selectedSkills
                          ..clear()
                          ..addAll(res.compoundSkillIds);
                      });
                    }
                  },
                  icon: const Icon(Icons.category_outlined),
                  label: Text(
                    _localizations.seekerChooseJobTypeButton,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Text(
                widget.selectedLanguage == Language.hindi ? 'नौकरी का प्रकार' : 'Job type',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['full_time', 'part_time', 'any'].map((jt) {
                  final isSelected = (_jobType ?? 'any') == jt;
                  return GestureDetector(
                    onTap: () => setState(() => _jobType = jt),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF3D3D7B).withOpacity(0.1) : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isSelected ? const Color(0xFF3D3D7B) : Colors.grey.shade300),
                      ),
                      child: Text(
                        _jobTypeLabel(jt),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected ? const Color(0xFF3D3D7B) : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  widget.selectedLanguage == Language.hindi ? 'तुरंत जॉइन कर सकता हूँ' : 'Available to join immediately',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF121A2C)),
                ),
                value: _immediateJoin,
                activeColor: const Color(0xFF3D3D7B),
                onChanged: (v) => setState(() => _immediateJoin = v),
              ),
              const SizedBox(height: 12),

              // Experience
              Text(_localizations.experienceField, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: _experienceOptions.map((exp) {
                  final isSelected = _experience == exp;
                  return GestureDetector(
                    onTap: () => setState(() => _experience = exp),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF3D3D7B).withOpacity(0.1) : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isSelected ? const Color(0xFF3D3D7B) : Colors.grey.shade300),
                      ),
                      child: Text(_localizedExperience(exp), style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400, color: isSelected ? const Color(0xFF3D3D7B) : Colors.grey.shade700)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Text(
                widget.selectedLanguage == Language.hindi
                    ? 'कुल अनुभव (साल) — ${_experienceYears.round()}'
                    : 'Total experience (years): ${_experienceYears.round()}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              Slider(
                value: _experienceYears.clamp(0, 25),
                min: 0,
                max: 25,
                divisions: 25,
                activeColor: const Color(0xFF3D3D7B),
                onChanged: (v) => setState(() => _experienceYears = v),
              ),
              const SizedBox(height: 20),

              Text(
                widget.selectedLanguage == Language.hindi ? 'ईमेल (वैकल्पिक)' : 'Email (optional)',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'you@example.com',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 20),

              Text(
                _localizations.seekerMaritalStatus,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['single', 'married', 'widowed', 'divorced', 'prefer_not_say'].map((m) {
                  final isSelected = _maritalStatus == m;
                  return GestureDetector(
                    onTap: () => setState(() => _maritalStatus = m),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF3D3D7B).withOpacity(0.1) : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isSelected ? const Color(0xFF3D3D7B) : Colors.grey.shade300),
                      ),
                      child: Text(
                        _maritalLabel(m),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected ? const Color(0xFF3D3D7B) : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              Text(
                _localizations.seekerCurrentSalary,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _currentSalaryController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  hintText: '12000',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 20),

              Text(
                _localizations.expectedSalaryField,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _salaryController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  hintText: '15000',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.selectedLanguage == Language.hindi ? 'अपेक्षित सैलरी (अधिकतम, वैकल्पिक)' : 'Expected salary max (optional)',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _expectedSalaryMaxController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  hintText: '22000',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 20),

              Text(
                widget.selectedLanguage == Language.hindi ? 'कोई प्रोफेशनल कोर्स किया है?' : 'Completed a professional course?',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ChoiceChip(
                    label: Text(widget.selectedLanguage == Language.hindi ? 'हाँ' : 'Yes'),
                    selected: _hasProfessionalCourse == true,
                    onSelected: (_) => setState(() => _hasProfessionalCourse = true),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(widget.selectedLanguage == Language.hindi ? 'नहीं' : 'No'),
                    selected: _hasProfessionalCourse == false,
                    onSelected: (_) => setState(() => _hasProfessionalCourse = false),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _uploadingCertificate ? null : _pickCertificate,
                icon: _uploadingCertificate
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_file_outlined, size: 20),
                label: Text(
                  widget.selectedLanguage == Language.hindi ? 'प्रमाणपत्र फोटो अपलोड' : 'Upload certificate photo',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (_certificateUrl != null && _certificateUrl!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    widget.selectedLanguage == Language.hindi ? 'अपलोड हो गया' : 'Uploaded',
                    style: TextStyle(fontSize: 12, color: Colors.green.shade700),
                  ),
                ),
              const SizedBox(height: 20),

              Text(
                _localizations.seekerWorkPortfolio,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 88,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    ..._workPortfolio.asMap().entries.map((e) {
                      final i = e.key;
                      final item = e.value;
                      final isVideo = item['kind'] == 'video';
                      final previewSrc = item['localPath'] ?? item['displayUrl'] ?? item['url'];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Stack(
                          children: [
                            SizedBox(
                              width: 88,
                              height: 88,
                              child: isVideo
                                  ? Container(
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Center(
                                        child: Icon(Icons.videocam, size: 36, color: Color(0xFF3D3D7B)),
                                      ),
                                    )
                                  : jobtreeMediaThumbnail(urlOrPath: previewSrc),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: Material(
                                color: Colors.black54,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () => setState(() => _workPortfolio.removeAt(i)),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(Icons.close, color: Colors.white, size: 16),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (_workPortfolio.length < 8)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Column(
                          children: [
                            IconButton.filledTonal(
                              onPressed: _uploadingPortfolio ? null : () => _pickPortfolioMedia(video: false),
                              icon: const Icon(Icons.add_photo_alternate_outlined),
                            ),
                            IconButton.filledTonal(
                              onPressed: _uploadingPortfolio ? null : () => _pickPortfolioMedia(video: true),
                              icon: const Icon(Icons.video_call_outlined),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3D3D7B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isSaving
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_localizations.saveAndContinue, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============== POST JOB STEP 1 SCREEN (EMPLOYER FLOW) ==============
class PostJobStep1Screen extends StatefulWidget {
  final Language selectedLanguage;
  final String phoneNumber;
  
  const PostJobStep1Screen({
    super.key,
    required this.selectedLanguage,
    required this.phoneNumber,
  });

  @override
  State<PostJobStep1Screen> createState() => _PostJobStep1ScreenState();
}

class _PostJobStep1ScreenState extends State<PostJobStep1Screen> {
  late AppLocalizations _localizations;
  final ApiService _apiService = ApiService();
  JobTaxonomyCatalog? _jobTaxonomy;

  // Mandatory fields
  String? _selectedJobRole;
  String? _selectedLocation;
  int _numberOfStaff = 1;
  double _salaryMin = 8000;
  double _salaryMax = 25000;
  RangeValues _salaryRange = const RangeValues(10000, 20000);
  
  // Optional fields
  final TextEditingController _salonNameController = TextEditingController();
  final TextEditingController _ownerNameController = TextEditingController();
  
  // "Other" role handling
  String? _selectedOtherCategory;
  final TextEditingController _customRoleNameController = TextEditingController();
  
  // Skill bundles (for core service roles only)
  Set<String> _selectedSkillBundles = {};
  
  // Work timing & benefits (included in basic job details)
  ShiftTimingState _shiftTiming = ShiftTimingState.defaults();
  Set<String> _weeklyOff = {};
  Set<String> _selectedFacilities = {};
  late List<Map<String, String>> _daysOfWeek;
  
  // Location data
  List<String> _allLocations = [];
  bool _isLoadingLocations = false;
  
  // Job roles (main roles - max 8)
  List<Map<String, dynamic>> _jobRoles = [];
  
  // "Other" category groups
  List<Map<String, dynamic>> _otherCategories = [];
  
  // Skill bundles per role
  Map<String, List<Map<String, String>>> _skillBundlesPerRole = {};
  
  // Saving state
  bool _isSavingProfile = false;

  @override
  void initState() {
    super.initState();
    _localizations = AppLocalizations(widget.selectedLanguage);
    _initJobRoles();
    _initOtherCategories();
    _initSkillBundles();
    _initDaysOfWeek();
    _loadLocations();
    _loadExistingProfile();
    JobTaxonomyCatalog.instance().then((c) {
      if (mounted) setState(() => _jobTaxonomy = c);
    });
  }
  
  // Load existing salon profile data if available
  Future<void> _loadExistingProfile() async {
    try {
      final response = await _apiService.getSalonProfile();
      if (!mounted) return;
      
      if (response.success && response.data != null) {
        final profile = response.data!;
        setState(() {
          if (profile.salonName != null && profile.salonName!.isNotEmpty) {
            _salonNameController.text = profile.salonName!;
          }
          if (profile.ownerName != null && profile.ownerName!.isNotEmpty) {
            _ownerNameController.text = profile.ownerName!;
          }
          if (profile.city != null && profile.city!.isNotEmpty) {
            _selectedLocation = profile.city;
          }
        });
      }
    } catch (e) {
      // Silently handle - user can fill in data manually
    }
  }
  
  // Save salon profile data to backend
  Future<void> _saveSalonProfile() async {
    // Only save if there's data to save
    final updates = <String, dynamic>{};
    
    if (_salonNameController.text.trim().isNotEmpty) {
      updates['salonName'] = _salonNameController.text.trim();
    }
    if (_ownerNameController.text.trim().isNotEmpty) {
      updates['ownerName'] = _ownerNameController.text.trim();
    }
    if (_selectedLocation != null) {
      updates['city'] = _selectedLocation;
    }
    
    if (updates.isEmpty) return;
    
    setState(() {
      _isSavingProfile = true;
    });
    
    try {
      await _apiService.updateSalonProfile(updates);
    } catch (e) {
      // Silently handle - this is background save
    } finally {
      if (mounted) {
        setState(() {
          _isSavingProfile = false;
        });
      }
    }
  }

  void _initJobRoles() {
    // Main roles - max 8, one-tap selection
    _jobRoles = [
      {'id': 'hair_stylist', 'icon': Icons.content_cut, 'label': _localizations.hairStylist},
      {'id': 'beautician', 'icon': Icons.face_retouching_natural, 'label': _localizations.beautician},
      {'id': 'makeup_artist', 'icon': Icons.palette, 'label': _localizations.makeupArtist},
      {'id': 'massage_therapist', 'icon': Icons.spa, 'label': _localizations.massageTherapist},
      {'id': 'receptionist', 'icon': Icons.support_agent, 'label': _localizations.receptionist},
      {'id': 'helper', 'icon': Icons.handshake, 'label': _localizations.helper},
      {'id': 'manager', 'icon': Icons.manage_accounts, 'label': _localizations.manager},
      {'id': 'other', 'icon': Icons.more_horiz, 'label': _localizations.other},
    ];
  }
  
  void _initOtherCategories() {
    // Secondary grouped selection for "Other" - max 6-8 categories
    _otherCategories = [
      {'id': 'academy_training', 'icon': Icons.school, 'label': _localizations.academyTraining},
      {'id': 'management', 'icon': Icons.business_center, 'label': _localizations.managementRole},
      {'id': 'billing_cashier', 'icon': Icons.point_of_sale, 'label': _localizations.billingCashier},
      {'id': 'support_staff', 'icon': Icons.cleaning_services, 'label': _localizations.supportStaff},
      {'id': 'specialist', 'icon': Icons.star, 'label': _localizations.specialistRole},
      {'id': 'educator_trainer', 'icon': Icons.record_voice_over, 'label': _localizations.educatorTrainer},
      {'id': 'something_else', 'icon': Icons.edit_note, 'label': _localizations.somethingElse},
    ];
  }
  
  void _initSkillBundles() {
    // Skill bundles per core service role - max 4-6 bundles each
    _skillBundlesPerRole = {
      'hair_stylist': [
        {'id': 'haircuts_styling', 'label': _localizations.haircutsStyling},
        {'id': 'color_treatments', 'label': _localizations.colorTreatments},
        {'id': 'hair_spa_care', 'label': _localizations.hairSpaCare},
        {'id': 'beard_grooming', 'label': _localizations.beardGrooming},
      ],
      'beautician': [
        {'id': 'facials_skincare', 'label': _localizations.facialsSkincare},
        {'id': 'waxing_threading', 'label': _localizations.waxingThreading},
        {'id': 'manicure_pedicure', 'label': _localizations.manicurePedicure},
        {'id': 'bleach_cleanup', 'label': _localizations.bleachCleanup},
      ],
      'makeup_artist': [
        {'id': 'bridal_makeup', 'label': _localizations.bridalMakeup},
        {'id': 'party_makeup', 'label': _localizations.partyMakeup},
        {'id': 'hd_airbrush', 'label': _localizations.hdAirbrush},
        {'id': 'eye_makeup', 'label': _localizations.eyeMakeup},
      ],
      'massage_therapist': [
        {'id': 'body_massage', 'label': _localizations.bodyMassage},
        {'id': 'head_shoulder', 'label': _localizations.headShoulder},
        {'id': 'aromatherapy', 'label': _localizations.aromatherapy},
        {'id': 'foot_reflexology', 'label': _localizations.footReflexology},
      ],
    };
  }

  void _initDaysOfWeek() {
    _daysOfWeek = [
      {'id': 'sun', 'label': _localizations.sunday},
      {'id': 'mon', 'label': _localizations.monday},
      {'id': 'tue', 'label': _localizations.tuesday},
      {'id': 'wed', 'label': _localizations.wednesday},
      {'id': 'thu', 'label': _localizations.thursday},
      {'id': 'fri', 'label': _localizations.friday},
      {'id': 'sat', 'label': _localizations.saturday},
    ];
  }

  Future<void> _loadLocations() async {
    setState(() => _isLoadingLocations = true);
    try {
      IndiaCityService.instance.clearCache();
      final cities = await IndiaCityService.instance.loadCities(forceRefresh: true);
      if (mounted) setState(() => _allLocations = cities);
    } finally {
      if (mounted) setState(() => _isLoadingLocations = false);
    }
  }

  bool get _isMandatoryFieldsFilled {
    if (_selectedLocation == null || _numberOfStaff < 1) return false;
    if (_selectedJobRole == null) return false;
    if (_selectedJobRole == 'other') {
      return _customRoleNameController.text.trim().isNotEmpty ||
          _selectedSkillBundles.isNotEmpty;
    }
    final cat = _jobTaxonomy?.categoryById(_selectedJobRole);
    if (cat != null && cat.subcategories.isNotEmpty) {
      return _selectedSkillBundles.any((s) => s.startsWith('${_selectedJobRole!}/'));
    }
    return true;
  }

  Future<void> _showLocationPicker() async {
    final picked = await showIndiaCityPickerSheet(
      context,
      cities: _allLocations,
      isLoading: _isLoadingLocations,
      selected: _selectedLocation,
      title: _localizations.location,
      searchHint: _localizations.searchLocation,
    );
    if (picked != null && mounted) setState(() => _selectedLocation = picked);
  }

  String _formatSalary(double value) {
    if (value >= 1000) {
      return '₹${(value / 1000).toStringAsFixed(0)}K';
    }
    return '₹${value.toStringAsFixed(0)}';
  }

  @override
  void dispose() {
    _salonNameController.dispose();
    _ownerNameController.dispose();
    _customRoleNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // App bar with back button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.arrow_back, size: 20),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            
            // Three-step progress bar
            Padding(
              padding: AppResponsive.formScreenPadding(context),
              child: Row(
                children: [
                  // Step 1 (active)
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3D3D7B),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Step 2 (inactive)
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Step 3 (inactive)
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Title
            Padding(
              padding: AppResponsive.formScreenPadding(context),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _localizations.basicJobDetails,
                  style: TextStyle(
                    fontSize: AppResponsive.formTitleFontSize(context),
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF121A2C),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                padding: AppResponsive.formScreenPadding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. JOB TYPE & SKILLS (Mandatory)
                    Text(
                      '${_localizations.selectJobRole} *',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF121A2C),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final cat = await JobTaxonomyCatalog.instance();
                          if (!mounted) return;
                          final res = await Navigator.of(context).push<JobTaxonomyPickResult>(
                            MaterialPageRoute(
                              builder: (_) => JobTaxonomySelectionScreen(
                                hindi: widget.selectedLanguage == Language.hindi,
                                catalog: cat,
                                initialCategoryId: _selectedJobRole,
                                initialCompoundSkills: _selectedSkillBundles.toList(),
                              ),
                            ),
                          );
                          if (res != null && mounted) {
                            setState(() {
                              _selectedJobRole = res.categoryId;
                              _selectedSkillBundles
                                ..clear()
                                ..addAll(res.compoundSkillIds);
                              if (_selectedJobRole != 'other') {
                                _selectedOtherCategory = null;
                              }
                            });
                          }
                        },
                        icon: const Icon(Icons.category_outlined),
                        label: Text(
                          _localizations.chooseJobTypeAndSkills,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    if (_selectedJobRole != null) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Chip(
                            label: Text(
                              _jobTaxonomy?.categoryLabel(
                                    _selectedJobRole!,
                                    widget.selectedLanguage == Language.hindi,
                                  ) ??
                                  _selectedJobRole!,
                              style: const TextStyle(fontSize: 11),
                            ),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          ..._selectedSkillBundles.map((s) {
                            final lab = _jobTaxonomy?.compoundLabel(
                                  s,
                                  widget.selectedLanguage == Language.hindi,
                                ) ??
                                s;
                            return Chip(
                              label: Text(lab, style: const TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            );
                          }),
                        ],
                      ),
                    ],
                    if (_selectedJobRole == 'other') ...[
                      const SizedBox(height: 16),
                      Text(
                        _localizations.roleNameOptional,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF121A2C),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _customRoleNameController,
                        maxLength: 30,
                        decoration: InputDecoration(
                          hintText: _localizations.roleNamePlaceholder,
                          hintStyle: TextStyle(color: Colors.grey.shade400),
                          counterText: '',
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF3D3D7B)),
                          ),
                        ),
                      ),
                    ],
                    
                    const SizedBox(height: 24),
                    
                    // 2. LOCATION (Mandatory)
                    Text(
                      '${_localizations.location} *',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF121A2C),
                      ),
                    ),
                    const SizedBox(height: 8),
                    CompactLocationField(
                      selectedLocation: _selectedLocation,
                      placeholder: _localizations.selectLocation,
                      onTap: () => _showLocationPicker(),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // 3. NUMBER OF STAFF (Mandatory)
                    Text(
                      '${_localizations.numberOfStaff} *',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF121A2C),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FormBulletOptionRow<int>(
                      options: [
                        (value: 1, label: '1'),
                        (value: 2, label: '2'),
                        (value: 3, label: '3+'),
                      ],
                      groupValue: _numberOfStaff,
                      onChanged: (v) {
                        if (v != null) setState(() => _numberOfStaff = v);
                      },
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // 4. SALARY RANGE (Mandatory)
                    ResponsiveLabelValueRow(
                      label: Text(
                        '${_localizations.salaryRange} *',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF121A2C),
                        ),
                      ),
                      value: Text(
                        '${_formatSalary(_salaryRange.start)} - ${_formatSalary(_salaryRange.end)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF3D3D7B),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: const Color(0xFF3D3D7B),
                        inactiveTrackColor: Colors.grey.shade300,
                        thumbColor: const Color(0xFF3D3D7B),
                        overlayColor: const Color(0xFF3D3D7B).withOpacity(0.2),
                        rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 10),
                      ),
                      child: RangeSlider(
                        values: _salaryRange,
                        min: _salaryMin,
                        max: _salaryMax,
                        divisions: 17,
                        onChanged: (values) {
                          setState(() => _salaryRange = values);
                        },
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatSalary(_salaryMin),
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        Text(
                          _formatSalary(_salaryMax),
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 32),
                    
                    ShiftTimingPicker(
                      labels: ShiftTimingLabels(
                        hindi: widget.selectedLanguage == Language.hindi,
                        shiftTiming: _localizations.shiftTiming,
                        partTimeFreelance: _localizations.partTimeFreelance,
                        chooseTimeSlot: _localizations.shiftTimeSelectLabel,
                        fromLabel: _localizations.shiftFromLabel,
                        toLabel: _localizations.shiftToLabel,
                      ),
                      state: _shiftTiming,
                      onChanged: (s) => setState(() => _shiftTiming = s),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    Text(
                      _localizations.weeklyOff,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _daysOfWeek.map((day) {
                        final isSelected = _weeklyOff.contains(day['id']);
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _weeklyOff.remove(day['id']);
                              } else {
                                _weeklyOff.add(day['id']!);
                              }
                            });
                          },
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF3D3D7B) : Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? const Color(0xFF3D3D7B) : Colors.grey.shade300,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                day['label']!,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: isSelected ? Colors.white : const Color(0xFF121A2C),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    Text(
                      _localizations.facilitiesBenefits,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        {'id': 'accommodation', 'label': _localizations.accommodation, 'icon': Icons.home_outlined},
                        {'id': 'food', 'label': _localizations.foodProvided, 'icon': Icons.restaurant_outlined},
                        {'id': 'incentives', 'label': _localizations.incentives, 'icon': Icons.monetization_on_outlined},
                        {'id': 'paid_leave', 'label': _localizations.paidLeave, 'icon': Icons.event_available_outlined},
                        {'id': 'training', 'label': _localizations.training, 'icon': Icons.school_outlined},
                      ].map((facility) {
                        final isSelected = _selectedFacilities.contains(facility['id']);
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedFacilities.remove(facility['id']);
                              } else {
                                _selectedFacilities.add(facility['id'] as String);
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF3D3D7B) : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF3D3D7B) : Colors.grey.shade300,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  facility['icon'] as IconData,
                                  size: 18,
                                  color: isSelected ? Colors.white : Colors.grey.shade600,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  facility['label'] as String,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: isSelected ? Colors.white : const Color(0xFF121A2C),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Divider
                    Container(
                      height: 1,
                      color: Colors.grey.shade200,
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Optional fields header
                    Text(
                      widget.selectedLanguage == Language.hindi 
                          ? 'विश्वास बढ़ाने के लिए (वैकल्पिक)' 
                          : 'Build trust (optional)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // 5. SALON NAME (Optional)
                    Text(
                      _localizations.salonNameOptional,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF121A2C),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _salonNameController,
                      maxLength: 20,
                      decoration: InputDecoration(
                        hintText: _localizations.salonNamePlaceholder,
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        counterText: '',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF3D3D7B)),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // 6. OWNER NAME (Optional)
                    Text(
                      _localizations.ownerNameOptional,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF121A2C),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _ownerNameController,
                      decoration: InputDecoration(
                        hintText: _localizations.ownerNamePlaceholder,
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF3D3D7B)),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Contact number verified
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.verified,
                            color: Color(0xFF4CAF50),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _localizations.contactVerified,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF4CAF50),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 100), // Space for button
                  ],
                ),
              ),
            ),
            
            // Continue button
            Container(
              padding: AppResponsive.formFooterPadding(context),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: (_isMandatoryFieldsFilled && !_isSavingProfile) ? () async {
                    // Save salon profile in background
                    _saveSalonProfile();
                    
                    // Navigate to Step 2 immediately (don't wait for save)
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => PostJobStep2Screen(
                          selectedLanguage: widget.selectedLanguage,
                          phoneNumber: widget.phoneNumber,
                          // Pass Step 1 data
                          jobRole: _selectedJobRole!,
                          otherCategory: _selectedOtherCategory,
                          customRoleName: _customRoleNameController.text,
                          selectedSkills: _selectedSkillBundles.toList(),
                          location: _selectedLocation!,
                          numberOfStaff: _numberOfStaff,
                          salaryRange: _salaryRange,
                          salonName: _salonNameController.text,
                          ownerName: _ownerNameController.text,
                          shiftTiming: _shiftTiming,
                          weeklyOff: _weeklyOff.toList(),
                          selectedFacilities: _selectedFacilities.toList(),
                        ),
                      ),
                    );
                  } : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isMandatoryFieldsFilled 
                        ? const Color(0xFF3D3D7B) 
                        : Colors.grey.shade300,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _localizations.continueArrow,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _isMandatoryFieldsFilled ? Colors.white : Colors.grey.shade700,
                    ),
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

// ============== POST JOB STEP 2 SCREEN (WORK DETAILS) ==============
class PostJobStep2Screen extends StatefulWidget {
  final Language selectedLanguage;
  final String phoneNumber;
  
  // Data from Step 1
  final String jobRole;
  final String? otherCategory;
  final String customRoleName;
  final List<String> selectedSkills;
  final String location;
  final int numberOfStaff;
  final RangeValues salaryRange;
  final String salonName;
  final String ownerName;
  final ShiftTimingState shiftTiming;
  final List<String> weeklyOff;
  final List<String> selectedFacilities;
  
  const PostJobStep2Screen({
    super.key,
    required this.selectedLanguage,
    required this.phoneNumber,
    required this.jobRole,
    this.otherCategory,
    required this.customRoleName,
    required this.selectedSkills,
    required this.location,
    required this.numberOfStaff,
    required this.salaryRange,
    required this.salonName,
    required this.ownerName,
    required this.shiftTiming,
    required this.weeklyOff,
    required this.selectedFacilities,
  });

  @override
  State<PostJobStep2Screen> createState() => _PostJobStep2ScreenState();
}

class _PostJobStep2ScreenState extends State<PostJobStep2Screen> {
  late AppLocalizations _localizations;
  
  // Mandatory fields
  String _selectedWorkType = 'full_time'; // default for low-friction quick post
  String _selectedExperience = 'fresher_ok'; // default for low-friction quick post
  
  // Optional fields
  String? _selectedAccommodation; // 'yes' or 'no' (null = not selected)
  String? _selectedGender; // 'male', 'female', 'any' (null = treated as 'any')

  @override
  void initState() {
    super.initState();
    _localizations = AppLocalizations(widget.selectedLanguage);
  }

  bool get _isMandatoryFieldsFilled {
    // Quick flow should never block; defaults keep backend happy
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // App bar with back button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.arrow_back, size: 20),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            
            // Three-step progress bar
            Padding(
              padding: AppResponsive.formScreenPadding(context),
              child: Row(
                children: [
                  // Step 1 (completed)
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50), // Green for completed
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Step 2 (active)
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3D3D7B),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Step 3 (inactive)
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Title
            Padding(
              padding: AppResponsive.formScreenPadding(context),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _localizations.workDetails,
                  style: TextStyle(
                    fontSize: AppResponsive.formTitleFontSize(context),
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF121A2C),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: AppResponsive.formScreenPadding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. EXPERIENCE (Mandatory)
                    Text(
                      '${_localizations.experience} *',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF121A2C),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FormBulletOption<String>(
                      value: 'fresher_ok',
                      groupValue: _selectedExperience,
                      label: _localizations.fresherOk,
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedExperience = v);
                      },
                    ),
                    FormBulletOption<String>(
                      value: 'experience_required',
                      groupValue: _selectedExperience,
                      label: _localizations.experienceRequired,
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedExperience = v);
                      },
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Divider
                    Container(
                      height: 1,
                      color: Colors.grey.shade200,
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Optional section header
                    Text(
                      widget.selectedLanguage == Language.hindi 
                          ? 'अतिरिक्त जानकारी (वैकल्पिक)' 
                          : 'Additional info (optional)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // 3. GENDER PREFERENCE (Optional)
                    Text(
                      _localizations.genderPreferenceOptional,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ResponsiveChipRow(
                      children: [
                        _buildGenderChip(
                          id: 'male',
                          label: _localizations.male,
                          isSelected: _selectedGender == 'male',
                          onTap: () => setState(() {
                            _selectedGender = _selectedGender == 'male' ? null : 'male';
                          }),
                        ),
                        _buildGenderChip(
                          id: 'female',
                          label: _localizations.female,
                          isSelected: _selectedGender == 'female',
                          onTap: () => setState(() {
                            _selectedGender = _selectedGender == 'female' ? null : 'female';
                          }),
                        ),
                        _buildGenderChip(
                          id: 'any',
                          label: _localizations.anyGender,
                          isSelected: _selectedGender == 'any',
                          onTap: () => setState(() {
                            _selectedGender = _selectedGender == 'any' ? null : 'any';
                          }),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 100), // Space for button
                  ],
                ),
              ),
            ),
            
            // Continue button
            Container(
              padding: AppResponsive.formFooterPadding(context),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isMandatoryFieldsFilled ? () {
                    // Navigate to Step 3 (Review & Post)
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => PostJobStep3Screen(
                          selectedLanguage: widget.selectedLanguage,
                          phoneNumber: widget.phoneNumber,
                          // Step 1 data
                          jobRole: widget.jobRole,
                          otherCategory: widget.otherCategory,
                          customRoleName: widget.customRoleName,
                          selectedSkills: widget.selectedSkills,
                          location: widget.location,
                          numberOfStaff: widget.numberOfStaff,
                          salaryRange: widget.salaryRange,
                          salonName: widget.salonName,
                          ownerName: widget.ownerName,
                          shiftTiming: widget.shiftTiming,
                          weeklyOff: widget.weeklyOff,
                          selectedFacilities: widget.selectedFacilities,
                          // Step 2 data
                          workType: _selectedWorkType,
                          experience: _selectedExperience,
                          accommodation: _selectedAccommodation,
                          gender: _selectedGender,
                        ),
                      ),
                    );
                  } : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isMandatoryFieldsFilled 
                        ? const Color(0xFF3D3D7B) 
                        : Colors.grey.shade300,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _localizations.continueArrow,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _isMandatoryFieldsFilled ? Colors.white : Colors.grey.shade700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenderChip({
    required String id,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3D3D7B).withOpacity(0.1) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF3D3D7B) : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? const Color(0xFF3D3D7B) : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}

// ============== POST JOB STEP 3 SCREEN (REVIEW & POST) ==============
class PostJobStep3Screen extends StatefulWidget {
  final Language selectedLanguage;
  final String phoneNumber;
  
  // Step 1 data
  final String jobRole;
  final String? otherCategory;
  final String customRoleName;
  final List<String> selectedSkills;
  final String location;
  final int numberOfStaff;
  final RangeValues salaryRange;
  final String salonName;
  final String ownerName;
  
  // Step 2 data
  final String workType;
  final String experience;
  final String? accommodation;
  final String? gender;
  final ShiftTimingState shiftTiming;
  final List<String> weeklyOff;
  final List<String> selectedFacilities;
  
  const PostJobStep3Screen({
    super.key,
    required this.selectedLanguage,
    required this.phoneNumber,
    required this.jobRole,
    this.otherCategory,
    required this.customRoleName,
    required this.selectedSkills,
    required this.location,
    required this.numberOfStaff,
    required this.salaryRange,
    required this.salonName,
    required this.ownerName,
    required this.workType,
    required this.experience,
    this.accommodation,
    this.gender,
    required this.shiftTiming,
    required this.weeklyOff,
    required this.selectedFacilities,
  });

  @override
  State<PostJobStep3Screen> createState() => _PostJobStep3ScreenState();
}

class _PostJobStep3ScreenState extends State<PostJobStep3Screen> {
  late AppLocalizations _localizations;
  bool _isPosting = false;
  final ApiService _apiService = ApiService();
  JobTaxonomyCatalog? _taxonomy;

  @override
  void initState() {
    super.initState();
    _localizations = AppLocalizations(widget.selectedLanguage);
    JobTaxonomyCatalog.instance().then((c) {
      if (mounted) setState(() => _taxonomy = c);
    });
  }

  String get _displayRoleName {
    final hi = widget.selectedLanguage == Language.hindi;
    if (widget.jobRole == 'other') {
      if (widget.customRoleName.isNotEmpty) {
        return widget.customRoleName;
      }
      return _localizations.salonStaff;
    }
    final cat = _taxonomy?.categoryById(widget.jobRole);
    if (cat != null) return cat.labelFor(hi);
    final roleNames = {
      'hair_stylist': _localizations.hairStylist,
      'beautician': _localizations.beautician,
      'makeup_artist': _localizations.makeupArtist,
      'massage_therapist': _localizations.massageTherapist,
      'receptionist': _localizations.receptionist,
      'helper': _localizations.helper,
      'manager': _localizations.manager,
    };
    return roleNames[widget.jobRole] ?? _localizations.salonStaff;
  }

  String get _displayWorkType {
    return widget.workType == 'full_time' 
        ? _localizations.fullTime 
        : _localizations.partTime;
  }

  String get _displayExperience {
    return widget.experience == 'fresher_ok' 
        ? _localizations.fresherOk 
        : _localizations.experienceRequired;
  }

  String get _displayGender {
    if (widget.gender == 'male') return _localizations.male;
    if (widget.gender == 'female') return _localizations.female;
    return _localizations.anyGender;
  }

  String _formatSalary(double value) {
    if (value >= 1000) {
      return '₹${(value / 1000).toStringAsFixed(0)}K';
    }
    return '₹${value.toStringAsFixed(0)}';
  }

  Future<void> _postJob() async {
    setState(() => _isPosting = true);
    
    try {
      // Call API to create job
      final response = await _apiService.createJob(
        jobRole: widget.jobRole,
        otherCategory: widget.otherCategory,
        customRoleName: widget.customRoleName.isNotEmpty ? widget.customRoleName : null,
        skills: widget.selectedSkills.isNotEmpty ? widget.selectedSkills : null,
        location: widget.location,
        numberOfStaff: widget.numberOfStaff,
        salaryMin: widget.salaryRange.start,
        salaryMax: widget.salaryRange.end,
        workType: widget.workType,
        experience: widget.experience,
        accommodation: widget.accommodation,
        preferredGender: widget.gender ?? 'any',
        shiftType: widget.shiftTiming.toApiShiftType(),
        weeklyOff: widget.weeklyOff.isNotEmpty ? widget.weeklyOff : null,
        facilities: widget.selectedFacilities.isNotEmpty ? widget.selectedFacilities : null,
        description: ShiftTimingMeta.mergeIntoDescription('', widget.shiftTiming),
      );
      
      if (response.success && response.data != null && mounted) {
        // Navigate to success screen with job data (including job completion from DB)
        final createdJob = response.data!;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => JobPostedSuccessScreen(
              selectedLanguage: widget.selectedLanguage,
              jobId: createdJob.id,
              jobRole: _displayRoleName,
              location: widget.location,
              initialJobCompletionPercent: createdJob.completionPercent,
            ),
          ),
        );
      } else {
        // Show error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Failed to post job. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => _isPosting = false);
        }
      }
    } catch (e) {
      print('Error posting job: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error posting job: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isPosting = false);
      }
    }
  }

  void _goToStep(int step) {
    // Pop back to the relevant step
    int popCount = 3 - step;
    for (int i = 0; i < popCount; i++) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // App bar with back button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.arrow_back, size: 20),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            
            // Three-step progress bar (all completed/active)
            Padding(
              padding: AppResponsive.formScreenPadding(context),
              child: Row(
                children: [
                  // Step 1 (completed)
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Step 2 (completed)
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Step 3 (active)
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3D3D7B),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Title and subtitle
            Padding(
              padding: AppResponsive.formScreenPadding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _localizations.postJob,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF121A2C),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _localizations.reviewOnce,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Job Summary Card
            Expanded(
              child: SingleChildScrollView(
                padding: AppResponsive.formScreenPadding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Summary card
                    Container(
                      width: double.infinity,
                      padding: AppResponsive.cardPaddingInsets(context),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header with edit button
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _localizations.jobSummary,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF121A2C),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => _goToStep(1),
                                child: Text(
                                  _localizations.edit,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF3D3D7B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 20),
                          
                          // Role
                          _buildSummaryRow(
                            icon: Icons.work_outline,
                            label: _localizations.roleLabel,
                            value: _displayRoleName,
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Location
                          _buildSummaryRow(
                            icon: Icons.location_on_outlined,
                            label: _localizations.locationLabel,
                            value: widget.location,
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Staff needed
                          _buildSummaryRow(
                            icon: Icons.people_outline,
                            label: _localizations.staffNeeded,
                            value: widget.numberOfStaff >= 3 ? '3+' : '${widget.numberOfStaff}',
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Salary
                          _buildSummaryRow(
                            icon: Icons.currency_rupee,
                            label: _localizations.salaryLabel,
                            value: '${_formatSalary(widget.salaryRange.start)} - ${_formatSalary(widget.salaryRange.end)} ${_localizations.perMonth}',
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Work type
                          _buildSummaryRow(
                            icon: Icons.schedule_outlined,
                            label: _localizations.workTypeLabel,
                            value: _displayWorkType,
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Experience
                          _buildSummaryRow(
                            icon: Icons.verified_user_outlined,
                            label: _localizations.experienceLabel,
                            value: _displayExperience,
                          ),
                          
                          // Gender (only if not 'any' or null)
                          if (widget.gender != null && widget.gender != 'any') ...[
                            const SizedBox(height: 16),
                            _buildSummaryRow(
                              icon: Icons.person_outline,
                              label: _localizations.genderLabel,
                              value: _displayGender,
                            ),
                          ],
                          
                          // Salon name (only if provided)
                          if (widget.salonName.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _buildSummaryRow(
                              icon: Icons.store_outlined,
                              label: _localizations.salonLabel,
                              value: widget.salonName,
                            ),
                          ],
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 100), // Space for button
                  ],
                ),
              ),
            ),
            
            // Post Job button
            Container(
              padding: AppResponsive.formFooterPadding(context),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isPosting ? null : _postJob,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3D3D7B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isPosting
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _localizations.posting,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          _localizations.postJobButton,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: Colors.grey.shade600,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF121A2C),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============== JOB POSTED SUCCESS SCREEN ==============
class JobPostedSuccessScreen extends StatefulWidget {
  final Language selectedLanguage;
  final String jobId; // Job ID to fetch completion from DB
  final String jobRole;
  final String location;
  final int initialJobCompletionPercent; // Initial completion from created job
  
  const JobPostedSuccessScreen({
    super.key,
    required this.selectedLanguage,
    required this.jobId,
    required this.jobRole,
    required this.location,
    required this.initialJobCompletionPercent,
  });

  @override
  State<JobPostedSuccessScreen> createState() => _JobPostedSuccessScreenState();
}

class _JobPostedSuccessScreenState extends State<JobPostedSuccessScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late AppLocalizations _localizations;
  final ApiService _apiService = ApiService();
  
  // Job completion state (fetched from jobs table in DB)
  late int _completionPercentage;
  Set<String> _completedSections = {};
  bool _isLoadingJobCompletion = false;

  @override
  void initState() {
    super.initState();
    _localizations = AppLocalizations(widget.selectedLanguage);
    
    // Initialize with the completion from the created job (from DB)
    _completionPercentage = widget.initialJobCompletionPercent;
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    ));

    _animationController.forward();
    
    // Fetch latest job completion from database
    _loadJobCompletion();
  }
  
  /// Fetch job completion percentage from jobs table in database
  Future<void> _loadJobCompletion() async {
    setState(() {
      _isLoadingJobCompletion = true;
    });
    
    try {
      // Fetch job data including completion_percent from database
      final jobResponse = await _apiService.getJobById(widget.jobId);
      
      if (!mounted) return;
      
      if (jobResponse.success && jobResponse.data != null) {
        setState(() {
          // Use completion_percent from jobs table
          _completionPercentage = jobResponse.data!.completionPercent;
        });
      }
    } catch (e) {
      // Silently handle error - keep initial value
      print('Error loading job completion: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingJobCompletion = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return Opacity(
              opacity: _fadeAnimation.value,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: AppResponsive.formScreenPadding(context),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 80),
                            
                            // Success checkmark
                            Transform.scale(
                              scale: _scaleAnimation.value,
                              child: Container(
                                width: 120,
                                height: 120,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF4CAF50),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 60,
                                ),
                              ),
                            ),
                            
                            const SizedBox(height: 32),
                            
                            // Success message
                            Text(
                              _localizations.jobLive,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF121A2C),
                              ),
                            ),
                            
                            const SizedBox(height: 12),
                            
                            // Job details
                            Text(
                              '${widget.jobRole} • ${widget.location}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w400,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            
                            const SizedBox(height: 48),
                            
                            // Loading indicator while fetching profile
                            if (_isLoadingJobCompletion)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 16),
                                child: SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3D3D7B)),
                                  ),
                                ),
                              ),
                            
                            // Nudge card (non-blocking) - shows improvement nudge or success based on completion
                            if (!_isLoadingJobCompletion && _completionPercentage >= 90)
                              // Success card when job profile is mostly complete
                              Container(
                                width: double.infinity,
                                padding: AppResponsive.cardPaddingInsets(context),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8F5E9),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppResponsive.ownerHomeCardBorder),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle,
                                      color: Color(0xFF4CAF50),
                                      size: 24,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            widget.selectedLanguage == Language.hindi
                                                ? 'बहुत बढ़िया! 🎉'
                                                : 'Great job! 🎉',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF2E7D32),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${_localizations.jobProfileComplete} $_completionPercentage% ${_localizations.complete}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w400,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else if (!_isLoadingJobCompletion)
                              // Improvement nudge card
                              Container(
                                width: double.infinity,
                                padding: AppResponsive.cardPaddingInsets(context),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF8E1),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppResponsive.ownerHomeCardBorder),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.lightbulb_outline,
                                          color: Color(0xFFF9A825),
                                          size: 24,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            _localizations.improveJobNudge,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: Color(0xFF5D4037),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    // Progress indicator (showing JOB completion from jobs table)
                                    Row(
                                      children: [
                                        if (_isLoadingJobCompletion)
                                          const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        else
                                          Text(
                                            '${_localizations.jobProfileComplete} $_completionPercentage%',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w400,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: _completionPercentage / 100,
                                        backgroundColor: Colors.grey.shade300,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          _completionPercentage >= 80 
                                              ? const Color(0xFF4CAF50)  // Green when high
                                              : const Color(0xFFF9A825), // Yellow otherwise
                                        ),
                                        minHeight: 6,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    // Improve button (जानकारी जोड़ें) - Shows only optional fields
                                    GestureDetector(
                                      onTap: () async {
                                        final result = await Navigator.of(context).push<Map<String, dynamic>>(
                                          MaterialPageRoute(
                                            builder: (context) => JobEditScreen(
                                              selectedLanguage: widget.selectedLanguage,
                                              jobId: widget.jobId,
                                            ),
                                          ),
                                        );
                                        
                                        // Refresh job completion from database after returning from Improve Job
                                        if (result != null && result['success'] == true && mounted) {
                                          await _loadJobCompletion(); // Fetch fresh completion from DB
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: AppResponsive.ownerHomeCardBorder),
                                        ),
                                        child: Text(
                                          _localizations.improveJob,
                                          textAlign: TextAlign.center,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          softWrap: true,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFFF9A825),
                                            height: 1.25,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  // Bottom actions
                  Container(
                    padding: AppResponsive.formFooterPadding(context),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // View Job button
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => CandidateListScreen(
                                    selectedLanguage: widget.selectedLanguage,
                                    jobId: widget.jobId,
                                    jobTitle: widget.jobRole,
                                    jobLocation: widget.location,
                                  ),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3D3D7B),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              _localizations.viewJob,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              softWrap: true,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Go to Dashboard button
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: TextButton(
                            onPressed: () {
                              // Navigate to home screen
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (context) => JobOwnerHomeScreen(
                                    selectedLanguage: widget.selectedLanguage,
                                  ),
                                ),
                                (route) => false,
                              );
                            },
                            style: TextButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              _localizations.goToDashboard,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ============== IMPROVE JOB SCREEN (OPTIONAL FIELDS ONLY) ==============
class ImproveJobScreen extends StatefulWidget {
  final Language selectedLanguage;
  final String jobId;
  
  const ImproveJobScreen({
    super.key,
    required this.selectedLanguage,
    required this.jobId,
  });

  @override
  State<ImproveJobScreen> createState() => _ImproveJobScreenState();
}

class _ImproveJobScreenState extends State<ImproveJobScreen> {
  late AppLocalizations _localizations;
  final ApiService _apiService = ApiService();
  
  Job? _job;
  bool _isLoadingJob = true;
  bool _isSaving = false;
  int _completionPercentage = 40;
  int? _expandedSection;
  
  // Section 1: Skills
  String? _selectedJobRole;
  Set<String> _selectedSkills = {};
  bool _skillsSaved = false;
  
  // Section 2: Work Timings
  ShiftTimingState _shiftTiming = ShiftTimingState.defaults();
  Set<String> _weeklyOff = {};
  bool _timingsSaved = false;
  
  // Section 3: Facilities
  Set<String> _selectedFacilities = {};
  bool _facilitiesSaved = false;
  
  // Section 4: Salon Details
  final TextEditingController _descriptionController = TextEditingController();
  bool _salonDetailsSaved = false;
  
  // Available skills based on role
  late List<String> _availableSkills;
  late List<Map<String, String>> _daysOfWeek;
  
  // Skill bundles per role (legacy; improve flow uses taxonomy picker)
  Map<String, List<Map<String, String>>> _skillBundlesPerRole = {};
  JobTaxonomyCatalog? _jobTaxonomy;
  
  @override
  void initState() {
    super.initState();
    _localizations = AppLocalizations(widget.selectedLanguage);
    _initSkills();
    _initDaysOfWeek();
    _initSkillBundles();
    _loadJobFromDatabase();
    JobTaxonomyCatalog.instance().then((c) {
      if (mounted) setState(() => _jobTaxonomy = c);
    });
  }
  
  void _initSkills() {
    _availableSkills = [
      _localizations.haircutsStyling,
      _localizations.colorTreatments,
      _localizations.hairSpaCare,
      _localizations.beardGrooming,
      _localizations.facialsSkincare,
      _localizations.waxingThreading,
      _localizations.manicurePedicure,
      _localizations.bridalMakeup,
      _localizations.partyMakeup,
      _localizations.bodyMassage,
    ];
  }
  
  void _initDaysOfWeek() {
    _daysOfWeek = [
      {'id': 'sun', 'label': _localizations.sunday},
      {'id': 'mon', 'label': _localizations.monday},
      {'id': 'tue', 'label': _localizations.tuesday},
      {'id': 'wed', 'label': _localizations.wednesday},
      {'id': 'thu', 'label': _localizations.thursday},
      {'id': 'fri', 'label': _localizations.friday},
      {'id': 'sat', 'label': _localizations.saturday},
    ];
  }
  
  void _initSkillBundles() {
    _skillBundlesPerRole = {
      'hair_stylist': [
        {'id': 'haircuts_styling', 'label': _localizations.haircutsStyling},
        {'id': 'color_treatments', 'label': _localizations.colorTreatments},
        {'id': 'hair_spa_care', 'label': _localizations.hairSpaCare},
        {'id': 'beard_grooming', 'label': _localizations.beardGrooming},
      ],
      'beautician': [
        {'id': 'facials_skincare', 'label': _localizations.facialsSkincare},
        {'id': 'waxing_threading', 'label': _localizations.waxingThreading},
        {'id': 'manicure_pedicure', 'label': _localizations.manicurePedicure},
        {'id': 'bleach_cleanup', 'label': _localizations.bleachCleanup},
      ],
      'makeup_artist': [
        {'id': 'bridal_makeup', 'label': _localizations.bridalMakeup},
        {'id': 'party_makeup', 'label': _localizations.partyMakeup},
        {'id': 'hd_airbrush', 'label': _localizations.hdAirbrush},
        {'id': 'eye_makeup', 'label': _localizations.eyeMakeup},
      ],
      'massage_therapist': [
        {'id': 'body_massage', 'label': _localizations.bodyMassage},
        {'id': 'head_shoulder', 'label': _localizations.headShoulder},
        {'id': 'aromatherapy', 'label': _localizations.aromatherapy},
        {'id': 'foot_reflexology', 'label': _localizations.footReflexology},
      ],
    };
  }
  
  Future<void> _loadJobFromDatabase() async {
    setState(() {
      _isLoadingJob = true;
    });
    
    try {
      final response = await _apiService.getJobById(widget.jobId);
      
      if (!mounted) return;
      
      if (response.success && response.data != null) {
        final job = response.data!;
        setState(() {
          _job = job;
          _completionPercentage = job.completionPercent;
          
          // Load existing optional fields
          final loadedRole = JobTaxonomyCatalog.effectiveCategoryId(
            jobRole: job.jobRole,
            skills: job.skills,
          );
          _selectedJobRole = loadedRole.isEmpty ? null : loadedRole;
          _selectedSkills = JobTaxonomyCatalog.skillsMatchingRole(loadedRole, job.skills).toSet();
          _skillsSaved = _selectedSkills.isNotEmpty;
          
          _shiftTiming = ShiftTimingState.fromJob(
            shiftType: job.shiftType,
            description: job.description,
          );
          if (job.shiftType != null) {
            _timingsSaved = true;
          }
          
          _weeklyOff = job.weeklyOff.toSet();
          if (_weeklyOff.isNotEmpty) {
            _timingsSaved = true;
          }
          
          _selectedFacilities = job.facilities.toSet();
          _facilitiesSaved = job.facilities.isNotEmpty;
          
          if (job.description != null && job.description!.isNotEmpty) {
            _descriptionController.text =
                ShiftTimingMeta.stripMeta(job.description!);
            _salonDetailsSaved = true;
          }
        });
      }
    } catch (e) {
      print('Error loading job: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingJob = false;
        });
      }
    }
  }
  
  void _toggleSection(int index) {
    setState(() {
      _expandedSection = _expandedSection == index ? null : index;
    });
  }
  
  Future<void> _saveSection(int section) async {
    if (_isSaving) return;
    
    setState(() {
      _isSaving = true;
    });
    
    try {
      Map<String, dynamic> updates = {};
      
      switch (section) {
        case 0: // Skills + sync job_role from taxonomy picker
          final newRole = _selectedJobRole ??
              (_job != null
                  ? JobTaxonomyCatalog.effectiveCategoryId(
                      jobRole: _job!.jobRole,
                      skills: _selectedSkills.toList(),
                    )
                  : null) ??
              JobTaxonomyCatalog.categoryIdFromSkills(_selectedSkills);
          final roleId = newRole ?? '';
          final filteredSkills = JobTaxonomyCatalog.skillsMatchingRole(roleId, _selectedSkills);
          updates = {
            'skills': filteredSkills,
            if (newRole != null && newRole.isNotEmpty) 'jobRole': newRole,
          };
          break;
        case 1: // Work Timings
          updates = {
            'shiftType': _shiftTiming.toApiShiftType(),
            'weeklyOff': _weeklyOff.toList(),
            'description': ShiftTimingMeta.mergeIntoDescription(
              _descriptionController.text.trim(),
              _shiftTiming,
            ),
          };
          break;
        case 2: // Facilities
          updates = {
            'facilities': _selectedFacilities.toList(),
          };
          break;
        case 3: // Job Description
          updates = {
            'description': _descriptionController.text.trim(),
          };
          break;
      }
      
      if (updates.isEmpty) {
        setState(() {
          _isSaving = false;
        });
        return;
      }
      
      final response = await _apiService.updateJob(
        jobId: widget.jobId,
        updates: updates,
      );
      
      if (!mounted) return;
      
      if (response.success && response.data != null) {
        await _loadJobFromDatabase();
        
        setState(() {
          switch (section) {
            case 0:
              _skillsSaved = _selectedSkills.isNotEmpty;
              break;
            case 1:
              _timingsSaved = _weeklyOff.isNotEmpty || _shiftTiming.mode.isNotEmpty;
              break;
            case 2:
              _facilitiesSaved = _selectedFacilities.isNotEmpty;
              break;
            case 3:
              _salonDetailsSaved = _descriptionController.text.trim().isNotEmpty;
              break;
          }
          _expandedSection = null;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_localizations.saved),
              duration: const Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF4CAF50),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                widget.selectedLanguage == Language.hindi
                    ? 'सेव करने में समस्या हुई'
                    : 'Failed to save',
              ),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.selectedLanguage == Language.hindi
                  ? 'कुछ गलत हो गया'
                  : 'Something went wrong',
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
  
  void _goBackWithData() {
    Navigator.of(context).pop({
      'success': true,
      'jobId': widget.jobId,
      'completionPercent': _completionPercentage,
    });
  }
  
  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _goBackWithData();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              // App bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _goBackWithData,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.arrow_back, size: 20),
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
              
              // Progress bar
              if (_isLoadingJob)
                Padding(
                  padding: AppResponsive.screenPaddingAll(context),
                  child: const Center(child: CircularProgressIndicator()),
                )
              else
                Padding(
                  padding: AppResponsive.formScreenPadding(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_localizations.jobProfileProgress} $_completionPercentage% ${_localizations.complete}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _completionPercentage / 100,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                ),
            
            const SizedBox(height: 24),
            
            // Title
            Padding(
              padding: AppResponsive.formScreenPadding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _localizations.improveJobTitle,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF121A2C),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _localizations.improveJobSubtext,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Accordion sections
            Expanded(
              child: SingleChildScrollView(
                padding: AppResponsive.formScreenPadding(context),
                child: Column(
                  children: [
                    // Section 1: Skills & Work Details
                    _buildAccordionSection(
                      index: 0,
                      title: _localizations.skillsWorkDetails,
                      subtitle: _localizations.recommended,
                      isRecommended: true,
                      isSaved: _skillsSaved,
                      content: _buildSkillsContent(),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Section 2: Work Timings
                    _buildAccordionSection(
                      index: 1,
                      title: _localizations.workTimings,
                      subtitle: _localizations.optional,
                      isRecommended: false,
                      isSaved: _timingsSaved,
                      content: _buildTimingsContent(),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Section 3: Facilities & Benefits
                    _buildAccordionSection(
                      index: 2,
                      title: _localizations.facilitiesBenefits,
                      subtitle: _localizations.optional,
                      isRecommended: false,
                      isSaved: _facilitiesSaved,
                      content: _buildFacilitiesContent(),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Section 4: Salon Details
                    _buildAccordionSection(
                      index: 3,
                      title: _localizations.salonDetails,
                      subtitle: _localizations.optional,
                      isRecommended: false,
                      isSaved: _salonDetailsSaved,
                      content: _buildSalonDetailsContent(),
                    ),
                    
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
            
            // Done button
            Container(
              padding: AppResponsive.formFooterPadding(context),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _goBackWithData,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3D3D7B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _localizations.doneGoBack,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildAccordionSection({
    required int index,
    required String title,
    required String subtitle,
    required bool isRecommended,
    required bool isSaved,
    required Widget content,
  }) {
    final isExpanded = _expandedSection == index;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpanded ? const Color(0xFF3D3D7B) : Colors.grey.shade200,
          width: isExpanded ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => _toggleSection(index),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF121A2C),
                              ),
                            ),
                            if (isSaved) ...[
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.check_circle,
                                size: 18,
                                color: Color(0xFF4CAF50),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isRecommended 
                                ? const Color(0xFF3D3D7B).withOpacity(0.1)
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: isRecommended 
                                  ? const Color(0xFF3D3D7B)
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),
          
          if (isExpanded)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: content,
            ),
        ],
      ),
    );
  }
  
  Widget _buildSkillsContent() {
    final hi = widget.selectedLanguage == Language.hindi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 12),
        Text(
          _localizations.selectRelevantSkills,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 12),
        if (_selectedSkills.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _selectedSkills.map((s) {
              final lab = _jobTaxonomy?.compoundLabel(s, hi) ?? s;
              return Chip(
                label: Text(lab, style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              );
            }).toList(),
          )
        else
          Text(hi ? 'अभी कोई कौशल नहीं चुना' : 'No skills selected yet', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _job == null
                ? null
                : () async {
                    final cat = await JobTaxonomyCatalog.instance();
                    if (!mounted) return;
                    final res = await Navigator.of(context).push<JobTaxonomyPickResult>(
                      MaterialPageRoute(
                        builder: (_) => JobTaxonomySelectionScreen(
                          hindi: hi,
                          catalog: cat,
                          initialCategoryId: JobTaxonomyCatalog.effectiveCategoryId(
                            jobRole: _selectedJobRole ?? _job!.jobRole,
                            skills: _selectedSkills.toList(),
                          ),
                          initialCompoundSkills: _selectedSkills.toList(),
                        ),
                      ),
                    );
                    if (res != null && mounted) {
                      setState(() {
                        _selectedJobRole = res.categoryId;
                        _selectedSkills
                          ..clear()
                          ..addAll(res.compoundSkillIds);
                      });
                    }
                  },
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(_localizations.chooseSkillSetChange),
          ),
        ),
        const SizedBox(height: 16),
        _buildSaveButton(0),
      ],
    );
  }
  
  Widget _buildTimingsContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 12),
        
        ShiftTimingPicker(
          labels: ShiftTimingLabels(
            hindi: widget.selectedLanguage == Language.hindi,
            shiftTiming: _localizations.shiftTiming,
            partTimeFreelance: _localizations.partTimeFreelance,
            chooseTimeSlot: _localizations.shiftTimeSelectLabel,
            fromLabel: _localizations.shiftFromLabel,
            toLabel: _localizations.shiftToLabel,
          ),
          state: _shiftTiming,
          onChanged: (s) => setState(() => _shiftTiming = s),
        ),
        
        const SizedBox(height: 16),
        
        Text(
          _localizations.weeklyOff,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _daysOfWeek.map((day) {
            final isSelected = _weeklyOff.contains(day['id']);
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _weeklyOff.remove(day['id']);
                  } else {
                    _weeklyOff.add(day['id']!);
                  }
                });
              },
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF3D3D7B) : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? const Color(0xFF3D3D7B) : Colors.grey.shade300,
                  ),
                ),
                child: Center(
                  child: Text(
                    day['label']!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? Colors.white : const Color(0xFF121A2C),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        
        const SizedBox(height: 16),
        _buildSaveButton(1),
      ],
    );
  }
  
  Widget _buildFacilitiesContent() {
    final facilities = [
      {'id': 'accommodation', 'label': _localizations.accommodation, 'icon': Icons.home_outlined},
      {'id': 'food', 'label': _localizations.foodProvided, 'icon': Icons.restaurant_outlined},
      {'id': 'incentives', 'label': _localizations.incentives, 'icon': Icons.monetization_on_outlined},
      {'id': 'paid_leave', 'label': _localizations.paidLeave, 'icon': Icons.event_available_outlined},
      {'id': 'training', 'label': _localizations.training, 'icon': Icons.school_outlined},
    ];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: facilities.map((facility) {
            final isSelected = _selectedFacilities.contains(facility['id']);
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _selectedFacilities.remove(facility['id']);
                  } else {
                    _selectedFacilities.add(facility['id'] as String);
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF3D3D7B) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF3D3D7B) : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      facility['icon'] as IconData,
                      size: 18,
                      color: isSelected ? Colors.white : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      facility['label'] as String,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                        color: isSelected ? Colors.white : const Color(0xFF121A2C),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        _buildSaveButton(2),
      ],
    );
  }
  
  Widget _buildSalonDetailsContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 12),
        
        GestureDetector(
          onTap: () {
            // TODO: Implement photo picker
          },
          child: Container(
            width: double.infinity,
            padding: AppResponsive.cardPaddingInsets(context),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.grey.shade300,
                style: BorderStyle.solid,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 32,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 8),
                Text(
                  _localizations.addPhotos,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        Text(
          _localizations.shortDescription,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _descriptionController,
          maxLength: 300,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: _localizations.descriptionPlaceholder,
            hintStyle: TextStyle(color: Colors.grey.shade400),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF3D3D7B)),
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        _buildSaveButton(3),
      ],
    );
  }
  
  Widget _buildSaveButton(int section) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton(
        onPressed: _isSaving ? null : () => _saveSection(section),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF3D3D7B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
        child: Text(
          _localizations.saved.replaceAll('✓ ', ''),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ============== JOB EDIT SCREEN (FULL EDIT) ==============
class JobEditScreen extends StatefulWidget {
  final Language selectedLanguage;
  final String jobId; // Job ID to fetch data from database
  
  const JobEditScreen({
    super.key,
    required this.selectedLanguage,
    required this.jobId,
  });

  @override
  State<JobEditScreen> createState() => _JobEditScreenState();
}

class _JobEditScreenState extends State<JobEditScreen> {
  late AppLocalizations _localizations;
  final ApiService _apiService = ApiService();
  
  // Job data from database
  Job? _job;
  bool _isLoadingJob = true;
  bool _isSaving = false;
  
  // Form fields - ALL job fields
  String? _selectedJobRole;
  String? _selectedOtherCategory;
  final TextEditingController _customRoleNameController = TextEditingController();
  Set<String> _selectedSkills = {};
  String? _selectedLocation;
  int _numberOfStaff = 1;
  // Salary slider bounds and values are derived from existing job values
  double _salarySliderMin = 5000;
  double _salarySliderMax = 100000;
  double _salaryMin = 8000;
  double _salaryMax = 25000;
  RangeValues _salaryRange = const RangeValues(10000, 20000);
  String _selectedWorkType = 'full_time';
  String _selectedExperience = 'fresher_ok';
  String? _selectedAccommodation;
  String? _selectedGender;
  final TextEditingController _descriptionController = TextEditingController();
  ShiftTimingState _shiftTiming = ShiftTimingState.defaults();
  Set<String> _weeklyOff = {};
  Set<String> _selectedFacilities = {};
  
  // Job roles and categories
  List<Map<String, dynamic>> _jobRoles = [];
  List<Map<String, dynamic>> _otherCategories = [];
  Map<String, List<Map<String, String>>> _skillBundlesPerRole = {};
  List<String> _allLocations = [];
  bool _isLoadingLocations = false;
  JobTaxonomyCatalog? _jobTaxonomy;
  
  // Days of week
  late List<Map<String, String>> _daysOfWeek;

  @override
  void initState() {
    super.initState();
    _localizations = AppLocalizations(widget.selectedLanguage);
    _initJobRoles();
    _initOtherCategories();
    _initSkillBundles();
    _initDaysOfWeek();
    _loadLocations();
    _loadJobFromDatabase();
    JobTaxonomyCatalog.instance().then((c) {
      if (mounted) setState(() => _jobTaxonomy = c);
    });
  }
  
  void _initJobRoles() {
    _jobRoles = [
      {'id': 'hair_stylist', 'icon': Icons.content_cut, 'label': _localizations.hairStylist},
      {'id': 'beautician', 'icon': Icons.face_retouching_natural, 'label': _localizations.beautician},
      {'id': 'makeup_artist', 'icon': Icons.palette, 'label': _localizations.makeupArtist},
      {'id': 'massage_therapist', 'icon': Icons.spa, 'label': _localizations.massageTherapist},
      {'id': 'receptionist', 'icon': Icons.support_agent, 'label': _localizations.receptionist},
      {'id': 'helper', 'icon': Icons.handshake, 'label': _localizations.helper},
      {'id': 'manager', 'icon': Icons.manage_accounts, 'label': _localizations.manager},
      {'id': 'other', 'icon': Icons.more_horiz, 'label': _localizations.other},
    ];
  }
  
  void _initOtherCategories() {
    _otherCategories = [
      {'id': 'academy_training', 'icon': Icons.school, 'label': _localizations.academyTraining},
      {'id': 'management', 'icon': Icons.business_center, 'label': _localizations.managementRole},
      {'id': 'billing_cashier', 'icon': Icons.point_of_sale, 'label': _localizations.billingCashier},
      {'id': 'support_staff', 'icon': Icons.cleaning_services, 'label': _localizations.supportStaff},
      {'id': 'specialist', 'icon': Icons.star, 'label': _localizations.specialistRole},
      {'id': 'educator_trainer', 'icon': Icons.record_voice_over, 'label': _localizations.educatorTrainer},
      {'id': 'something_else', 'icon': Icons.edit_note, 'label': _localizations.somethingElse},
    ];
  }
  
  void _initSkillBundles() {
    _skillBundlesPerRole = {
      'hair_stylist': [
        {'id': 'haircuts_styling', 'label': _localizations.haircutsStyling},
        {'id': 'color_treatments', 'label': _localizations.colorTreatments},
        {'id': 'hair_spa_care', 'label': _localizations.hairSpaCare},
        {'id': 'beard_grooming', 'label': _localizations.beardGrooming},
      ],
      'beautician': [
        {'id': 'facials_skincare', 'label': _localizations.facialsSkincare},
        {'id': 'waxing_threading', 'label': _localizations.waxingThreading},
        {'id': 'manicure_pedicure', 'label': _localizations.manicurePedicure},
        {'id': 'bleach_cleanup', 'label': _localizations.bleachCleanup},
      ],
      'makeup_artist': [
        {'id': 'bridal_makeup', 'label': _localizations.bridalMakeup},
        {'id': 'party_makeup', 'label': _localizations.partyMakeup},
        {'id': 'hd_airbrush', 'label': _localizations.hdAirbrush},
        {'id': 'eye_makeup', 'label': _localizations.eyeMakeup},
      ],
      'massage_therapist': [
        {'id': 'body_massage', 'label': _localizations.bodyMassage},
        {'id': 'head_shoulder', 'label': _localizations.headShoulder},
        {'id': 'aromatherapy', 'label': _localizations.aromatherapy},
        {'id': 'foot_reflexology', 'label': _localizations.footReflexology},
      ],
    };
  }
  
  void _initDaysOfWeek() {
    _daysOfWeek = [
      {'id': 'sun', 'label': _localizations.sunday},
      {'id': 'mon', 'label': _localizations.monday},
      {'id': 'tue', 'label': _localizations.tuesday},
      {'id': 'wed', 'label': _localizations.wednesday},
      {'id': 'thu', 'label': _localizations.thursday},
      {'id': 'fri', 'label': _localizations.friday},
      {'id': 'sat', 'label': _localizations.saturday},
    ];
  }
  
  Future<void> _loadLocations() async {
    setState(() => _isLoadingLocations = true);
    try {
      final cities = await IndiaCityService.instance.loadCities();
      if (mounted) setState(() => _allLocations = cities);
    } finally {
      if (mounted) setState(() => _isLoadingLocations = false);
    }
  }
  
  /// Load job data from database and populate form
  Future<void> _loadJobFromDatabase() async {
    setState(() {
      _isLoadingJob = true;
    });
    
    try {
      final response = await _apiService.getJobById(widget.jobId);
      
      if (!mounted) return;
      
      if (response.success && response.data != null) {
        final job = response.data!;
        setState(() {
          _job = job;
          
          // Populate ALL form fields with existing job data
          var role = JobTaxonomyCatalog.effectiveCategoryId(
            jobRole: job.jobRole,
            skills: job.skills,
          );
          if (role.isEmpty && (job.customRoleName != null && job.customRoleName!.trim().isNotEmpty)) {
            role = 'other';
          }
          _selectedJobRole = role.isEmpty ? null : role;
          _selectedOtherCategory = job.otherCategory;
          if (job.customRoleName != null) {
            _customRoleNameController.text = job.customRoleName!;
          }
          _selectedSkills = JobTaxonomyCatalog.skillsMatchingRole(role, job.skills).toSet();
          _selectedLocation = job.location;
          _numberOfStaff = job.numberOfStaff;
          // Salary slider bounds adapt to existing values so the control stays draggable
          final double minVal = job.salaryMin.toDouble();
          final double maxVal = job.salaryMax.toDouble();
          _salarySliderMin = minVal < 5000 ? minVal : 5000;
          _salarySliderMax = maxVal > 100000 ? maxVal : 100000;
          // Prevent degenerate range (min == max) by adding a small cushion
          final double adjustedMax = maxVal <= minVal ? minVal + 1000 : maxVal;
          _salaryMin = minVal;
          _salaryMax = adjustedMax;
          _salaryRange = RangeValues(_salaryMin, adjustedMax);
          _selectedWorkType = job.workType;
          _selectedExperience = job.experience;
          _selectedAccommodation = job.accommodation;
          _selectedGender = job.preferredGender ?? 'any';
          if (job.description != null) {
            _descriptionController.text = ShiftTimingMeta.stripMeta(job.description!);
          }
          _shiftTiming = ShiftTimingState.fromJob(
            shiftType: job.shiftType,
            description: job.description,
          );
          _weeklyOff = job.weeklyOff.toSet();
          _selectedFacilities = job.facilities.toSet();
        });
      }
    } catch (e) {
      print('Error loading job: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.selectedLanguage == Language.hindi
                  ? 'जॉब लोड करने में समस्या हुई'
                  : 'Failed to load job',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingJob = false;
        });
      }
    }
  }
  
  bool get _isFormValid {
    if (_selectedJobRole == null || _selectedLocation == null || _numberOfStaff <= 0) {
      return false;
    }
    if (_selectedJobRole == 'other') {
      if (_selectedSkills.isEmpty &&
          _customRoleNameController.text.trim().isEmpty &&
          _selectedOtherCategory == null) {
        return false;
      }
    } else {
      final cat = _jobTaxonomy?.categoryById(_selectedJobRole);
      if (cat != null && cat.subcategories.isNotEmpty) {
        if (!_selectedSkills.any((s) => s.startsWith('${_selectedJobRole!}/'))) {
          return false;
        }
      }
    }
    if (_salaryMin > _salaryMax) {
      return false;
    }
    return true;
  }
  
  String _formatSalary(double value) {
    if (value >= 1000) {
      return '₹${(value / 1000).toStringAsFixed(0)}K';
    }
    return '₹${value.toStringAsFixed(0)}';
  }
  
  Future<void> _showLocationPicker() async {
    final picked = await showIndiaCityPickerSheet(
      context,
      cities: _allLocations,
      isLoading: _isLoadingLocations,
      selected: _selectedLocation,
      title: _localizations.location,
      searchHint: _localizations.searchLocation,
    );
    if (picked != null && mounted) setState(() => _selectedLocation = picked);
  }
  
  /// Save all changes to backend
  Future<void> _saveChanges() async {
    if (_isSaving || !_isFormValid) return;
    
    // Validate salary range
    if (_salaryMin > _salaryMax) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.selectedLanguage == Language.hindi
                ? 'न्यूनतम वेतन अधिकतम से कम होना चाहिए'
                : 'Minimum salary must be less than maximum',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    setState(() {
      _isSaving = true;
    });
    
    try {
      final resolvedRole = _selectedJobRole ??
          JobTaxonomyCatalog.categoryIdFromSkills(_selectedSkills) ??
          _job?.jobRole;
      final roleId = resolvedRole ?? '';
      final filteredSkills = JobTaxonomyCatalog.skillsMatchingRole(roleId, _selectedSkills);
      // Prepare all updates
      final Map<String, dynamic> updates = {
        if (resolvedRole != null && resolvedRole.isNotEmpty) 'jobRole': resolvedRole,
        if (_selectedOtherCategory != null) 'otherCategory': _selectedOtherCategory,
        if (_customRoleNameController.text.trim().isNotEmpty) 'customRoleName': _customRoleNameController.text.trim(),
            'skills': filteredSkills,
        'location': _selectedLocation,
        'numberOfStaff': _numberOfStaff,
        'salaryMin': _salaryMin,
        'salaryMax': _salaryMax,
        'workType': _selectedWorkType,
        'experience': _selectedExperience,
        if (_selectedAccommodation != null) 'accommodation': _selectedAccommodation,
        'preferredGender': _selectedGender ?? 'any',
        'description': ShiftTimingMeta.mergeIntoDescription(
          _descriptionController.text.trim(),
          _shiftTiming,
        ),
            'shiftType': _shiftTiming.toApiShiftType(),
            'weeklyOff': _weeklyOff.toList(),
            'facilities': _selectedFacilities.toList(),
          };
      
      // Call API to update job (backend will recalculate completion_percent)
      final response = await _apiService.updateJob(
        jobId: widget.jobId,
        updates: updates,
      );
      
      if (!mounted) return;
      
      if (response.success && response.data != null) {
        // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
            content: Text(
              widget.selectedLanguage == Language.hindi
                  ? 'जॉब सफलतापूर्वक अपडेट हो गई'
                  : 'Job updated successfully',
            ),
              backgroundColor: const Color(0xFF4CAF50),
            duration: const Duration(seconds: 2),
            ),
          );
        
        // Navigate back and refresh home screen
        Navigator.of(context).pop({'success': true, 'jobId': widget.jobId});
      } else {
        // Show error
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
              response.message ?? (widget.selectedLanguage == Language.hindi
                    ? 'सेव करने में समस्या हुई'
                  : 'Failed to save'),
              ),
              backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
            ),
          );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.selectedLanguage == Language.hindi
                  ? 'कुछ गलत हो गया'
                  : 'Something went wrong',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _customRoleNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingJob) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    
    if (_job == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(_localizations.editJobTitle),
        ),
        body: Center(
          child: Text(
            widget.selectedLanguage == Language.hindi
                ? 'जॉब लोड नहीं हो सकी'
                : 'Failed to load job',
          ),
        ),
      );
    }
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          _localizations.editJobTitle,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: AppResponsive.formScreenPadding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    // Job type & skills
                  Text(
                      '${_localizations.selectJobRole} *',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      color: Color(0xFF121A2C),
                    ),
                  ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final cat = await JobTaxonomyCatalog.instance();
                          if (!mounted) return;
                          final hi = widget.selectedLanguage == Language.hindi;
                          final res = await Navigator.of(context).push<JobTaxonomyPickResult>(
                            MaterialPageRoute(
                              builder: (_) => JobTaxonomySelectionScreen(
                                hindi: hi,
                                catalog: cat,
                                initialCategoryId: _selectedJobRole,
                                initialCompoundSkills: _selectedSkills.toList(),
                              ),
                            ),
                          );
                          if (res != null && mounted) {
                            setState(() {
                              _selectedJobRole = res.categoryId;
                              _selectedSkills
                                ..clear()
                                ..addAll(res.compoundSkillIds);
                              if (_selectedJobRole != 'other') {
                                _selectedOtherCategory = null;
                              }
                            });
                          }
                        },
                        icon: const Icon(Icons.category_outlined),
                        label: Text(
                          _localizations.chooseJobTypeAndSkills,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    if (_selectedJobRole != null) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Chip(
                            label: Text(
                              _jobTaxonomy?.categoryLabel(
                                    _selectedJobRole!,
                                    widget.selectedLanguage == Language.hindi,
                                  ) ??
                                  _selectedJobRole!,
                              style: const TextStyle(fontSize: 11),
                            ),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          ..._selectedSkills.map((s) {
                            final lab = _jobTaxonomy?.compoundLabel(
                                  s,
                                  widget.selectedLanguage == Language.hindi,
                                ) ??
                                s;
                            return Chip(
                              label: Text(lab, style: const TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            );
                          }),
                        ],
                      ),
                    ],
                    if (_selectedJobRole == 'other') ...[
                      const SizedBox(height: 16),
                      Text(
                        _localizations.roleNameOptional,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF121A2C),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _customRoleNameController,
                        maxLength: 30,
                        decoration: InputDecoration(
                          hintText: _localizations.roleNamePlaceholder,
                          hintStyle: TextStyle(color: Colors.grey.shade400),
                          counterText: '',
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF3D3D7B)),
                          ),
                        ),
                      ),
                    ],
                    
                    const SizedBox(height: 24),
                    
                    // Location
                    Text(
                      '${_localizations.location} *',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF121A2C),
                      ),
                    ),
                    const SizedBox(height: 8),
                    CompactLocationField(
                      selectedLocation: _selectedLocation,
                      placeholder: _localizations.selectLocation,
                      onTap: () => _showLocationPicker(),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Number of Staff
                    Text(
                      '${_localizations.numberOfStaff} *',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF121A2C),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FormBulletOptionRow<int>(
                      options: [
                        (value: 1, label: '1'),
                        (value: 2, label: '2'),
                        (value: 3, label: '3+'),
                      ],
                      groupValue: _numberOfStaff,
                      onChanged: (v) {
                        if (v != null) setState(() => _numberOfStaff = v);
                      },
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Salary Range
                    ResponsiveLabelValueRow(
                      label: Text(
                        '${_localizations.salaryRange} *',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF121A2C),
                        ),
                      ),
                      value: Text(
                        '${_formatSalary(_salaryRange.start)} - ${_formatSalary(_salaryRange.end)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF3D3D7B),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: const Color(0xFF3D3D7B),
                        inactiveTrackColor: Colors.grey.shade300,
                        thumbColor: const Color(0xFF3D3D7B),
                        overlayColor: const Color(0xFF3D3D7B).withOpacity(0.2),
                        rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 10),
                      ),
                      child: RangeSlider(
                        values: _salaryRange,
                        min: _salarySliderMin,
                        max: _salarySliderMax,
                        divisions: 40,
                        onChanged: (values) {
                          setState(() {
                            _salaryRange = values;
                            _salaryMin = values.start;
                            _salaryMax = values.end;
                          });
                        },
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatSalary(_salaryMin),
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        Text(
                          _formatSalary(_salaryMax),
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 24),
                    
                    // Experience
                    Text(
                      '${_localizations.experience} *',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF121A2C),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FormBulletOption<String>(
                      value: 'fresher_ok',
                      groupValue: _selectedExperience,
                      label: _localizations.fresherOk,
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedExperience = v);
                      },
                    ),
                    FormBulletOption<String>(
                      value: 'experience_required',
                      groupValue: _selectedExperience,
                      label: _localizations.experienceRequired,
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedExperience = v);
                      },
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Gender Preference
        Text(
                      _localizations.genderPreferenceOptional,
          style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 12),
                    ResponsiveChipRow(
                      children: [
                        _buildGenderChip(
                          id: 'male',
                          label: _localizations.male,
                          isSelected: _selectedGender == 'male',
                          onTap: () => setState(() => _selectedGender = 'male'),
                        ),
                        _buildGenderChip(
                          id: 'female',
                          label: _localizations.female,
                          isSelected: _selectedGender == 'female',
                          onTap: () => setState(() => _selectedGender = 'female'),
                        ),
                        _buildGenderChip(
                          id: 'any',
                          label: _localizations.anyGender,
                          isSelected: _selectedGender == 'any',
                          onTap: () => setState(() => _selectedGender = 'any'),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    ShiftTimingPicker(
                      labels: ShiftTimingLabels(
                        hindi: widget.selectedLanguage == Language.hindi,
                        shiftTiming: _localizations.shiftTiming,
                        partTimeFreelance: _localizations.partTimeFreelance,
                        chooseTimeSlot: _localizations.shiftTimeSelectLabel,
                        fromLabel: _localizations.shiftFromLabel,
                        toLabel: _localizations.shiftToLabel,
                      ),
                      state: _shiftTiming,
                      onChanged: (s) => setState(() => _shiftTiming = s),
                    ),
        
                    const SizedBox(height: 24),
        
                    // Weekly off
        Text(
          _localizations.weeklyOff,
          style: TextStyle(
                        fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade700,
          ),
        ),
                    const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _daysOfWeek.map((day) {
            final isSelected = _weeklyOff.contains(day['id']);
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _weeklyOff.remove(day['id']);
                  } else {
                    _weeklyOff.add(day['id']!);
                  }
                });
              },
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF3D3D7B) : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? const Color(0xFF3D3D7B) : Colors.grey.shade300,
                  ),
                ),
                child: Center(
                  child: Text(
                    day['label']!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? Colors.white : const Color(0xFF121A2C),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        
                    const SizedBox(height: 24),
                    
                    // Facilities
                    Text(
                      _localizations.facilitiesBenefits,
          style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
      {'id': 'accommodation', 'label': _localizations.accommodation, 'icon': Icons.home_outlined},
      {'id': 'food', 'label': _localizations.foodProvided, 'icon': Icons.restaurant_outlined},
      {'id': 'incentives', 'label': _localizations.incentives, 'icon': Icons.monetization_on_outlined},
      {'id': 'paid_leave', 'label': _localizations.paidLeave, 'icon': Icons.event_available_outlined},
      {'id': 'training', 'label': _localizations.training, 'icon': Icons.school_outlined},
                      ].map((facility) {
            final isSelected = _selectedFacilities.contains(facility['id']);
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _selectedFacilities.remove(facility['id']);
                  } else {
                    _selectedFacilities.add(facility['id'] as String);
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF3D3D7B) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF3D3D7B) : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      facility['icon'] as IconData,
                      size: 18,
                      color: isSelected ? Colors.white : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      facility['label'] as String,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                        color: isSelected ? Colors.white : const Color(0xFF121A2C),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
                    
                    const SizedBox(height: 24),
        
        // Description
        Text(
          _localizations.shortDescription,
          style: TextStyle(
                        fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade700,
          ),
        ),
                    const SizedBox(height: 12),
        TextField(
          controller: _descriptionController,
          maxLength: 300,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: _localizations.descriptionPlaceholder,
            hintStyle: TextStyle(color: Colors.grey.shade400),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF3D3D7B)),
            ),
          ),
        ),
        
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
            
            // Save Changes Button
            Container(
              padding: AppResponsive.formFooterPadding(context),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SizedBox(
      width: double.infinity,
                height: 56,
      child: ElevatedButton(
                  onPressed: (_isFormValid && !_isSaving) ? _saveChanges : null,
        style: ElevatedButton.styleFrom(
                    backgroundColor: (_isFormValid && !_isSaving) ? const Color(0xFF3D3D7B) : Colors.grey.shade300,
          shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          _localizations.saveChanges,
          style: const TextStyle(
                            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildGenderChip({
    required String id,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3D3D7B).withOpacity(0.1) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF3D3D7B) : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? const Color(0xFF3D3D7B) : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}

// ============== JOB OWNER HOME SCREEN ==============
class JobOwnerHomeScreen extends StatefulWidget {
  final Language selectedLanguage;
  
  const JobOwnerHomeScreen({
    super.key,
    required this.selectedLanguage,
  });

  @override
  State<JobOwnerHomeScreen> createState() => _JobOwnerHomeScreenState();
}

class _JobOwnerHomeScreenState extends State<JobOwnerHomeScreen> {
  late AppLocalizations _localizations;
  final ApiService _apiService = ApiService();
  
  // ========== STATE MANAGEMENT (STRICT DATA SEPARATION) ==========
  // 
  // CRITICAL: Salon Profile and Job Posting are TWO SEPARATE ENTITIES
  // 
  // Salon Profile State:
  //   - Source: GET /api/salon/me → _salonProfile
  //   - Completion: GET /api/salon/completion → _profileCompletion
  //   - Used for: Profile banner, salon name/avatar in header
  //
  // Job State:
  //   - Source: GET /api/jobs/my-jobs → _jobs
  //   - Each job has its own completion_percent (from jobs table)
  //   - Used for: Job cards, job status, job actions
  //
  // DO NOT mix these two data sources.
  // DO NOT use job completion to infer profile completion or vice versa.
  
  SalonProfile? _salonProfile;
  ProfileCompletion? _profileCompletion;
  List<Job> _jobs = [];
  bool _isLoading = true;
  bool _profileBannerDismissed = false;
  int _selectedFilterTab = 0; // 0: All, 1: Shortlisted, 2: Interviewed
  int _selectedBottomNavIndex = 0; // 0: Home, 1: Candidates, 2: Chat, 3: Profile
  DateTime? _lastBackPressedAt;
  JobTaxonomyCatalog? _jobTaxonomy;

  // Candidates tab (all job seekers on platform)
  List<Map<String, dynamic>> _allSeekers = [];
  bool _loadingSeekers = false;
  String? _seekerFilterJobRole;
  String? _seekerFilterCity;
  List<String> _seekerFilterCities = [];
  
  // Language state (can be changed from Profile tab)
  late Language _currentLanguage;
  StreamSubscription<PushDeepLink>? _deepLinkSub;
  
  @override
  void initState() {
    super.initState();
    _currentLanguage = widget.selectedLanguage;
    _localizations = AppLocalizations(_currentLanguage);
    JobTaxonomyCatalog.instance().then((c) {
      if (mounted) setState(() => _jobTaxonomy = c);
    });
    _loadData();
    PushNotificationService().registerTokenIfLoggedIn();
    _deepLinkSub = PushNotificationService.onDeepLink.listen(_handleDeepLink);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handlePendingDeepLink());
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    super.dispose();
  }

  void _handleDeepLink(PushDeepLink link) {
    if (link.host != 'owner' || !mounted) return;
    _navigateFromDeepLink(link);
  }

  void _handlePendingDeepLink() {
    final link = PushNotificationService.getAndClearPendingDeepLink();
    if (link != null && link.host == 'owner' && mounted) _navigateFromDeepLink(link);
  }

  void _navigateFromDeepLink(PushDeepLink link) {
    if (!mounted) return;
    if (link.path.startsWith('job/')) {
      final jobId = link.path.substring(4).trim();
      if (jobId.isEmpty) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => CandidateListScreen(
            selectedLanguage: _currentLanguage,
            jobId: jobId,
            jobTitle: '',
            jobLocation: '',
          ),
        ),
      );
    }
  }
  
  void _updateLanguage(Language newLanguage) {
    setState(() {
      _currentLanguage = newLanguage;
      _localizations = AppLocalizations(_currentLanguage);
    });
  }
  
  /// Loads salon profile, completion, and jobs from backend. Backend is source of truth.
  /// Never assign a single job to _jobs – only the full list from GET /api/jobs/my-jobs.
  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      // Load salon profile
      final profileResponse = await _apiService.getSalonProfile();
      if (!mounted) return;
      if (profileResponse.success && profileResponse.data != null) {
        setState(() {
          _salonProfile = profileResponse.data;
        });
      } else {
        print('Profile load failed: ${profileResponse.message}');
      }

      // Load profile completion
      final completionResponse = await _apiService.getProfileCompletion();
      if (!mounted) return;
      if (completionResponse.success && completionResponse.data != null) {
        setState(() {
          _profileCompletion = completionResponse.data;
        });
      } else {
        print('Completion load failed: ${completionResponse.message}');
      }

      // Load ALL jobs – must use list from API, never a single job
      final jobsResponse = await _apiService.getJobs();
      if (!mounted) return;
      print('Jobs API response: success=${jobsResponse.success}, count=${jobsResponse.data?.length ?? 0}');

      if (jobsResponse.success && jobsResponse.data != null) {
        final list = jobsResponse.data!;
        if (!mounted) return;
        setState(() {
          _jobs = List<Job>.from(list);
          _jobs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        });
        print('Loaded ${_jobs.length} jobs (backend source of truth)');
      } else {
        print('Jobs load failed: ${jobsResponse.message}');
        if (!mounted) return;
        setState(() {
          _jobs = [];
        });
      }
    } catch (e, stackTrace) {
      print('Error loading data: $e');
      print('Stack trace: $stackTrace');
      if (!mounted) return;
      setState(() {
        _jobs = [];
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  void _refreshData() {
    _loadData();
  }

  Map<String, String> get _legacyJobRoleLabels => {
        'hair_stylist': _localizations.hairStylist,
        'beautician': _localizations.beautician,
        'makeup_artist': _localizations.makeupArtist,
        'massage_therapist': _localizations.massageTherapist,
        'receptionist': _localizations.receptionist,
        'helper': _localizations.helper,
        'manager': _localizations.manager,
        'other': _localizations.salonStaff,
      };

  /// User-friendly job role label (localized). Use this instead of raw job.jobRole.
  String _displayRoleForJob(Job job) {
    final hi = _currentLanguage == Language.hindi;
    if (_jobTaxonomy != null) {
      return _jobTaxonomy!.displayRoleLabel(
        customRoleName: job.customRoleName,
        jobRole: job.jobRole,
        skills: job.skills,
        hindi: hi,
        legacyRoleLabels: _legacyJobRoleLabels,
      );
    }
    if (job.customRoleName != null && job.customRoleName!.isNotEmpty) {
      return job.customRoleName!;
    }
    final id = JobTaxonomyCatalog.effectiveCategoryId(
      jobRole: job.jobRole,
      skills: job.skills,
    );
    final localized = _legacyJobRoleLabels[id];
    if (localized != null) return localized;
    return id
        .split('_')
        .map((word) => word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
        .join(' ');
  }
  
  /// Android back: non-home tabs → Home; on Home → double-tap to exit.
  void _handleOwnerBackPress(bool didPop, Object? result) {
    if (didPop) return;
    if (_selectedBottomNavIndex != 0) {
      setState(() {
        _selectedBottomNavIndex = 0;
        _lastBackPressedAt = null;
      });
      return;
    }
    final now = DateTime.now();
    if (_lastBackPressedAt == null ||
        now.difference(_lastBackPressedAt!) > const Duration(seconds: 2)) {
      _lastBackPressedAt = now;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_localizations.tapAgainToExit),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check if any job has candidates
    final hasCandidates = _jobs.any((job) => job.applicationsCount > 0);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handleOwnerBackPress,
      child: _buildOwnerTabBody(hasCandidates),
    );
  }

  Widget _buildOwnerTabBody(bool hasCandidates) {
    // Show Profile tab if selected
    if (_selectedBottomNavIndex == 3) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        body: SafeArea(
          child: ProfileScreen(
            selectedLanguage: _currentLanguage,
            salonProfile: _salonProfile,
            profileCompletion: _profileCompletion,
            onProfileUpdated: _loadData,
            onLanguageChanged: _updateLanguage,
          ),
        ),
        bottomNavigationBar: _buildBottomNav(),
      );
    }

    if (_selectedBottomNavIndex == 1) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: Text(
            _localizations.allApplicantsTitle,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF121A2C),
            ),
          ),
          centerTitle: true,
          iconTheme: const IconThemeData(color: Color(0xFF121A2C)),
          actions: [
            TextButton.icon(
              onPressed: _openSeekerFilters,
              icon: const Icon(Icons.tune, size: 20, color: Color(0xFF3D3D7B)),
              label: Text(
                _localizations.filterApplicants,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3D3D7B),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: ResponsiveContent(
            child: RefreshIndicator(
              onRefresh: _loadAllSeekers,
              child: _buildOwnerSeekersTab(),
            ),
          ),
        ),
        bottomNavigationBar: _buildBottomNav(),
      );
    }

    if (_selectedBottomNavIndex == 2) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: Text(
            _localizations.chat,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF121A2C),
            ),
          ),
          centerTitle: true,
          iconTheme: const IconThemeData(color: Color(0xFF121A2C)),
        ),
        body: SafeArea(
          child: ResponsiveContent(
            child: _OwnerChatHub(selectedLanguage: _currentLanguage),
          ),
        ),
        bottomNavigationBar: _buildBottomNav(),
      );
    }

    return Scaffold(
        backgroundColor: Colors.grey.shade50,
        body: SafeArea(
          child: ResponsiveContent(
            child: Column(
            children: [
              // 1. TOP APP BAR
              _buildTopAppBar(),
              
              // 2. PROFILE COMPLETION BANNER (Conditional - based on SALON profile, not job)
              if (_shouldShowProfileBanner()) _buildProfileBanner(),
              
              // 3. SEARCH BAR (Only show if candidates exist)
              if (hasCandidates) _buildSearchBar(),
              
              // 4. FILTER TABS (Only show if candidates exist)
              if (hasCandidates) _buildFilterTabs(),
              
              // 5. MAIN CONTENT AREA (Job cards OR empty state)
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: _buildMainContent(),
                      ),
              ),
            ],
          ),
          ),
        ),
        // 6. FLOATING ACTION BUTTON
        floatingActionButton: _buildFAB(),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        
        // 7. BOTTOM NAVIGATION BAR
        bottomNavigationBar: _buildBottomNav(),
      );
  }
  
  String _salonAvatarLetter() {
    final name = _salonProfile?.salonName ?? _salonProfile?.ownerName;
    if (name != null && name.isNotEmpty) return name.substring(0, 1).toUpperCase();
    return 'S';
  }

  Widget _buildSalonHeaderAvatar({double radius = 20}) {
    final photoUrl = _salonProfile?.displayAvatarUrl;
    final letter = _salonAvatarLetter();
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    final size = radius * 2;

    Widget fallback() => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          color: const Color(0xFF3D3D7B),
          child: Text(
            letter,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: radius * 0.8,
            ),
          ),
        );

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: hasPhoto
            ? Image.network(
                photoUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback(),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    color: const Color(0xFF3D3D7B),
                    child: Center(
                      child: SizedBox(
                        width: radius,
                        height: radius,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                  );
                },
              )
            : fallback(),
      ),
    );
  }

  Widget _buildTopAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildSalonHeaderAvatar(),
          const SizedBox(width: 12),
          
          // Salon Name & City
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _salonProfile?.salonName ??
                            _salonProfile?.ownerName ??
                            'Salon',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF121A2C),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_salonProfile?.isSalonVerified == true)
                      const Icon(Icons.verified, color: Color(0xFF1565C0), size: 20),
                  ],
                ),
                if (_salonProfile?.city != null)
                  Text(
                    _salonProfile!.city!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ),
          
          // Notification bell
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            color: Colors.grey.shade700,
            onPressed: () {
              // Passive for now
            },
          ),
        ],
      ),
    );
  }
  
  bool _shouldShowProfileBanner() {
    // Banner is based on SALON profile completion, NOT job completion
    if (_profileBannerDismissed) return false;
    if (_profileCompletion == null) return false;
    // Use profile completion percent from /api/salon/completion
    return _profileCompletion!.completionPercent < 100;
  }
  
  Widget _buildProfileBanner() {
    final percent = _profileCompletion?.completionPercent ?? 0;
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppResponsive.ownerHomeCardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = AppResponsive.stackProfileBanner(context, constraints);
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                        value: percent / 100,
                        strokeWidth: 4,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          percent >= 70 ? const Color(0xFF4CAF50) : const Color(0xFFF9A825),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _localizations.profileIncomplete.replaceAll('{p}', '$percent'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF121A2C),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      color: Colors.grey.shade600,
                      onPressed: () {
                        setState(() {
                          _profileBannerDismissed = true;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _localizations.addMissingDetails,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _selectedBottomNavIndex = 3;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3D3D7B),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      _localizations.completeNow,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
          return Row(
            children: [
              // Circular progress indicator
              SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  value: percent / 100,
                  strokeWidth: 4,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    percent >= 70 ? const Color(0xFF4CAF50) : const Color(0xFFF9A825),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _localizations.profileIncomplete.replaceAll('{p}', '$percent'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF121A2C),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _localizations.addMissingDetails,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),

              // CTA Button
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _selectedBottomNavIndex = 3;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3D3D7B),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  _localizations.completeNow,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),

              // Close icon
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                color: Colors.grey.shade600,
                onPressed: () {
                  setState(() {
                    _profileBannerDismissed = true;
                  });
                },
              ),
            ],
          );
        },
      ),
    );
  }
  
  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.search, color: Colors.grey.shade400, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _localizations.searchCandidates,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade400,
              ),
            ),
          ),
          Icon(Icons.mic, color: Colors.grey.shade400, size: 20),
        ],
      ),
    );
  }
  
  Widget _buildFilterTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      child: Row(
        children: [
          _buildFilterTab(0, _localizations.all),
          const SizedBox(width: 8),
          _buildFilterTab(1, _localizations.shortlisted),
          const SizedBox(width: 8),
          _buildFilterTab(2, _localizations.interviewed),
        ],
      ),
    );
  }
  
  Widget _buildFilterTab(int index, String label) {
    final isSelected = _selectedFilterTab == index;
    final hasCandidates = _jobs.any((job) => job.applicationsCount > 0);
    
    return Expanded(
      child: GestureDetector(
        onTap: hasCandidates ? () {
          setState(() {
            _selectedFilterTab = index;
          });
        } : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF3D3D7B) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? const Color(0xFF3D3D7B) : Colors.grey.shade300,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isSelected 
                  ? Colors.white 
                  : (hasCandidates ? Colors.grey.shade700 : Colors.grey.shade400),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildMainContent() {
    // STRICT: Show empty state ONLY if jobs.length === 0
    if (_jobs.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: [
          _buildEmptyState(),
        ],
      );
    }
    
    final compact = _jobs.length > 1;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 100),
      child: Column(
        children: _jobs.map((job) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildJobCard(job, compact: compact),
        )).toList(),
      ),
    );
  }

  String _formatSalaryRange(Job job) {
    String fmt(double v) {
      if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(0)}K';
      return '₹${v.toStringAsFixed(0)}';
    }
    return '${fmt(job.salaryMin)} - ${fmt(job.salaryMax)} ${_localizations.perMonth}';
  }

  String _workTypeLabel(String workType) {
    if (workType == 'part_time') return _localizations.partTime;
    return _localizations.fullTime;
  }

  String _experienceLabel(String exp) {
    if (exp == 'experience_required') return _localizations.experienceRequired;
    return _localizations.fresherOk;
  }
  
  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.work_outline,
          size: 80,
          color: Colors.grey.shade300,
        ),
        const SizedBox(height: 24),
        Text(
          _localizations.noJobsPosted,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF121A2C),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _localizations.postFirstJobSubtext,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: () {
            // Always open the quick 3-step job posting flow
            openQuickJobFlow(context, widget.selectedLanguage);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3D3D7B),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          child: Text(
            _localizations.postYourFirstJob,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _loadData,
          child: Text(
            'Refresh',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildJobCard(Job job, {required bool compact}) {
  Widget liveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF4CAF50),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _localizations.jobStatusLive,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2E7D32),
            ),
          ),
        ],
      ),
    );
  }

  Widget titleBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _displayRoleForJob(job),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF121A2C),
            height: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          job.location,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = AppResponsive.layoutWidth(context, constraints);
        final cardPad = AppResponsive.cardPadding(w);
        final stackHeader = AppResponsive.stackJobCardHeader(context, constraints);
        final btnFont = AppResponsive.jobCardButtonFontSize(w);

        return SizedBox(
          width: double.infinity,
          child: Container(
      padding: EdgeInsets.all(cardPad),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppResponsive.ownerHomeCardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (stackHeader) ...[
            titleBlock(),
            if (job.status == 'active') ...[
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: liveBadge()),
            ],
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: titleBlock()),
                if (job.status == 'active') ...[
                  const SizedBox(width: 8),
                  liveBadge(),
                ],
              ],
            ),
          
          if (!compact) ...[
            const SizedBox(height: 12),
            _jobDetailLine(Icons.payments_outlined, _formatSalaryRange(job)),
            _jobDetailLine(Icons.people_outline, '${job.numberOfStaff} ${_localizations.staffNeeded}'),
            _jobDetailLine(Icons.schedule, _workTypeLabel(job.workType)),
            _jobDetailLine(Icons.work_history_outlined, _experienceLabel(job.experience)),
            if (job.totalApplications > 0)
              _jobDetailLine(
                Icons.how_to_reg_outlined,
                '${job.totalApplications} ${_localizations.applicantsCountLabel}',
              ),
          ],
          
          const SizedBox(height: 16),
          
          // Badges row: applicants / hire status
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Applicant count badge
              if (job.totalApplications > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.people, size: 14, color: Color(0xFFE65100)),
                      const SizedBox(width: 4),
                      Text(
                        '${job.totalApplications} ${_localizations.applicantsCountLabel}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFE65100),
                        ),
                      ),
                    ],
                  ),
                ),
              // Position Filled badge OR hired count badge
              if (job.hiredCount > 0 && job.hiredCount >= job.vacancyCount)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC8E6C9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF4CAF50), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, size: 14, color: Color(0xFF2E7D32)),
                      const SizedBox(width: 4),
                      Text(
                        _localizations.positionFilled,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                    ],
                  ),
                )
              else if (job.hiredCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${job.hiredCount}/${job.vacancyCount} ${_localizations.hiredLabel}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                ),
            ],
          ),
          
          const SizedBox(height: 16),
          _buildJobCardActions(
            job: job,
            buttonFontSize: btnFont,
          ),
          if (!compact && job.completionPercent < 70)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _localizations.completeJobHelper,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    ),
        );
      },
    );
  }

  Widget _buildJobCardActions({
    required Job job,
    required double buttonFontSize,
  }) {
    final showImprove = job.completionPercent < 100;

    final improveBtn = SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () async {
          final result = await Navigator.of(context).push<Map<String, dynamic>>(
            MaterialPageRoute(
              builder: (context) => JobEditScreen(
                selectedLanguage: _currentLanguage,
                jobId: job.id,
              ),
            ),
          );
          if (result != null && result['success'] == true) {
            _refreshData();
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF3D3D7B),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: Text(
          _localizations.improveJobCTA,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
          style: TextStyle(
            fontSize: buttonFontSize,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            height: 1.2,
          ),
        ),
      ),
    );

    final viewBtn = SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => CandidateListScreen(
                selectedLanguage: _currentLanguage,
                jobId: job.id,
                jobTitle: job.customRoleName ?? job.jobRole,
                jobLocation: job.location,
              ),
            ),
          );
        },
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: const BorderSide(color: Color(0xFF3D3D7B)),
        ),
        child: Text(
          _localizations.viewJobCTA,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
          style: TextStyle(
            fontSize: buttonFontSize,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF3D3D7B),
            height: 1.2,
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showImprove) improveBtn,
        if (showImprove) const SizedBox(height: 10),
        viewBtn,
      ],
    );
  }

  Widget _jobDetailLine(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFAB() {
    return FloatingActionButton(
      onPressed: () {
        // Always open the quick 3-step job posting flow (use current language from settings)
        openQuickJobFlow(context, _currentLanguage);
      },
      backgroundColor: const Color(0xFF3D3D7B),
      child: const Icon(Icons.add, color: Colors.white),
    );
  }

  Future<void> _loadAllSeekers() async {
    setState(() => _loadingSeekers = true);
    final res = await _apiService.getOwnerAllSeekers(
      jobRole: _seekerFilterJobRole,
      location: _seekerFilterCity,
      limit: 100,
    );
    if (!mounted) return;
    if (res.success && res.data != null) {
      final seekers = (res.data!['seekers'] as List<dynamic>? ?? [])
          .map((s) => Map<String, dynamic>.from(s as Map))
          .toList();
      final cities = (res.data!['cities'] as List<dynamic>? ?? [])
          .map((c) => c.toString())
          .where((c) => c.isNotEmpty)
          .toList();
      setState(() {
        _allSeekers = seekers;
        if (cities.isNotEmpty) _seekerFilterCities = cities;
        _loadingSeekers = false;
      });
    } else {
      setState(() {
        _allSeekers = [];
        _loadingSeekers = false;
      });
    }
  }

  Future<void> _openSeekerFilters() async {
    final result = await Navigator.of(context).push<Map<String, String?>>(
      MaterialPageRoute(
        builder: (context) => OwnerApplicantsFilterScreen(
          selectedLanguage: _currentLanguage,
          jobs: _jobs,
          taxonomy: _jobTaxonomy,
          cityOptions: _seekerFilterCities,
          initialJobRole: _seekerFilterJobRole,
          initialCity: _seekerFilterCity,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _seekerFilterJobRole = result['jobRole'];
      _seekerFilterCity = result['city'];
    });
    await _loadAllSeekers();
  }

  String _seekerRoleLabel(Map<String, dynamic> seeker) {
    final role = seeker['preferredRole']?.toString() ?? '';
    if (role.isEmpty) return '—';
    final hi = _currentLanguage == Language.hindi;
    if (_jobTaxonomy != null) {
      return _jobTaxonomy!.categoryLabel(role, hi);
    }
    return JobTaxonomyCatalog.toTitleCase(role.replaceAll('_', ' '));
  }

  String _seekerExperienceLabel(Map<String, dynamic> seeker) {
    final years = seeker['experienceYears'];
    if (years is num && years > 0) {
      return _currentLanguage == Language.hindi ? '$years साल अनुभव' : '$years yrs experience';
    }
    final exp = seeker['experience']?.toString() ?? '';
    if (exp.isEmpty) {
      return _currentLanguage == Language.hindi ? 'फ्रेशर' : 'Fresher';
    }
    return exp;
  }

  Widget _buildOwnerSeekerTile(Map<String, dynamic> seeker) {
    final name = seeker['fullName']?.toString() ?? '—';
    final seekerCity = seeker['city']?.toString() ?? '';
    final roleLabel = _seekerRoleLabel(seeker);
    final completion = seeker['profileCompletionPercent'] is num
        ? (seeker['profileCompletionPercent'] as num).toInt()
        : 0;
    final photo = seeker['profilePhotoUrl']?.toString() ?? '';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => OwnerSeekerProfileScreen(
                selectedLanguage: _currentLanguage,
                seeker: seeker,
                taxonomy: _jobTaxonomy,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFEEEEF8),
                backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                child: photo.isEmpty
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF3D3D7B),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF121A2C),
                      ),
                    ),
                    if (seekerCity.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          seekerCity,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '$roleLabel • ${_seekerExperienceLabel(seeker)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF3D3D7B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$completion%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Owner candidates tab: browse all job seekers + filter by job type / city.
  Widget _buildOwnerSeekersTab() {
    if (_loadingSeekers && _allSeekers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_allSeekers.isEmpty) {
      final hasFilter =
          (_seekerFilterJobRole != null && _seekerFilterJobRole!.isNotEmpty) ||
          (_seekerFilterCity != null && _seekerFilterCity!.isNotEmpty);
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        children: [
          Icon(Icons.people_outline, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 20),
          Text(
            hasFilter ? _localizations.noApplicantsFound : _localizations.noCandidatesYet,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Color(0xFF121A2C),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            hasFilter
                ? (_currentLanguage == Language.hindi
                    ? 'फ़िल्टर बदलकर दोबारा खोजें।'
                    : 'Try changing filters and search again.')
                : _localizations.browseCandidatesHint,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.4),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _openSeekerFilters,
            icon: const Icon(Icons.tune),
            label: Text(_localizations.filterApplicants),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF3D3D7B),
              side: const BorderSide(color: Color(0xFF3D3D7B)),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 100),
      itemCount: _allSeekers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _buildOwnerSeekerTile(_allSeekers[i]),
    );
  }

  Widget _buildBottomNav() {
    final items = <({IconData icon, String label})>[
      (icon: Icons.home_outlined, label: _localizations.home),
      (icon: Icons.people_outline, label: _localizations.ownerApplicantsTab),
      (icon: Icons.chat_bubble_outline, label: _localizations.chat),
      (icon: Icons.person_outline, label: _localizations.ownerSalonTab),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final selected = _selectedBottomNavIndex == index;
              final color = selected ? const Color(0xFF3D3D7B) : Colors.grey.shade400;
              return Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() => _selectedBottomNavIndex = index);
                    if (index == 0) {
                      _loadData();
                    } else if (index == 1) {
                      _loadAllSeekers();
                    }
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.icon,
                          size: 22,
                          color: color,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          softWrap: true,
                          style: TextStyle(
                            fontSize: AppResponsive.bottomNavLabelFontSize(context),
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                            color: color,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Salon owner Chat tab: application threads + WebSocket chat + support link.
class _OwnerChatHub extends StatefulWidget {
  final Language selectedLanguage;

  const _OwnerChatHub({required this.selectedLanguage});

  @override
  State<_OwnerChatHub> createState() => _OwnerChatHubState();
}

class _OwnerChatHubState extends State<_OwnerChatHub> {
  final ApiService _api = ApiService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _threads = [];

  bool get _hi => widget.selectedLanguage == Language.hindi;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await _api.getChatThreads();
    if (!mounted) return;
    if (r.success && r.data != null) {
      setState(() {
        _threads = r.data!;
        _loading = false;
      });
    } else {
      setState(() {
        _error = r.message ?? (_hi ? 'लोड नहीं हो सका' : 'Could not load');
        _loading = false;
      });
    }
  }

  String _roleTitle(Map<String, dynamic> t) {
    final custom = t['customRoleName']?.toString();
    if (custom != null && custom.isNotEmpty) return custom;
    final role = t['jobRole']?.toString() ?? '';
    return role.replaceAll('_', ' ');
  }

  String _subtitle(Map<String, dynamic> t) {
    final body = t['lastBody']?.toString();
    if (body != null && body.isNotEmpty) return body;
    return _hi ? 'अभी तक कोई संदेश नहीं' : 'No messages yet';
  }

  String _timeLabel(dynamic raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      final now = DateTime.now();
      if (now.difference(dt).inDays < 1) {
        final h = dt.hour.toString().padLeft(2, '0');
        final m = dt.minute.toString().padLeft(2, '0');
        return '$h:$m';
      }
      return '${dt.day}/${dt.month}';
    } catch (_) {
      return '';
    }
  }

  void _openThread(Map<String, dynamic> t) {
    final appId = t['applicationId']?.toString();
    if (appId == null || appId.isEmpty) return;
    final seeker = t['seekerName']?.toString() ?? '';
    final title = '${_roleTitle(t)} · $seeker'.trim();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ApplicationChatScreen(
          applicationId: appId,
          languageCode: _hi ? 'hi' : 'en',
          title: title,
          isSalonOwner: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
              children: [
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  Padding(
                    padding: AppResponsive.screenPaddingAll(context),
                    child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
                  )
                else if (_threads.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: Column(
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 56, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text(
                          _hi ? 'अभी कोई बातचीत नहीं' : 'No conversations yet',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _hi
                              ? 'उम्मीदवार कार्ड से संदेश भेजें या यहाँ रिफ्रेश करें।'
                              : 'Message a candidate from their card, or pull to refresh.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  )
                else
                  ..._threads.map((t) {
                    final at = t['lastMessageAt'];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        onTap: () => _openThread(t),
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFEEEEF8),
                          child: Text(
                            (t['seekerName']?.toString().isNotEmpty == true)
                                ? t['seekerName'].toString()[0].toUpperCase()
                                : '?',
                            style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF3D3D7B)),
                          ),
                        ),
                        title: Text(
                          t['seekerName']?.toString() ?? (_hi ? 'उम्मीदवार' : 'Candidate'),
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Color(0xFF121A2C)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _roleTitle(t),
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _subtitle(t),
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        trailing: Text(
                          _timeLabel(at),
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  tileColor: Colors.white,
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3D3D7B).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.support_agent, color: Color(0xFF3D3D7B)),
                  ),
                  title: Text(
                    _hi ? 'सहायता और सपोर्ट' : 'Help & support',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF121A2C)),
                  ),
                  subtitle: Text(
                    _hi ? 'टिकट, अक्सर पूछे प्रश्न, संपर्क' : 'Tickets, FAQ, contact',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => HelpSupportScreen(selectedLanguage: widget.selectedLanguage),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ============== JOB DETAIL VIEW (Owner, read-only) ==============

class JobOwnerJobDetailScreen extends StatefulWidget {
  final Language selectedLanguage;
  final String jobId;

  const JobOwnerJobDetailScreen({
    super.key,
    required this.selectedLanguage,
    required this.jobId,
  });

  @override
  State<JobOwnerJobDetailScreen> createState() => _JobOwnerJobDetailScreenState();
}

class _JobOwnerJobDetailScreenState extends State<JobOwnerJobDetailScreen> {
  late AppLocalizations _localizations;
  final ApiService _apiService = ApiService();
  Job? _job;
  bool _isLoading = true;
  JobTaxonomyCatalog? _taxonomy;

  @override
  void initState() {
    super.initState();
    _localizations = AppLocalizations(widget.selectedLanguage);
    _loadJob();
    JobTaxonomyCatalog.instance().then((c) {
      if (mounted) setState(() => _taxonomy = c);
    });
  }

  Future<void> _loadJob() async {
    setState(() => _isLoading = true);
    final res = await _apiService.getJobById(widget.jobId);
    if (!mounted) return;
    var job = res.success ? res.data : null;
    if (job != null) {
      final fromSkills = JobTaxonomyCatalog.categoryIdFromSkills(job.skills);
      if (fromSkills != null &&
          fromSkills.isNotEmpty &&
          fromSkills != job.jobRole) {
        final fix = await _apiService.updateJob(
          jobId: widget.jobId,
          updates: {'jobRole': fromSkills},
        );
        if (fix.success && fix.data != null) job = fix.data;
      }
    }
    if (!mounted) return;
    setState(() {
      _job = job;
      _isLoading = false;
    });
  }

  String _roleLabel(Job job) {
    final hi = widget.selectedLanguage == Language.hindi;
    if (_taxonomy != null) {
      return _taxonomy!.displayRoleLabel(
        customRoleName: job.customRoleName,
        jobRole: job.jobRole,
        skills: job.skills,
        hindi: hi,
      );
    }
    if (job.customRoleName != null && job.customRoleName!.trim().isNotEmpty) {
      return job.customRoleName!.trim();
    }
    final id = JobTaxonomyCatalog.effectiveCategoryId(
      jobRole: job.jobRole,
      skills: job.skills,
    );
    return id;
  }

  String _fmtSalary(double v) {
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(0)}K';
    return '₹${v.toStringAsFixed(0)}';
  }

  Map<String, String> _dayLabels() => {
        'sun': _localizations.sunday,
        'mon': _localizations.monday,
        'tue': _localizations.tuesday,
        'wed': _localizations.wednesday,
        'thu': _localizations.thursday,
        'fri': _localizations.friday,
        'sat': _localizations.saturday,
      };

  Map<String, String> _facilityLabels() => {
        'accommodation': _localizations.accommodation,
        'food': _localizations.foodProvided,
        'incentives': _localizations.incentives,
        'paid_leave': _localizations.paidLeave,
        'training': _localizations.training,
      };

  String? _shiftTimingLabel(Job job) {
    final hi = widget.selectedLanguage == Language.hindi;
    final timing = ShiftTimingState.fromJob(
      shiftType: job.shiftType,
      description: job.description,
    );
    if (job.shiftType != null || ShiftTimingMeta.parseFromDescription(job.description) != null) {
      return timing.displayLabel(hi);
    }
    return null;
  }

  String? _weeklyOffLabel(Job job) {
    if (job.weeklyOff.isEmpty) return null;
    final days = _dayLabels();
    final labels = job.weeklyOff
        .map((id) => days[id] ?? id)
        .where((s) => s.isNotEmpty)
        .toList();
    return labels.isEmpty ? null : labels.join(', ');
  }

  String? _facilitiesLabel(Job job) {
    if (job.facilities.isEmpty) return null;
    final labels = _facilityLabels();
    final names = job.facilities
        .map((id) => labels[id] ?? id.replaceAll('_', ' '))
        .where((s) => s.isNotEmpty)
        .toList();
    return names.isEmpty ? null : names.join(', ');
  }

  String? _accommodationLabel(Job job) {
    if (job.accommodation == null) return null;
    return job.accommodation == 'yes' ? _localizations.yes : _localizations.no;
  }

  String? _descriptionText(Job job) {
    final text = ShiftTimingMeta.stripMeta(job.description);
    return text.isEmpty ? null : text;
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF121A2C))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hi = widget.selectedLanguage == Language.hindi;
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF121A2C),
        elevation: 0,
        title: Text(
          AppLocalizations(widget.selectedLanguage).jobDetailsTitle,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_job != null)
            TextButton(
              onPressed: () async {
                final result = await Navigator.of(context).push<Map<String, dynamic>>(
                  MaterialPageRoute(
                    builder: (context) => JobEditScreen(
                      selectedLanguage: widget.selectedLanguage,
                      jobId: widget.jobId,
                    ),
                  ),
                );
                if (result != null && result['success'] == true) {
                  await _loadJob();
                }
              },
              child: Text(
                _localizations.editJobDetailsCTA,
                style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF3D3D7B)),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _job == null
              ? Center(child: Text(hi ? 'जॉब लोड नहीं हो सकी' : 'Could not load job'))
              : SingleChildScrollView(
                  padding: AppResponsive.scrollScreenPadding(context),
                  child: Container(
                    width: double.infinity,
                    padding: AppResponsive.cardPaddingInsets(context),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _row(_localizations.roleLabel, _roleLabel(_job!)),
                        _row(_localizations.locationLabel, _job!.location),
                        _row(
                          _localizations.salaryLabel,
                          '${_fmtSalary(_job!.salaryMin)} - ${_fmtSalary(_job!.salaryMax)} ${_localizations.perMonth}',
                        ),
                        _row(_localizations.staffNeeded, '${_job!.numberOfStaff}'),
                        _row(
                          _localizations.workTypeLabel,
                          _job!.workType == 'part_time' ? _localizations.partTime : _localizations.fullTime,
                        ),
                        _row(
                          _localizations.experienceLabel,
                          _job!.experience == 'experience_required'
                              ? _localizations.experienceRequired
                              : _localizations.fresherOk,
                        ),
                        if (_job!.preferredGender != null && _job!.preferredGender != 'any')
                          _row(
                            _localizations.genderLabel,
                            _job!.preferredGender == 'male' ? _localizations.male : _localizations.female,
                          ),
                        if (_shiftTimingLabel(_job!) != null)
                          _row(_localizations.shiftType, _shiftTimingLabel(_job!)!),
                        if (_weeklyOffLabel(_job!) != null)
                          _row(_localizations.weeklyOff, _weeklyOffLabel(_job!)!),
                        if (_accommodationLabel(_job!) != null)
                          _row(_localizations.accommodation, _accommodationLabel(_job!)!),
                        if (_facilitiesLabel(_job!) != null)
                          _row(_localizations.facilitiesBenefits, _facilitiesLabel(_job!)!),
                        if (_job!.skills.isNotEmpty) ...[
                          Text(
                            _localizations.selectSkills,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _job!.skills.map((s) {
                              final lab = _taxonomy?.compoundLabel(s, hi) ?? s;
                              return Chip(label: Text(lab, style: const TextStyle(fontSize: 11)));
                            }).toList(),
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (_descriptionText(_job!) != null)
                          _row(_localizations.shortDescription, _descriptionText(_job!)!),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => CandidateListScreen(
                                    selectedLanguage: widget.selectedLanguage,
                                    jobId: _job!.id,
                                    jobTitle: _roleLabel(_job!),
                                    jobLocation: _job!.location,
                                  ),
                                ),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(color: Color(0xFF3D3D7B)),
                            ),
                            child: Text(
                              _localizations.viewJobCTA,
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              softWrap: true,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF3D3D7B),
                                height: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}

// ============== OWNER SEEKER PROFILE (browse) ==============

class OwnerSeekerProfileScreen extends StatelessWidget {
  final Language selectedLanguage;
  final Map<String, dynamic> seeker;
  final JobTaxonomyCatalog? taxonomy;

  const OwnerSeekerProfileScreen({
    super.key,
    required this.selectedLanguage,
    required this.seeker,
    this.taxonomy,
  });

  bool get _hi => selectedLanguage == Language.hindi;

  String _roleLabel() {
    final role = seeker['preferredRole']?.toString() ?? '';
    if (role.isEmpty) return '—';
    return taxonomy?.categoryLabel(role, _hi) ??
        JobTaxonomyCatalog.toTitleCase(role.replaceAll('_', ' '));
  }

  String _fmtSalary(dynamic v) {
    if (v == null) return '—';
    final n = v is num ? v.toDouble() : double.tryParse(v.toString());
    if (n == null) return '—';
    if (n >= 1000) return '₹${(n / 1000).toStringAsFixed(0)}K';
    return '₹${n.toStringAsFixed(0)}';
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF121A2C)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations(selectedLanguage);
    final name = seeker['fullName']?.toString() ?? '—';
    final photo = seeker['profilePhotoUrl']?.toString() ?? '';
    final skills = (seeker['skills'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
    final completion = seeker['profileCompletionPercent'] is num
        ? (seeker['profileCompletionPercent'] as num).toInt()
        : 0;
    final years = seeker['experienceYears'];
    final expText = years is num && years > 0
        ? (_hi ? '$years साल' : '$years years')
        : (seeker['experience']?.toString().isNotEmpty == true
            ? seeker['experience'].toString()
            : (_hi ? 'फ्रेशर' : 'Fresher'));

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(_hi ? 'कैंडिडेट प्रोफ़ाइल' : 'Candidate profile'),
      ),
      body: SingleChildScrollView(
        padding: AppResponsive.scrollScreenPadding(context),
        child: Container(
          width: double.infinity,
          padding: AppResponsive.cardPaddingInsets(context),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: const Color(0xFFEEEEF8),
                    backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                    child: photo.isEmpty
                        ? Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF3D3D7B)),
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('$completion% ${_hi ? 'प्रोफ़ाइल पूरी' : 'profile complete'}',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _row(loc.roleLabel, _roleLabel()),
              _row(loc.locationLabel, seeker['city']?.toString() ?? '—'),
              _row(loc.experienceLabel, expText),
              _row(
                loc.salaryLabel,
                seeker['expectedSalaryMax'] != null
                    ? '${_fmtSalary(seeker['expectedSalary'])} - ${_fmtSalary(seeker['expectedSalaryMax'])} ${loc.perMonth}'
                    : _fmtSalary(seeker['expectedSalary']),
              ),
              if (skills.isNotEmpty) ...[
                Text(loc.selectSkills, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: skills.map((s) {
                    final lab = taxonomy?.compoundLabel(s, _hi) ?? s;
                    return Chip(
                      label: Text(lab, style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ============== OWNER APPLICANTS FILTER ==============

class OwnerApplicantsFilterScreen extends StatefulWidget {
  final Language selectedLanguage;
  final List<Job> jobs;
  final JobTaxonomyCatalog? taxonomy;
  final List<String>? cityOptions;
  final String? initialJobRole;
  final String? initialCity;

  const OwnerApplicantsFilterScreen({
    super.key,
    required this.selectedLanguage,
    required this.jobs,
    this.taxonomy,
    this.cityOptions,
    this.initialJobRole,
    this.initialCity,
  });

  @override
  State<OwnerApplicantsFilterScreen> createState() => _OwnerApplicantsFilterScreenState();
}

class _OwnerApplicantsFilterScreenState extends State<OwnerApplicantsFilterScreen> {
  late AppLocalizations _loc;
  String? _jobRole;
  String? _city;

  @override
  void initState() {
    super.initState();
    _loc = AppLocalizations(widget.selectedLanguage);
    _jobRole = widget.initialJobRole;
    _city = widget.initialCity;
  }

  List<({String id, String label})> _jobTypeOptions() {
    final hi = widget.selectedLanguage == Language.hindi;
    if (widget.taxonomy != null) {
      return widget.taxonomy!.allCategories()
          .map((c) => (id: c.id, label: c.labelFor(hi)))
          .toList()
        ..sort((a, b) => a.label.compareTo(b.label));
    }
    final seen = <String>{};
    final out = <({String id, String label})>[];
    for (final job in widget.jobs) {
      if (job.jobRole.isEmpty || seen.contains(job.jobRole)) continue;
      seen.add(job.jobRole);
      final label = job.customRoleName?.trim().isNotEmpty == true
          ? job.customRoleName!.trim()
          : JobTaxonomyCatalog.toTitleCase(job.jobRole.replaceAll('_', ' '));
      out.add((id: job.jobRole, label: label));
    }
    out.sort((a, b) => a.label.compareTo(b.label));
    return out;
  }

  List<String> _cityOptions() {
    if (widget.cityOptions != null && widget.cityOptions!.isNotEmpty) {
      return List<String>.from(widget.cityOptions!)..sort((a, b) => a.compareTo(b));
    }
    final cities = widget.jobs.map((j) => j.location).where((l) => l.isNotEmpty).toSet().toList();
    cities.sort((a, b) => a.compareTo(b));
    return cities;
  }

  @override
  Widget build(BuildContext context) {
    final jobTypes = _jobTypeOptions();
    final cities = _cityOptions();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _loc.applicantFiltersTitle,
          style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF121A2C)),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF121A2C)),
      ),
      body: SingleChildScrollView(
        padding: AppResponsive.scrollScreenPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _loc.roleLabel,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              value: _jobRole,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(_loc.allJobTypesFilter),
                ),
                ...jobTypes.map(
                  (o) => DropdownMenuItem<String?>(value: o.id, child: Text(o.label)),
                ),
              ],
              onChanged: (v) => setState(() => _jobRole = v),
            ),
            const SizedBox(height: 20),
            Text(
              _loc.locationLabel,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              value: _city,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(_loc.allCitiesFilter),
                ),
                ...cities.map(
                  (c) => DropdownMenuItem<String?>(value: c, child: Text(c)),
                ),
              ],
              onChanged: (v) => setState(() => _city = v),
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop({
                    'jobRole': _jobRole,
                    'city': _city,
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3D3D7B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  _loc.applyFilters,
                  style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop({'jobRole': null, 'city': null});
              },
              child: Text(_loc.clearFilters),
            ),
          ],
        ),
      ),
    );
  }
}

// ============== CANDIDATE LIST SCREEN (Owner) ==============

class CandidateListScreen extends StatefulWidget {
  final Language selectedLanguage;
  final String jobId;
  final String jobTitle;
  final String jobLocation;

  const CandidateListScreen({
    super.key,
    required this.selectedLanguage,
    required this.jobId,
    required this.jobTitle,
    required this.jobLocation,
  });

  @override
  State<CandidateListScreen> createState() => _CandidateListScreenState();
}

class _CandidateListScreenState extends State<CandidateListScreen> {
  late AppLocalizations _localizations;
  final ApiService _apiService = ApiService();

  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  List<Map<String, dynamic>> _applications = [];
  int _totalApplications = 0;
  Map<String, int> _statusBreakdown = {};
  String _selectedFilter = 'all';

  // Vacancy tracking
  int _vacancyCount = 1;
  int _hiredCount = 0;
  bool _vacancyFull = false;

  // Call masking state
  String? _callingApplicationId; // tracks which card is in "connecting" state

  // Debounce flag to prevent duplicate API calls
  bool _isUpdatingStatus = false;

  @override
  void initState() {
    super.initState();
    _localizations = AppLocalizations(widget.selectedLanguage);
    _loadCandidates();
  }

  Future<void> _loadCandidates() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    final statusFilter = _selectedFilter == 'all' ? null : _selectedFilter;
    final response = await _apiService.getJobCandidates(
      widget.jobId,
      status: statusFilter,
    );

    if (!mounted) return;

    if (response.success && response.data != null) {
      final data = response.data!;
      final apps = (data['applications'] as List<dynamic>? ?? [])
          .map((a) => Map<String, dynamic>.from(a as Map))
          .toList();

      // Extract vacancy info from job object
      final jobInfo = data['job'] as Map<String, dynamic>? ?? {};

      setState(() {
        _applications = apps;
        _totalApplications = data['total'] ?? apps.length;
        _statusBreakdown = Map<String, int>.from(
          (data['statusBreakdown'] as Map<String, dynamic>? ?? {}).map(
            (k, v) => MapEntry(k, (v as num).toInt()),
          ),
        );
        _vacancyCount = jobInfo['vacancyCount'] ?? 1;
        _hiredCount = jobInfo['hiredCount'] ?? (_statusBreakdown['hired'] ?? 0);
        _vacancyFull = jobInfo['vacancyFull'] ?? (_hiredCount >= _vacancyCount);
        _isLoading = false;
      });
    } else {
      setState(() {
        _hasError = true;
        _errorMessage = response.message ?? _localizations.errorLoadingCandidates;
        _isLoading = false;
      });
    }
  }

  Future<void> _updateStatus(String applicationId, String newStatus) async {
    if (_isUpdatingStatus) return;
    _isUpdatingStatus = true;

    // Optimistic update
    final previousApps = List<Map<String, dynamic>>.from(_applications);
    setState(() {
      for (int i = 0; i < _applications.length; i++) {
        if (_applications[i]['applicationId'] == applicationId) {
          _applications[i] = Map<String, dynamic>.from(_applications[i]);
          _applications[i]['status'] = newStatus;
          break;
        }
      }
    });

    final response = await _apiService.updateCandidateStatus(applicationId, newStatus);

    _isUpdatingStatus = false;

    if (!mounted) return;

    if (response.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_localizations.statusUpdateSuccess),
          backgroundColor: const Color(0xFF3D3D7B),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      // Refetch to sync status breakdown
      _loadCandidates();
    } else {
      // Revert optimistic update
      setState(() {
        _applications = previousApps;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response.message ?? _localizations.statusUpdateFailed),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _initiateSecureCall(String applicationId) async {
    if (_callingApplicationId != null) return; // prevent double-tap

    setState(() {
      _callingApplicationId = applicationId;
    });

    final response = await _apiService.initiateSecureCall(applicationId);

    if (!mounted) return;

    setState(() {
      _callingApplicationId = null;
    });

    if (response.success && response.data != null) {
      final data = response.data!;
      final remaining = data['remainingCallsToday'] ?? 0;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _localizations.callInitiated,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                '$remaining ${_localizations.callsRemainingToday}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response.message ?? _localizations.callFailed),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _getTimeAgo(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inDays > 30) {
        final months = (diff.inDays / 30).floor();
        return widget.selectedLanguage == Language.hindi
            ? '$months महीने ${_localizations.appliedAgo}'
            : '$months month${months > 1 ? 's' : ''} ${_localizations.appliedAgo}';
      } else if (diff.inDays > 0) {
        return widget.selectedLanguage == Language.hindi
            ? '${diff.inDays} दिन ${_localizations.appliedAgo}'
            : '${diff.inDays} day${diff.inDays > 1 ? 's' : ''} ${_localizations.appliedAgo}';
      } else if (diff.inHours > 0) {
        return widget.selectedLanguage == Language.hindi
            ? '${diff.inHours} घंटे ${_localizations.appliedAgo}'
            : '${diff.inHours} hour${diff.inHours > 1 ? 's' : ''} ${_localizations.appliedAgo}';
      } else if (diff.inMinutes > 0) {
        return widget.selectedLanguage == Language.hindi
            ? '${diff.inMinutes} मिनट ${_localizations.appliedAgo}'
            : '${diff.inMinutes} min ${_localizations.appliedAgo}';
      }
      return widget.selectedLanguage == Language.hindi ? 'अभी' : 'Just now';
    } catch (_) {
      return '';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'applied':
        return Colors.grey.shade600;
      case 'shortlisted':
        return const Color(0xFF2196F3);
      case 'interview':
        return const Color(0xFF9C27B0);
      case 'rejected':
        return const Color(0xFFE53935);
      case 'hired':
        return const Color(0xFF4CAF50);
      default:
        return Colors.grey;
    }
  }

  Color _getStatusBgColor(String status) {
    switch (status) {
      case 'applied':
        return Colors.grey.shade100;
      case 'shortlisted':
        return const Color(0xFFE3F2FD);
      case 'interview':
        return const Color(0xFFF3E5F5);
      case 'rejected':
        return const Color(0xFFFFEBEE);
      case 'hired':
        return const Color(0xFFE8F5E9);
      default:
        return Colors.grey.shade100;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'applied':
        return _localizations.statusApplied;
      case 'shortlisted':
        return _localizations.statusShortlisted;
      case 'interview':
        return _localizations.statusInterview;
      case 'rejected':
        return _localizations.statusRejected;
      case 'hired':
        return _localizations.statusHired;
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF3D3D7B)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _localizations.candidateListTitle,
              style: const TextStyle(
                color: Color(0xFF1A1A2E),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${widget.jobTitle} • ${widget.jobLocation}',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Color(0xFF3D3D7B)),
                  const SizedBox(height: 16),
                  Text(
                    _localizations.loadingCandidates,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  ),
                ],
              ),
            )
          : _hasError
              ? _buildErrorState()
              : _applications.isEmpty && _selectedFilter == 'all'
                  ? _buildEmptyState()
                  : _buildCandidatesList(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              style: const TextStyle(fontSize: 16, color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadCandidates,
              icon: const Icon(Icons.refresh),
              label: Text(_localizations.retry),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3D3D7B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: AppResponsive.screenPaddingHV(context, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFFEEEEF8),
                borderRadius: BorderRadius.circular(50),
              ),
              child: const Icon(Icons.people_outline, size: 48, color: Color(0xFF3D3D7B)),
            ),
            const SizedBox(height: 24),
            Text(
              _localizations.noApplicationsYet,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _localizations.noApplicationsSubtext,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCandidatesList() {
    return Column(
      children: [
        // Summary header
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF3D3D7B).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_localizations.totalApplications}: $_totalApplications',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3D3D7B),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Filter tabs
        Container(
          height: 48,
          color: Colors.white,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              _buildFilterChip('all', _localizations.allFilter, null),
              _buildFilterChip('applied', _localizations.statusApplied, _statusBreakdown['applied']),
              _buildFilterChip('shortlisted', _localizations.statusShortlisted, _statusBreakdown['shortlisted']),
              _buildFilterChip('interview', _localizations.statusInterview, _statusBreakdown['interview']),
              _buildFilterChip('hired', _localizations.statusHired, _statusBreakdown['hired']),
              _buildFilterChip('rejected', _localizations.statusRejected, _statusBreakdown['rejected']),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Candidate cards
        Expanded(
          child: _applications.isEmpty
              ? Center(
                  child: Text(
                    _localizations.noApplicationsYet,
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadCandidates,
                  color: const Color(0xFF3D3D7B),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _applications.length,
                    itemBuilder: (context, index) => _buildCandidateCard(_applications[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String value, String label, int? count) {
    final isSelected = _selectedFilter == value;
    final displayLabel = count != null ? '$label ($count)' : label;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: GestureDetector(
        onTap: () {
          if (_selectedFilter != value) {
            setState(() {
              _selectedFilter = value;
            });
            _loadCandidates();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF3D3D7B) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? const Color(0xFF3D3D7B) : Colors.grey.shade300,
            ),
          ),
          child: Text(
            displayLabel,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isSelected ? Colors.white : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCandidateCard(Map<String, dynamic> application) {
    final seeker = application['seeker'] as Map<String, dynamic>? ?? {};
    final status = application['status'] ?? 'applied';
    final applicationId = application['applicationId'] ?? '';
    final appliedAt = application['appliedAt']?.toString();

    final fullName = seeker['fullName'] ?? 'Unknown';
    final city = seeker['city'] ?? '';
    final experience = seeker['experience'] ?? '';
    final expectedSalary = seeker['expectedSalary'];
    final profileCompletion = seeker['profileCompletion'] ?? 0;
    final profilePhoto = seeker['profilePhoto'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: photo, name, status badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile photo
              CircleAvatar(
                radius: 26,
                backgroundColor: const Color(0xFFEEEEF8),
                backgroundImage: profilePhoto.isNotEmpty ? NetworkImage(profilePhoto) : null,
                child: profilePhoto.isEmpty
                    ? Text(
                        fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF3D3D7B),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),

              // Name + city + time
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    if (city.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            Icon(Icons.location_on, size: 14, color: Colors.grey.shade500),
                            const SizedBox(width: 2),
                            Text(
                              city,
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    if (appliedAt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _getTimeAgo(appliedAt),
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                        ),
                      ),
                  ],
                ),
              ),

              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusBgColor(status),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _getStatusLabel(status),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _getStatusColor(status),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Info chips: experience, salary, profile completion
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (experience.isNotEmpty)
                _buildInfoChip(Icons.work_outline, '${_localizations.experienceLabel2}: $experience'),
              if (expectedSalary != null)
                _buildInfoChip(Icons.currency_rupee, '${_localizations.expectedSalaryLabel}: ₹${expectedSalary is num ? expectedSalary.toStringAsFixed(0) : expectedSalary}'),
              _buildInfoChip(
                Icons.pie_chart_outline,
                '${_localizations.profileCompletionLabel}: $profileCompletion%',
              ),
            ],
          ),

          if (applicationId.toString().isNotEmpty && status != 'rejected') ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => ApplicationChatScreen(
                        applicationId: applicationId.toString(),
                        languageCode: widget.selectedLanguage == Language.hindi ? 'hi' : 'en',
                        title: fullName.toString(),
                        isSalonOwner: true,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: Text(widget.selectedLanguage == Language.hindi ? 'संदेश' : 'Message'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF3D3D7B),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  side: const BorderSide(color: Color(0xFF3D3D7B)),
                ),
              ),
            ),
          ],

          // Call (Secure) button — only for shortlisted / interview
          if (status == 'shortlisted' || status == 'interview') ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: _callingApplicationId == applicationId
                  ? Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3E5F5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF7B1FA2)),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _localizations.connecting,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF7B1FA2),
                            ),
                          ),
                        ],
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: () => _initiateSecureCall(applicationId),
                      icon: const Icon(Icons.phone, size: 16),
                      label: Text(_localizations.callSecure),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF7B1FA2),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        side: const BorderSide(color: Color(0xFF7B1FA2)),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _localizations.secureCallInfo,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
              ),
            ),
          ],

          // Action buttons based on status
          if (status != 'rejected' && status != 'hired') ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _buildActionButtons(applicationId, status, application),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  /// Show confirmation dialog for destructive/important actions
  Future<bool> _showConfirmationDialog({
    required String title,
    required String message,
    required Color confirmColor,
    String? confirmText,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text(message, style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(_localizations.cancelAction, style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: Text(confirmText ?? _localizations.confirmAction),
          ),
        ],
      ),
    );
    return result == true;
  }

  /// Show interview scheduling bottom sheet
  Future<void> _showScheduleInterviewModal(String applicationId, {String? existingDate, String? existingMode, String? existingNotes, bool isReschedule = false}) async {
    DateTime? selectedDate;
    TimeOfDay? selectedTime;
    String selectedMode = existingMode ?? 'in_person';
    final notesController = TextEditingController(text: existingNotes ?? '');
    bool isSubmitting = false;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isReschedule ? _localizations.rescheduleInterview : _localizations.scheduleInterview,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E)),
                ),
                const SizedBox(height: 20),

                // Date picker
                Text(_localizations.selectDate, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now().add(const Duration(days: 1)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 90)),
                    );
                    if (picked != null) setModalState(() => selectedDate = picked);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, size: 18, color: Colors.grey.shade600),
                        const SizedBox(width: 10),
                        Text(
                          selectedDate != null
                              ? '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}'
                              : (widget.selectedLanguage == Language.hindi ? 'तारीख चुनें' : 'Pick a date'),
                          style: TextStyle(fontSize: 15, color: selectedDate != null ? Colors.black87 : Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Time picker
                Text(_localizations.selectTime, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: ctx,
                      initialTime: const TimeOfDay(hour: 10, minute: 0),
                    );
                    if (picked != null) setModalState(() => selectedTime = picked);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.access_time, size: 18, color: Colors.grey.shade600),
                        const SizedBox(width: 10),
                        Text(
                          selectedTime != null
                              ? selectedTime!.format(ctx)
                              : (widget.selectedLanguage == Language.hindi ? 'समय चुनें' : 'Pick a time'),
                          style: TextStyle(fontSize: 15, color: selectedTime != null ? Colors.black87 : Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Mode selector
                Text(_localizations.interviewMode, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildModeChip('in_person', _localizations.inPerson, Icons.person, selectedMode, (v) => setModalState(() => selectedMode = v)),
                    _buildModeChip('phone_call', _localizations.phoneCall, Icons.phone, selectedMode, (v) => setModalState(() => selectedMode = v)),
                    _buildModeChip('video_call', _localizations.videoCall, Icons.videocam, selectedMode, (v) => setModalState(() => selectedMode = v)),
                  ],
                ),
                const SizedBox(height: 16),

                // Notes
                Text(_localizations.notesOptional, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: _localizations.notesHint,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
                const SizedBox(height: 24),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isSubmitting ? null : () async {
                      if (selectedDate == null || selectedTime == null) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text(_localizations.mustSelectDateTime), backgroundColor: Colors.orange),
                        );
                        return;
                      }
                      setModalState(() => isSubmitting = true);

                      final dateTime = DateTime(
                        selectedDate!.year, selectedDate!.month, selectedDate!.day,
                        selectedTime!.hour, selectedTime!.minute,
                      );

                      final response = isReschedule
                          ? await _apiService.rescheduleInterview(applicationId, interviewAt: dateTime.toUtc().toIso8601String(), mode: selectedMode, notes: notesController.text)
                          : await _apiService.scheduleInterview(applicationId, interviewAt: dateTime.toUtc().toIso8601String(), mode: selectedMode, notes: notesController.text);

                      setModalState(() => isSubmitting = false);

                      if (response.success) {
                        Navigator.of(ctx).pop(true);
                      } else {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text(response.message ?? 'Failed'), backgroundColor: Colors.red),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF9C27B0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: isSubmitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(isReschedule ? _localizations.rescheduleInterview : _localizations.scheduleInterview, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isReschedule ? _localizations.rescheduleSuccess : _localizations.scheduleSuccess),
          backgroundColor: const Color(0xFF9C27B0),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _loadCandidates();
    }
  }

  Widget _buildModeChip(String value, String label, IconData icon, String selected, void Function(String) onSelect) {
    final isSelected = selected == value;
    return GestureDetector(
      onTap: () => onSelect(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF9C27B0).withOpacity(0.1) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? const Color(0xFF9C27B0) : Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? const Color(0xFF9C27B0) : Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: isSelected ? const Color(0xFF9C27B0) : Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }

  /// Complete interview with confirmation
  Future<void> _completeInterview(String applicationId) async {
    final confirmed = await _showConfirmationDialog(
      title: _localizations.markInterviewComplete,
      message: _localizations.hireOrReject,
      confirmColor: const Color(0xFF9C27B0),
      confirmText: _localizations.markInterviewComplete,
    );
    if (!confirmed) return;

    final response = await _apiService.completeInterview(applicationId);
    if (!mounted) return;

    if (response.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_localizations.completeSuccess), backgroundColor: const Color(0xFF9C27B0), behavior: SnackBarBehavior.floating),
      );
      _loadCandidates();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(response.message ?? 'Failed'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
      );
    }
  }

  /// Reject with confirmation dialog
  Future<void> _confirmAndReject(String applicationId) async {
    final confirmed = await _showConfirmationDialog(
      title: _localizations.confirmRejectTitle,
      message: _localizations.confirmRejectMessage,
      confirmColor: Colors.red.shade600,
      confirmText: _localizations.rejectAction,
    );
    if (confirmed) {
      _updateStatus(applicationId, 'rejected');
    }
  }

  /// Hire with confirmation dialog
  Future<void> _confirmAndHire(String applicationId) async {
    final confirmed = await _showConfirmationDialog(
      title: _localizations.confirmHireTitle,
      message: _localizations.confirmHireMessage,
      confirmColor: const Color(0xFF4CAF50),
      confirmText: _localizations.markHiredAction,
    );
    if (confirmed) {
      _updateStatus(applicationId, 'hired');
    }
  }

  Widget _buildActionButtons(String applicationId, String status, [Map<String, dynamic>? application]) {
    final interviewStatus = application?['interviewStatus'] ?? 'not_scheduled';
    final interviewAt = application?['interviewScheduledAt']?.toString();
    final interviewMode = application?['interviewMode']?.toString();
    final interviewNotes = application?['interviewNotes']?.toString();

    switch (status) {
      case 'applied':
        return ResponsiveDualButtons(
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _updateStatus(applicationId, 'shortlisted'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2196F3),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: Text(_localizations.shortlistAction, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _confirmAndReject(applicationId),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade600,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  side: BorderSide(color: Colors.red.shade300),
                ),
                child: Text(_localizations.rejectAction, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        );

      case 'shortlisted':
        return ResponsiveDualButtons(
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showScheduleInterviewModal(applicationId),
                icon: const Icon(Icons.event, size: 16),
                label: Text(_localizations.scheduleInterview, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF9C27B0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _confirmAndReject(applicationId),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade600,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  side: BorderSide(color: Colors.red.shade300),
                ),
                child: Text(_localizations.rejectAction, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        );

      case 'interview':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Interview info banner (if scheduled)
            if (interviewStatus == 'scheduled' && interviewAt != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E5F5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF9C27B0).withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.event, size: 16, color: Color(0xFF7B1FA2)),
                        const SizedBox(width: 6),
                        Text(
                          _localizations.interviewScheduled,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF7B1FA2)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatInterviewDateTime(interviewAt),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E)),
                    ),
                    if (interviewMode != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '📍 ${interviewMode == 'in_person' ? _localizations.inPerson : interviewMode == 'phone_call' ? _localizations.phoneCall : _localizations.videoCall}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ),
                    if (interviewNotes != null && interviewNotes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('📝 $interviewNotes', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              ResponsiveDualButtons(
                gap: 8,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _showScheduleInterviewModal(
                        applicationId,
                        existingMode: interviewMode,
                        existingNotes: interviewNotes,
                        isReschedule: true,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF9C27B0),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        side: const BorderSide(color: Color(0xFF9C27B0)),
                      ),
                      child: Text(_localizations.rescheduleInterview, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _completeInterview(applicationId),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF9C27B0),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: Text(_localizations.markInterviewComplete, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            // Interview completed banner
            if (interviewStatus == 'completed') ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE7F6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, size: 16, color: Color(0xFF7B1FA2)),
                    const SizedBox(width: 6),
                    Text(_localizations.interviewCompleted, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF7B1FA2))),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            ResponsiveDualButtons(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Tooltip(
                    message: _vacancyFull ? _localizations.allPositionsFilled : '',
                    child: ElevatedButton(
                      onPressed: _vacancyFull ? null : () => _confirmAndHire(applicationId),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _vacancyFull ? Colors.grey.shade300 : const Color(0xFF4CAF50),
                        foregroundColor: _vacancyFull ? Colors.grey.shade500 : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: Text(_localizations.markHiredAction, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _confirmAndReject(applicationId),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade600,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      side: BorderSide(color: Colors.red.shade300),
                    ),
                    child: Text(_localizations.rejectAction, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
            if (_vacancyFull)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _localizations.allPositionsFilled,
                  style: TextStyle(fontSize: 11, color: Colors.orange.shade700, fontStyle: FontStyle.italic),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        );

      default:
        return const SizedBox.shrink();
    }
  }

  String _formatInterviewDateTime(String? isoString) {
    if (isoString == null) return '';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final minute = dt.minute.toString().padLeft(2, '0');
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year} at $hour:$minute $ampm';
    } catch (_) {
      return isoString;
    }
  }
}

/// Full-screen edit for salon name, owner, city, address (owner profile tab).
class SalonEditProfileScreen extends StatefulWidget {
  final Language selectedLanguage;
  final SalonProfile profile;

  const SalonEditProfileScreen({
    super.key,
    required this.selectedLanguage,
    required this.profile,
  });

  @override
  State<SalonEditProfileScreen> createState() => _SalonEditProfileScreenState();
}

class _SalonEditProfileScreenState extends State<SalonEditProfileScreen> {
  late AppLocalizations _localizations;
  final ApiService _apiService = ApiService();
  late final TextEditingController _salonName;
  late final TextEditingController _ownerName;
  late final TextEditingController _area;
  late final TextEditingController _address;
  String? _city;
  List<String> _cities = [];
  bool _loadingCities = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _localizations = AppLocalizations(widget.selectedLanguage);
    final p = widget.profile;
    _salonName = TextEditingController(text: p.salonName ?? '');
    _ownerName = TextEditingController(text: p.ownerName ?? '');
    _area = TextEditingController(text: p.area ?? '');
    _address = TextEditingController(text: p.fullAddress ?? '');
    _city = p.city;
    _loadCities();
  }

  Future<void> _loadCities() async {
    setState(() => _loadingCities = true);
    try {
      final list = await IndiaCityService.instance.loadCities();
      if (mounted) setState(() => _cities = list);
    } finally {
      if (mounted) setState(() => _loadingCities = false);
    }
  }

  @override
  void dispose() {
    _salonName.dispose();
    _ownerName.dispose();
    _area.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _pickCity() async {
    final picked = await showIndiaCityPickerSheet(
      context,
      cities: _cities,
      isLoading: _loadingCities,
      selected: _city,
      title: _localizations.city,
      searchHint: _localizations.searchLocation,
    );
    if (picked != null && mounted) setState(() => _city = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final updates = <String, dynamic>{
        if (_salonName.text.trim().isNotEmpty) 'salonName': _salonName.text.trim(),
        if (_ownerName.text.trim().isNotEmpty) 'ownerName': _ownerName.text.trim(),
        if (_city != null && _city!.trim().isNotEmpty) 'city': _city!.trim(),
        if (_area.text.trim().isNotEmpty) 'area': _area.text.trim(),
        if (_address.text.trim().isNotEmpty) 'fullAddress': _address.text.trim(),
      };
      if (updates.isEmpty) {
        if (mounted) Navigator.pop(context, false);
        return;
      }
      final res = await _apiService.updateSalonProfile(updates);
      if (!mounted) return;
      if (res.success) {
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.message ?? 'Update failed'), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saveLabel = widget.selectedLanguage == Language.hindi ? 'सेव' : 'Save';
    final bottomSave = widget.selectedLanguage == Language.hindi ? 'सेव करें' : 'Save changes';
    final areaLabel = widget.selectedLanguage == Language.hindi ? 'इलाका (वैकल्पिक)' : 'Area (optional)';
    final addrLabel = widget.selectedLanguage == Language.hindi ? 'पूरा पता (वैकल्पिक)' : 'Full address (optional)';

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF121A2C),
        title: Text(_localizations.editProfile, style: const TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(saveLabel, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF3D3D7B))),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: AppResponsive.scrollScreenPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_localizations.salonName, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _salonName,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),
            Text(_localizations.ownerManagerName, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _ownerName,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),
            Text(_localizations.loginPhoneLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                widget.profile.phoneNumber.isNotEmpty
                    ? widget.profile.phoneNumber
                    : _localizations.notAdded,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _localizations.contactNumberHint,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.35),
            ),
            const SizedBox(height: 20),
            Text(_localizations.city, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickCity,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  suffixIcon: const Icon(Icons.arrow_drop_down),
                ),
                child: Text(
                  _city?.isNotEmpty == true ? _city! : (_loadingCities ? '...' : _localizations.notAdded),
                  style: TextStyle(color: _city == null ? Colors.grey.shade600 : const Color(0xFF121A2C)),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(areaLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _area,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),
            Text(addrLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _address,
              maxLines: 3,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3D3D7B),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(bottomSave, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============== PROFILE SCREEN ==============
class ProfileScreen extends StatefulWidget {
  final Language selectedLanguage;
  final SalonProfile? salonProfile;
  final ProfileCompletion? profileCompletion;
  final VoidCallback onProfileUpdated;
  final ValueChanged<Language>? onLanguageChanged;
  
  const ProfileScreen({
    super.key,
    required this.selectedLanguage,
    this.salonProfile,
    this.profileCompletion,
    required this.onProfileUpdated,
    this.onLanguageChanged,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late AppLocalizations _localizations;
  final ApiService _apiService = ApiService();
  bool _isLoggingOut = false;
  
  SalonProfile? _salonProfile;
  ProfileCompletion? _profileCompletion;
  String? _profilePhotoUrl;
  bool _isLoading = true;
  bool _completionCardDismissed = false;
  bool _salonDetailsExpanded = false;
  bool _verificationExpanded = false;
  bool _uploadingExtraPhoto = false;
  bool _uploadingVerification = false;

  // Local language state (can be different from widget.selectedLanguage)
  late Language _currentLanguage = widget.selectedLanguage;
  
  @override
  void initState() {
    super.initState();
    _currentLanguage = widget.selectedLanguage;
    _localizations = AppLocalizations(_currentLanguage);
    _salonProfile = widget.salonProfile;
    _profileCompletion = widget.profileCompletion;
    _loadProfileData();
  }
  
  @override
  void didUpdateWidget(ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update language if parent changed it
    if (oldWidget.selectedLanguage != widget.selectedLanguage) {
      setState(() {
        _currentLanguage = widget.selectedLanguage;
        _localizations = AppLocalizations(_currentLanguage);
      });
    }
  }
  
  void _updateLanguage(Language newLanguage) {
    setState(() {
      _currentLanguage = newLanguage;
      _localizations = AppLocalizations(_currentLanguage);
    });
    
    // Notify parent to update language across entire app
    if (widget.onLanguageChanged != null) {
      widget.onLanguageChanged!(newLanguage);
    }
  }
  
  Future<void> _showLanguageDialog() async {
    await showLanguageBottomSheet(
      context,
      _currentLanguage,
      (newLanguage) {
        _updateLanguage(newLanguage);
      },
    );
  }

  Future<void> _handleLogout() async {
    if (_isLoggingOut) return;

    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(_localizations.logout),
          content: Text(
            _currentLanguage == Language.hindi
                ? 'क्या आप वाकई लॉग आउट करना चाहते हैं?'
                : 'Are you sure you want to log out?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(_localizations.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(_localizations.logout),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true) return;

    setState(() {
      _isLoggingOut = true;
    });

    try {
      await PushNotificationService().unregisterToken();
      await _apiService.logout();
    } catch (_) {
      // Ignore API failure; continue clearing local state
    } finally {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const SplashScreen()),
        (route) => false,
      );
    }
  }
  
  Future<void> _loadProfileData({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _isLoading = true;
      });
    }
    
    try {
      final profileResponse = await _apiService.getSalonProfile();
      if (profileResponse.success && profileResponse.data != null) {
        setState(() {
          _salonProfile = profileResponse.data;
          _syncAvatarFromMedia();
        });
      }
      
      final completionResponse = await _apiService.getProfileCompletion();
      if (completionResponse.success && completionResponse.data != null) {
        setState(() {
          _profileCompletion = completionResponse.data;
        });
      }
    } catch (e) {
      print('Error loading profile: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _syncAvatarFromMedia() {
    _profilePhotoUrl = _salonProfile?.displayAvatarUrl;
  }

  Future<void> _uploadProfilePhoto() async {
    if (_isLoading) return;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (picked == null) return;

      final file = File(picked.path);
      final contentType = jobtreeInferImageContentType(picked.path, picked.mimeType);

      final bytes = await file.readAsBytes();
      final uploadRes = await _apiService.uploadSalonMediaDirect(
        bodyBytes: bytes,
        contentType: contentType,
        mediaType: 'photo',
        isPrimary: true,
        filename: picked.name,
      );
      if (!uploadRes.success) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _currentLanguage == Language.hindi
                  ? 'फोटो अपलोड असफल: ${uploadRes.message ?? uploadRes.errorCode ?? ''}'
                  : 'Photo upload failed: ${uploadRes.message ?? uploadRes.errorCode ?? ''}',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      if (!mounted) return;
      await _loadProfileData(quiet: true);
      widget.onProfileUpdated();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_currentLanguage == Language.hindi ? 'फोटो अपडेट हो गया' : 'Profile photo updated'),
          backgroundColor: const Color(0xFF3D3D7B),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_currentLanguage == Language.hindi ? 'फोटो अपडेट में समस्या आई' : 'Failed to update photo'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  static const int _maxSalonGalleryPhotos = 12;

  int get _salonImageCount => (_salonProfile?.media ?? []).where((m) => m.isImage).length;

  Future<void> _openEditSalonProfile() async {
    if (_salonProfile == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_currentLanguage == Language.hindi ? 'प्रोफ़ाइल लोड हो रही है' : 'Profile is still loading'),
        ),
      );
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (ctx) => SalonEditProfileScreen(
          selectedLanguage: _currentLanguage,
          profile: _salonProfile!,
        ),
      ),
    );
    if (changed == true && mounted) {
      await _loadProfileData(quiet: true);
      widget.onProfileUpdated();
    }
  }

  Future<void> _addSalonPhotoFromGallery() async {
    if (_uploadingExtraPhoto || _isLoading) return;
    if (_salonImageCount >= _maxSalonGalleryPhotos) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _currentLanguage == Language.hindi
                ? 'अधिकतम $_maxSalonGalleryPhotos फ़ोटो'
                : 'Maximum $_maxSalonGalleryPhotos photos',
          ),
        ),
      );
      return;
    }
    setState(() => _uploadingExtraPhoto = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null) return;

      final file = File(picked.path);
      final contentType = jobtreeInferImageContentType(picked.path, picked.mimeType);

      final bytes = await file.readAsBytes();
      final hasPrimary = (_salonProfile?.media ?? []).any((m) => m.isImage && m.isPrimary);
      final uploadRes = await _apiService.uploadSalonMediaDirect(
        bodyBytes: bytes,
        contentType: contentType,
        mediaType: 'photo',
        isPrimary: !hasPrimary,
        filename: picked.name,
      );
      if (!uploadRes.success) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _currentLanguage == Language.hindi
                  ? 'फोटो अपलोड असफल: ${uploadRes.message ?? uploadRes.errorCode ?? ''}'
                  : 'Photo upload failed: ${uploadRes.message ?? uploadRes.errorCode ?? ''}',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      if (!mounted) return;
      await _loadProfileData(quiet: true);
      widget.onProfileUpdated();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_currentLanguage == Language.hindi ? 'फोटो जोड़ा गया' : 'Photo added'),
          backgroundColor: const Color(0xFF3D3D7B),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_currentLanguage == Language.hindi ? 'फोटो अपलोड में समस्या' : 'Photo upload failed'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingExtraPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return RefreshIndicator(
      onRefresh: () => _loadProfileData(quiet: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 80, top: 8),
        child: ResponsiveContent(
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. PROFILE HEADER
            _buildProfileHeader(),
            
            const SizedBox(height: 16),
            
            // 2. PROFILE COMPLETION CARD (Single card, dismissible)
            if (!_completionCardDismissed && _profileCompletion != null && _profileCompletion!.completionPercent < 100)
              _buildCompletionCard(),
            
            const SizedBox(height: 16),
            
            // 3. SALON DETAILS CARD (Collapsible)
            _buildSalonDetailsCard(),
            
            const SizedBox(height: 16),
            
            // 4. VERIFICATION & DOCUMENTS (Optional, collapsible)
            _buildVerificationCard(),
            
            const SizedBox(height: 16),
            
            // 5. MEDIA & PHOTOS
            _buildMediaSection(),
            
            const SizedBox(height: 16),
            
            // 6. SETTINGS
            _buildSettingsSection(),
            
            const SizedBox(height: 80), // Space for bottom nav
          ],
        ),
        ),
      ),
    );
  }
  
  // 1. PROFILE HEADER
  Widget _buildProfileHeader() {
    final salonName = _salonProfile?.salonName ?? _salonProfile?.ownerName ?? 'Salon';
    final city = _salonProfile?.city ?? '';
    final phone = _salonProfile?.phoneNumber ?? '';
    final firstLetter = salonName.isNotEmpty ? salonName[0].toUpperCase() : 'S';
    
    return Container(
      padding: AppResponsive.cardPaddingInsets(context),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openEditSalonProfile,
              borderRadius: BorderRadius.circular(12),
              child: Row(
            children: [
              // Salon Logo/Avatar
              GestureDetector(
                onTap: _uploadProfilePhoto,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: const Color(0xFF3D3D7B),
                      backgroundImage: _profilePhotoUrl != null
                          ? NetworkImage(_profilePhotoUrl!)
                          : null,
                      child: _profilePhotoUrl == null
                          ? Text(
                              firstLetter,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Color(0xFF4CAF50),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              
              // Salon Name & City
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            salonName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF121A2C),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_salonProfile?.isSalonVerified == true)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.verified, color: Color(0xFF1565C0), size: 22),
                          ),
                      ],
                    ),
                    if (city.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.location_on, size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            city,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (phone.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          Icon(Icons.phone, size: 16, color: Colors.grey.shade600),
                          Text(
                            phone,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4CAF50).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _localizations.verified,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF4CAF50),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _localizations.tapToEditProfile,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }
  
  // 2. PROFILE COMPLETION CARD (Progressive upsell based on stage)
  Widget _buildCompletionCard() {
    final percent = _profileCompletion?.completionPercent ?? 0;
    final upsellStage = _profileCompletion?.upsellStage ?? 'early';
    final percentText = _localizations.yourProfileIsComplete.replaceAll('{p}', '$percent');
    
    // Different UI based on upsell stage
    switch (upsellStage) {
      case 'early': // 0-40%
        return _buildEarlyStageCard(percent, percentText);
      case 'activation': // 41-70%
        return _buildActivationStageCard(percent, percentText);
      case 'trust': // 71-85%
        return _buildTrustStageCard(percent, percentText);
      case 'ready': // 86-100%
        return _buildReadyStageCard(percent, percentText);
      default:
        return _buildEarlyStageCard(percent, percentText);
    }
  }
  
  // Early Stage (0-40%) - No pricing, just completion
  Widget _buildEarlyStageCard(int percent, String percentText) {
    return Container(
      padding: AppResponsive.cardPaddingInsets(context),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppResponsive.ownerHomeCardBorder),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 28),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = AppResponsive.stackCompletionCard(context, constraints);
                final ring = ProfilePercentRing(
                  size: 60,
                  percent: percent,
                  strokeWidth: 6,
                  trackColor: Colors.grey.shade300,
                  valueColor: const Color(0xFFF9A825),
                  textColor: const Color(0xFF5D4037),
                );
                final copy = Column(
                  crossAxisAlignment: narrow ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
                  children: [
                    Text(
                      percentText,
                      textAlign: narrow ? TextAlign.center : TextAlign.start,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF5D4037),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _localizations.completeProfileToGetBetterCandidates,
                      textAlign: narrow ? TextAlign.center : TextAlign.start,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _openEditSalonProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF9A825),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          _localizations.completeNow,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: ring),
                      const SizedBox(height: 12),
                      copy,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ring,
                    const SizedBox(width: 16),
                    Expanded(child: copy),
                  ],
                );
              },
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              icon: const Icon(Icons.close, size: 20),
              color: Colors.grey.shade600,
              onPressed: () {
                setState(() {
                  _completionCardDismissed = true;
                });
              },
            ),
          ),
        ],
      ),
    );
  }
  
  // Activation Stage (41-70%) - Soft nudge about photos
  Widget _buildActivationStageCard(int percent, String percentText) {
    return Container(
      padding: AppResponsive.cardPaddingInsets(context),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppResponsive.ownerHomeCardBorder),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 28),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = AppResponsive.stackCompletionCard(context, constraints);
                final ring = ProfilePercentRing(
                  size: 60,
                  percent: percent,
                  strokeWidth: 6,
                  trackColor: Colors.grey.shade300,
                  valueColor: const Color(0xFFF9A825),
                  textColor: const Color(0xFF5D4037),
                );
                final copy = Column(
                  crossAxisAlignment: narrow ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
                  children: [
                    Text(
                      percentText,
                      textAlign: narrow ? TextAlign.center : TextAlign.start,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF5D4037),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.selectedLanguage == Language.hindi
                          ? 'फोटो वाली प्रोफ़ाइल को 2× ज़्यादा एप्लिकेशन मिलते हैं'
                          : 'Profiles with photos get 2× more applications',
                      textAlign: narrow ? TextAlign.center : TextAlign.start,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _addSalonPhotoFromGallery,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF9A825),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          widget.selectedLanguage == Language.hindi ? 'फोटो जोड़ें' : 'Add Photos',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: ring),
                      const SizedBox(height: 12),
                      copy,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ring,
                    const SizedBox(width: 16),
                    Expanded(child: copy),
                  ],
                );
              },
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              icon: const Icon(Icons.close, size: 20),
              color: Colors.grey.shade600,
              onPressed: () {
                setState(() {
                  _completionCardDismissed = true;
                });
              },
            ),
          ),
        ],
      ),
    );
  }
  
  // Trust Stage (71-85%) - Subtle premium teaser (NO pricing)
  Widget _buildTrustStageCard(int percent, String percentText) {
    return Container(
      padding: AppResponsive.cardPaddingInsets(context),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppResponsive.ownerHomeCardBorder),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ProfilePercentRing(
                    size: 50,
                    percent: percent,
                    strokeWidth: 5,
                    trackColor: Colors.grey.shade300,
                    valueColor: const Color(0xFF2196F3),
                    textColor: const Color(0xFF1565C0),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.selectedLanguage == Language.hindi
                              ? 'सत्यापित सैलून बैज के साथ आगे बढ़ें'
                              : 'Stand out with a Verified Salon badge',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1565C0),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.selectedLanguage == Language.hindi
                              ? 'सत्यापित सैलून को तेज़ जवाब मिलते हैं'
                              : 'Verified salons get faster responses',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _showVerifiedSalonLearnMore,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF2196F3)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    widget.selectedLanguage == Language.hindi ? 'और जानें' : 'Learn More',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2196F3),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              icon: const Icon(Icons.close, size: 20),
              color: Colors.grey.shade600,
              onPressed: () {
                setState(() {
                  _completionCardDismissed = true;
                });
              },
            ),
          ),
        ],
      ),
    );
  }
  
  // Ready Stage (86-100%) - First time pricing appears
  Widget _buildReadyStageCard(int percent, String percentText) {
    return Container(
      padding: AppResponsive.cardPaddingInsets(context),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppResponsive.ownerHomeCardBorder),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ProfilePercentRing(
                    size: 50,
                    percent: percent,
                    strokeWidth: 5,
                    trackColor: Colors.grey.shade300,
                    valueColor: const Color(0xFF4CAF50),
                    textColor: const Color(0xFF2E7D32),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.selectedLanguage == Language.hindi
                              ? 'अपनी job visibility बढ़ाएं'
                              : 'Boost your job visibility',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.selectedLanguage == Language.hindi
                              ? 'Featured listing • Priority candidates • Verified badge'
                              : 'Featured listing • Priority candidates • Verified badge',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // TODO: Navigate to pricing/plans (FIRST TIME pricing appears)
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    widget.selectedLanguage == Language.hindi ? 'Plans देखें' : 'View Plans',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              icon: const Icon(Icons.close, size: 20),
              color: Colors.grey.shade600,
              onPressed: () {
                setState(() {
                  _completionCardDismissed = true;
                });
              },
            ),
          ),
        ],
      ),
    );
  }
  
  // 3. SALON DETAILS CARD (Collapsible)
  Widget _buildSalonDetailsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header (always visible)
          InkWell(
            onTap: () {
              setState(() {
                _salonDetailsExpanded = !_salonDetailsExpanded;
              });
            },
            child: Padding(
              padding: AppResponsive.cardPaddingInsets(context),
              child: Row(
                children: [
                  const Icon(Icons.business, color: Color(0xFF3D3D7B)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _localizations.salonDetailsProfile,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF121A2C),
                      ),
                    ),
                  ),
                  Icon(
                    _salonDetailsExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),
          
          // Expanded content
          if (_salonDetailsExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow(
                    _localizations.salonName,
                    _salonProfile?.salonName ?? _localizations.notAdded,
                    valueTrailing: _salonProfile?.isSalonVerified == true
                        ? const Icon(Icons.verified, color: Color(0xFF1565C0), size: 18)
                        : null,
                  ),
                  const SizedBox(height: 16),
                  _buildDetailRow(
                    _localizations.ownerManagerName,
                    _salonProfile?.ownerName ?? _localizations.notAdded,
                  ),
                  const SizedBox(height: 16),
                  _buildDetailRow(
                    _localizations.city,
                    _salonProfile?.city ?? _localizations.notAdded,
                  ),
                  const SizedBox(height: 16),
                  _buildDetailRow(
                    _localizations.contactNumber,
                    _salonProfile?.phoneNumber ?? _localizations.notAdded,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildDetailRow(String label, String value, {Widget? valueTrailing}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF121A2C),
                  ),
                ),
              ),
              if (valueTrailing != null) valueTrailing,
            ],
          ),
        ),
      ],
    );
  }

  Widget _verificationStatusTag() {
    final st = _salonProfile?.verificationStatus ?? 'unverified';
    String t;
    Color bg;
    Color fg;
    switch (st) {
      case 'verified':
        t = _currentLanguage == Language.hindi ? 'सत्यापित' : 'Verified';
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
        break;
      case 'pending':
        t = _currentLanguage == Language.hindi ? 'सत्यापन जारी' : 'In review';
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade900;
        break;
      case 'rejected':
        t = _currentLanguage == Language.hindi ? 'अस्वीकृत' : 'Rejected';
        bg = Colors.red.shade50;
        fg = Colors.red.shade900;
        break;
      default:
        t = _localizations.optional;
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade700;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        t,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }

  void _showVerifiedSalonLearnMore() {
    final hi = _currentLanguage == Language.hindi;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(hi ? 'सत्यापित सैलून बैज' : 'Verified Salon badge'),
        content: SingleChildScrollView(
          child: Text(
            hi
                ? 'जब आप आधार और व्यापार प्रमाण जमा करके हमारी टीम से मंजूरी लेते हैं, तो आपके सैलून के नाम के बगल में नीला सत्यापन चिह्न दिखाई देता है। उम्मीदवारों को भरोसा बढ़ता है।\n\nसमीक्षा अभी टीम द्वारा की जाती है; एडमिन पोर्टल जल्द उपलब्ध होगा।'
                : 'After you submit ID and business proof and our team approves your salon, a blue verified badge appears next to your salon name so job seekers trust your listings more.\n\nReviews are handled by our team for now; an admin portal will follow.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(hi ? 'ठीक' : 'OK')),
        ],
      ),
    );
  }

  Future<void> _openVerificationDocUrl(String? url) async {
    if (url == null || url.isEmpty || !mounted) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_currentLanguage == Language.hindi ? 'लिंक नहीं खुल सका' : 'Could not open link')),
      );
    }
  }

  Future<void> _pickAndUploadVerificationDoc(String docType) async {
    if (_uploadingVerification) return;
    setState(() => _uploadingVerification = true);
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf', 'heic'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) return;
      final name = f.name;
      final ct = jobtreeInferDocContentType(name, f.extension);
      final upload = await _apiService.uploadSalonVerificationDocument(
        bodyBytes: bytes,
        contentType: ct,
        docType: docType,
        filename: name,
      );
      if (!mounted) return;
      if (upload.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _currentLanguage == Language.hindi
                  ? 'दस्तावेज़ जमा हो गया। सत्यापन लंबित है।'
                  : 'Document submitted. Verification is pending.',
            ),
            backgroundColor: const Color(0xFF3D3D7B),
          ),
        );
        await _loadProfileData(quiet: true);
        widget.onProfileUpdated();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(upload.message ?? upload.errorCode ?? 'Upload failed'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingVerification = false);
    }
  }

  // 4. VERIFICATION & DOCUMENTS
  Widget _buildVerificationCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _verificationExpanded = !_verificationExpanded;
              });
            },
            child: Padding(
              padding: AppResponsive.cardPaddingInsets(context),
              child: Row(
                children: [
                  const Icon(Icons.verified_user, color: Color(0xFF3D3D7B)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _localizations.verificationDocuments,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF121A2C),
                      ),
                    ),
                  ),
                  _verificationStatusTag(),
                  const SizedBox(width: 8),
                  Icon(
                    _verificationExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),
          if (_verificationExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((_salonProfile?.verificationStatus ?? '') == 'rejected')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _currentLanguage == Language.hindi
                            ? 'पिछला सत्यापन अस्वीकार हो गया। स्पष्ट दस्तावेज़ फिर से अपलोड करें।'
                            : 'Your last verification was not approved. Please upload clear documents again.',
                        style: TextStyle(fontSize: 13, color: Colors.red.shade800),
                      ),
                    ),
                  if ((_salonProfile?.verificationStatus ?? '') == 'pending')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _currentLanguage == Language.hindi
                            ? 'आपके दस्तावेज़ समीक्षा में हैं।'
                            : 'Your documents are under review.',
                        style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade800),
                      ),
                    ),
                  if ((_salonProfile?.verificationDocs ?? []).isNotEmpty) ...[
                    Text(
                      _currentLanguage == Language.hindi ? 'जमा दस्तावेज़' : 'Submitted documents',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    for (final d in _salonProfile!.verificationDocs.take(8))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${d.docType} · ${d.status}',
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                              ),
                            ),
                            if (d.docFileUrl != null && d.docFileUrl!.isNotEmpty)
                              TextButton(
                                onPressed: () => _openVerificationDocUrl(d.docFileUrl),
                                child: Text(_currentLanguage == Language.hindi ? 'खोलें' : 'Open'),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    _currentLanguage == Language.hindi
                        ? 'आधार / पहचान और व्यापार प्रमाण (GST, लाइसेंस, फोटो या PDF) अपलोड करें।'
                        : 'Upload ID (Aadhaar) and business proof (GST, license — photo or PDF).',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _uploadingVerification ? null : () => _pickAndUploadVerificationDoc('aadhaar'),
                        icon: const Icon(Icons.badge_outlined, size: 18),
                        label: Text(_currentLanguage == Language.hindi ? 'KYC / आधार' : 'KYC / Aadhaar'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _uploadingVerification ? null : () => _pickAndUploadVerificationDoc('gst'),
                        icon: const Icon(Icons.receipt_long_outlined, size: 18),
                        label: Text(_currentLanguage == Language.hindi ? 'GST' : 'GST'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _uploadingVerification ? null : () => _pickAndUploadVerificationDoc('shop_license'),
                        icon: const Icon(Icons.store_outlined, size: 18),
                        label: Text(_currentLanguage == Language.hindi ? 'दुकान लाइसेंस' : 'Shop license'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // 5. MEDIA & PHOTOS
  Widget _buildMediaSection() {
    final images = (_salonProfile?.media ?? []).where((m) => m.isImage).toList();
    final canAddMore = images.length < _maxSalonGalleryPhotos;

    return Container(
      padding: AppResponsive.cardPaddingInsets(context),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.photo_library, color: Color(0xFF3D3D7B)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _localizations.mediaPhotos,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF121A2C),
                  ),
                ),
              ),
              Text(
                '${images.length}/$_maxSalonGalleryPhotos',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 104,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final m in images)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => showJobtreeImagePreview(context, m.mediaUrl),
                        borderRadius: BorderRadius.circular(10),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 100,
                            height: 100,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(
                                  m.mediaUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => ColoredBox(
                                    color: Colors.grey.shade300,
                                    child: Icon(Icons.broken_image_outlined, color: Colors.grey.shade600),
                                  ),
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Center(
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          value: loadingProgress.expectedTotalBytes != null
                                              ? loadingProgress.cumulativeBytesLoaded /
                                                  loadingProgress.expectedTotalBytes!
                                              : null,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                if (m.isPrimary)
                                  Positioned(
                                    left: 6,
                                    top: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        _currentLanguage == Language.hindi ? 'मुख्य' : 'Main',
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (canAddMore)
                  InkWell(
                    onTap: _uploadingExtraPhoto ? null : _addSalonPhotoFromGallery,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade400),
                      ),
                      child: _uploadingExtraPhoto
                          ? const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2)))
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate_outlined, size: 32, color: Colors.grey.shade700),
                                const SizedBox(height: 4),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Text(
                                    _localizations.addPhoto,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 6. SETTINGS
  Widget _buildSettingsSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildSettingsItem(Icons.language, _localizations.languageLabel, () {
            _showLanguageDialog();
          }),
          _buildSettingsItem(Icons.notifications_outlined, _localizations.notifications, () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => NotificationsScreen(
                  selectedLanguage: _currentLanguage,
                ),
              ),
            );
          }),
          _buildSettingsItem(Icons.help_outline, _localizations.helpSupport, () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => HelpSupportScreen(
                  selectedLanguage: _currentLanguage,
                ),
              ),
            );
          }),
          _buildSettingsItem(Icons.info_outline, _localizations.about, () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => AboutJobTreeScreen(
                  selectedLanguage: _currentLanguage,
                ),
              ),
            );
          }),
          _buildSettingsItem(Icons.notifications_active, _currentLanguage == Language.hindi ? 'टेस्ट पुश भेजें' : 'Send test push', () async {
            final res = await _apiService.sendTestPush();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(res.success ? (_currentLanguage == Language.hindi ? 'टेस्ट नोटिफिकेशन भेजा गया' : 'Test notification sent') : (res.message ?? 'Failed')),
                backgroundColor: res.success ? Colors.green : Colors.orange,
              ),
            );
          }),
          Divider(height: 1, color: Colors.grey.shade200),
          _buildSettingsItem(
            Icons.logout,
            _isLoggingOut ? (_currentLanguage == Language.hindi ? 'लॉग आउट हो रहा है...' : 'Logging out...') : _localizations.logout,
            _isLoggingOut ? () {} : _handleLogout,
            isDestructive: true,
          ),
        ],
      ),
    );
  }
  
  Widget _buildSettingsItem(IconData icon, String label, VoidCallback onTap, {bool isDestructive = false}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: AppResponsive.screenPaddingHV(context, vertical: 16),
        child: Row(
          children: [
            Icon(
              icon,
              color: isDestructive ? Colors.red : const Color(0xFF3D3D7B),
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isDestructive ? Colors.red : const Color(0xFF121A2C),
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }
}

// ============== LANGUAGE SELECTION BOTTOM SHEET ==============
class LanguageSelectionBottomSheet extends StatefulWidget {
  final Language currentLanguage;
  final ValueChanged<Language> onLanguageSelected;
  
  const LanguageSelectionBottomSheet({
    super.key,
    required this.currentLanguage,
    required this.onLanguageSelected,
  });

  @override
  State<LanguageSelectionBottomSheet> createState() => _LanguageSelectionBottomSheetState();
}

class _LanguageSelectionBottomSheetState extends State<LanguageSelectionBottomSheet> {
  bool _isProcessing = false;
  
  Future<void> _selectLanguage(Language language) async {
    if (_isProcessing || language == widget.currentLanguage) {
      Navigator.of(context).pop();
      return;
    }
    
    setState(() {
      _isProcessing = true;
    });
    
    try {
      // Save to local storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_language', language == Language.hindi ? 'hi' : 'en');
      
      // Play voice confirmation (non-blocking)
      _playVoiceConfirmation(language);
      
      // Update language immediately
      widget.onLanguageSelected(language);
      
      // Close bottom sheet
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      // Silently handle errors - don't block user
      print('Error saving language: $e');
      if (mounted) {
        widget.onLanguageSelected(language);
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }
  
  void _playVoiceConfirmation(Language language) {
    // Use Flutter's TTS or audio player for voice confirmation
    // For now, we'll use a simple approach with system sounds
    // In production, you can use packages like flutter_tts or audioplayers
    
    // Hindi: "आपने हिंदी भाषा चुनी है"
    // English: "You have selected English"
    
    // Note: For actual voice playback, you would need to:
    // 1. Add flutter_tts package: flutter pub add flutter_tts
    // 2. Or use pre-recorded audio files with audioplayers
    // 3. For now, we'll skip audio to keep it simple and non-blocking
    
    // Future enhancement: Add TTS here
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations(widget.currentLanguage);
    final isHindi = widget.currentLanguage == Language.hindi;
    
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.40,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header
          Padding(
            padding: AppResponsive.screenPaddingHV(context, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isHindi ? 'भाषा चुनें' : 'Choose your language',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF121A2C),
                    letterSpacing: 0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  isHindi ? 'इसे बाद में बदल सकते हैं' : 'You can change this anytime',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Language options
          Flexible(
            child: Padding(
              padding: AppResponsive.formScreenPadding(context),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Hindi option (PRIMARY, shown first)
                  _buildLanguageButton(
                    context,
                    Language.hindi,
                    'हिंदी',
                    widget.currentLanguage == Language.hindi,
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // English option
                  _buildLanguageButton(
                    context,
                    Language.english,
                    'English',
                    widget.currentLanguage == Language.english,
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
        ],
      ),
    );
  }
  
  Widget _buildLanguageButton(
    BuildContext context,
    Language language,
    String displayName,
    bool isSelected,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isProcessing ? null : () => _selectLanguage(language),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          height: 60,
          padding: AppResponsive.formScreenPadding(context),
          decoration: BoxDecoration(
            color: isSelected 
                ? const Color(0xFF3D3D7B).withOpacity(0.08)
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected 
                  ? const Color(0xFF3D3D7B)
                  : Colors.grey.shade200,
              width: isSelected ? 2 : 1.5,
            ),
          ),
          child: Center(
            child: Text(
              displayName,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isSelected 
                    ? const Color(0xFF3D3D7B)
                    : const Color(0xFF121A2C),
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Helper function to show language bottom sheet
Future<void> showLanguageBottomSheet(
  BuildContext context,
  Language currentLanguage,
  ValueChanged<Language> onLanguageSelected,
) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.5),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(24),
        topRight: Radius.circular(24),
      ),
    ),
    builder: (context) => LanguageSelectionBottomSheet(
      currentLanguage: currentLanguage,
      onLanguageSelected: onLanguageSelected,
    ),
  );
}

// ============== NOTIFICATION LIST SCREEN (Seeker notification center) ==============
class NotificationListScreen extends StatefulWidget {
  final Language selectedLanguage;

  const NotificationListScreen({
    super.key,
    required this.selectedLanguage,
  });

  @override
  State<NotificationListScreen> createState() => _NotificationListScreenState();
}

class _NotificationListScreenState extends State<NotificationListScreen> {
  final ApiService _apiService = ApiService();
  late AppLocalizations _localizations;
  List<AppNotification> _notifications = [];
  bool _isLoading = true;
  bool _loadingMore = false;
  static const int _pageSize = 20;
  int _offset = 0;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _localizations = AppLocalizations(widget.selectedLanguage);
    _loadNotifications();
  }

  Future<void> _loadNotifications({bool append = false}) async {
    if (append) {
      if (_loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _isLoading = true;
        _offset = 0;
        _notifications = [];
        _hasMore = true;
      });
    }

    try {
      final res = await _apiService.getNotifications(
        limit: _pageSize,
        offset: append ? _notifications.length : 0,
      );
      if (!mounted) return;
      if (res.success && res.data != null) {
        final list = res.data!;
        setState(() {
          if (append) {
            _notifications.addAll(list);
          } else {
            _notifications = list;
          }
          _offset = _notifications.length;
          _hasMore = list.length >= _pageSize;
          _isLoading = false;
          _loadingMore = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _markAsRead(AppNotification notification) async {
    if (notification.isRead) return;
    await _apiService.markNotificationAsRead(notification.id);
    if (!mounted) return;
    setState(() {
      _notifications = _notifications.map((n) {
        if (n.id == notification.id) {
          return AppNotification(
            id: n.id,
            salonId: n.salonId,
            type: n.type,
            title: n.title,
            message: n.message,
            deepLink: n.deepLink,
            isRead: true,
            createdAt: n.createdAt,
          );
        }
        return n;
      }).toList();
    });
  }

  String _timeAgo(DateTime time) {
    final now = DateTime.now();
    final d = now.difference(time);
    if (d.inDays > 7) return '${time.day}/${time.month}/${time.year}';
    if (d.inDays > 0) return '${d.inDays} ${d.inDays == 1 ? 'day' : 'days'} ago';
    if (d.inHours > 0) return '${d.inHours} ${d.inHours == 1 ? 'hour' : 'hours'} ago';
    if (d.inMinutes > 0) return '${d.inMinutes} ${d.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    return 'Just now';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF121A2C)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _localizations.notificationsTitle,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF121A2C),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: () => _loadNotifications(),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: _notifications.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _notifications.length) {
                        if (!_loadingMore) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted && _hasMore && !_loadingMore) {
                              _loadNotifications(append: true);
                            }
                          });
                        }
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: _loadingMore
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        );
                      }
                      return _buildNotificationItem(_notifications[index]);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              _localizations.noNotificationsYet,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF121A2C),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _localizations.noNotificationsSubtext,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationItem(AppNotification notification) {
    return InkWell(
      onTap: () => _markAsRead(notification),
      child: Container(
        padding: AppResponsive.screenPaddingHV(context, vertical: 16),
        decoration: BoxDecoration(
          color: notification.isRead ? Colors.white : const Color(0xFF3D3D7B).withOpacity(0.06),
          border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 1)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: notification.isRead ? FontWeight.w500 : FontWeight.w600,
                      color: const Color(0xFF121A2C),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.message,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _timeAgo(notification.createdAt),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            if (!notification.isRead)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(left: 8, top: 6),
                decoration: const BoxDecoration(
                  color: Color(0xFF3D3D7B),
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============== NOTIFICATIONS SCREEN ==============
class NotificationsScreen extends StatefulWidget {
  final Language selectedLanguage;
  
  const NotificationsScreen({
    super.key,
    required this.selectedLanguage,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late AppLocalizations _localizations;
  final ApiService _apiService = ApiService();
  
  // Notification preferences
  bool _hiringUpdates = true; // Always ON, cannot be disabled
  bool _jobTips = true;
  bool _profileImprovements = true;
  bool _accountAlerts = true;
  bool _offersUpdates = false; // OFF by default
  
  // Notifications list
  List<AppNotification> _notifications = [];
  int _unreadCount = 0;
  
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _localizations = AppLocalizations(widget.selectedLanguage);
    _loadNotificationPreferences();
  }
  
  Future<void> _loadNotificationPreferences() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Load preferences from backend
      final prefsResponse = await _apiService.getNotificationPreferences();
      if (prefsResponse.success && prefsResponse.data != null) {
        setState(() {
          _jobTips = prefsResponse.data!.jobTips;
          _profileImprovements = prefsResponse.data!.profileImprovements;
          _accountAlerts = prefsResponse.data!.accountAlerts;
          _offersUpdates = prefsResponse.data!.promotions;
        });
      }
      
      // Load notifications
      final notificationsResponse = await _apiService.getNotifications();
      if (notificationsResponse.success && notificationsResponse.data != null) {
        setState(() {
          _notifications = notificationsResponse.data!;
        });
      }
      
      // Load unread count
      final unreadResponse = await _apiService.getUnreadNotificationCount();
      if (unreadResponse.success && unreadResponse.data != null) {
        setState(() {
          _unreadCount = unreadResponse.data!;
        });
      }
      
    } catch (e) {
      print('Error loading notification preferences: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  Future<void> _updatePreference(String key, bool value) async {
    try {
      // Update local state immediately
      setState(() {
        switch (key) {
          case 'hiringUpdates':
            // Cannot be disabled
            break;
          case 'jobTips':
            _jobTips = value;
            break;
          case 'profileImprovements':
            _profileImprovements = value;
            break;
          case 'accountAlerts':
            _accountAlerts = value;
            break;
          case 'offersUpdates':
            _offersUpdates = value;
            break;
        }
      });
      
      // Save to backend API
      await _apiService.updateNotificationPreferences(
        jobTips: key == 'jobTips' ? value : null,
        profileImprovements: key == 'profileImprovements' ? value : null,
        accountAlerts: key == 'accountAlerts' ? value : null,
        promotions: key == 'offersUpdates' ? value : null,
      );
    } catch (e) {
      print('Error updating notification preference: $e');
      // Silently fail - don't block user
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF121A2C)),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF121A2C)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _localizations.notificationsTitle,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF121A2C),
              ),
            ),
            Text(
              _localizations.notificationsSubtext,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        titleSpacing: 0,
      ),
      body: _buildNotificationContent(),
    );
  }
  
  Widget _buildNotificationContent() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 8),
          
          // Show notifications if any exist
          if (_notifications.isNotEmpty) ...[
            ..._notifications.map((notification) => _buildNotificationItem(notification)),
            const SizedBox(height: 20),
            Divider(height: 1, color: Colors.grey.shade200),
            const SizedBox(height: 20),
          ],
          
          // Preferences section header
          Padding(
            padding: AppResponsive.screenPaddingHV(context, vertical: 8),
            child: Row(
              children: [
                Text(
                  _localizations.settings,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF121A2C),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 8),
          
          // A. Hiring Updates (MOST IMPORTANT - Cannot be disabled)
          _buildNotificationSection(
            title: _localizations.hiringUpdates,
            description: _localizations.hiringUpdatesDesc,
            value: _hiringUpdates,
            onChanged: (value) {
              // Show helper text if trying to disable
              if (!value) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_localizations.requiredForHiring),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: const Color(0xFF3D3D7B),
                  ),
                );
              }
              // Do not allow disabling
            },
            enabled: false, // Toggle is disabled
          ),
          
          Divider(height: 1, color: Colors.grey.shade200),
          
          // B. Job Tips
          _buildNotificationSection(
            title: _localizations.jobTips,
            description: _localizations.jobTipsDesc,
            value: _jobTips,
            onChanged: (value) => _updatePreference('jobTips', value),
          ),
          
          Divider(height: 1, color: Colors.grey.shade200),
          
          // C. Profile Improvements
          _buildNotificationSection(
            title: _localizations.profileImprovements,
            description: _localizations.profileImprovementsDesc,
            value: _profileImprovements,
            onChanged: (value) => _updatePreference('profileImprovements', value),
          ),
          
          Divider(height: 1, color: Colors.grey.shade200),
          
          // D. Account Alerts
          _buildNotificationSection(
            title: _localizations.accountAlerts,
            description: _localizations.accountAlertsDesc,
            value: _accountAlerts,
            onChanged: (value) => _updatePreference('accountAlerts', value),
          ),
          
          Divider(height: 1, color: Colors.grey.shade200),
          
          // E. Offers & Updates (OFF by default, clearly optional)
          _buildNotificationSection(
            title: _localizations.offersUpdates,
            description: _localizations.offersUpdatesDesc,
            value: _offersUpdates,
            onChanged: (value) => _updatePreference('offersUpdates', value),
            isOptional: true,
          ),
          
          const SizedBox(height: 20),
        ],
      ),
    );
  }
  
  Widget _buildNotificationItem(AppNotification notification) {
    return InkWell(
      onTap: () async {
        // Mark as read if unread
        if (!notification.isRead) {
          await _apiService.markNotificationAsRead(notification.id);
          setState(() {
            _notifications = _notifications.map((n) {
              if (n.id == notification.id) {
                return AppNotification(
                  id: n.id,
                  salonId: n.salonId,
                  type: n.type,
                  title: n.title,
                  message: n.message,
                  deepLink: n.deepLink,
                  isRead: true,
                  createdAt: n.createdAt,
                );
              }
              return n;
            }).toList();
            _unreadCount = _unreadCount > 0 ? _unreadCount - 1 : 0;
          });
        }
        
        // Navigate to deep link if available
        if (notification.deepLink != null) {
          // TODO: Handle deep link navigation
          print('Navigate to: ${notification.deepLink}');
        }
      },
      child: Container(
        padding: AppResponsive.screenPaddingHV(context, vertical: 16),
        decoration: BoxDecoration(
          color: notification.isRead ? Colors.white : const Color(0xFF3D3D7B).withOpacity(0.05),
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: notification.isRead ? FontWeight.w500 : FontWeight.w600,
                      color: const Color(0xFF121A2C),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.message,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatNotificationTime(notification.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            if (!notification.isRead)
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF3D3D7B),
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  String _formatNotificationTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    
    if (difference.inDays > 7) {
      return '${time.day}/${time.month}/${time.year}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    } else {
      return 'Just now';
    }
  }
  
  Widget _buildNotificationSection({
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
    bool isOptional = false,
  }) {
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      child: Padding(
        padding: AppResponsive.screenPaddingAll(context),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF121A2C),
                        ),
                      ),
                      if (isOptional) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _localizations.optional,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Switch(
              value: value,
              onChanged: enabled ? onChanged : null,
              activeColor: const Color(0xFF3D3D7B),
            ),
          ],
        ),
      ),
    );
  }
}

// ============== HELP & SUPPORT SCREEN ==============
class HelpSupportScreen extends StatefulWidget {
  final Language selectedLanguage;
  
  const HelpSupportScreen({
    super.key,
    required this.selectedLanguage,
  });

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  late AppLocalizations _localizations;
  final ApiService _apiService = ApiService();
  
  String? _supportPhone;
  String? _whatsappNumber;
  String? _whatsappMessage;
  bool _isLoadingConfig = true;
  
  String? _selectedIssueType;
  final TextEditingController _descriptionController = TextEditingController();
  bool _isSubmitting = false;
  
  @override
  void initState() {
    super.initState();
    _localizations = AppLocalizations(widget.selectedLanguage);
    _loadSupportConfig();
  }
  
  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }
  
  Future<void> _loadSupportConfig() async {
    try {
      final response = await _apiService.getSupportConfig();
      if (response.success && response.data != null) {
        setState(() {
          _supportPhone = response.data!['supportPhone'];
          _whatsappNumber = response.data!['whatsappNumber'];
          _whatsappMessage = response.data!['whatsappMessage'] ?? 'Hi, I need help with JobTree';
        });
      }
    } catch (e) {
      setState(() {
        _supportPhone = '+91-1800-XXX-XXXX';
        _whatsappNumber = '+91-9876543210';
        _whatsappMessage = 'Hi, I need help with JobTree';
      });
    } finally {
      setState(() {
        _isLoadingConfig = false;
      });
    }
  }
  
  Future<void> _callSupport() async {
    if (_supportPhone == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Calling: $_supportPhone'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
  
  Future<void> _openWhatsApp() async {
    if (_whatsappNumber == null || _whatsappMessage == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Opening WhatsApp...'),
        duration: Duration(seconds: 2),
      ),
    );
  }
  
  Future<void> _submitTicket() async {
    if (_selectedIssueType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_localizations.issueType),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    setState(() {
      _isSubmitting = true;
    });
    
    try {
      final response = await _apiService.createSupportTicket(
        issueType: _selectedIssueType!,
        description: _descriptionController.text.trim().isEmpty 
            ? null 
            : _descriptionController.text.trim(),
        appVersion: '1.0.0',
        deviceInfo: 'iOS/Android',
      );
      
      if (response.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_localizations.ticketSubmitted),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        setState(() {
          _selectedIssueType = null;
          _descriptionController.clear();
        });
        Navigator.of(context).pop();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }
  
  void _showReportProblemDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_localizations.reportProblem),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _localizations.issueType,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF121A2C),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedIssueType,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'JOB_POSTING',
                    child: Text(_localizations.issueTypeJobPosting),
                  ),
                  DropdownMenuItem(
                    value: 'CANDIDATE',
                    child: Text(_localizations.issueTypeCandidate),
                  ),
                  DropdownMenuItem(
                    value: 'APP_ISSUE',
                    child: Text(_localizations.issueTypeAppIssue),
                  ),
                  DropdownMenuItem(
                    value: 'PAYMENT',
                    child: Text(_localizations.issueTypePayment),
                  ),
                  DropdownMenuItem(
                    value: 'OTHER',
                    child: Text(_localizations.issueTypeOther),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedIssueType = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              Text(
                _localizations.description,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF121A2C),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _descriptionController,
                maxLines: 4,
                maxLength: 300,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  hintText: _localizations.description,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_localizations.cancel),
          ),
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submitTicket,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3D3D7B),
              foregroundColor: Colors.white,
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    _localizations.submit,
                    style: const TextStyle(color: Colors.white),
                  ),
          ),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF121A2C)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _localizations.helpSupportTitle,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF121A2C),
              ),
            ),
            Text(
              _localizations.helpSupportSubtext,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        titleSpacing: 0,
      ),
      body: _isLoadingConfig
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: AppResponsive.scrollScreenPadding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildQuickHelpButton(
                          icon: Icons.phone,
                          label: _localizations.callSupport,
                          onTap: _callSupport,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildQuickHelpButton(
                          icon: Icons.chat,
                          label: _localizations.chatWhatsApp,
                          onTap: _openWhatsApp,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Text(
                    _localizations.frequentlyAskedQuestions,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF121A2C),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildFAQItem(question: _localizations.faqQ1, answer: _localizations.faqA1),
                  _buildFAQItem(question: _localizations.faqQ2, answer: _localizations.faqA2),
                  _buildFAQItem(question: _localizations.faqQ3, answer: _localizations.faqA3),
                  _buildFAQItem(question: _localizations.faqQ4, answer: _localizations.faqA4),
                  _buildFAQItem(question: _localizations.faqQ5, answer: _localizations.faqA5),
                  const SizedBox(height: 32),
                  InkWell(
                    onTap: _showReportProblemDialog,
                    child: Container(
                      width: double.infinity,
                      padding: AppResponsive.screenPaddingAll(context),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.bug_report_outlined, color: Colors.grey.shade700, size: 24),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _localizations.reportProblem,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF121A2C),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _localizations.reportProblemDesc,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: Colors.grey.shade400),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextButton(
                        onPressed: () {},
                        child: Text(
                          _localizations.termsConditions,
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                        ),
                      ),
                      TextButton(
                        onPressed: () {},
                        child: Text(
                          _localizations.privacyPolicy,
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text(
                          '${_localizations.appVersion}: 1.0.0',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
  
  Widget _buildQuickHelpButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF3D3D7B),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Icon(icon, color: Colors.white, size: 32),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildFAQItem({
    required String question,
    required String answer,
  }) {
    return _FAQAccordionItem(question: question, answer: answer);
  }
}

class _FAQAccordionItem extends StatefulWidget {
  final String question;
  final String answer;
  
  const _FAQAccordionItem({required this.question, required this.answer});

  @override
  State<_FAQAccordionItem> createState() => _FAQAccordionItemState();
}

class _FAQAccordionItemState extends State<_FAQAccordionItem> {
  bool _isExpanded = false;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.question,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF121A2C),
                      ),
                    ),
                  ),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                widget.answer,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                  height: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============== ABOUT JOBTREE SCREEN ==============
class AboutJobTreeScreen extends StatelessWidget {
  final Language selectedLanguage;
  
  const AboutJobTreeScreen({
    super.key,
    required this.selectedLanguage,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations(selectedLanguage);
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF121A2C)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localizations.aboutJobTreeTitle,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF121A2C),
              ),
            ),
            Text(
              localizations.aboutJobTreeSubtext,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        titleSpacing: 0,
      ),
      body: SingleChildScrollView(
        padding: AppResponsive.scrollScreenPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // What is JobTree?
            _buildSection(
              title: localizations.whatIsJobTree,
              content: Text(
                localizations.whatIsJobTreeContent,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey.shade700,
                  height: 1.6,
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Why JobTree exists
            _buildSection(
              title: localizations.whyJobTreeExists,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBulletPoint(localizations.whyJobTreeBullet1),
                  _buildBulletPoint(localizations.whyJobTreeBullet2),
                  _buildBulletPoint(localizations.whyJobTreeBullet3),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            
            // How JobTree helps
            _buildSection(
              title: localizations.howJobTreeHelps,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBulletPoint(localizations.howJobTreeBullet1),
                  _buildBulletPoint(localizations.howJobTreeBullet2),
                  _buildBulletPoint(localizations.howJobTreeBullet3),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Trust & Safety
            _buildSection(
              title: localizations.trustSafety,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBulletPoint(localizations.trustBullet1),
                  _buildBulletPoint(localizations.trustBullet2),
                  _buildBulletPoint(localizations.trustBullet3),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Company Info
            Container(
              padding: AppResponsive.cardPaddingInsets(context),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    localizations.companyDetails,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'JobTree Technologies Pvt. Ltd.',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    localizations.madeInIndia,
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () {
                      // TODO: Open email client
                    },
                    child: Text(
                      'support@jobtree.in',
                      style: TextStyle(
                        fontSize: 15,
                        color: const Color(0xFF3D3D7B),
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            
            // App Version
            Center(
              child: Text(
                'Version 1.0.0',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
            ),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSection({
    required String title,
    required Widget content,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF121A2C),
          ),
        ),
        const SizedBox(height: 12),
        content,
      ],
    );
  }
  
  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• ',
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade700,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
