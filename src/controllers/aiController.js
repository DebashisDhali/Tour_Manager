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

    const systemPrompt = `You are a Professional Financial Coach and Auditor.
Your goal is to provide deep, actionable insights for travelers or event organizers.
Analyze spending patterns, budget efficiency, and identify any financial leaks.

RULES:
1. Output in strictly formatted Markdown.
2. Use a friendly yet professional tone.
3. Be brutally honest about wasteful spending.
4. Suggestions must be actionable.
5. Highlight the "Total Budget utilized" vs "Total Funds collected".

REPORT STRUCTURE:
# 📊 Financial Overview
# 🔍 Spending Analysis & Insights
# 💡 How to Save More / Optimization
# 🎯 Final Verdict`;

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

