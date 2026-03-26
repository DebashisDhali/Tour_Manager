# API Documentation - Tour Expense Manager

## Base URL
```
https://tour-manager-navy.vercel.app
```

## Endpoints

### 1. Users

#### Create/Update User
```http
POST /users
Content-Type: application/json

{
  "id": "uuid-string",
  "name": "John Doe",
  "phone": "+8801712345678"
}
```

**Response:**
```json
{
  "id": "uuid-string",
  "name": "John Doe",
  "phone": "+8801712345678",
  "is_registered": true,
  "createdAt": "2026-01-25T00:00:00.000Z",
  "updatedAt": "2026-01-25T00:00:00.000Z"
}
```

#### Get All Users
```http
GET /users
```

**Response:**
```json
[
  {
    "id": "uuid-1",
    "name": "John Doe",
    "phone": "+8801712345678"
  }
]
```

---

### 2. Tours

#### Create Tour
```http
POST /tours
Content-Type: application/json

{
  "id": "tour-uuid",
  "name": "Cox's Bazar Trip 2026",
  "created_by": "user-uuid"
}
```

**Response:**
```json
{
  "id": "tour-uuid",
  "name": "Cox's Bazar Trip 2026",
  "created_by": "user-uuid",
  "status": "active",
  "createdAt": "2026-01-25T00:00:00.000Z"
}
```

#### Get All Tours
```http
GET /tours
```

#### Get Tour Details
```http
GET /tours/:id
```

**Response:**
```json
{
  "id": "tour-uuid",
  "name": "Cox's Bazar Trip 2026",
  "created_by": "user-uuid",
  "status": "active",
  "Users": [
    {
      "id": "user-uuid",
      "name": "John Doe"
    }
  ]
}
```

---

### 3. Expenses

#### Create Expense
```http
POST /expenses
Content-Type: application/json

{
  "id": "expense-uuid",
  "tour_id": "tour-uuid",
  "payer_id": "user-uuid",
  "amount": 1500.00,
  "title": "Hotel Booking",
  "category": "Hotel",
  "splits": [
    {
      "id": "split-uuid-1",
      "user_id": "user-uuid-1",
      "amount": 500.00
    },
    {
      "id": "split-uuid-2",
      "user_id": "user-uuid-2",
      "amount": 500.00
    },
    {
      "id": "split-uuid-3",
      "user_id": "user-uuid-3",
      "amount": 500.00
    }
  ]
}
```

**Response:**
```json
{
  "id": "expense-uuid",
  "tour_id": "tour-uuid",
  "payer_id": "user-uuid",
  "amount": "1500.00",
  "title": "Hotel Booking",
  "category": "Hotel",
  "synced_at": "2026-01-25T00:00:00.000Z"
}
```

#### Get Expenses by Tour
```http
GET /expenses/tour/:tourId
```

**Response:**
```json
[
  {
    "id": "expense-uuid",
    "tour_id": "tour-uuid",
    "payer_id": "user-uuid",
    "amount": "1500.00",
    "title": "Hotel Booking",
    "category": "Hotel",
    "payer": {
      "id": "user-uuid",
      "name": "John Doe"
    },
    "ExpenseSplits": [
      {
        "user_id": "user-uuid-1",
        "amount": "500.00"
      }
    ]
  }
]
```

#### Sync Expenses (Bulk)
```http
POST /expenses/sync
Content-Type: application/json

{
  "expenses": [
    {
      "id": "expense-uuid",
      "tour_id": "tour-uuid",
      "payer_id": "user-uuid",
      "amount": 1500.00,
      "title": "Hotel Booking",
      "category": "Hotel"
    }
  ]
}
```

**Response:**
```json
{
  "status": "synced",
  "count": 1
}
```

---

## Settlement Algorithm

The settlement calculation is done client-side (offline) using the greedy algorithm.

**Algorithm Steps:**
1. Calculate net balance for each user (Total Paid - Total Owed)
2. Separate users into Debtors (negative balance) and Creditors (positive balance)
3. Match largest debtor with largest creditor
4. Transfer minimum of their absolute balances
5. Repeat until all balanced

**Example:**
- User A paid 1000৳, owes 500৳ → Net: +500৳ (Creditor)
- User B paid 200৳, owes 500৳ → Net: -300৳ (Debtor)
- User C paid 0৳, owes 200৳ → Net: -200৳ (Debtor)

**Settlement:**
- B pays 300৳ to A
- C pays 200৳ to A

Total transactions: 2 (optimized)
