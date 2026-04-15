const { Tour, User, Expense, ExpenseSplit, TourMember, Settlement } = require('../models');

exports.getTourInsights = async (req, res) => {
  try {
    const { tourId } = req.params;
    const { message } = req.body;

    if (!process.env.OPENROUTER_API_KEY) {
      return res.status(500).json({ error: "OpenRouter API Key not configured." });
    }

    // Fetch Tour Data
    const tour = await Tour.findByPk(tourId);
    if (!tour) {
      return res.status(404).json({ error: "Tour not found" });
    }

    const members = await TourMember.findAll({
      where: { tour_id: tourId },
      include: [User]
    });

    const expenses = await Expense.findAll({
      where: { tour_id: tourId },
      include: [ExpenseSplit]
    });

    const settlements = await Settlement.findAll({
      where: { tour_id: tourId }
    });

    // Compile Context
    let contextStr = `Here is the data for the tour/event named "${tour.name}":\n`;
    contextStr += `Total Members: ${members.length}\n`;
    contextStr += `Total Expenses: ${expenses.length}\n\n`;

    const memberNames = members.map(m => m.User ? m.User.name : 'Unknown').join(', ');
    contextStr += `Members involved: ${memberNames}\n\n`;

    contextStr += `Expenses:\n`;
    let totalCost = 0;
    expenses.forEach(e => {
        totalCost += e.amount;
        contextStr += `- ${e.title}: ৳${e.amount} (Category: ${e.category || 'N/A'}, Paid By: ${e.payer_id || 'Unknown'})\n`;
    });
    contextStr += `\nTotal Cost so far: ৳${totalCost}\n\n`;

    contextStr += `Based on this data, please act as an Expert Financial Auditor and Optimizer. Analyze the expenses above and generate a structured optimization report. Follow this exact format:
    
# 📊 Financial Dashboard
- **Total Spent:** ৳[totalCost]
- **Members Involved:** [count]

# 🔍 Cost Breakdown & Anomalies
[Analyze category-wise spending. Point out disproportionately high costs or wasteful spending (e.g., if snacks/transport is too high per head).]

# 💡 Optimization Opportunities
[Give 2-4 actionable suggestions on how they could have organized this more efficiently or cheaper.]

# 🎯 Final Verdict
[A brief, blunt 1-2 sentence conclusion on their financial management for this event.]

Make sure the output is pure Markdown and strictly follows the structure. Do not chat or add pleasantries.`;

    // Call OpenRouter
    const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${process.env.OPENROUTER_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "openrouter/auto",
        messages: [
          {
            role: "system",
            content: "You are a strict financial auditor AI. Output only structured Markdown reports based on user data. No pleasantries. No conversational fluff."
          },
          {
            role: "user",
            content: contextStr
          }
        ],
        // Set model to "auto" if supported, but OpenRouter usually needs a specific model string like `google/gemini-pro`
      })
    });

    const data = await response.json();
    
    if (data.choices && data.choices.length > 0) {
      return res.json({ reply: data.choices[0].message.content });
    } else {
        console.error("OpenRouter Error:", data);
        return res.status(500).json({ error: "Failed to generate AI response", details: data });
    }

  } catch (error) {
    console.error("AI Insights Error:", error);
    res.status(500).json({ error: "Internal server error during AI analysis." });
  }
};
