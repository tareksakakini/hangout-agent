/**
 * Prompt templates and formatting for OpenAI calls.
 * All variables are injected via function arguments for clarity.
 */

/**
 * Format the prompt for asking a user about their availability.
 * @param {string} firstName - The user's first name.
 * @param {string} dateRangeText - The planning date range (e.g., "June 10 to June 15").
 * @returns {{system: string, user: string}}
 */
function getAvailabilityPrompt(firstName, dateRangeText) {
  return {
    system: `You are a friendly and casual AI helping a group of friends coordinate hangouts for a specific time period.`,
    user: `Write a message addressed to ${firstName}, asking about their availability for ${dateRangeText}. Make it sound natural, upbeat, and brief. Invite them to suggest activities, locations, or timing preferences.`
  };
}

/**
 * Format the prompt for suggesting group outing options.
 * @param {string} conversationHistory - The formatted conversation history.
 * @param {string[]} userCities - Array of user home cities.
 * @param {string} dateRangeText - The planning date range.
 * @param {string} dateContext - Additional date instructions/context.
 * @returns {{system: string, user: string}}
 */
function getSuggestionPrompt(conversationHistory, userCities, dateRangeText, dateContext) {
  const locationRequirement = userCities.length > 0
    ? `\n\nIMPORTANT LOCATION REQUIREMENT: All suggestions MUST be located in or easily accessible from the group members' areas: ${[...new Set(userCities)].join(', ')}. Consider travel time and convenience for all participants when selecting venues.`
    : '';
  return {
    system: `You are a helpful assistant that analyzes group chat conversations and suggests GROUP activities that appeal to ALL participants collectively. Focus on finding common interests and preferences that work for the entire group. If preferences conflict, favor the most popular ones mentioned by multiple people. Suggest activities that accommodate the group size and allow everyone to participate together. CRITICAL: ALL suggestions must be in or easily accessible from the group members' areas - consider travel distance and convenience for all group members. For each suggestion, include activity, specific location with address, date (use the exact dates provided), specific start and end times. IMPORTANT: Use the exact date format provided (YYYY-MM-DD) in the Date field.`,
    user: `Conversation history:\n${conversationHistory}${locationRequirement}${dateContext}\n\nAnalyze this group conversation to identify shared interests, common preferences, and activities that would appeal to the ENTIRE GROUP collectively.\n\nLook for:\n- Activities mentioned positively by multiple people\n- Common interests or themes across participants\n- Group-friendly activities that everyone can enjoy together\n- Venues that are geographically convenient for all group members\n\nSuggest 5 group outing options for ${dateRangeText} that cater to the collective preferences of all participants AND are conveniently located for everyone. If individual preferences conflict, prioritize those mentioned by multiple people or that have broader appeal. Format each suggestion as a separate paragraph with these details clearly labeled: Activity, Location (with specific address), Date (use YYYY-MM-DD format), Start Time, End Time. Add a brief 1-2 sentence description about why this would appeal to the group as a whole.`
  };
}

/**
 * Format the prompt for selecting the final plan from suggestions.
 * @param {string} conversationHistory - The formatted conversation history.
 * @param {string[]} availableUserNames - Names of available users.
 * @param {string} dateRangeText - The planning date range.
 * @param {string} formattedSuggestions - Numbered list of suggestions.
 * @returns {{system: string, user: string}}
 */
function getFinalPlanPrompt(conversationHistory, availableUserNames, dateRangeText, formattedSuggestions) {
  return {
    system: `You analyze group chat conversations to select the most popular plan from the original suggestions for the specified date range. You must choose exactly one of the numbered options provided. Look for explicit preferences (e.g., 'I like option 1' or 'the first one sounds good') and implicit preferences in the conversation.`,
    user: `Conversation history:\n${conversationHistory}\n\nAvailable participants: ${availableUserNames.join(', ')}\n\nPlanning period: ${dateRangeText}\n\nOriginal suggestions (numbered for reference):\n${formattedSuggestions}\n\nBased on the conversation, which option (1-${formattedSuggestions.split('Option ').length - 1}) is most preferred by the group for ${dateRangeText}? Return ONLY the number of your selection (e.g., '1' or '2').`
  };
}

module.exports = {
  getAvailabilityPrompt,
  getSuggestionPrompt,
  getFinalPlanPrompt
}; 