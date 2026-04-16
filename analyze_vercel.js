const https = require('https');

function get(path) {
  return new Promise((resolve) => {
    https.get(`https://tour-manager-navy.vercel.app${path}`, (res) => {
      let data = '';
      res.on('data', chunk => { data += chunk; });
      res.on('end', () => { try { resolve(JSON.parse(data)); } catch(e) { resolve({ raw: data.substring(0, 300) }); } });
    }).on('error', err => resolve({ error: err.message }));
  });
}

(async () => {
  console.log("=== Checking Vercel DB: All Tours & Invite Codes ===\n");
  const result = await get('/tours/diagnostic/list-codes');
  
  if (result.error) {
    console.log("❌ Error:", result.error);
    return;
  }
  if (result.raw) {
    console.log("Raw response:", result.raw);
    return;
  }
  
  console.log(`Total tours in DB: ${result.count}\n`);
  
  if (!result.tours || result.tours.length === 0) {
    console.log("⚠️  NO TOURS FOUND IN DATABASE! This is the root cause.");
    console.log("   → Sync is not pushing tours to the server.");
    console.log("   → Check if the user is authenticated when syncing.");
    return;
  }
  
  result.tours.forEach((t, i) => {
    const codeStatus = t.has_invite_code ? `✅ ${t.invite_code}` : '❌ NULL (MISSING!)';
    console.log(`[${i+1}] "${t.name}"`);
    console.log(`    invite_code: ${codeStatus}`);
    console.log(`    id: ${t.id}`);
    console.log(`    last updated: ${t.updated_at}`);
    console.log('');
  });
  
  const missing = result.tours.filter(t => !t.has_invite_code);
  const present = result.tours.filter(t => t.has_invite_code);
  
  console.log("=== SUMMARY ===");
  console.log(`Tours WITH invite_code: ${present.length}`);
  console.log(`Tours WITHOUT invite_code: ${missing.length}`);
  
  if (missing.length > 0) {
    console.log("\n⚠️ ROOT CAUSE FOUND: Some tours have NULL invite_code on server!");
    console.log("   → invite_code is not being saved during sync.");
  } else if (present.length > 0) {
    console.log("\n✅ All tours have invite_codes. Test join with one of these codes:");
    present.forEach(t => console.log(`   → ${t.invite_code} (${t.name})`));
  }
})();
