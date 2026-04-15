const { Tour, User, Expense, ExpenseSplit, TourMember, Settlement, ProgramIncome } = require('../models');

exports.getTourInsights = async (req, res) => {
  try {
    const { tourId } = req.params;

    if (!process.env.OPENROUTER_API_KEY) {
      return res.status(500).json({ error: "OpenRouter API Key not configured." });
    }

    // Fetch Tour Data with Members
    const tour = await Tour.findByPk(tourId, {
      include: [{ model: User, through: { attributes: [] } }]
    });
    if (!tour) {
      return res.status(404).json({ error: "Tour/Event not found" });
    }

    const members = tour.Users || [];

    // Fetch Expenses with Payer details
    const expenses = await Expense.findAll({
      where: { tour_id: tourId },
      include: [
        { model: User, as: 'payer', attributes: ['name'] },
        ExpenseSplit
      ]
    });

    // Fetch Settlements
    const settlements = await Settlement.findAll({
      where: { tour_id: tourId },
      include: [
        { model: User, as: 'sender', attributes: ['name'] },
        { model: User, as: 'receiver', attributes: ['name'] }
      ]
    });

    // Fetch Program Income (Fund Collections)
    const incomes = await ProgramIncome.findAll({
      where: { tour_id: tourId },
      include: [{ model: User, as: 'collector', attributes: ['name'] }]
    });

    // Compile Context
    let contextStr = `Analyze the financial state of the event "${tour.name}".
Purpose: ${tour.category || 'General'}
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

সবকিছু বাংলায় (Bangla) উত্তর দিন।

REPORT STRUCTURE (বাংলায়):

# 🏛️ সম্পদ বরাদ্দ নিরীক্ষা (Wealth Audit)
| সূচক (Indicator) | কৌশল (Strategy) | অবস্থা (Status) |
| :--- | :--- | :--- |
| **মূলধন দক্ষতা** | [Score 0-100]% | [Efficiency Level] |
| **ভবিষ্যৎ বিনিয়োগ সম্ভাবনা** | ৳[Amount] | [যদি সঞ্চয় করা হতো] |
| **অভিজ্ঞতার ROI** | [High/Low] | [অর্জিত মূল্য] |

# 🔍 সম্পদ বনাম দায় (Asset vs Liability)
| বিভাগ | শ্রেণিবিভাগ | মেন্টর ইনসাইট |
| :--- | :--- | :--- |
| [আইটেম] | [সম্পদ/দায়] | [এটি কীভাবে আপনার নেট ওয়ার্থকে প্রভাবিত করে] |
| [আইটেম] | [খরচ/অপচয়] | [বড় কোনো ভুল বা সঠিক সিদ্ধান্ত] |

# 🧠 বিলিয়নেয়ার মাইন্ডসেট শিফট
*এই ডেটার ওপর ভিত্তি করে একটি গভীর মনস্তাত্ত্বিক "সম্পদ রহস্য" শেয়ার করুন।*
- **শিফট:** [একজন বিলিয়নেয়ার এই পরিস্থিতিটি কীভাবে আলাদাভাবে পরিচালনা করতেন।]

# 🎯 লেগাসি ভারডিক্ট
[এই ইভেন্টটি আপনার ১০ বছরের সফলতার পথে কতটা অবদান রেখেছে তার একটি শক্তিশালী বক্তব্য।]

নিয়ম:
১. সম্পূর্ণ উত্তর বাংলায় হতে হবে।
২. ভাষা হতে হবে গম্ভীর, সরাসরি এবং দূরদর্শী।
৩. তথ্যের গভীরতা বজায় রাখুন।`;





    // Call OpenRouter
    const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${process.env.OPENROUTER_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "google/gemini-2.0-flash-001",
        max_tokens: 2000,
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

