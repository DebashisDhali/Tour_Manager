# Deployment Guide - Tour Expense Manager

## Prerequisites
- Node.js 18+ installed
- Flutter SDK installed
- For Android: Android Studio with SDK
- For iOS: Xcode (macOS only)

## Backend Deployment

### Option 1: Local/Development Server

1. **Install Dependencies**
```bash
cd backend
npm install
```

2. **Configure Environment** (Optional)
```bash
cp .env.example .env
# Edit .env if needed (currently using SQLite, no config needed)
```

3. **Start Server**
```bash
npm run dev  # Development with auto-reload
# OR
npm start    # Production
```

Server runs on `http://localhost:3000`

### Option 2: Cloud Deployment (Render/Railway/Heroku)

1. **Prepare for Production**
   - The app uses SQLite by default (file-based)
   - For production, switch to PostgreSQL in `src/models/index.js`
   - Update environment variables on your hosting platform

2. **Deploy to Render.com** (Example)
   - Connect your GitHub repository
   - Set build command: `npm install`
   - Set start command: `npm start`
   - Add environment variables if using PostgreSQL

3. **Deploy to Railway.app**
   - **Option A (CLI):**
     ```bash
     cd backend
     railway up
     ```
   - **Option B (Dashboard/GitHub):**
     - Connect your repo
     - Go to **Settings** > **General**
     - Set **Root Directory** to `/backend`

---

## Frontend Deployment

### Mobile App (Android)

1. **Build APK**
```bash
cd frontend
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

2. **Install on Device**
```bash
flutter install
# OR manually transfer APK to phone
```

3. **Build App Bundle (for Play Store)**
```bash
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`

### Mobile App (iOS)

1. **Build iOS App**
```bash
cd frontend
flutter build ios --release
```

2. **Open in Xcode**
```bash
open ios/Runner.xcworkspace
```

3. **Archive and Upload to App Store**
   - Use Xcode's Archive feature
   - Follow Apple's submission guidelines

### Web Deployment

1. **Build for Web**
```bash
cd frontend
flutter build web --release
```

Output: `build/web/`

2. **Deploy to Netlify/Vercel/Firebase Hosting**

**Netlify:**
```bash
npm install -g netlify-cli
netlify deploy --dir=build/web --prod
```

**Vercel:**
```bash
npm install -g vercel
cd build/web
vercel --prod
```

**Firebase Hosting:**
```bash
npm install -g firebase-tools
firebase init hosting
# Select build/web as public directory
firebase deploy
```

---

## Configuration for Production

### Update API Base URL

**Mobile App:**
Edit `frontend/lib/data/sync/sync_service.dart`:
```dart
String get baseUrl {
    if (kIsWeb) return 'https://your-backend.com';
    try {
        if (Platform.isAndroid) return 'https://your-backend.com';
    } catch (e) {}
    return 'https://your-backend.com';
}
```

**Backend CORS:**
Edit `backend/src/app.js`:
```javascript
app.use(cors({
  origin: ['https://your-frontend.com', 'http://localhost:*']
}));
```

---

## Database Migration (SQLite → PostgreSQL)

When scaling to production with multiple users:

1. **Install PostgreSQL**
```bash
npm install pg pg-hstore
```

2. **Update `backend/src/models/index.js`**
```javascript
const sequelize = new Sequelize(
  process.env.DB_NAME,
  process.env.DB_USER,
  process.env.DB_PASSWORD,
  {
    host: process.env.DB_HOST,
    dialect: 'postgres',
    logging: false
  }
);
```

3. **Set Environment Variables**
```
DB_NAME=tour_expense
DB_USER=your_user
DB_PASSWORD=your_password
DB_HOST=your_postgres_host
```

---

## Testing the Deployment

1. **Backend Health Check**
```bash
curl http://localhost:3000
# Should return: "Tour Expense Manager API is running"
```

2. **Create Test User**
```bash
curl -X POST http://localhost:3000/users \
  -H "Content-Type: application/json" \
  -d '{"id":"test-123","name":"Test User"}'
```

3. **Mobile App**
   - Create a tour
   - Add expenses
   - Check settlement calculations
   - Test offline mode (airplane mode)
   - Reconnect and verify sync

---

## Monitoring & Maintenance

### Logs
- Backend logs: Check console output or configure logging service
- Mobile logs: Use `flutter logs` or Firebase Crashlytics

### Database Backups
```bash
# SQLite
cp backend/database.sqlite backend/backup-$(date +%Y%m%d).sqlite

# PostgreSQL
pg_dump -U username database_name > backup.sql
```

### Updates
```bash
# Backend
cd backend
npm update

# Frontend
cd frontend
flutter pub upgrade
```

---

## Troubleshooting

### Backend won't start
- Check if port 3000 is available
- Verify Node.js version: `node --version`
- Check database connection

### Mobile app won't build
- Run `flutter doctor` to check setup
- Clear cache: `flutter clean && flutter pub get`
- Rebuild: `flutter build apk --release`

### Sync not working
- Verify backend URL is correct
- Check network connectivity
- Review console logs for errors
- Ensure CORS is configured properly

---

## Security Considerations

1. **Add Authentication** (Future Enhancement)
   - Implement JWT tokens
   - Add user login/registration
   - Secure API endpoints

2. **HTTPS Only**
   - Use SSL certificates in production
   - Never use HTTP for production APIs

3. **Input Validation**
   - Validate all user inputs
   - Sanitize data before database operations
   - Implement rate limiting

4. **Database Security**
   - Use strong passwords
   - Restrict database access
   - Regular backups
   - Enable encryption at rest
