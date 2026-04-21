const { Tour, User, Expense, ExpenseSplit, TourMember, Settlement, ProgramIncome } = require('../models');

exports.getTourInsights = async (req, res) => {
  try {
    const normalizedTourId = req.params.tourId?.toString().toLowerCase() || '';
    if (!normalizedTourId) {
      return res.status(400).json({ error: "tourId is required" });
    }

    if (!process.env.OPENROUTER_API_KEY) {
      return res.status(500).json({ error: "OpenRouter API Key not configured." });
    }

    // Fetch Tour Data with Members
    const tour = await Tour.findByPk(normalizedTourId, {
      include: [{ model: User, through: { attributes: [] } }]
    });
    if (!tour) {
      return res.status(404).json({ error: "Tour/Event not found" });
    }

    const members = tour.Users || [];

    // Fetch Expenses with Payer details
    const expenses = await Expense.findAll({
      where: { tour_id: normalizedTourId },
      include: [
        { model: User, as: 'payer', attributes: ['name'] },
        ExpenseSplit
      ]
    });

    // Fetch Settlements
    const settlements = await Settlement.findAll({
      where: { tour_id: normalizedTourId },
      include: [
        { model: User, as: 'sender', attributes: ['name'] },
        { model: User, as: 'receiver', attributes: ['name'] }
      ]
    });

    // Fetch Program Income (Fund Collections)
    const incomes = await ProgramIncome.findAll({
      where: { tour_id: normalizedTourId },
      include: [{ model: User, as: 'collector', attributes: ['name'] }]
    });

    // Compile Context
    let contextStr = `Analyze the financial state of the event "${tour.name}".
Purpose: ${tour.purpose || 'General'}
Total Members: ${members.length}
Members: ${members.map(m => m.name).join(', ')}

--- FUND COLLECTIONS (INCOME) ---
${incomes.length > 0 ? incomes.map(i => `- ${i.source}: ৳${i.amount} (Collected by: ${i.collector?.name || 'Admin'})`).join('\n') : "No funds collected yet."}

--- EXPENSES ---
${expenses.length > 0 ? expenses.map(e => `- ${e.title}: ৳${e.amount} [Category: ${e.category || 'Other'}] (Paid by: ${e.payer?.name || 'Unknown'})`).join('\n') : "No expenses recorded."}

--- SETTLEMENTS (DEBT PAYMENTS) ---
${settlements.length > 0 ? settlements.map(s => `- ${s.sender?.name} paid ৳${s.amount} to ${s.receiver?.name}`).join('\n') : "No settlements recorded."}

Calculate totals and provide an optimization report.`;

    const systemPrompt = `You are a World-Class Billionaire Financial Mentor and Wealth Strategist.
আপনার লক্ষ্য হলো ব্যবহারকারীর আর্থিক চিন্তাভাবনাকে "ভোক্তা" থেকে "সম্পদ নির্মাতা" হিসেবে উন্নত করা।
এই ইভেন্টটিকে একটি সাধারণ ট্যুর হিসেবে নয়, বরং মূলধন বরাদ্দের (Capital Allocation) একটি সিরিজ হিসেবে বিশ্লেষণ করুন।

সবকিছু বাংলায় (Bangla) উত্তর দিন। একই ধরনের উত্তর বারবার দেবেন না। ডেটার ধরন এবং খরচের প্রকৃতির ওপর ভিত্তি করে আপনার উত্তরের ধরন, বিশ্লেষণ কৌশল এবং টেবিলের প্যারামিটারগুলো ডাইনামিক হতে হবে।

REPORT STRUCTURE GUIDELINES (বাংলায়):

১. ডায়নামিক টেবুলার ডেটা (Dynamic Tabular Data): 
উত্তরের ডেটাগুলো সবসময় সুন্দর মার্কডাউন টেবিল (Markdown Table) ফরম্যাটে উপস্থাপন করবেন। তবে টেবিলের কলাম বা প্যারামিটারগুলো নির্দিষ্ট করা নেই! ইভেন্টের খরচের ধরনের ওপর ভিত্তি করে সবচেয়ে পারফেক্ট টেবিল স্ট্রাকচারটি আপনি তৈরি করে নেবেন (যেমন- কখনো মাথাপিছু খরচ, কখনো ক্যাটাগরিভিত্তিক অপচয়, আবার কখনো সম্পদ বনাম দায়)।

২. গভীর মনস্তাত্ত্বিক ইনসাইট (Deep Psychological Insights):
শুধু হিসাব কষবেন না। খরচগুলোর গভীরে গিয়ে মানুষের মনস্তত্ত্ব এবং ভুল সিদ্ধান্তগুলো ধরিয়ে দিন। একজন বিলিয়নেয়ার কীভাবে এই টাকাগুলো পরিচালনা করতেন তার একটি পাওয়ারফুল "মাইন্ডসেট শিফট" শেয়ার করুন।

৩. লেগাসি এবং ভবিষ্যৎ রোডম্যাপ (Legacy & Future Roadmap):
এই ইভেন্টের আর্থিক সিদ্ধান্তগুলো তাদের ভবিষ্যতের ৫-১০ বছর পর কোথায় নিয়ে যাবে, সে সম্পর্কে একটি শক্তিশালী ভবিষ্যৎবাণী (Verdict) দিন।

নিয়ম:
১. সম্পূর্ণ উত্তর বাংলায় হতে হবে।
২. ভাষা হতে হবে গম্ভীর, স্মার্ট, সরাসরি এবং দূরদর্শী।
৩. কোনো একঘেঁয়ে বা ফিক্সড টেমপ্লেট ব্যবহার করবেন না; প্রতিটি উত্তর যেন ইউনিক এবং পারফেক্ট হয়।`;

    // Call OpenRouter with a more stable flash model
    const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${process.env.OPENROUTER_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "google/gemini-2.0-flash-lite-001", 
        max_tokens: 2500,
        messages: [
          {
            role: "system",
            content: systemPrompt
          },
          {
            role: "user",
            content: contextStr
          }
        ],
      })
    });

    const data = await response.json();
    
    if (data.choices && data.choices.length > 0) {
      return res.json({ reply: data.choices[0].message.content });
    } else {
        console.error("OpenRouter Error Details:", JSON.stringify(data, null, 2));
        const errorMessage = data.error?.message || "Failed to generate AI response";
        return res.status(500).json({ 
            error: "AI Generation Error", 
            details: errorMessage 
        });
    }

  } catch (error) {
    console.error("AI Insights Exception:", error);
    res.status(500).json({ error: "Internal server error during AI analysis." });
  }
};

