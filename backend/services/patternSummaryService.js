const OpenAI = require('openai');

class PatternSummaryService {
  constructor() {
    this.openai = new OpenAI({
      apiKey: process.env.OPENAI_API_KEY,
      timeout: 60000, // 60 second timeout for all API calls
      maxRetries: 2 // Retry up to 2 times on failure
    });
  }

  async generatePatternSummary(mealsToday) {
    try {
      if (process.env.NODE_ENV !== 'production') {
        console.log('📊 Pattern Summary Service: Generating summary for', mealsToday.length, 'meals');
        console.log('📊 Starting OpenAI API call...');
      }
      
      const startTime = Date.now();

      // Build the input data for GPT
      // Handle both camelCase (from Swift) and snake_case formats
      const mealsData = mealsToday.map(meal => {
        const mealData = {
          timestamp: meal.timestamp,
          detected_ingredients: meal.ingredients || meal.detected_ingredients || [],
          cuisine_guess: meal.cuisine || meal.cuisine_guess || null,
          portion_size_estimate: meal.portionSize || meal.portion_size_estimate || 'medium',
          meal_type_guess: meal.mealType || meal.meal_type_guess || 'snack',
          calories: meal.calories || 0,
          carbs: meal.carbs || 0,
          protein: meal.protein || 0,
          fat: meal.fat || 0
        };
        // Only include location if it's actually provided (not defaulted to 'home')
        if (meal.location && meal.location !== 'home') {
          mealData.location = meal.location;
        }
        return mealData;
      });

      // Extract patterns from the data
      const patterns = this.extractPatterns(mealsToday);
      
      // Format timestamps in local time for display
      // Extract time directly from ISO8601 string to preserve original timezone
      const formattedMealsData = mealsData.map(meal => {
        const formatted = { ...meal };
        if (meal.timestamp) {
          try {
            const timestampStr = meal.timestamp;
            // Extract time from ISO8601 format: YYYY-MM-DDTHH:MM:SS[.SSS][Z|±HH:MM]
            // Match the time portion (HH:MM:SS)
            const timeMatch = timestampStr.match(/T(\d{2}):(\d{2}):(\d{2})/);
            if (timeMatch) {
              let hours = parseInt(timeMatch[1], 10);
              const minutes = parseInt(timeMatch[2], 10);
              
              const ampm = hours >= 12 ? 'PM' : 'AM';
              const displayHours = hours % 12 || 12;
              const displayMinutes = minutes.toString().padStart(2, '0');
              formatted.timestamp_display = `${displayHours}:${displayMinutes} ${ampm}`;
            }
          } catch (e) {
            // Keep original if parsing fails
            console.error('Error formatting timestamp:', e);
          }
        }
        return formatted;
      });

      const prompt = `You are generating a daily eating pattern summary for a food-tracking app. Your goal is to identify INTERESTING, MEANINGFUL patterns and trends that would be genuinely insightful to the user.

The summary must be 100% descriptive and must NOT give advice, evaluations, nutrition judgments, recommendations, or health conclusions. It must remain fully App-Store–safe under guideline 1.4.1, meaning: 

- No statements about what the user should eat. 
- No statements about healthiness, diet quality, risks, or medical impact. 
- No nutritional judgments (e.g., "too much sugar," "high-fat meal," "unhealthy," "better choices"). 
- Only objective observations, patterns, frequencies, and comparisons.

IMPORTANT NOTES ABOUT THE DATA:
- Each entry in "Food items logged today" represents a FOOD ITEM, not a separate meal session
- If meal_type_distribution shows "lunch: 2", this means 2 food items were logged for lunch, not 2 separate lunch meals
- Only mention location if it's explicitly provided in the data (don't assume "home" if not specified)
- Use timestamp_display for time references (it's in the user's local timezone)
- Use second person ("you", "your") when addressing the user, not third person ("the user", "their")

INPUT YOU WILL RECEIVE:

Food items logged today:
${JSON.stringify(formattedMealsData, null, 2)}

Extracted patterns:
${JSON.stringify(patterns, null, 2)}

IMPORTANT: The patterns object includes:
- meal_type_macro_distribution: Shows protein/carbs/fat for each meal type (breakfast, lunch, dinner, snack)
- total_macros: Shows the TOTAL protein/carbs/fat across ALL meal types - use this for total consumption statements
- meal_type_distribution: Shows count of food items per meal type

CRITICAL: When stating total protein/carbs/fat consumed, ALWAYS use total_macros.protein, total_macros.carbs, or total_macros.fat. Do NOT add up meal_type_macro_distribution values yourself, as this can lead to errors if meal types are missing or incorrectly categorized.

TASK:

Using ONLY the provided data, produce INTERESTING and INSIGHTFUL observations:

1. A concise 3–6 bullet "Today's Eating Pattern Summary" that highlights MEANINGFUL patterns, trends, and comparisons. Focus on:
   - Timing patterns (early/late food items, gaps between eating occasions, eating frequency)
   - Size comparisons (which meal TYPE was largest - breakfast, lunch, dinner, or snack - based on total calories for that meal type)
   - Macro patterns (which macronutrient had the most grams/calories in your day, distribution across eating occasions - use actual numbers like "protein accounted for 40% of your total calories" or "you consumed 120g of carbs". IMPORTANT: If a bullet point mentions calories from macros (protein, carbs, or fat), it MUST end with "(estimated)". Other bullet points should NOT include "(estimated)".)
   - Meal type calorie distribution (what percentage of your TOTAL daily calories came from each meal type - e.g., "60% of your total calories came from dinner")
   - Any notable patterns or outliers
   
   IMPORTANT LANGUAGE RULES:
   - Use "food item" or "eating occasion" instead of "meal" when referring to snacks or when the meal type is unclear
   - Only use "meal" when specifically referring to breakfast, lunch, or dinner
   - Use "latest food item" or "last eating occasion" instead of "latest meal" when it could be a snack
   - Use "first food item" or "first eating occasion" instead of "first meal" when it could be a snack
   
   CRITICAL: When identifying the "largest meal", you MUST use the meal TYPE (breakfast/lunch/dinner/snack) with the most TOTAL calories, NOT the largest single food item. The patterns data includes "largest_meal_type" which explicitly shows which meal type has the most calories - USE THIS DATA. ONLY ONE meal type can be the largest - do NOT say multiple meal types were the largest.
   - ALWAYS check the "largest_meal_type" field in the patterns data to determine which meal type is largest
   - CORRECT: "Breakfast was your largest meal, accounting for 45% of your total calories" (if largest_meal_type shows breakfast)
   - WRONG: "Breakfast was your largest meal" AND "Dinner was your largest meal" (both cannot be true - only one meal type can have the most calories)
   - WRONG: Referring to the largest single food item (largest_portion) as "largest meal" - use meal TYPE totals (largest_meal_type) instead
   - ABSOLUTELY FORBIDDEN: Do NOT mention portion size (small/medium/large) when discussing the largest meal or largest food item. Portion size is NOT a food item and should NOT be mentioned in relation to "largest" anything. For example:
     * WRONG: "Breakfast accounted for 38% of your total daily calories, with a medium portion size being the largest single food item logged"
     * CORRECT: "Breakfast accounted for 38% of your total daily calories" (stop there - don't mention portion size or individual food items)
   - DO NOT combine statements about meal type calorie distribution with statements about individual food items or portion sizes in the same bullet point
   
   IMPORTANT: When talking about calorie distribution by meal type, always refer to the percentage of TOTAL daily calories, not calories within a meal type. For example:
   - CORRECT: "60% of your total calories came from dinner" (meaning dinner items accounted for 60% of all calories logged today)
   - WRONG: "you got more than half of your dinner calories from a dinner item" (this doesn't make sense - all dinner items are part of dinner)
   
   CRITICAL: When discussing which meal type contributed the most protein, carbs, or fat, you MUST use the meal_type_macro_distribution data provided in the patterns. Do NOT infer or calculate this yourself - use the exact values from meal_type_macro_distribution. For example:
   - CORRECT: "Snacks provided the most protein at [meal_type_macro_distribution.snack.protein]g" (if meal_type_macro_distribution shows snack has the most protein)
   - CORRECT: "Breakfast contributed [meal_type_macro_distribution.breakfast.protein]g of protein" (use exact values from data)
   - WRONG: Inferring which meal type has the most protein without checking meal_type_macro_distribution - always use the provided data
   - WRONG: Saying "breakfast contributed the majority of protein" when meal_type_macro_distribution shows snacks have more protein
   - ALWAYS check meal_type_macro_distribution to see which meal type has the highest protein/carbs/fat values before making statements about which meal type contributed the most
   
   CRITICAL: When stating the TOTAL amount of protein, carbs, or fat consumed, you MUST use the total_macros data provided in the patterns. The total_macros field shows the sum across ALL meal types. For example:
   - CORRECT: "You consumed a total of [total_macros.protein]g of protein" (use the exact value from total_macros.protein)
   - CORRECT: "You consumed [total_macros.carbs]g of carbs today"
   - WRONG: Adding up meal_type_macro_distribution values yourself - always use total_macros for totals
   - WRONG: Saying "You consumed 46.5g of protein" when total_macros.protein shows 52.5g - you MUST use the exact value from total_macros
   
   IMPORTANT: When discussing macronutrients, use actual numbers (grams, percentages of total calories) rather than classifications like "carb heavy" or "balanced". For example:
   - CORRECT: "Protein accounted for 35% of your total calories (estimated)" or "You consumed 150g of carbs today"
   - CORRECT: "Carbs provided 288 calories from 72g (estimated)"
   - CORRECT: "You consumed 20g of protein providing 80 calories (estimated)"
   - WRONG: "Most of your meals were carb-heavy" or "5 meals were balanced"
   - CRITICAL: If a bullet point mentions CALORIES from macros (protein, carbs, or fat), it MUST end with "(estimated)". Bullet points that only mention grams or percentages without calories should NOT include "(estimated)".
   
   DO NOT mention specific ingredients, food names, individual food items, or portion sizes (small/medium/large). Focus on patterns, timing, meal type sizes (breakfast/lunch/dinner/snack totals), and macro distribution (using actual numbers) instead.
   - Portion size (small/medium/large) is NOT a meaningful pattern and should NEVER be mentioned
   - Do NOT say things like "medium portion size" or "largest portion size" - these are not insights
   - Focus on meal TYPE totals, not individual food item attributes

2. A single, compelling sentence (the "overall" insight) that synthesizes the MOST INTERESTING pattern from the day. This should be the "aha moment" - the one thing that stands out most about today's eating pattern when looking at the patterns within today's data. Use second person.

CRITICAL REQUIREMENTS FOR THE "OVERALL" INSIGHT:
- It must SYNTHESIZE multiple patterns, not just restate a single bullet point
- It should connect dots between timing, calorie distribution, macros, or meal sizes to reveal something meaningful
- It should feel like a genuine insight that makes the user think "hmm, interesting!"
- Avoid generic statements - be specific with numbers and comparisons
- Make it thought-provoking but still descriptive (no advice)

WHAT MAKES AN INSIGHT INTERESTING AND SYNTHESIZED:
- GOOD: "Your eating pattern shifted dramatically today, with 70% of calories coming in the evening after a light morning start" (connects timing + calorie distribution)
- GOOD: "You front-loaded your day with protein, getting 50% of your daily protein before noon while keeping breakfast calories minimal" (connects timing + macro distribution + meal size)
- GOOD: "Despite having 5 eating occasions, dinner alone accounted for more calories than all your other meals combined" (connects frequency + calorie distribution)
- GOOD: "Your eating occasions clustered tightly in a 4-hour window, with evenly spaced meals that were surprisingly similar in size" (connects timing pattern + meal size consistency)
- GOOD: "Carbs dominated your macro intake at 55% of total calories, with most of that coming from your afternoon eating occasions" (connects macro distribution + timing)
- BAD: "You had breakfast, lunch, and dinner" (just listing facts - not insightful)
- BAD: "You logged 3 food items today" (obvious fact - not a pattern)
- BAD: "Your first food item was at 8am" (single fact - not synthesized)
- BAD: "You consumed calories throughout the day" (too generic - everyone does this)

WHAT MAKES AN INSIGHT INTERESTING (for reference):
- Comparisons: "Dinner was 3x larger than breakfast" (comparing meal TYPE totals, not just "you had dinner")
- Patterns: "You ate 4 times between 8am and 2pm, then nothing until 7pm" (not just "first food item at 8am")
- Trends: "Protein accounted for 40% of your total calories (estimated)" (not just "you had protein" or "protein-rich foods") - note the "(estimated)" suffix when mentioning macro calories
- Timing insights: "Your eating occasions were evenly spaced 4 hours apart" or "Your meals were evenly spaced 4 hours apart" (use "meals" only if all items are breakfast/lunch/dinner, otherwise use "eating occasions")
- Calorie distribution: "60% of your total calories came from dinner" (meaning dinner items accounted for 60% of all calories logged today - NOT about calories within dinner)
- Largest meal: "Breakfast was your largest meal, accounting for 45% of your total calories" (use the meal TYPE with the most total calories from the data - only ONE can be largest)
- Macro insights: Use actual numbers like "You consumed 120g of carbs, 80g of protein, and 60g of fat" or "Carbs made up 50% of your total calories (estimated)" - add "(estimated)" ONLY when mentioning calories from macros

AVOID BORING OBSERVATIONS:
- Don't just list what happened: "You had lunch at 1:16pm" is boring
- Don't state the obvious: "You logged 2 food items for lunch" is not insightful
- Don't repeat basic facts: Focus on patterns, comparisons, and trends instead
- DO NOT mention specific ingredients, food names, or individual food items - this is confusing and not insightful
- Focus on patterns, timing, calorie distribution, and macro trends instead of listing foods

RULES:

- Do NOT use any evaluative words like "healthy," "unhealthy," "balanced," "better," "worse," "should," "avoid," or anything implying advice.
- Do NOT classify meals or foods as "carb heavy," "protein-rich," "fat-heavy," "balanced," or any other macro classification. These are judgments.
- When discussing macronutrients, use actual numbers (grams, percentages) from the data, not classifications. For example:
  - CORRECT: "Protein accounted for 35% of your total calories (estimated)" or "You consumed 150g of carbs"
  - CORRECT: "Carbs provided 288 calories from 72g (estimated)"
  - WRONG: "Most meals were carb-heavy" or "5 meals were balanced"
  - CRITICAL: If a bullet point mentions CALORIES from macros (protein, carbs, or fat), it MUST end with "(estimated)". Bullet points that only mention grams or percentages without calories should NOT include "(estimated)".
- ONLY describe what can be directly inferred from the input data.
- Focus on INTERESTING patterns, comparisons, and trends - not just basic facts.
- If data is incomplete or minimal, still produce insightful observations based on what is available.
- Stay neutral, factual, and helpful.
- Make it feel intelligent and insightful but never prescriptive or judgmental.
- Always use second person ("you", "your") instead of third person ("the user", "their").
- Prioritize meaningful insights over trivial details.

FORMAT:

Return exactly this JSON structure:
{
  "summary": "Today's Eating Pattern",
  "bullets": [
    "bullet 1",
    "bullet 2",
    "bullet 3",
    "bullet 4"
  ],
  "overall": "A single synthesized insight sentence that connects multiple patterns"
}

IMPORTANT: The "overall" field is displayed prominently at the bottom of the summary. It should be the MOST insightful observation that synthesizes patterns from the bullets above. Think of it as the key takeaway - what's the one thing that stands out most about today's eating pattern when looking at the patterns within today's data? Focus on distinctive patterns, notable contrasts, or interesting relationships between timing, calorie distribution, macros, or meal sizes that appear in today's data. It should NOT just repeat a bullet point, but rather connect multiple insights together to reveal something meaningful about the day's pattern.

Ensure the bullets are interesting, descriptive, and based on the actual data provided.`;

      // Add timeout wrapper for OpenAI API call
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
        max_tokens: 1000,
        temperature: 0.3,
        response_format: { type: "json_object" } // Force JSON response
      });
      
      const response = await Promise.race([apiCallPromise, timeoutPromise]);
      
      const elapsedTime = Date.now() - startTime;
      if (process.env.NODE_ENV !== 'production') {
        console.log(`✅ OpenAI API call completed in ${elapsedTime}ms`);
        console.log('📊 Response received, parsing JSON...');
      }

      const content = response.choices[0].message.content;
      
      // Parse JSON response
      let summary;
      try {
        const jsonMatch = content.match(/\{[\s\S]*\}/);
        if (jsonMatch) {
          summary = JSON.parse(jsonMatch[0]);
        } else {
          throw new Error('No JSON found in response');
        }
      } catch (parseError) {
        console.error('Error parsing pattern summary response:', parseError);
        // Fallback summary
        summary = {
          summary: "Today's Eating Pattern",
          bullets: [
            "No patterns detected yet",
            "Continue logging meals to see insights"
          ],
          overall: "Start tracking your meals to see eating patterns emerge."
        };
      }

      return summary;

    } catch (error) {
      console.error('❌ Pattern Summary Service Error:', error);
      console.error('❌ Error message:', error.message);
      console.error('❌ Error stack:', error.stack);
      
      // Check for specific error types
      if (error.message && error.message.includes('timeout')) {
        console.error('⏱️ OpenAI API request timed out');
      } else if (error.message && error.message.includes('API key')) {
        console.error('🔑 OpenAI API key error - check your .env file');
      } else if (error.code === 'ECONNREFUSED' || error.code === 'ENOTFOUND') {
        console.error('🌐 Network error - cannot reach OpenAI API');
      }
      
      // Return a safe fallback
      return {
        summary: "Today's Eating Pattern",
        bullets: [
          "Unable to generate pattern summary",
          "Please try again later"
        ],
        overall: "Pattern analysis is currently unavailable."
      };
    }
  }

  extractPatterns(meals) {
    if (!meals || meals.length === 0) {
      return {};
    }

    const patterns = {
      first_food_time: null,
      latest_food_time: null,
      largest_portion: null,
      ingredient_frequency: {},
      meal_type_distribution: {},
      // Note: location_distribution only included if actual location data exists
      location_distribution: {}
    };

    // Find first and latest food item times
    const sortedByTime = meals.sort((a, b) => 
      new Date(a.timestamp) - new Date(b.timestamp)
    );
    if (sortedByTime.length > 0) {
      // Extract time directly from ISO8601 string to preserve original timezone
      const formatTime = (timestampStr) => {
        try {
          // Extract time from ISO8601 format: YYYY-MM-DDTHH:MM:SS[.SSS][Z|±HH:MM]
          const timeMatch = timestampStr.match(/T(\d{2}):(\d{2}):(\d{2})/);
          if (timeMatch) {
            let hours = parseInt(timeMatch[1], 10);
            const minutes = parseInt(timeMatch[2], 10);
            
            const ampm = hours >= 12 ? 'PM' : 'AM';
            const displayHours = hours % 12 || 12;
            const displayMinutes = minutes.toString().padStart(2, '0');
            return `${displayHours}:${displayMinutes} ${ampm}`;
          }
          return 'Unknown';
        } catch (e) {
          return 'Unknown';
        }
      };
      patterns.first_food_time = formatTime(sortedByTime[0].timestamp);
      patterns.latest_food_time = formatTime(sortedByTime[sortedByTime.length - 1].timestamp);
    }

    // Find largest portion (by calories)
    const largestMeal = meals.reduce((max, meal) => 
      (meal.calories || 0) > (max.calories || 0) ? meal : max, meals[0]
    );
    if (largestMeal) {
      patterns.largest_portion = {
        meal_type: largestMeal.mealType || largestMeal.meal_type_guess || 'snack',
        calories: largestMeal.calories || 0,
        portion_size: largestMeal.portionSize || largestMeal.portion_size_estimate || 'medium'
      };
    }

    // Count ingredient frequency
    meals.forEach(meal => {
      const ingredients = meal.ingredients || meal.detected_ingredients || [];
      if (Array.isArray(ingredients) && ingredients.length > 0) {
        ingredients.forEach(ingredient => {
          patterns.ingredient_frequency[ingredient] = 
            (patterns.ingredient_frequency[ingredient] || 0) + 1;
        });
      }
    });

    // Count meal type distribution (counts food items, not separate meals)
    const mealTypeCalories = {};
    const mealTypeCounts = {};
    const mealTypeProtein = {}; // Track protein by meal type
    const mealTypeCarbs = {}; // Track carbs by meal type
    const mealTypeFat = {}; // Track fat by meal type
    let totalCalories = 0;
    let totalProtein = 0; // Track total protein across all meals
    let totalCarbs = 0; // Track total carbs across all meals
    let totalFat = 0; // Track total fat across all meals
    
    meals.forEach(meal => {
      // Handle both camelCase (from Swift) and snake_case formats
      const mealType = (meal.mealType || meal.meal_type_guess || 'snack').toLowerCase();
      const calories = meal.calories || 0;
      const protein = meal.protein || 0;
      const carbs = meal.carbs || 0;
      const fat = meal.fat || 0;
      
      // Debug logging to help identify issues
      if (process.env.NODE_ENV !== 'production') {
        console.log(`📊 Processing meal: mealType="${mealType}", protein=${protein}g, calories=${calories}`);
      }
      
      mealTypeCounts[mealType] = (mealTypeCounts[mealType] || 0) + 1;
      mealTypeCalories[mealType] = (mealTypeCalories[mealType] || 0) + calories;
      mealTypeProtein[mealType] = (mealTypeProtein[mealType] || 0) + protein;
      mealTypeCarbs[mealType] = (mealTypeCarbs[mealType] || 0) + carbs;
      mealTypeFat[mealType] = (mealTypeFat[mealType] || 0) + fat;
      totalCalories += calories;
      totalProtein += protein;
      totalCarbs += carbs;
      totalFat += fat;
    });
    
    patterns.meal_type_distribution = mealTypeCounts;
    
    // Calculate macro distribution by meal type
    patterns.meal_type_macro_distribution = {};
    Object.keys(mealTypeProtein).forEach(mealType => {
      patterns.meal_type_macro_distribution[mealType] = {
        protein: Math.round(mealTypeProtein[mealType] * 10) / 10,
        carbs: Math.round(mealTypeCarbs[mealType] * 10) / 10,
        fat: Math.round(mealTypeFat[mealType] * 10) / 10,
        calories: mealTypeCalories[mealType] || 0
      };
    });
    
    // Add total macros to patterns so AI can use accurate totals
    patterns.total_macros = {
      protein: Math.round(totalProtein * 10) / 10,
      carbs: Math.round(totalCarbs * 10) / 10,
      fat: Math.round(totalFat * 10) / 10,
      calories: totalCalories
    };
    
    // Debug logging
    if (process.env.NODE_ENV !== 'production') {
      console.log('📊 Meal type macro distribution:', JSON.stringify(patterns.meal_type_macro_distribution, null, 2));
      console.log('📊 Total macros:', JSON.stringify(patterns.total_macros, null, 2));
    }
    
    // Calculate calorie distribution by meal type (as percentage of total)
    patterns.meal_type_calorie_distribution = {};
    if (totalCalories > 0) {
      Object.keys(mealTypeCalories).forEach(mealType => {
        const percentage = Math.round((mealTypeCalories[mealType] / totalCalories) * 100);
        patterns.meal_type_calorie_distribution[mealType] = {
          calories: mealTypeCalories[mealType],
          percentage: percentage
        };
      });
      
      // Find the meal type with the most total calories (largest meal type)
      // If there's a tie, prefer breakfast > lunch > dinner > snack
      // Only set largest meal if it has calories > 0
      const mealTypePriority = { breakfast: 0, lunch: 1, dinner: 2, snack: 3 };
      let largestMealType = null;
      let largestMealTypeCalories = 0;
      Object.keys(mealTypeCalories).forEach(mealType => {
        const calories = mealTypeCalories[mealType];
        if (calories > 0 && (calories > largestMealTypeCalories || 
            (calories === largestMealTypeCalories && 
             mealTypePriority[mealType] < mealTypePriority[largestMealType]))) {
          largestMealTypeCalories = calories;
          largestMealType = mealType;
        }
      });
      
      // Only set largest meal type if it has actual calories (> 0)
      if (largestMealType && largestMealTypeCalories > 0) {
        patterns.largest_meal_type = {
          meal_type: largestMealType,
          calories: largestMealTypeCalories,
          percentage: Math.round((largestMealTypeCalories / totalCalories) * 100)
        };
      }
    }

    // Count location distribution (only if location is actually provided)
    meals.forEach(meal => {
      const location = meal.location;
      // Only count if location is explicitly provided and not the default 'home'
      if (location && location !== 'home') {
        patterns.location_distribution[location] = 
          (patterns.location_distribution[location] || 0) + 1;
      }
    });
    
    // Remove location_distribution if empty (no actual location data)
    if (Object.keys(patterns.location_distribution).length === 0) {
      delete patterns.location_distribution;
    }

    return patterns;
  }
}

module.exports = new PatternSummaryService();


