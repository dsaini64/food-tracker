# Railway Deployment Guide

## 🚀 Quick Deploy to Railway

### Step 1: Create Railway Project
1. Go to [railway.app](https://railway.app)
2. Sign in with GitHub
3. Click "New Project"
4. Select "Deploy from GitHub repo"
5. Choose `dsaini64/food-tracker-current`
6. **IMPORTANT**: Select the `backend` folder as the root directory

### Step 2: Set Environment Variables
In Railway dashboard, add these variables:

```
NODE_ENV=production
PORT=3000
OPENAI_API_KEY=your-openai-api-key-here
ALLOWED_ORIGINS=*
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX_REQUESTS=100
MAX_IMAGE_SIZE_MB=10
SUPPORTED_FORMATS=image/jpeg,image/jpg,image/png,image/webp
```

### Step 3: Deploy
Railway will automatically:
- Detect Node.js
- Install dependencies with `npm ci`
- Run build with `npm run build`
- Start with `npm start`

## 🔧 Troubleshooting

### If Build Fails:
1. Check that you selected the `backend` folder
2. Verify all environment variables are set
3. Check Railway logs for specific errors

### If App Won't Start:
1. Verify `OPENAI_API_KEY` is set correctly
2. Check that `NODE_ENV=production`
3. Ensure `PORT` is set to 3000

### Health Check:
Visit `https://your-app.railway.app/health` to verify deployment.

## 📱 Update iOS App
After deployment, update `FoodAnalysisService.swift`:
```swift
private let baseURL = "https://your-railway-app-url.railway.app"
```
