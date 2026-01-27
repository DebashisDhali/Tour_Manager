# Join Error Troubleshooting Guide

## Quick Fix Steps

### Step 1: Restart Backend
```bash
# Stop backend (Ctrl+C in backend terminal)
cd backend
rm database.sqlite  # Delete old database
npm run dev         # Start fresh
```

### Step 2: Hot Restart Frontend
In the Flutter terminal, press:
- **`R`** (capital R) for hot restart
- Or stop and run: `flutter run`

### Step 3: Clear Browser Data (if using web)
1. Open Chrome DevTools (F12)
2. Go to Application tab
3. Click "Clear storage"
4. Check "IndexedDB"
5. Click "Clear site data"
6. Reload page (F5)

## Common Errors and Solutions

### Error: "Invalid invite code"
**Cause:** Code doesn't exist or typo  
**Solution:** 
- Double-check the code
- Make sure creator's tour is synced to backend
- Try creating a new tour

### Error: "You are already a member"
**Cause:** Already joined this tour  
**Solution:**
- Check "My Tours" tab - tour should be there
- If not visible, click sync button
- If still not visible, clear local data and sync again

### Error: Network/Connection errors
**Cause:** Backend not running or wrong URL  
**Solution:**
- Check backend is running: `curl http://localhost:3000/tours`
- Check frontend baseUrl in sync_service.dart
- For deployed app, check Railway/Render URL

### Error: Database/Schema errors
**Cause:** Database schema mismatch  
**Solution:**
```bash
# Backend
cd backend
rm database.sqlite
npm run dev

# Frontend (web)
# Clear browser IndexedDB (see Step 3 above)

# Frontend (mobile)
# Uninstall and reinstall app
```

## Debug Mode

### Enable Detailed Logs

The latest code has detailed logging. To see logs:

**Web:**
1. Open Chrome DevTools (F12)
2. Go to Console tab
3. Look for messages starting with:
   - `=== JOIN REQUEST START ===`
   - `✅` (success messages)
   - `❌` (error messages)
   - `⚠️` (warning messages)

**Mobile:**
1. Run with: `flutter run --verbose`
2. Check terminal output
3. Or use `flutter logs`

### What to Look For

Good join flow should show:
```
=== JOIN REQUEST START ===
Invite Code: ABC123
User ID: xxx
User Name: xxx
Response Status: 200
Response Data: {tour: {...}, message: ...}
✅ Joined successfully on server
📦 Saving joined tour to local DB: Tour Name
✅ Tour saved to local DB
👥 Saving 2 members...
✅ Member saved: User A
✅ Member saved: User B
✅ All members saved
✅ Tour and members saved successfully to local DB
🔄 Starting post-join sync...
✅ Post-join sync completed successfully
=== JOIN REQUEST COMPLETE ===
```

Error flow will show:
```
=== JOIN REQUEST START ===
❌ DioException during join:
  Status Code: 404
  Response Data: {error: "Invalid invite code"}
  Message: ...
```

## Testing Checklist

Before reporting an issue, verify:

- [ ] Backend is running (check terminal)
- [ ] Backend responds to: `curl http://localhost:3000/tours`
- [ ] Frontend is connected to correct backend URL
- [ ] Invite code is correct (6 characters, uppercase)
- [ ] Tour creator has synced their tour
- [ ] Browser/app has internet connection
- [ ] No CORS errors in browser console
- [ ] Database files are not corrupted

## Still Not Working?

1. **Collect Debug Info:**
   - Backend terminal output
   - Frontend console logs
   - Error message screenshot
   - Network tab in DevTools (F12 → Network)

2. **Try Clean Install:**
   ```bash
   # Backend
   cd backend
   rm -rf node_modules database.sqlite
   npm install
   npm run dev
   
   # Frontend
   cd frontend
   flutter clean
   flutter pub get
   dart run build_runner build --delete-conflicting-outputs
   flutter run
   ```

3. **Check Code Version:**
   - Make sure you have the latest fixes
   - Check tourController.js has transaction support
   - Check sync_service.dart has detailed logging

## Contact Support

If still facing issues, provide:
1. Error message (exact text)
2. Console logs (from DevTools)
3. Backend terminal output
4. Steps to reproduce
5. Environment (web/mobile, OS, browser version)
