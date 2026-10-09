import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'login_screen.dart';
import 'register_screen_tabs.dart';
import 'address_gate_screen.dart'; // ✅ إضافة شاشة اختيار العنوان
import '../providers/app_state_provider.dart';
import '../constants/app_colors.dart'; // إضافة استيراد ملف الألوان

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final PageController _controller = PageController();

  final List<Map<String, String>> slides = [
    {"image": "assets/images/slide1.png", "text": "استمتع بوجبتك بسرعة"},
    {"image": "assets/images/slide2.png", "text": "خيارات متعددة من المطاعم"},
    {"image": "assets/images/slide3.png", "text": "سهولة الدفع والتوصيل"},
  ];

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration.zero, () {
      Future.doWhile(() async {
        await Future.delayed(const Duration(seconds: 3));
        if (!mounted) return false;
        int nextPage = _controller.page!.toInt() + 1;
        if (nextPage >= slides.length) nextPage = 0;
        _controller.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
        return true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth  = MediaQuery.of(context).size.width;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppColors.primary, // البنفسجي اللامع
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            Column(
              children: [
              const SizedBox(height: 60),
              const Text(
                "زاد",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2,
                  shadows: [
                    Shadow(
                      color: Color(0x33FFD600), // تأثير أصفر خفيف
                      offset: Offset(0, 0),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(25),
                      topRight: Radius.circular(25),
                    ),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 30),
                      SizedBox(
                        height: screenHeight * 0.45, // تقريباً 45٪ من الشاشة
                        child: PageView.builder(
                          controller: _controller,
                          itemCount: slides.length,
                          itemBuilder: (context, index) {
                            final slide = slides[index];
                            return Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Expanded(
                                  flex: 8,
                                  child: Container(
                                    width: screenWidth * 0.90,
                                    margin: const EdgeInsets.symmetric(horizontal: 16),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black12,
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                      color: Colors.white,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(20),
                                      child: Image.asset(
                                        slide["image"]!,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Expanded(
                                  flex: 2,
                                  child:                                  Text(
                                    slide["text"]!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 22,
                                      color: AppColors.primary, // البنفسجي اللامع
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      SmoothPageIndicator(
                        controller: _controller,
                        count: slides.length,
                        effect: WormEffect(
                          activeDotColor: AppColors.secondary, // الأصفر الكهربائي
                          dotColor: Colors.grey.withOpacity(0.4),
                          dotHeight: 12,
                          dotWidth: 12,
                          spacing: 8,
                        ),
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () async {
                                  if (!mounted) return;
                                  final navigator = Navigator.of(context);
                                  await navigator.push(
                                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                                  );
                                  // دع شاشة تسجيل الدخول تتولى التنقل بالكامل - لا حاجة لفعل أي شيء هنا
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary, // البنفسجي اللامع
                                  foregroundColor: AppColors.secondary,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  elevation: 2,
                                  shadowColor: AppColors.primary.withOpacity(0.3),
                                ),
                                child: const Text(
                                  'تسجيل الدخول',
                                  style: TextStyle(color: Colors.white, fontSize: 16),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () async {
                                  if (!mounted) return;
                                  final navigator = Navigator.of(context);
                                  await navigator.push(
                                    MaterialPageRoute(builder: (_) => const RegisterScreenTabs()),
                                  );
                                  // دع شاشة التسجيل تتولى التنقل بالكامل - لا حاجة لفعل أي شيء هنا
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primary, // البنفسجي اللامع
                                  side: BorderSide(color: AppColors.primary, width: 1.5),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                ),
                                child: const Text(
                                  'إنشاء حساب جديد',
                                  style: TextStyle(fontSize: 16),
                                ),
                              ),
                            ),
                            const SizedBox(height: 30),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            ),
            // زر التخطي المحسّن في أعلى يمين الشاشة
            Positioned(
              top: 40,
              right: 20,
              child: GestureDetector(
                onTap: () => _showSkipConfirmation(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withOpacity(0.15), // أصفر شفاف
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(color: AppColors.secondary.withOpacity(0.4), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    textDirection: TextDirection.rtl, // اتجاه عربي
                    children: [
                      const Icon(
                        Icons.arrow_back_ios,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'تصفح ',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.secondary, // الأصفر الكهربائي
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'كضيف',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
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
      ),
    );
  }

  // عرض تأكيد التخطي مع توضيح الخيارات
  void _showSkipConfirmation(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(25),
              topRight: Radius.circular(25),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // مؤشر السحب
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                
                // أيقونة التصفح
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1), // بنفسجي شفاف
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Icon(
                    Icons.travel_explore_rounded,
                    size: 40,
                    color: AppColors.primary, // بنفسجي لامع
                  ),
                ),
                const SizedBox(height: 20),
                
                // العنوان
                const Text(
                  'تصفح كضيف؟',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                
                // الوصف
                Text(
                  'يمكنك تصفح التطبيق والطلب دون إنشاء حساب، لكن ستفوتك بعض الميزات الرائعة!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                
                // الميزات المفقودة
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withOpacity(0.1), // أصفر شفاف
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.secondary.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: AppColors.primary, // بنفسجي لامع
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'بدون حساب لن تتمكن من:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary, // بنفسجي لامع
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ..._buildMissingFeatures(),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                
                // الأزرار
                Row(
                  children: [
                    // زر التصفح كضيف
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          await _proceedAsGuest();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey[600],
                          side: BorderSide(color: Colors.grey[400]!),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'متابعة كضيف',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // زر تسجيل الدخول
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const LoginScreen()),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary, // البنفسجي اللامع
                          foregroundColor: AppColors.secondary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                          shadowColor: AppColors.primary.withOpacity(0.3),
                        ),
                        child: const Text(
                          'تسجيل الدخول',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
              ],
            ),
          ),
        );
      },
    );
  }

  // قائمة الميزات المفقودة
  List<Widget> _buildMissingFeatures() {
    final features = [
      'حفظ المطاعم المفضلة',
      'تتبع تاريخ الطلبات',
      'حفظ العناوين',
      'العروض الحصرية',
    ];

    return features.map((feature) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            Icons.close,
            color: AppColors.primary, // بنفسجي لامع
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              feature,
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    )).toList();
  }

  // المتابعة كضيف
  Future<void> _proceedAsGuest() async {
    try {
      // استخدام AppStateProvider لتسجيل الدخول كضيف
      final appState = Provider.of<AppStateProvider>(context, listen: false);
      await appState.loginAsGuest();
      
      if (!mounted) return;
      
      // ✅ التحديث: الانتقال إلى AddressGateScreen بدلاً من HomeScreen مباشرة
      // يجب على الضيف اختيار عنوان توصيل قبل عرض المطاعم
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const AddressGateScreen(isGuest: true),
        ),
      );
    } catch (e) {
      // في حالة الخطأ، انتقل لشاشة اختيار العنوان
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const AddressGateScreen(isGuest: true),
          ),
        );
      }
    }
  }
}
