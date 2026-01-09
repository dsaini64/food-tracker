const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

// Add CORS for all origins
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization');
  if (req.method === 'OPTIONS') {
    res.sendStatus(200);
  } else {
    next();
  }
});

// Body parsing middleware
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

// Simple test server
app.get('/', (req, res) => {
  console.log('🏠 Root endpoint accessed');
  res.json({ 
    message: 'Food Tracker Backend API - Test Version',
    status: 'OK',
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV || 'development',
    port: PORT
  });
});

app.get('/health', (req, res) => {
  console.log('🏥 Health check accessed');
  res.json({ 
    status: 'OK',
    timestamp: new Date().toISOString(),
    version: '1.0.0-test',
    environment: process.env.NODE_ENV || 'development',
    port: PORT
  });
});

app.post('/api/analyze-food', (req, res) => {
  console.log('🍎 Food analysis endpoint accessed');
  console.log('📱 Request body:', req.body);
  console.log('📱 Request headers:', req.headers);
  
  res.json({
    success: true,
    message: 'Test endpoint working',
    timestamp: new Date().toISOString(),
    receivedData: {
      bodyKeys: Object.keys(req.body),
      contentType: req.headers['content-type'],
      contentLength: req.headers['content-length']
    }
  });
});

// Error handling
app.use((err, req, res, next) => {
  console.error('❌ Error:', err);
  res.status(500).json({
    error: err.message,
    timestamp: new Date().toISOString()
  });
});

// 404 handler
app.use('*', (req, res) => {
  console.log('❌ 404 - Route not found:', req.originalUrl);
  res.status(404).json({
    error: 'Route not found',
    path: req.originalUrl,
    timestamp: new Date().toISOString()
  });
});

const server = app.listen(PORT, () => {
  console.log(`🍎 Test Food Tracker Backend running on port ${PORT}`);
  console.log(`📊 Health check: http://localhost:${PORT}/health`);
  console.log(`🔍 Food analysis: http://localhost:${PORT}/api/analyze-food`);
  console.log(`🌍 Environment: ${process.env.NODE_ENV || 'development'}`);
});

// Handle server errors
server.on('error', (error) => {
  console.error('❌ Server error:', error);
});

module.exports = app;
