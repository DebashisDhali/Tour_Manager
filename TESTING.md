# Tour Expense Manager - Testing Guide

## Manual Testing Scenarios

### Scenario 1: Basic Tour Creation (Offline)
**Steps:**
1. Open app (ensure offline - airplane mode)
2. Click "New Tour"
3. Enter tour name: "Cox's Bazar Trip"
4. Enter your name: "Rahim"
5. Click "Start Tour"

**Expected:**
- Tour appears in list immediately
- No network errors
- Data persists after app restart

---

### Scenario 2: Adding Expenses
**Steps:**
1. Open a tour
2. Click "+" to add expense
3. Enter:
   - Description: "Hotel Booking"
   - Amount: 3000
   - Category: Hotel
   - Paid by: Rahim
4. Save

**Expected:**
- Expense appears in list
- Amount shows as "3000 ৳"
- Works offline

---

### Scenario 3: Settlement Calculation
**Setup:**
Create a tour with 3 members: Rahim, Karim, Siam

**Add expenses:**
1. Rahim pays 1500৳ for hotel (split equally: 500 each)
2. Karim pays 600৳ for food (split equally: 200 each)
3. Siam pays 0৳

**Steps:**
1. Click "Settlement" button
2. View settlement plan

**Expected Settlement:**
```
Karim pays 100৳ to Rahim
Siam pays 500৳ to Rahim
Karim pays 200৳ to Karim (or optimized differently)
```

**Calculation:**
- Rahim: Paid 1500, Owes 700 → Net: +800
- Karim: Paid 600, Owes 700 → Net: -100
- Siam: Paid 0, Owes 700 → Net: -700

---

### Scenario 4: Sync Test
**Steps:**
1. Create tour offline
2. Add 2-3 expenses offline
3. Turn on internet
4. Wait 5 seconds (auto-sync)
5. Check backend: `GET http://localhost:3000/tours`

**Expected:**
- Data appears in backend
- No duplicate entries
- All expenses synced

---

### Scenario 5: Custom Split
**Steps:**
1. Add expense: 1000৳
2. Select "Custom Split"
3. Assign:
   - Rahim: 500৳
   - Karim: 300৳
   - Siam: 200৳
4. Save

**Expected:**
- Total split = 1000৳
- Settlement reflects custom amounts

---

### Scenario 6: Multiple Tours
**Steps:**
1. Create "Cox's Bazar Trip"
2. Create "Sylhet Trip"
3. Add expenses to both
4. Switch between tours

**Expected:**
- Expenses don't mix
- Each tour has separate settlement
- Tour list shows both

---

### Scenario 7: Edge Cases

#### Empty Tour
- Create tour with no expenses
- View settlement
- Expected: "Everything is settled! ✅"

#### Single Member
- Create tour with only yourself
- Add expense
- Expected: No settlement needed

#### Zero Amount
- Try to add expense with 0৳
- Expected: Validation error

#### Negative Amount
- Try to add expense with -100৳
- Expected: Validation error

---

## Backend API Testing

### Test User Creation
```bash
curl -X POST http://localhost:3000/users \
  -H "Content-Type: application/json" \
  -d '{
    "id": "user-123",
    "name": "Test User",
    "phone": "+8801712345678"
  }'
```

**Expected Response:**
```json
{
  "id": "user-123",
  "name": "Test User",
  "phone": "+8801712345678",
  "is_registered": true
}
```

### Test Tour Creation
```bash
curl -X POST http://localhost:3000/tours \
  -H "Content-Type: application/json" \
  -d '{
    "id": "tour-456",
    "name": "Test Tour",
    "created_by": "user-123"
  }'
```

### Test Expense Creation
```bash
curl -X POST http://localhost:3000/expenses \
  -H "Content-Type: application/json" \
  -d '{
    "id": "exp-789",
    "tour_id": "tour-456",
    "payer_id": "user-123",
    "amount": 1000,
    "title": "Test Expense",
    "category": "Food",
    "splits": [
      {
        "id": "split-1",
        "user_id": "user-123",
        "amount": 1000
      }
    ]
  }'
```

---

## Performance Testing

### Load Test
1. Create 10 tours
2. Add 50 expenses per tour
3. Calculate settlement for each
4. Measure time

**Expected:**
- Settlement calculation < 100ms
- UI remains responsive
- No memory leaks

### Offline Performance
1. Create 100 expenses offline
2. Turn on internet
3. Measure sync time

**Expected:**
- Sync completes in < 10 seconds
- No data loss
- No duplicate entries

---

## Browser Testing (Web Version)

### Browsers to Test
- ✅ Chrome (latest)
- ✅ Edge (latest)
- ✅ Firefox (latest)
- ✅ Safari (latest)

### Features to Verify
- [ ] IndexedDB works
- [ ] Data persists after refresh
- [ ] Responsive design
- [ ] No console errors
- [ ] Settlement calculation works

---

## Mobile Testing

### Android
- [ ] Test on Android 8+
- [ ] Test on different screen sizes
- [ ] Test offline mode
- [ ] Test background sync
- [ ] Test app restart

### iOS (if applicable)
- [ ] Test on iOS 12+
- [ ] Test on iPhone/iPad
- [ ] Test offline mode
- [ ] Test background sync

---

## Regression Testing Checklist

After any code change, verify:
- [ ] Can create tour
- [ ] Can add expense
- [ ] Settlement calculates correctly
- [ ] Offline mode works
- [ ] Sync works when online
- [ ] No console errors
- [ ] Data persists after restart
- [ ] Backend API responds correctly

---

## Bug Report Template

```markdown
**Bug Title:** [Short description]

**Steps to Reproduce:**
1. 
2. 
3. 

**Expected Behavior:**
[What should happen]

**Actual Behavior:**
[What actually happens]

**Environment:**
- Device: [Android/iOS/Web]
- OS Version: [e.g., Android 12]
- App Version: [e.g., 1.0.0]
- Browser (if web): [e.g., Chrome 120]

**Screenshots:**
[If applicable]

**Console Logs:**
[If applicable]
```

---

## Automated Testing (Future)

### Unit Tests
```dart
// Example: Settlement Calculator Test
test('Settlement minimizes transactions', () {
  final expenses = [...];
  final splits = [...];
  final users = [...];
  
  final result = SettlementCalculator().calculate(expenses, splits, users);
  
  expect(result.length, lessThan(users.length));
});
```

### Integration Tests
```dart
testWidgets('Create tour flow', (tester) async {
  await tester.pumpWidget(MyApp());
  
  await tester.tap(find.text('New Tour'));
  await tester.pumpAndSettle();
  
  await tester.enterText(find.byType(TextField).first, 'Test Tour');
  await tester.tap(find.text('Start Tour'));
  await tester.pumpAndSettle();
  
  expect(find.text('Test Tour'), findsOneWidget);
});
```

---

## Test Data

### Sample Tour Data
```json
{
  "tour_name": "Cox's Bazar Trip 2026",
  "members": [
    {"name": "Rahim", "id": "user-1"},
    {"name": "Karim", "id": "user-2"},
    {"name": "Siam", "id": "user-3"}
  ],
  "expenses": [
    {
      "title": "Hotel",
      "amount": 3000,
      "payer": "user-1",
      "split": "equal"
    },
    {
      "title": "Food",
      "amount": 1500,
      "payer": "user-2",
      "split": "equal"
    },
    {
      "title": "Transport",
      "amount": 900,
      "payer": "user-3",
      "split": "equal"
    }
  ]
}
```

**Expected Settlement:**
- Karim pays 300৳ to Rahim
- Siam pays 500৳ to Rahim
