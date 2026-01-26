# 🧳 Tour Expense Manager

A production-ready, **offline-first** mobile application for managing group tour expenses. Built with Flutter and Node.js, optimized for Bengali users and group travel scenarios.

![Architecture](https://img.shields.io/badge/Architecture-Offline--First-blue)
![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)
![Node.js](https://img.shields.io/badge/Node.js-18+-339933?logo=node.js)
![License](https://img.shields.io/badge/License-MIT-green)

## ✨ Key Features

### 🎯 Core Functionality
- ✅ **Offline-First**: Works completely without internet
- ✅ **Smart Settlement**: Minimizes transactions using greedy algorithm
- ✅ **Group Management**: Create tours, add members, track expenses
- ✅ **Auto-Sync**: Syncs data when internet is available
- ✅ **Bengali-Friendly**: Simple UI optimized for Bengali users
- ✅ **Multiple Split Types**: Equal split & custom split support

### 💡 Use Case
Perfect for group tours where:
- Friends travel together
- Each person pays at different times
- You need to know "who owes whom" at the end
- Internet connectivity is unreliable
- Simple, quick expense tracking is needed

## 🏗 Architecture

```
┌─────────────────┐
│  Flutter App    │  ← Offline-first (Drift/SQLite)
│  (Mobile/Web)   │
└────────┬────────┘
         │ Sync when online
         ↓
┌─────────────────┐
│  Node.js API    │  ← Cloud backup & sync
│  (Express)      │
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│  SQLite/        │  ← Data persistence
│  PostgreSQL     │
└─────────────────┘
```

**Key Design Principles:**
- **Local-First**: All operations work offline
- **Eventual Consistency**: Sync when possible
- **Clean Architecture**: Separation of concerns
- **Production-Ready**: Error handling, logging, validation

## 🚀 Quick Start

### Prerequisites
- Node.js 18+
- Flutter SDK 3.x
- (Optional) Android Studio for mobile development

### 1️⃣ Backend Setup
```bash
cd backend
npm install
npm run dev
```
Server runs on `http://localhost:3000`

### 2️⃣ Frontend Setup
```bash
cd frontend
flutter pub get
dart run build_runner build
flutter run -d chrome  # For web
# OR
flutter run            # For mobile (with device connected)
```

### 3️⃣ Test the App
1. Create a new tour
2. Add members (yourself + friends)
3. Add expenses with different payers
4. View settlement plan (who pays whom)

## 📱 Screens

1. **Tour List**: View all your tours
2. **Create Tour**: Start a new trip
3. **Tour Details**: See all expenses for a tour
4. **Add Expense**: Record a payment
5. **Settlement**: See optimized payment plan

## 🧮 Settlement Algorithm

The app uses a **Greedy Algorithm** to minimize transactions:

**Example:**
```
Rahim paid 1000৳, owes 500৳ → Net: +500৳ (receives)
Karim paid 200৳, owes 500৳ → Net: -300৳ (pays)
Siam paid 0৳, owes 200৳ → Net: -200৳ (pays)

Settlement:
✓ Karim pays 300৳ to Rahim
✓ Siam pays 200৳ to Rahim

Total: 2 transactions (optimized from potentially 6)
```

**Algorithm Steps:**
1. Calculate net balance for each person
2. Separate into debtors and creditors
3. Match largest debtor with largest creditor
4. Transfer minimum amount
5. Repeat until balanced

## 📂 Project Structure

```
Tour_Cost/
├── backend/                 # Node.js + Express API
│   ├── src/
│   │   ├── models/         # Sequelize models
│   │   ├── controllers/    # Request handlers
│   │   ├── routes/         # API routes
│   │   ├── services/       # Business logic (Settlement)
│   │   └── app.js          # Entry point
│   └── package.json
│
├── frontend/               # Flutter mobile app
│   ├── lib/
│   │   ├── data/
│   │   │   ├── local/      # Drift database
│   │   │   ├── sync/       # Sync service
│   │   │   └── providers/  # Riverpod providers
│   │   ├── domain/
│   │   │   └── logic/      # Settlement calculator
│   │   ├── presentation/
│   │   │   ├── screens/    # UI screens
│   │   │   └── widgets/    # Reusable components
│   │   └── main.dart
│   └── pubspec.yaml
│
├── ARCHITECTURE.md         # System design
├── API_DOCUMENTATION.md    # API reference
├── DEPLOYMENT.md          # Deployment guide
└── README.md              # This file
```

## 🛠 Tech Stack

### Frontend
- **Framework**: Flutter 3.x
- **State Management**: Riverpod
- **Local Database**: Drift (SQLite)
- **HTTP Client**: Dio
- **Connectivity**: connectivity_plus

### Backend
- **Runtime**: Node.js 18+
- **Framework**: Express.js
- **ORM**: Sequelize
- **Database**: SQLite (dev) / PostgreSQL (prod)

## 📚 Documentation

- [Architecture Overview](./ARCHITECTURE.md) - System design and data flow
- [API Documentation](./API_DOCUMENTATION.md) - REST API reference
- [Deployment Guide](./DEPLOYMENT.md) - How to deploy to production

## 🧪 Testing

### Backend
```bash
cd backend
npm test  # (Add tests as needed)
```

### Frontend
```bash
cd frontend
flutter test
```

### Manual Testing Checklist
- [ ] Create tour offline
- [ ] Add expenses offline
- [ ] View settlement offline
- [ ] Sync when online
- [ ] Handle sync conflicts
- [ ] Test on slow network
- [ ] Test on airplane mode

## 🔐 Security Notes

**Current Implementation:**
- No authentication (local-only app)
- UUID-based user identification
- Client-side validation

**Production Recommendations:**
- Add JWT authentication
- Implement user registration/login
- Add API rate limiting
- Use HTTPS only
- Encrypt sensitive data
- Add input sanitization

## 🚧 Future Enhancements

- [ ] User authentication (phone/email)
- [ ] Photo attachments for expenses
- [ ] Multi-currency support
- [ ] Expense categories with icons
- [ ] Export to PDF/Excel
- [ ] Push notifications for settlements
- [ ] Tour templates
- [ ] Recurring expenses
- [ ] Budget tracking
- [ ] Analytics dashboard

## 🤝 Contributing

This is a production-ready template. Feel free to:
1. Fork the repository
2. Add features
3. Submit pull requests
4. Report issues

## 📄 License

MIT License - Feel free to use for personal or commercial projects.

## 👨‍💻 Developer Notes

### Why Offline-First?
- Tours often happen in remote areas (hills, beaches)
- Internet is unreliable during travel
- Users need instant access to data
- Reduces server costs
- Better user experience

### Why Greedy Algorithm?
- Simple to implement
- Fast computation (O(n log n))
- Minimizes transactions effectively
- Deterministic results
- Easy to explain to users

### Database Choice
- **SQLite (Mobile)**: Lightweight, embedded, perfect for offline
- **SQLite (Backend Dev)**: Zero-config, easy setup
- **PostgreSQL (Backend Prod)**: Scalable, reliable, feature-rich

## 📞 Support

For issues or questions:
1. Check [ARCHITECTURE.md](./ARCHITECTURE.md) for design details
2. Check [API_DOCUMENTATION.md](./API_DOCUMENTATION.md) for API reference
3. Check [DEPLOYMENT.md](./DEPLOYMENT.md) for deployment help
4. Open an issue on GitHub

---

**Built with ❤️ for group travelers**

*Simple. Offline. Powerful.*
