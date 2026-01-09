const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const multer = require('multer');
const sharp = require('sharp');
const { v4: uuidv4 } = require('uuid');
require('dotenv').config();

const chatGPTService = require('./services/chatgptService');
const nutritionService = require('./services/nutritionService');
const patternSummaryService = require('./services/patternSummaryService');

const app = express();
const PORT = process.env.PORT || 3000;

// Trust proxy - required for reverse proxy (Railway, Heroku, etc.) to get real client IP
app.set('trust proxy', 1);

// Security middleware
app.use(helmet());

// CORS configuration
const corsOptions = {
  origin: process.env.NODE_ENV === 'production' 
    ? true // Allow all origins in production (Railway)
    : (process.env.ALLOWED_ORIGINS?.split(',') || ['http://localhost:3000']),
  credentials: true
};
app.use(cors(corsOptions));

// Rate limiting
const limiter = rateLimit({
  windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS) || 15 * 60 * 1000, // 15 minutes
  max: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS) || 100, // limit each IP to 100 requests per windowMs
  message: 'Too many requests from this IP, please try again later.'
});
app.use('/api/', limiter);

// Configure multer for image uploads
const storage = multer.memoryStorage();
const upload = multer({
  storage: storage,
  limits: {
    fileSize: (parseInt(process.env.MAX_IMAGE_SIZE_MB) || 10) * 1024 * 1024 // 10MB default
  },
  fileFilter: (req, file, cb) => {
    // Accept all image files for now to avoid iOS upload issues
    const allowedMimeTypes = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'application/octet-stream'];
    
    if (allowedMimeTypes.includes(file.mimetype) || file.mimetype.startsWith('image/')) {
      if (process.env.NODE_ENV !== 'production') {
      console.log(`File accepted: ${file.originalname}, mimetype: ${file.mimetype}`);
      }
      cb(null, true);
    } else {
      console.log(`File rejected: ${file.originalname}, mimetype: ${file.mimetype}`);
      cb(new Error(`Invalid file type. Allowed types: image files`), false);
    }
  }
});

// Body parsing middleware for JSON routes only (not for multipart/form-data)
// Apply only to routes that need JSON parsing, not globally
// This prevents express.json() from consuming the body stream before multer can read it
const jsonParser = express.json({ limit: '50mb' });
const urlencodedParser = express.urlencoded({ extended: true, limit: '50mb' });

// Root endpoint
app.get('/', (req, res) => {
  res.json({ 
    message: 'Food Tracker Backend API',
    status: 'OK',
    version: '1.0.0',
    endpoints: {
      health: '/health',
      analyze: '/api/analyze-food'
    }
  });
});

// Health check endpoint
app.get('/health', (req, res) => {
  console.log('🏥 Health check requested');
  res.json({ 
    status: 'OK',
    timestamp: new Date().toISOString(),
    version: '1.0.0',
    environment: process.env.NODE_ENV || 'development',
    port: process.env.PORT || 3000
  });
});

// Test endpoint for debugging
app.get('/test', (req, res) => {
  res.json({ 
    message: 'Backend is working!',
    timestamp: new Date().toISOString(),
    ip: req.ip,
    userAgent: req.get('User-Agent')
  });
});

// Analyze food image endpoint
app.post('/api/analyze-food', upload.single('image'), async (req, res) => {
  const requestStartTime = Date.now();
  
  // Set keep-alive headers to prevent Railway load balancer timeout
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('Keep-Alive', 'timeout=100');
  
  // Set a timeout for the entire request (100 seconds - longer than OpenAI timeout to account for processing)
  const requestTimeout = setTimeout(() => {
    if (!res.headersSent) {
      console.error('⏱️ Food analysis request timed out after 100 seconds');
      console.error('⏱️ Timeout occurred at:', Date.now() - requestStartTime, 'ms after request start');
      res.status(504).json({
        error: 'Request timeout',
        code: 'ANALYSIS_TIMEOUT',
        message: 'Food analysis took too long. Please try again.'
      });
    }
  }, 100000); // 100 seconds - gives buffer beyond OpenAI's 80s timeout
  
  try {
    // Log request details for debugging
    const contentType = req.get('Content-Type');
    if (process.env.NODE_ENV !== 'production') {
      console.log('🍎 Food analysis request received');
      console.log('📱 Request timestamp:', new Date().toISOString());
      console.log('📱 Content-Type:', contentType);
      console.log('📱 File info:', req.file ? {
        fieldname: req.file.fieldname,
        originalname: req.file.originalname,
        mimetype: req.file.mimetype,
        size: req.file.size
      } : 'No file');
    }
    
    // Check if Content-Type is correct
    if (!contentType || !contentType.includes('multipart/form-data')) {
      clearTimeout(requestTimeout);
      console.error('❌ Invalid Content-Type:', contentType);
      return res.status(400).json({
        error: 'Invalid Content-Type. Expected multipart/form-data',
        code: 'INVALID_CONTENT_TYPE',
        received: contentType
      });
    }
    
    if (!req.file) {
      clearTimeout(requestTimeout);
      console.log('❌ No image file provided');
      return res.status(400).json({ 
        error: 'No image provided',
        code: 'NO_IMAGE'
      });
    }

    // Process image with Sharp (resize, optimize)
    // Balance between quality and speed: 768x768 provides better accuracy while still being fast
    // Quality 80 maintains good image quality for accurate food recognition
    let processedImage;
    try {
      processedImage = await sharp(req.file.buffer)
        .resize(768, 768, { 
          fit: 'inside',
          withoutEnlargement: true
        })
        .jpeg({ 
          quality: 80, // Good balance between quality and file size
          mozjpeg: true // Use mozjpeg for better compression
        })
        .normalize() // Auto-adjust brightness/contrast to prevent "too dark" issues
        .toBuffer();
    } catch (sharpError) {
      clearTimeout(requestTimeout);
      console.error('❌ Sharp image processing error:', sharpError);
      if (sharpError.message && (sharpError.message.includes('Input buffer') || sharpError.message.includes('unsupported image format') || sharpError.message.includes('corrupt'))) {
        return res.status(400).json({
          error: 'Invalid image file',
          code: 'INVALID_IMAGE',
          message: 'The image file is corrupted or in an unsupported format. Please try a different image.'
        });
      }
      throw sharpError; // Re-throw to be caught by outer catch
    }

    // Convert to base64 for ChatGPT Vision
    const base64Image = processedImage.toString('base64');
    
    if (!base64Image || base64Image.length === 0) {
      clearTimeout(requestTimeout);
      console.error('❌ Failed to convert image to base64');
      return res.status(500).json({
        error: 'Image processing failed',
        code: 'IMAGE_CONVERSION_FAILED',
        message: 'Failed to process image. Please try again.'
      });
    }
    
    // Analyze with ChatGPT Vision
    const chatGPTStartTime = Date.now();
    console.log('🤖 Calling ChatGPT Vision API...');
    console.log('⏱️ Request elapsed so far:', chatGPTStartTime - requestStartTime, 'ms');
    console.log('📊 Base64 image size:', Math.round(base64Image.length / 1024), 'KB');
    
    let chatGPTResponse;
    try {
      chatGPTResponse = await chatGPTService.analyzeFoodImage(base64Image);
    } catch (chatGPTError) {
      clearTimeout(requestTimeout);
      console.error('❌ ChatGPT API error:', chatGPTError);
      // Re-throw to be handled by outer catch block
      throw chatGPTError;
    }
    
    const chatGPTElapsed = Date.now() - chatGPTStartTime;
    console.log(`✅ ChatGPT API call completed in ${chatGPTElapsed}ms`);
    console.log('⏱️ Total elapsed:', Date.now() - requestStartTime, 'ms');
    
    // Enhance with nutrition data
    let enhancedAnalysis;
    try {
      enhancedAnalysis = await nutritionService.enhanceWithNutritionData(chatGPTResponse);
    } catch (nutritionError) {
      // If nutrition enhancement fails, use the ChatGPT response directly
      console.error('⚠️ Nutrition enhancement failed, using ChatGPT response directly:', nutritionError);
      enhancedAnalysis = chatGPTResponse;
    }
    
    clearTimeout(requestTimeout);
    
    const totalElapsed = Date.now() - requestStartTime;
    if (process.env.NODE_ENV !== 'production') {
      console.log(`✅ Analysis complete in ${totalElapsed}ms`);
    }
    
    // Generate unique analysis ID
    const analysisId = uuidv4();
    
    res.json({
      success: true,
      analysisId,
      timestamp: new Date().toISOString(),
      analysis: enhancedAnalysis
    });

  } catch (error) {
    clearTimeout(requestTimeout);
    const elapsedTime = Date.now() - requestStartTime;
    console.error('❌ Error analyzing food:', error);
    console.error('❌ Error stack:', error.stack);
    console.error('❌ Error message:', error.message);
    console.error(`❌ Request failed after ${elapsedTime}ms`);
    
    // Check if response was already sent
    if (res.headersSent) {
      console.error('❌ Response already sent, cannot send error response');
      return;
    }
    
    // Handle specific error types
    if (error.message && error.message.includes('timed out')) {
      return res.status(504).json({
        error: 'Request timeout',
        code: 'ANALYSIS_TIMEOUT',
        message: 'Food analysis timed out. Please try again.'
      });
    }
    
    if (error.message && error.message.includes('Invalid file type')) {
      return res.status(400).json({
        error: 'Invalid file type',
        code: 'INVALID_FILE_TYPE',
        message: error.message
      });
    }
    
    if (error.message && error.message.includes('File too large')) {
      return res.status(400).json({
        error: 'File too large',
        code: 'FILE_TOO_LARGE',
        message: `Maximum file size is ${process.env.MAX_IMAGE_SIZE_MB || 10}MB`
      });
    }
    
    // Handle Sharp image processing errors (if not already handled)
    if (error.message && (error.message.includes('Input buffer') || error.message.includes('unsupported image format') || error.message.includes('corrupt'))) {
      return res.status(400).json({
        error: 'Invalid image file',
        code: 'INVALID_IMAGE',
        message: 'The image file is corrupted or in an unsupported format. Please try a different image.'
      });
    }
    
    if (error.message && error.message.includes('API key')) {
      return res.status(500).json({
        error: 'Server configuration error',
        code: 'API_KEY_ERROR',
        message: 'OpenAI API key is not configured correctly'
      });
    }
    
    // Generic error response with more details in development
    const errorMessage = process.env.NODE_ENV === 'production' 
      ? 'Failed to analyze food image'
      : error.message || 'Failed to analyze food image';
    
    res.status(500).json({
      error: 'Internal server error',
      code: 'ANALYSIS_FAILED',
      message: errorMessage
    });
  }
});

// Get nutrition suggestions endpoint
app.post('/api/nutrition-suggestions', jsonParser, async (req, res) => {
  try {
    const { foodItems, userGoals } = req.body;
    
    if (!foodItems || !Array.isArray(foodItems)) {
      return res.status(400).json({
        error: 'Invalid food items provided',
        code: 'INVALID_FOOD_ITEMS'
      });
    }
    
    const suggestions = await nutritionService.generateSuggestions(foodItems, userGoals);
    
    res.json({
      success: true,
      suggestions
    });
    
  } catch (error) {
    console.error('Error generating suggestions:', error);
    res.status(500).json({
      error: 'Failed to generate suggestions',
      code: 'SUGGESTIONS_FAILED'
    });
  }
});

// Estimate macros from food name endpoint
app.post('/api/estimate-macros', jsonParser, async (req, res) => {
  try {
    const { foodName } = req.body;
    
    if (!foodName || typeof foodName !== 'string' || foodName.trim().length === 0) {
      return res.status(400).json({
        error: 'Food name is required',
        code: 'INVALID_FOOD_NAME'
      });
    }
    
    if (process.env.NODE_ENV !== 'production') {
      console.log('🤖 Macro estimation request for:', foodName);
    }
    
    const estimate = await chatGPTService.estimateMacrosFromName(foodName.trim());
    
    res.json({
      success: true,
      estimate
    });
    
  } catch (error) {
    console.error('Error estimating macros:', error);
    
    if (error.message.includes('rate limit')) {
      return res.status(429).json({
        error: 'Rate limit exceeded',
        code: 'RATE_LIMITED',
        message: 'Too many requests. Please try again later.'
      });
    }
    
    if (error.message.includes('API key')) {
      return res.status(500).json({
        error: 'Server configuration error',
        code: 'API_KEY_ERROR',
        message: 'OpenAI API key is not configured correctly'
      });
    }
    
    res.status(500).json({
      error: 'Failed to estimate macros',
      code: 'ESTIMATION_FAILED',
      message: error.message
    });
  }
});

// Generate meal pattern summary endpoint
app.post('/api/pattern-summary', jsonParser, async (req, res) => {
  const requestStartTime = Date.now();
  
  // Set a timeout for the entire request (70 seconds - slightly longer than OpenAI timeout)
  const requestTimeout = setTimeout(() => {
    if (!res.headersSent) {
      console.error('⏱️ Pattern summary request timed out after 70 seconds');
      res.status(504).json({
        error: 'Request timeout',
        code: 'PATTERN_SUMMARY_TIMEOUT',
        message: 'Pattern summary generation took too long. Please try again.'
      });
    }
  }, 70000); // 70 seconds
  
  try {
    const { mealsToday } = req.body;
    
    if (process.env.NODE_ENV !== 'production') {
      console.log('📊 Pattern summary request received');
      console.log('📊 Meals count:', mealsToday?.length || 0);
      console.log('📊 Request timestamp:', new Date().toISOString());
    }
    
    if (!mealsToday || !Array.isArray(mealsToday)) {
      clearTimeout(requestTimeout);
      console.error('❌ Invalid meals data:', typeof mealsToday, mealsToday);
      return res.status(400).json({
        error: 'Invalid meals data provided',
        code: 'INVALID_MEALS_DATA'
      });
    }
    
    if (mealsToday.length === 0) {
      clearTimeout(requestTimeout);
      return res.status(400).json({
        error: 'No meals provided',
        code: 'NO_MEALS'
      });
    }
    
    if (process.env.NODE_ENV !== 'production') {
      console.log('📊 Calling patternSummaryService.generatePatternSummary...');
    }
    
    const summary = await patternSummaryService.generatePatternSummary(mealsToday);
    
    clearTimeout(requestTimeout);
    
    const elapsedTime = Date.now() - requestStartTime;
    if (process.env.NODE_ENV !== 'production') {
      console.log(`✅ Pattern summary generated successfully in ${elapsedTime}ms`);
    }
    
    res.json({
      success: true,
      summary
    });
    
  } catch (error) {
    clearTimeout(requestTimeout);
    const elapsedTime = Date.now() - requestStartTime;
    console.error('❌ Error generating pattern summary:', error);
    console.error('❌ Error message:', error.message);
    console.error('❌ Error stack:', error.stack);
    console.error(`❌ Request failed after ${elapsedTime}ms`);
    
    // Check if response was already sent
    if (res.headersSent) {
      console.error('❌ Response already sent, cannot send error response');
      return;
    }
    
    res.status(500).json({
      error: 'Failed to generate pattern summary',
      code: 'PATTERN_SUMMARY_FAILED',
      message: error.message
    });
  }
});

// Error handling middleware
app.use((error, req, res, next) => {
  console.error('❌ Unhandled error:', error);
  console.error('❌ Error message:', error.message);
  console.error('❌ Error stack:', error.stack);
  console.error('❌ Request Content-Type:', req.get('Content-Type'));
  
  if (error instanceof multer.MulterError) {
    console.error('❌ Multer error code:', error.code);
    if (error.code === 'LIMIT_FILE_SIZE') {
      return res.status(400).json({
        error: 'File too large',
        code: 'FILE_TOO_LARGE'
      });
    }
    // Handle other multer errors
    return res.status(400).json({
      error: 'File upload error',
      code: 'MULTER_ERROR',
      message: error.message
    });
  }
  
  // Handle busboy/multipart errors
  if (error.message && error.message.includes('Boundary not found')) {
    console.error('❌ Multipart boundary error - Content-Type may be incorrect');
    return res.status(400).json({
      error: 'Invalid request format',
      code: 'INVALID_MULTIPART',
      message: 'Multipart boundary not found. Check Content-Type header.'
    });
  }
  
  res.status(500).json({
    error: 'Internal server error',
    code: 'UNKNOWN_ERROR',
    message: process.env.NODE_ENV === 'production' ? undefined : error.message
  });
});

// 404 handler
app.use('*', (req, res) => {
  res.status(404).json({
    error: 'Endpoint not found',
    code: 'NOT_FOUND'
  });
});

// Start server with error handling
// Railway requires binding to 0.0.0.0, not just localhost
const server = app.listen(PORT, '0.0.0.0', () => {
  console.log(`🍎 Food Tracker Backend running on port ${PORT}`);
  console.log(`📊 Health check: http://0.0.0.0:${PORT}/health`);
  console.log(`🔍 Food analysis: http://0.0.0.0:${PORT}/api/analyze-food`);
  console.log(`🌍 Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`🔑 OpenAI API Key: ${process.env.OPENAI_API_KEY ? 'Set' : 'Missing'}`);
}).on('error', (error) => {
  console.error('❌ Failed to start server:', error);
  if (error.code === 'EADDRINUSE') {
    console.error(`Port ${PORT} is already in use`);
  }
  process.exit(1);
});

// Handle server errors
server.on('error', (error) => {
  console.error('❌ Server error:', error);
  if (error.code === 'EADDRINUSE') {
    console.error(`Port ${PORT} is already in use`);
  }
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('🛑 SIGTERM received, shutting down gracefully');
  server.close(() => {
    console.log('✅ Server closed');
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  console.log('🛑 SIGINT received, shutting down gracefully');
  server.close(() => {
    console.log('✅ Server closed');
    process.exit(0);
  });
});

module.exports = app;


