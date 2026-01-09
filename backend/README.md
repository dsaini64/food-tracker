# Food Tracker Backend

AI-powered nutrition tracking backend with ChatGPT Vision integration.

## 🚀 Railway Deployment

### Quick Deploy to Railway:

1. **Go to [railway.app](https://railway.app)**
2. **Sign in with GitHub**
3. **Click "New Project"**
4. **Select "Deploy from GitHub repo"**
5. **Choose `dsaini64/food-tracker-current`**
6. **Select the `backend` folder**
7. **Set environment variables:**
   ```
   NODE_ENV=production
   OPENAI_API_KEY=your-openai-api-key-here
   ALLOWED_ORIGINS=*
   RATE_LIMIT_WINDOW_MS=900000
   RATE_LIMIT_MAX_REQUESTS=100
   MAX_IMAGE_SIZE_MB=10
   SUPPORTED_FORMATS=image/jpeg,image/jpg,image/png,image/webp
   ```

### Environment Variables Required:
- `OPENAI_API_KEY` - Your OpenAI API key
- `NODE_ENV=production` - Set to production
- `ALLOWED_ORIGINS=*` - Allow all origins for mobile apps

### Health Check:
Visit `https://your-app.railway.app/health` to verify deployment.

## 🔧 Local Development

```bash
npm install
npm run dev
```

## 📱 API Endpoints

- `GET /health` - Health check
- `POST /api/analyze-food` - Analyze food image
- `GET /test` - Test endpoint

## 🛠️ Troubleshooting

### If Railpack Error Occurs:
1. Make sure you're deploying the `backend` folder
2. Check that all environment variables are set
3. Verify the `package.json` has correct scripts
4. Try redeploying

### Common Issues:
- **Missing API key**: Set `OPENAI_API_KEY` environment variable
- **CORS errors**: Set `ALLOWED_ORIGINS=*` for production
- **Build failures**: Check that `npm start` works locally