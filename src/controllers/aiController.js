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
Your mission is to upgrade the user's financial software from "Consumer" to "Architect of Wealth."
Analyze this event not as a "trip," but as a series of capital allocation decisions.

PRINCIPLES:
1. ROI-ONLY THINKING: Every expense is either an investment in experience/networking or a drain on potential capital.
2. OPPORTUNITY COST: Remind them what this money could have become if invested for 20 years.
3. WEALTH PSYCHOLOGY: Build a "Billionaire Habit" with every insight.

REPORT STRUCTURE:

# 🏛️ Wealth Allocation Audit
| Indicator | Strategy | Status |
| :--- | :--- | :--- |
| **Capital Efficiency** | [Score 0-100]% | [Efficiency Level] |
| **Passive Income Potential** | ৳[Amount] | [If saved/invested] |
| **Experience ROI** | [High/Low] | [Value gained] |

# 🔍 Asset vs Liability Breakdown
| Category | Classification | Mentor Insight |
| :--- | :--- | :--- |
| [Item] | [Asset/Liability] | [Why this affects your net worth pyramid] |
| [Item] | [Exp/Waste] | [The billion-dollar mistake avoided/made] |

# 🧠 The Billionaire Paradigm Shift
*Give one heavy, psychological "Wealth Secret" based on this specific data.*
- **The Shift:** [A deep insight into how a billionaire would have handled this differently.]

# 🎯 Legacy Verdict
[One sharp, powerful statement on whether this event contributed to their 10-year success trajectory or delayed it.]

TONE: High-Stakes, Direct, and Visionary.`;




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

