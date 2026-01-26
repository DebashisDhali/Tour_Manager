# Tour Expense Manager - System Architecture & Design

## 1. High-Level Architecture
The system follows a **Offline-First, Cloud-Sync** architecture.
- **Mobile App (Flutter)**: Primary interface. Uses a local database (SQLite via Drift) for ALL read/write operations. The UI *never* calls the API directly for data mutation. It observes the local database.
- **Sync Engine**: A background service in the app that pushes local changes (Expenses, Tours) to the backend and pulls updates.
- **Backend (Node.js)**: Acts as the central source of truth and backup. Uses PostgreSQL.

## 2. Data Model (ER schema)

### Users
- `id` (UUID, Primary Key)
- `name` (String)
- `phone` (String, optional)
- `created_at`

### Tours
- `id` (UUID)
- `name` (String)
- `created_by` (User UUID)
- `created_at`
- `is_synced` (Local only flag)

### TourMembers
- `tour_id` (UUID)
- `user_id` (UUID)
- `joined_at`

### Expenses
- `id` (UUID)
- `tour_id` (UUID)
- `payer_id` (UUID) - Who paid
- `amount` (Decimal)
- `title` (String)
- `category` (Enum: FOOD, TRANSPORT, etc)
- `split_type` (Enum: EQUAL, CUSTOM)
- `created_at`
- `synced_at` (Timestamp, null if not synced)

### ExpenseSplits (For detailed tracking)
- `expense_id` (UUID)
- `user_id` (UUID) - Who owes
- `owe_amount` (Decimal)

## 3. Sync Strategy (Last-Write-Wins)
We use a **Change Log** approach or simple **Dirty Flags**.
For simplicity and robustness:
1.  **Local Changes**: When a user creates/edits an expense, we save it locally with `synced_at = null` and `updated_at = now()`.
2.  **Push Sync**: The app periodically queries all records where `synced_at` is null. It sends them to the backend `POST /sync/push`.
3.  **Pull Sync**: The app sends `last_sync_timestamp` to `GET /sync/pull`. The server returns all records modified after that timestamp.
4.  **Conflict**: Server timestamp dominates. If the server has a newer version, the local app overwrites its data.

## 4. Settlement Algorithm (Minimize Transactions)
We use a **Greedy Algorithm** to minimize cash flow.

**Steps:**
1.  **Calculate Net Balance** for everyone.
    *   `Net = (Total Paid) - (Total Fair Share)`
    *   Positive Net = Creditor (Needs to receive money).
    *   Negative Net = Debtor (Needs to pay money).
2.  **Separate** into two lists: `Debtors` (sorted asc) and `Creditors` (sorted desc).
3.  **Iterate**:
    *   Take the biggest Debtor (D) and biggest Creditor (C).
    *   Find the minimum absolute amount `min(|D.balance|, C.balance)`.
    *   D pays C this amount.
    *   Update balances.
    *   Remove the one who reaches 0 from the list.
    *   Repeat until lists are empty.

---

## 5. Technology Stack Implementation
- **Frontend**: Flutter + `riverpod` (State) + `drift` (SQLite) + `dio` (Network).
- **Backend**: Node.js (Express) + `pg` (PostgreSQL) + `sequelize` or `typeorm`.
