import 'package:flutter/material.dart';

class HelpFaqScreen extends StatefulWidget {
  const HelpFaqScreen({super.key});

  @override
  State<HelpFaqScreen> createState() => _HelpFaqScreenState();
}

class _HelpFaqScreenState extends State<HelpFaqScreen> {
  final List<_FaqItem> _faqs = [
    _FaqItem(
      question: 'ট্যুর কি?',
      answer:
          'ট্যুর হল একটি গ্রুপিং যেখানে আপনি এবং আপনার বন্ধুরা খরচ ট্র্যাক করতে পারেন। এটা একটি ভ্রমণ, মেস, পার্টি বা যেকোনো গ্রুপ কার্যকলাপ হতে পারে।',
    ),
    _FaqItem(
      question: 'ট্যুর তৈরি করতে পারি কিভাবে?',
      answer:
          'হোম স্ক্রীনে "+" বাটন দিয়ে ক্লিক করুন। তারপর ট্যুরের নাম, তারিখ এবং সদস্যদের যোগ করুন। সেভ করলেই ট্যুর তৈরি হয়ে যাবে।',
    ),
    _FaqItem(
      question: 'অন্যদের ট্যুরে কিভাবে যোগ দিতে পারি?',
      answer:
          'হোম স্ক্রীনে "6-digit কোড দিয়ে যোগ দিন" অপশনে ক্লিক করুন। তারপর আপনার বন্ধু যে 6-digit কোড শেয়ার করেছে তা দিয়ে যোগ দিন।',
    ),
    _FaqItem(
      question: 'খরচ কিভাবে যোগ করব?',
      answer:
          'ট্যুরের ডিটেইলস পেজে খরচ আইকনে ক্লিক করুন। তারপর খরচের পরিমাণ, কে খরচ করেছে এবং কাদের মধ্যে ভাগ হবে তা নির্বাচন করুন।',
    ),
    _FaqItem(
      question: 'সেটেলমেন্ট মানে কি?',
      answer:
          'সেটেলমেন্ট হল চূড়ান্ত হিসাব যেখানে দেখা যায় কে কাকে কত টাকা দেবে। এটি সব খরচের উপর ভিত্তি করে অটোম্যাটিক ক্যালকুলেট হয়।',
    ),
    _FaqItem(
      question: 'আমি অফলাইনে কাজ করতে পারব?',
      answer:
          'হ্যাঁ! অ্যাপটি অফলাইনে ডেটা সেভ করে। যখন ইন্টারনেট সংযোগ হবে, তখন সিঙ্ক হবে। সিঙ্ক বাটন দিয়ে ম্যানুয়ালি সিঙ্ক করতে পারেন।',
    ),
    _FaqItem(
      question: 'আমার ডেটা নিরাপদ?',
      answer:
          'হ্যাঁ, আপনার সব ডেটা এনক্রিপ্টেড সার্ভারে সংরক্ষিত থাকে। শুধুমাত্র অনুমোদিত ব্যবহারকারীরা অ্যাক্সেস করতে পারেন।',
    ),
    _FaqItem(
      question: 'কি করব ভুল খরচ যোগ করে ফেলেছি?',
      answer:
          'খরচ ডিটেইলস এ গিয়ে ডিলিট বাটন দিয়ে সেটা মুছে দিতে পারেন। অথবা এডিট করে সঠিক করে নিতে পারেন।',
    ),
    _FaqItem(
      question: 'কত জন সদস্য যোগ করতে পারি?',
      answer:
          'অসীম সংখ্যক সদস্য যোগ করতে পারেন। তবে একটি ট্যুরে সাধারণত 5-50 জন থাকে যা ম্যানেজ করা সহজ।',
    ),
    _FaqItem(
      question: 'আমি ট্যুর থেকে বের হতে পারব?',
      answer:
          'ট্যুরের সেটিংস থেকে "ট্যুর থেকে বের হন" অপশনে ক্লিক করলে আপনি বের হয়ে যাবেন। তবে সেটেলমেন্টের আগে বের হওয়া ভাল।',
    ),
    _FaqItem(
      question: 'সিঙ্ক কি এবং কিভাবে করব?',
      answer:
          'সিঙ্ক মানে আপনার লোকাল ডেটা সার্ভারের সাথে আপডেট করা। হোম স্ক্রীনে সিঙ্ক বাটন দিয়ে ম্যানুয়ালি সিঙ্ক করতে পারেন। সাধারণত অটোম্যাটিক সিঙ্ক হয়।',
    ),
    _FaqItem(
      question: 'অ্যাপ ক্রাশ হলে কি হবে?',
      answer:
          'চিন্তা করবেন না, সব ডেটা সার্ভারে সেভ থাকে। অ্যাপ রিস্টার্ট করে লগইন করলে সব ডেটা ফিরে পাবেন।',
    ),
    _FaqItem(
      question: 'কাস্টমার সাপোর্ট এ যোগাযোগ করব কিভাবে?',
      answer:
          'প্রোফাইল স্ক্রীনে "সাহায্য/ফিডব্যাক" অপশন আছে। সেখান থেকে আমাদের কাছে বার্তা পাঠাতে পারেন। আমরা দ্রুত সাহায্য করব।',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('সাহায্য এবং প্রশ্নাবলী'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Help introduction
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.blue.withValues(alpha: 0.1),
                  Colors.purple.withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '❓ সবচেয়ে সাধারণ প্রশ্নের উত্তর',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'নিচে আপনার সব প্রশ্নের উত্তর পাবেন। যদি মনে হয় অন্য কোনো তথ্য দরকার, আমাদের বলুন।',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Quick tip
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.yellow.withValues(alpha: 0.1),
              border: Border.all(color: Colors.yellow.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline, color: Colors.orange),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'টিপ: অ্যাপের যেকোনো অংশে প্রশ্ন চিহ্ন (?) আইকনে ক্লিক করলে সাহায্য পাবেন।',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // FAQs
          ..._faqs.asMap().entries.map((entry) {
            final idx = entry.key;
            final faq = entry.value;
            return _FaqCard(
              index: idx + 1,
              question: faq.question,
              answer: faq.answer,
            );
          }),

          const SizedBox(height: 24),

          // Contact support
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Icon(Icons.support_agent, size: 32, color: Colors.blue),
                const SizedBox(height: 12),
                const Text(
                  'অন্য সাহায্য দরকার?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'আমাদের সাপোর্ট টিম সবসময় আপনাকে সাহায্য করতে প্রস্তুত।',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('ফিডব্যাক পাঠানোর ফিচার শীঘ্রই আসছে')),
                    );
                  },
                  child: const Text('ফিডব্যাক পাঠান'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _FaqCard extends StatefulWidget {
  final int index;
  final String question;
  final String answer;

  const _FaqCard({
    required this.index,
    required this.question,
    required this.answer,
  });

  @override
  State<_FaqCard> createState() => _FaqCardState();
}

class _FaqCardState extends State<_FaqCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Card(
        elevation: _isExpanded ? 4 : 1,
        child: InkWell(
          onTap: () {
            setState(() => _isExpanded = !_isExpanded);
            if (_isExpanded) {
              _animationController.forward();
            } else {
              _animationController.reverse();
            }
          },
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${widget.index}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.question,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    RotationTransition(
                      turns: Tween(begin: 0.0, end: 0.5)
                          .animate(_animationController),
                      child: const Icon(Icons.expand_more),
                    ),
                  ],
                ),
              ),
              if (_isExpanded)
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Colors.grey[200]!),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.answer,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                            height: 1.6,
                          ),
                        ),
                      ],
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

class _FaqItem {
  final String question;
  final String answer;

  _FaqItem({required this.question, required this.answer});
}
