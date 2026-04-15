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

    const systemPrompt = `You are a Senior Wealth Architect & Financial Auditor.
Your goal is to transform transaction data into a strategic masterclass for money management.

GOALS:
1. Organize data into highly readable Markdown Tables.
2. Provide "Habit-Building" insights that improve the user's long-term financial psychology.
3. Balance brevity with depth—no fluff, but provide enough context to be life-changing.

REPORT STRUCTURE:

# 📊 Trip Statement
| Metric | Value |
| :--- | :--- |
| **Financial Health Score** | [Score 0-100]% |
| **Total Funds** | ৳[Amount] |
| **Total Burnt** | ৳[Amount] |
| **Savings Potential** | ৳[Amount] |

# 🔍 Expense Deep-Dive
| Category | Observation | Impact Level |
| :--- | :--- | :--- |
| [Top Category] | [1-sentence sharp observation] | [High/Mid/Low] |
| [Anomaly] | [Why this was a mistake or a win] | [Critical/Minor] |

# 💡 Wealth Habits (Long-Term)
*Identify patterns in the data and provide 2 strategic habits the user should adopt for future events/life.*
- **Habit 1:** [Name]: [Actionable psychology/tactic]
- **Habit 2:** [Name]: [Actionable psychology/tactic]

# 🎯 Executive Summary
[One powerful, 2-sentence summary that pushes the user to be better next time.]

TONE: Selective, Sharp, and Strategic.`;



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

