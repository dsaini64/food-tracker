class NutritionService {
  constructor() {
    // Basic nutrition database (in production, this would be a real database)
    this.nutritionDatabase = {
      // Common foods with nutrition data
      "chicken breast": { calories: 165, protein: 31, carbs: 0, fat: 3.6, fiber: 0 },
      "brown rice": { calories: 112, protein: 2.6, carbs: 22, fat: 0.9, fiber: 1.8 },
      "salmon": { calories: 208, protein: 25, carbs: 0, fat: 12, fiber: 0 },
      "broccoli": { calories: 34, protein: 2.8, carbs: 7, fat: 0.4, fiber: 2.6 },
      "apple": { calories: 52, protein: 0.3, carbs: 14, fat: 0.2, fiber: 2.4 },
      "banana": { calories: 89, protein: 1.1, carbs: 23, fat: 0.3, fiber: 2.6 },
      "avocado": { calories: 160, protein: 2, carbs: 9, fat: 15, fiber: 7 },
      "eggs": { calories: 155, protein: 13, carbs: 1.1, fat: 11, fiber: 0 },
      "quinoa": { calories: 120, protein: 4.4, carbs: 22, fat: 1.9, fiber: 2.8 },
      "sweet potato": { calories: 86, protein: 1.6, carbs: 20, fat: 0.1, fiber: 3 }
    };
  }

  async enhanceWithNutritionData(chatGPTResponse) {
    try {
      const enhancedFoods = chatGPTResponse.foods.map((food, index) => {
        // Try to match with our nutrition database
        const matchedFood = this.findBestMatch(food.name);
        
        if (matchedFood) {
          // Use database values as base, adjust by confidence
          const confidence = food.confidence || 0.5;
          return {
            id: `food_${Date.now()}_${index}`, // Add unique ID
            ...food,
            calories: Math.round((matchedFood.calories * confidence) + (food.calories * (1 - confidence))),
            protein: Math.round((matchedFood.protein * confidence) + (food.protein * (1 - confidence)) * 10) / 10,
            carbs: Math.round((matchedFood.carbs * confidence) + (food.carbs * (1 - confidence)) * 10) / 10,
            fat: Math.round((matchedFood.fat * confidence) + (food.fat * (1 - confidence)) * 10) / 10,
            fiber: Math.round((matchedFood.fiber * confidence) + (food.fiber * (1 - confidence)) * 10) / 10,
            verified: true
          };
        } else {
          // Use ChatGPT estimates with lower confidence
          return {
            id: `food_${Date.now()}_${index}`, // Add unique ID
            ...food,
            verified: false,
            confidence: (food.confidence || 0.5) * 0.8 // Reduce confidence for unverified foods
          };
        }
      });

      // Calculate totals
      const totals = this.calculateTotals(enhancedFoods);
      
      // Generate health insights
      const insights = this.generateHealthInsights(enhancedFoods, totals);
      
      return {
        foods: enhancedFoods,
        overallConfidence: chatGPTResponse.overall_confidence || chatGPTResponse.overallConfidence || 0.5,
        imageDescription: chatGPTResponse.image_description || chatGPTResponse.imageDescription || "Food image",
        suggestions: chatGPTResponse.suggestions || [],
        totals,
        insights,
        timestamp: new Date().toISOString()
      };

    } catch (error) {
      console.error('Error enhancing nutrition data:', error);
      return chatGPTResponse; // Return original if enhancement fails
    }
  }

  findBestMatch(foodName) {
    const normalizedName = foodName.toLowerCase().trim();
    
    // Direct match
    if (this.nutritionDatabase[normalizedName]) {
      return this.nutritionDatabase[normalizedName];
    }
    
    // Partial match
    for (const [key, value] of Object.entries(this.nutritionDatabase)) {
      if (normalizedName.includes(key) || key.includes(normalizedName)) {
        return value;
      }
    }
    
    return null;
  }

  calculateTotals(foods) {
    return foods.reduce((totals, food) => {
      totals.calories += food.calories || 0;
      totals.protein += food.protein || 0;
      totals.carbs += food.carbs || 0;
      totals.fat += food.fat || 0;
      totals.fiber += food.fiber || 0;
      return totals;
    }, {
      calories: 0,
      protein: 0,
      carbs: 0,
      fat: 0,
      fiber: 0
    });
  }

  generateHealthInsights(foods, totals) {
    const insights = [];
    
    // Protein analysis
    if (totals.protein < 20) {
      insights.push("Consider adding more protein to this meal");
    } else if (totals.protein > 50) {
      insights.push("High protein meal - great for muscle building!");
    }
    
    // Fiber analysis
    if (totals.fiber < 5) {
      insights.push("Add more fiber-rich foods like vegetables or whole grains");
    }
    
    // Fat analysis
    if (totals.fat < 10) {
      insights.push("Consider adding healthy fats like avocado or nuts");
    } else if (totals.fat > 40) {
      insights.push("This meal is high in fat - consider lighter options");
    }
    
    // Calorie analysis
    if (totals.calories < 200) {
      insights.push("This might be a light meal - consider adding more food");
    } else if (totals.calories > 800) {
      insights.push("High calorie meal - consider portion control");
    }
    
    return insights;
  }

  async generateSuggestions(foodItems, userGoals) {
    try {
      const suggestions = [];
      
      // Analyze current meal
      const totals = this.calculateTotals(foodItems);
      
      // Goal-based suggestions
      if (userGoals.goal === 'weight_loss') {
        if (totals.calories > userGoals.dailyCalories * 0.4) {
          suggestions.push("This meal is high in calories for weight loss. Consider smaller portions.");
        }
        if (totals.fiber < 10) {
          suggestions.push("Add more fiber-rich foods to help with satiety and weight loss.");
        }
      }
      
      if (userGoals.goal === 'muscle_gain') {
        if (totals.protein < 30) {
          suggestions.push("Add more protein to support muscle growth.");
        }
        if (totals.calories < 500) {
          suggestions.push("Consider adding more calories for muscle building.");
        }
      }
      
      // General health suggestions
      if (totals.fiber < 5) {
        suggestions.push("Add vegetables or whole grains for more fiber.");
      }
      
      if (totals.protein < 20) {
        suggestions.push("Include a protein source like chicken, fish, or beans.");
      }
      
      return {
        suggestions,
        mealScore: this.calculateMealScore(totals, userGoals),
        nextMealAdvice: this.getNextMealAdvice(totals, userGoals)
      };
      
    } catch (error) {
      console.error('Error generating suggestions:', error);
      return {
        suggestions: ["Unable to generate suggestions at this time"],
        mealScore: 0,
        nextMealAdvice: "Try to include a variety of nutrients in your next meal"
      };
    }
  }

  calculateMealScore(totals, userGoals) {
    let score = 0;
    
    // Protein score (0-25 points)
    const proteinScore = Math.min(25, (totals.protein / 30) * 25);
    score += proteinScore;
    
    // Fiber score (0-25 points)
    const fiberScore = Math.min(25, (totals.fiber / 10) * 25);
    score += fiberScore;
    
    // Calorie appropriateness (0-25 points)
    const calorieScore = userGoals.dailyCalories ? 
      Math.max(0, 25 - Math.abs(totals.calories - (userGoals.dailyCalories * 0.3)) / 50) : 15;
    score += calorieScore;
    
    // Variety score (0-25 points)
    const varietyScore = Math.min(25, totals.fiber > 0 && totals.protein > 0 ? 25 : 15);
    score += varietyScore;
    
    return Math.round(score);
  }

  getNextMealAdvice(totals, userGoals) {
    if (totals.protein < 20) {
      return "Your next meal should focus on protein-rich foods like chicken, fish, or legumes.";
    }
    if (totals.fiber < 5) {
      return "Add more vegetables and whole grains to your next meal for better fiber intake.";
    }
    if (totals.calories < 300) {
      return "Consider a more substantial meal next time to meet your daily calorie needs.";
    }
    return "Great meal! Continue with balanced nutrition in your next meal.";
  }
}

module.exports = new NutritionService();


