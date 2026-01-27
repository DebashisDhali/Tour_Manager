# Testing Join with Code Feature

## Prerequisites
1. Backend server running on port 3000
2. Frontend app running (web or mobile)
3. Two different users/devices (or two browser windows)

## Test Scenario 1: Basic Join Flow

### User A (Creator):
1. Open the app
2. Click "New Tour" button
3. Enter tour name: "Test Trip"
4. Enter your name: "User A"
5. Click "Start Tour"
6. **Note the invite code** displayed on the tour details screen (6 characters)

### User B (Joiner):
1. Open the app in a different browser/incognito window
2. Enter your name: "User B" when prompted
3. Click the "Join Tour" icon (group_add icon) in the app bar
4. Enter the invite code from User A
5. Click "Join Now"
6. **Expected Result:** 
   - Success message appears: "Successfully joined!"
   - Tour appears immediately in "My Tours" tab
   - Can see all tour members including User A

## Test Scenario 2: Already Member Error

### Steps:
1. User B tries to join the same tour again with the same invite code
2. **Expected Result:** Error message: "You are already a member"

## Test Scenario 3: Invalid Code Error

### Steps:
1. User B clicks "Join Tour"
2. Enters invalid code: "XXXXXX"
3. Clicks "Join Now"
4. **Expected Result:** Error message: "Invalid invite code"

## Test Scenario 4: Network Offline

### Steps:
1. Turn off internet connection
2. Try to join a tour
3. **Expected Result:** Error message about network failure

## Test Scenario 5: Multiple Members

### Steps:
1. User A creates a tour
2. User B joins using invite code
3. User C joins using the same invite code
4. User D joins using the same invite code
5. **Expected Result:** 
   - All users can see each other in the members list
   - All users can add expenses
   - All users see the same data after sync

## Verification Checklist

After joining, verify:
- [ ] Tour appears in "My Tours" tab
- [ ] Tour name is correct
- [ ] All members are visible in tour details
- [ ] Can add expenses to the joined tour
- [ ] Can see expenses added by other members
- [ ] Settlement calculation includes all members
- [ ] Sync button works and updates data

## Backend Verification

Check backend logs for:
```
POST /tours/join - 200 OK
```

Check database:
```bash
# In backend directory
sqlite3 database.sqlite
SELECT * FROM TourMembers;
```

Should show the new member relationship.

## Common Issues

### Issue: Tour doesn't appear after joining
**Solution:** 
1. Check browser console for errors
2. Manually click sync button
3. Refresh the page
4. Check if backend is running

### Issue: "Already a member" but can't see tour
**Solution:**
1. Click sync button
2. Check backend database
3. Clear local database and try again

### Issue: Join succeeds but no members visible
**Solution:**
1. This is now fixed - the backend returns full tour data
2. If still happening, check backend logs
3. Verify the Tour model includes User association

## Performance Test

### Test with many members:
1. Create a tour
2. Join with 10+ different users
3. Verify all members appear
4. Check response time (should be < 2 seconds)

## Success Criteria

✅ Join completes in < 2 seconds  
✅ Tour appears immediately without manual sync  
✅ All members are visible  
✅ No errors in console  
✅ Works consistently (5/5 attempts)  
✅ Error messages are clear and helpful  
