const OpenAI = require('openai');

class ChatGPTService {
  constructor() {
    this.openai = new OpenAI({
      apiKey: process.env.OPENAI_API_KEY,
      timeout: 80000, // 80 second timeout for OpenAI API calls (increased for image analysis)
      maxRetries: 2 // Retry up to 2 times on failure
    });
  }

  async analyzeFoodImage(base64Image) {
    try {
      // Reduced logging for production performance
      if (process.env.NODE_ENV !== 'production') {
        console.log('🤖 ChatGPT Service: Starting analysis...');
        console.log('🤖 Image size:', base64Image.length, 'characters');
      }
      
      const prompt = `
        Analyze this food image and provide detailed nutrition information. 
        
        Please identify:
        1. All food items visible in the image
        2. Estimated portion sizes
        3. Cooking methods (grilled, fried, raw, etc.)
        4. Nutritional content for each item
        
        CRITICAL FOR MIXED DISHES: When analyzing mixed dishes (e.g., pasta with vegetables, rice with protein, stir-fries), you MUST identify ALL components:
        - Base ingredients (pasta, rice, noodles, bread) even if partially hidden under sauce or vegetables
        - Vegetables and toppings
        - Sauces, oils, and cooking fats
        - Proteins (meat, fish, tofu, etc.)
        
        IMPORTANT: Estimate nutrition for the ENTIRE visible portion shown in the image. If you see multiple items of the same food (e.g., 2 eggs, 3 pancakes), estimate nutrition for ALL of them combined, not just one. Count items and multiply accordingly (e.g., if you see 2 scrambled eggs, estimate ~12g protein for both eggs, not just one egg).
        
        CALORIE VALIDATION: For complete dishes, ensure calorie estimates are realistic:
        - Pasta dishes (spaghetti, penne, fettuccine, etc.): Typically 300-500 calories for a medium portion
        - Rice dishes (fried rice, risotto, etc.): Typically 250-400 calories for a medium portion
        - Noodle dishes (ramen, stir-fried noodles): Typically 300-500 calories for a medium portion
        - If you detect a dish name containing "pasta", "rice", or "noodles" but calories are < 200, you are likely missing components - re-examine the image for hidden base ingredients
        
        For each food item, provide:
        - name: Clear, SPECIFIC food name with details including quantity when multiple items are visible (e.g., "pasta with broccoli" not just "broccoli", "2 scrambled eggs" not just "scrambled eggs", "3 pancakes" not just "pancake", "grilled chicken breast" not just "chicken"). Include color, preparation method, quantity, or other distinguishing features when visible. For mixed dishes, use descriptive names like "pasta with broccoli", "chicken fried rice", "stir-fried noodles with vegetables".
        - calories: Estimated calories for the ENTIRE visible portion of this food item (if multiple items, include all of them). For mixed dishes, include calories from ALL components (base + vegetables + protein + sauce).
        - protein: Protein in grams for the ENTIRE visible portion (if multiple items, include all of them)
        - carbs: Carbohydrates in grams for the ENTIRE visible portion. For pasta/rice/noodle dishes, carbs should reflect the base ingredient (typically 40-60g for medium portions).
        - fat: Fat in grams for the ENTIRE visible portion. Include cooking oils and fats.
        - fiber: Fiber in grams (if applicable) for the ENTIRE visible portion
        - serving_size: Estimated serving size description (e.g., "2 large eggs", "1 cup of rice", "3 pancakes", "1 plate of pasta with broccoli")
        - confidence: Your confidence level (0-1)
        - cooking_method: How the food appears to be prepared
        - ingredients: Array of ALL main ingredients detected (e.g., ["pasta", "broccoli", "olive oil"] for pasta with broccoli, not just ["broccoli"]). Include base ingredients even if partially visible.
        - portion_size: Estimated portion size as "small", "medium", or "large" based on visual appearance and quantity
        - macro_guess: Primary macronutrient appearance as "carb-heavy", "protein-rich", "fat-heavy", or "balanced" based on visual characteristics
        
        CRITICAL: You MUST return ONLY a valid JSON object. Do NOT include any text before or after the JSON. Do NOT explain why you can't analyze the image. Even if the image is unclear, dark, or you cannot identify food items, you MUST still return valid JSON with empty or default values.
        
        Return the response as a JSON object with this EXACT structure:
        {
          "foods": [
            {
              "name": "string",
              "calories": number,
              "protein": number,
              "carbs": number,
              "fat": number,
              "fiber": number,
              "serving_size": "string",
              "confidence": number,
              "cooking_method": "string",
              "ingredients": ["string"],
              "portion_size": "small" | "medium" | "large",
              "macro_guess": "carb-heavy" | "protein-rich" | "fat-heavy" | "balanced"
            }
          ],
          "overall_confidence": number,
          "image_description": "string",
          "suggestions": ["string"]
        }
        
        If the image is too dark, unclear, or you cannot identify any food items:
        - Return foods as an empty array: []
        - Set overall_confidence to 0.1
        - Set image_description to describe why analysis failed (e.g., "Image too dark to identify food items")
        - Set suggestions to helpful tips (e.g., ["Try taking a clearer photo with better lighting"])
        - Still return valid JSON - never return plain text
        
        Be as accurate as possible with nutrition estimates. Count all visible items and estimate nutrition for the complete portion shown, not just a single serving.
        
        REMEMBER: For mixed dishes, always look for the complete dish, not just individual ingredients. If you see vegetables on pasta, estimate calories for BOTH the pasta AND the vegetables. If you see protein on rice, estimate calories for BOTH the rice AND the protein. Complete dishes should have complete calorie estimates.
      `;

      if (process.env.NODE_ENV !== 'production') {
        console.log('🤖 Calling OpenAI API...');
      }
      
      const startTime = Date.now();
      
      // Add timeout wrapper for OpenAI API call (85 seconds - gives buffer for network delays)
      // The OpenAI client has an 80s timeout, but Promise.race ensures we catch timeouts reliably
      const timeoutMs = 85000; // 85 seconds timeout
      const timeoutPromise = new Promise((_, reject) => {
        setTimeout(() => {
          const elapsed = Date.now() - startTime;
          console.error(`⏱️ ChatGPT API timeout after ${elapsed}ms (limit: ${timeoutMs}ms)`);
          reject(new Error('OpenAI API request timed out after 85 seconds'));
        }, timeoutMs);
      });
      
      const apiCallPromise = this.openai.chat.completions.create({
        model: "gpt-4o",
        messages: [
          {
            role: "user",
            content: [
              {
                type: "text",
                text: prompt
              },
              {
                type: "image_url",
                image_url: {
                  url: `data:image/jpeg;base64,${base64Image}`,
                  detail: "auto" // Use "auto" for better accuracy (ChatGPT decides optimal detail level)
                }
              }
            ]
          }
        ],
        max_tokens: 1500, // Increased for more detailed responses
        temperature: 0.3, // Slightly higher for better food recognition
        response_format: { type: "json_object" } // CRITICAL: Force JSON response format
      });
      
      const response = await Promise.race([apiCallPromise, timeoutPromise]);
      
      const elapsedTime = Date.now() - startTime;
      if (process.env.NODE_ENV !== 'production') {
        console.log(`✅ OpenAI API call completed in ${elapsedTime}ms`);
      }
      
      const content = response.choices[0].message.content;
      
      if (process.env.NODE_ENV !== 'production') {
        console.log('🤖 OpenAI API response received');
        console.log('🤖 Response length:', content ? content.length : 0);
      }
      
      // Parse JSON response
      // Since we're using response_format: { type: "json_object" }, response should be valid JSON
      let analysis;
      try {
        // Try direct JSON parse first (since we're forcing JSON format)
        let jsonContent = content.trim();
        
        // Remove any markdown code blocks if present (safety net)
        if (jsonContent.startsWith('```')) {
          jsonContent = jsonContent.replace(/^```json\s*/, '').replace(/^```\s*/, '').replace(/\s*```$/, '');
        }
        
        // Extract JSON if there's any extra text (safety net)
        const jsonMatch = jsonContent.match(/\{[\s\S]*\}/);
        if (jsonMatch) {
          analysis = JSON.parse(jsonMatch[0]);
          
          // Add IDs to foods if they don't have them
          // Also ensure optional fields have defaults
          if (analysis.foods && Array.isArray(analysis.foods)) {
            analysis.foods = analysis.foods.map((food, index) => ({
              id: food.id || `food_${Date.now()}_${index}`,
              ingredients: food.ingredients || [],
              portion_size: food.portion_size || 'medium',
              macro_guess: food.macro_guess || 'balanced',
              ...food
            }));
          }
          
          // Convert snake_case to camelCase for iOS compatibility
          if (analysis.overall_confidence !== undefined) {
            analysis.overallConfidence = analysis.overall_confidence;
            delete analysis.overall_confidence;
          }
          if (analysis.image_description !== undefined) {
            analysis.imageDescription = analysis.image_description;
            delete analysis.image_description;
          }
          
          // Process foods array
          if (analysis.foods && Array.isArray(analysis.foods)) {
            analysis.foods = analysis.foods.map(food => {
              return food;
            });
          }
        } else {
          throw new Error('No JSON found in response');
        }
      } catch (parseError) {
        console.error('Error parsing ChatGPT response:', parseError);
        console.error('Raw response:', content);
        
        // Fallback: create a basic response
        analysis = {
          foods: [{
            id: `food_${Date.now()}_0`, // Add unique ID
            name: "Unidentified Food",
            calories: 0,
            protein: 0,
            carbs: 0,
            fat: 0,
            fiber: 0,
            serving_size: "Unknown",
            confidence: 0.1,
            cooking_method: "Unknown",
            ingredients: []
          }],
          overallConfidence: 0.1,
          imageDescription: "Unable to analyze image",
          suggestions: ["Try taking a clearer photo with better lighting"]
        };
        
        // Process fallback response
        if (analysis.foods && Array.isArray(analysis.foods)) {
          analysis.foods = analysis.foods.map(food => {
            return food;
          });
        }
      }

      return analysis;

    } catch (error) {
      console.error('❌ ChatGPT API Error:', error);
      console.error('❌ Error message:', error.message);
      console.error('❌ Error stack:', error.stack);
      
      // Handle timeout errors specifically
      if (error.message && error.message.includes('timed out')) {
        console.error('⏱️ OpenAI API request timed out');
        throw new Error('OpenAI API request timed out. The image analysis is taking too long. Please try again.');
      }
      
      if (error.status === 401) {
        throw new Error('Invalid OpenAI API key');
      } else if (error.status === 429) {
        throw new Error('OpenAI API rate limit exceeded');
      } else if (error.status === 400) {
        throw new Error('Invalid request to OpenAI API');
      } else {
        throw new Error(`OpenAI API error: ${error.message}`);
      }
    }
  }

  async getNutritionAdvice(foodItems, userGoals) {
    try {
      const prompt = `
        Based on these food items and user goals, provide personalized nutrition advice:
        
        Food Items: ${JSON.stringify(foodItems)}
        User Goals: ${JSON.stringify(userGoals)}
        
        Provide:
        1. Overall nutrition assessment
        2. Suggestions for improvement
        3. Meal timing recommendations
        4. Portion size advice
        5. Health tips
        
        Return as JSON with fields: assessment, suggestions, meal_timing, portion_advice, health_tips
      `;

      const response = await this.openai.chat.completions.create({
        model: "gpt-4",
        messages: [
          {
            role: "user",
            content: prompt
          }
        ],
        max_tokens: 1000,
        temperature: 0.4
      });

      return JSON.parse(response.choices[0].message.content);

    } catch (error) {
      console.error('Error getting nutrition advice:', error);
      throw new Error('Failed to generate nutrition advice');
    }
  }

  async estimateMacrosFromName(foodName) {
    try {
      if (process.env.NODE_ENV !== 'production') {
        console.log('🤖 Estimating macros for:', foodName);
      }

      const prompt = `
        Estimate the typical nutritional information for this food item: "${foodName}"
        
        Provide accurate estimates based on standard serving sizes and typical preparation methods.
        Consider common variations (e.g., if it's a restaurant item like "Chipotle sofritas burrito", estimate based on typical restaurant portions).
        
        Return ONLY a JSON object with this exact structure:
        {
          "name": "${foodName}",
          "calories": number,
          "protein": number,
          "carbs": number,
          "fat": number,
          "fiber": number,
          "sugar": number,
          "sodium": number,
          "serving_size": "string describing typical serving",
          "confidence": number (0-1)
        }
        
        Important:
        - All macro values should be numbers (grams for protein, carbs, fat, fiber, sugar; mg for sodium)
        - Use realistic estimates based on typical serving sizes
        - For restaurant items, estimate based on standard restaurant portions
        - Confidence should reflect how certain you are about the estimate (0.9+ for common foods, 0.7-0.8 for specific restaurant items)
        - Return ONLY the JSON object, no additional text
      `;

      const startTime = Date.now();
      
      // Add timeout wrapper for OpenAI API call (60 seconds for text-only requests)
      const timeoutMs = 60000; // 60 seconds timeout
      const timeoutPromise = new Promise((_, reject) => {
        setTimeout(() => reject(new Error('OpenAI API request timed out after 60 seconds')), timeoutMs);
      });
      
      const apiCallPromise = this.openai.chat.completions.create({
        model: "gpt-4o",
        messages: [
          {
            role: "user",
            content: prompt
          }
        ],
        max_tokens: 500,
        temperature: 0.2, // Lower temperature for more consistent estimates
        response_format: { type: "json_object" } // Force JSON response format
      });
      
      const response = await Promise.race([apiCallPromise, timeoutPromise]);
      
      const elapsedTime = Date.now() - startTime;
      if (process.env.NODE_ENV !== 'production') {
        console.log(`✅ OpenAI API call completed in ${elapsedTime}ms`);
      }

      const content = response.choices[0].message.content.trim();
      
      if (process.env.NODE_ENV !== 'production') {
        console.log('🤖 Raw ChatGPT response:', content);
      }

      // Parse JSON response
      let estimate;
      try {
        // Extract JSON from response (in case there's extra text)
        const jsonMatch = content.match(/\{[\s\S]*\}/);
        if (jsonMatch) {
          estimate = JSON.parse(jsonMatch[0]);
        } else {
          throw new Error('No JSON found in response');
        }
      } catch (parseError) {
        console.error('Error parsing ChatGPT response:', parseError);
        console.error('Raw response:', content);
        throw new Error('Failed to parse macro estimate response');
      }

      // Ensure all required fields are present with defaults
      return {
        name: estimate.name || foodName,
        calories: estimate.calories || 0,
        protein: estimate.protein || 0,
        carbs: estimate.carbs || 0,
        fat: estimate.fat || 0,
        fiber: estimate.fiber || 0,
        sugar: estimate.sugar || 0,
        sodium: estimate.sodium || 0,
        serving_size: estimate.serving_size || "1 serving",
        confidence: estimate.confidence || 0.7
      };

    } catch (error) {
      console.error('❌ ChatGPT API Error (estimate macros):', error);
      console.error('❌ Error message:', error.message);
      console.error('❌ Error stack:', error.stack);
      
      // Handle timeout errors specifically
      if (error.message && error.message.includes('timed out')) {
        console.error('⏱️ OpenAI API request timed out');
        throw new Error('OpenAI API request timed out. Please try again.');
      }
      
      if (error.status === 401) {
        throw new Error('Invalid OpenAI API key');
      } else if (error.status === 429) {
        throw new Error('OpenAI API rate limit exceeded');
      } else if (error.status === 400) {
        throw new Error('Invalid request to OpenAI API');
      } else {
        throw new Error(`OpenAI API error: ${error.message}`);
      }
    }
  }
}

module.exports = new ChatGPTService();

