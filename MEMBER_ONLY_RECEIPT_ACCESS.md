# 🔒 Member-Only Receipt Access Control

## Feature Overview
This feature restricts receipt download and sharing to tour members only. Non-members who search for or access a tour cannot download or share receipts.

## What is Restricted?
- ✋ **Download Receipt** - Export report button disabled for non-members
- ✋ **Share Receipt** - Share button disabled for non-members  
- ✋ **Print Receipt** - Print button disabled for non-members

## Access Rules
| User Type | Access | Visibility |
|-----------|--------|-----------|
| **Tour Member** | ✅ Full access | Download, Share, Print buttons enabled |
| **Non-Member** | ❌ No access | Locked icon message shown |
| **Admin/Editor** | ✅ Full access | All features enabled |
| **Viewer Member** | ✅ Full access | Read-only but can download receipts |

## User Experience

### For Members ✅
Settlement Screen:
- "Export Report" button is **enabled** and clickable
- Leads to receipt generation screen

Final Receipt Screen:
- Share and Print icons in AppBar are **enabled**
- Share/Print buttons in body are **visible and clickable**

### For Non-Members 🔒
Settlement Screen:
- "Export Report" button is **disabled** (greyed out)
- Tooltip shows: "Only members can download receipts"

Final Receipt Screen:
- Share and Print icons in AppBar are **disabled**
- Lock message displayed: "Only members can download and share receipts"

## Implementation Details

### Files Modified
1. **settlement_screen.dart**
   - Added member check before enabling "Export Report" button
   - Added tooltip for non-members
   - Button styled as disabled (grey color) when not a member

2. **final_receipt_screen.dart**
   - Added member check for Share/Print buttons
   - Added conditional rendering of action buttons
   - Lock message displays for non-members

### Code Logic
```dart
// Check if current user is a member
final myId = ref.watch(currentUserProvider).value?.id;
final myMember = tourMembers.where((m) => m.user.id == myId).firstOrNull;
final isMember = myMember != null;

// Disable buttons if not a member
onPressed: isMember ? () { /* action */ } : null
```

## Testing Scenarios

### Test 1: Member Download Receipt
1. Login as tour member
2. Navigate to Settlement Screen
3. Verify "Export Report" button is **enabled** ✅
4. Click and verify receipt screen opens

### Test 2: Member Share Receipt
1. On Final Receipt Screen as member
2. Verify Share/Print buttons are **visible** ✅
3. Click Share → Receipt shared successfully

### Test 3: Non-Member Access
1. Search for a tour (without being a member)
2. Navigate to Settlement Screen
3. Verify "Export Report" button is **disabled** ✅
4. Tooltip shows "Only members can download receipts"

### Test 4: Non-Member Cannot Share
1. Non-member on Final Receipt Screen
2. Verify Share/Print buttons are **hidden** ✅
3. Lock message displays with explanation

## Security Notes
- Only database-verified members can access receipt functions
- Member status checked from `tourMembers` table
- No API calls are made for disabled buttons (frontend-only validation)
- UI provides clear feedback about access restrictions

## Future Enhancements
- [ ] Add "Request to join" button for non-members viewing settlement
- [ ] Send notification to tour admin when non-member tries to share
- [ ] Add "limited view" mode for non-members (see only their own balance)
