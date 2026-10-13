import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _reasonController = TextEditingController();
  
  bool _isLoading = false;
  bool _passwordVisible = false;
  bool _confirmationChecked = false;
  String _selectedReason = '';

  final List<String> _deleteReasons = [
    'لا أستخدم التطبيق بانتظام',
    'وجدت تطبيق آخر أفضل',
    'مشاكل في التوصيل',
    'أسعار مرتفعة',
    'مشاكل تقنية في التطبيق',
    'أسباب خصوصية',
    'سبب آخر',
  ];

  @override
  void dispose() {
    _passwordController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _deleteAccount() async {
    // Never claim deletion or clear the session without a server receipt.
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('خدمة حذف الحساب قيد التجهيز. لم يتم حذف حسابك أو تغيير رصيدك.'),
    ));
  }

  Future<bool> _showFinalConfirmationDialog() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.warning, color: AppColors.error),
            ),
            const SizedBox(width: 12),
            const Text(
              'تأكيد نهائي',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: const Text(
          'هل أنت متأكد من رغبتك في حذف حسابك نهائياً؟\n\nسيتم حذف جميع بياناتك وطلباتك السابقة ولا يمكن استرجاعها.',
          style: TextStyle(height: 1.5, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'إلغاء',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.secondary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'حذف الحساب',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.red,
        foregroundColor: AppColors.secondary,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWarningCard(),
              const SizedBox(height: 20),
              _buildReasonSection(),
              const SizedBox(height: 20),
              _buildPasswordSection(),
              const SizedBox(height: 20),
              _buildConfirmationSection(),
              const SizedBox(height: 30),
              _buildDeleteButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWarningCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Column(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 50,
            color: Colors.red[600],
          ),
          const SizedBox(height: 15),
          Text(
            'تحذير: حذف نهائي',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.red[800],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'عند حذف حسابك سيتم فقدان جميع البيانات التالية نهائياً:',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.red[700],
              height: 1.5,
            ),
          ),
          const SizedBox(height: 15),
          _buildWarningItem('جميع طلباتك السابقة'),
          _buildWarningItem('المطاعم والأطباق المفضلة'),
          _buildWarningItem('عناوين التوصيل المحفوظة'),
          _buildWarningItem('طرق الدفع المحفوظة'),
          _buildWarningItem('نقاط الولاء والعروض'),
        ],
      ),
    );
  }

  Widget _buildWarningItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(Icons.close, color: Colors.red[600], size: 16),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(color: Colors.red[700]),
          ),
        ],
      ),
    );
  }

  Widget _buildReasonSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'سبب حذف الحساب (اختياري)',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 15),
          Text(
            'ساعدنا في تحسين خدماتنا بإخبارنا عن سبب مغادرتك:',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 15),
          ..._deleteReasons.map((reason) => _buildReasonTile(reason)),
          if (_selectedReason == 'سبب آخر') ...[
            const SizedBox(height: 15),
            TextFormField(
              controller: _reasonController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'يرجى توضيح السبب...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReasonTile(String reason) {
    return InkWell(
      onTap: () => setState(() => _selectedReason = reason),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Radio<String>(
              value: reason,
              groupValue: _selectedReason,
              onChanged: (value) => setState(() => _selectedReason = value!),
              activeColor: AppColors.primary,
            ),
            Expanded(
              child: Text(
                reason,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'تأكيد كلمة المرور',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 15),
          TextFormField(
            controller: _passwordController,
            obscureText: !_passwordVisible,
            decoration: InputDecoration(
              hintText: 'أدخل كلمة المرور للتأكيد',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_passwordVisible ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
            validator: (value) {
              if (value?.isEmpty ?? true) {
                return 'يرجى إدخال كلمة المرور للتأكيد';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmationSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: CheckboxListTile(
        value: _confirmationChecked,
        onChanged: (value) => setState(() => _confirmationChecked = value!),
        activeColor: Colors.red,
        title: const Text(
          'أفهم أن حذف الحساب نهائي ولا يمكن التراجع عنه',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: const Text(
          'بتحديد هذا المربع، أؤكد موافقتي على حذف حسابي وجميع البيانات المرتبطة به نهائياً',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey,
          ),
        ),
        controlAffinity: ListTileControlAffinity.leading,
      ),
    );
  }

  Widget _buildDeleteButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _deleteAccount,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          foregroundColor: AppColors.secondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
        ),
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : const Text(
                'حذف الحساب نهائياً',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }
}
