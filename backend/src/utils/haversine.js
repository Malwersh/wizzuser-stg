/**
 * Haversine Distance Calculator
 * حساب المسافة بين نقطتين جغرافيتين باستخدام صيغة Haversine
 * 
 * Used for calculating distances between geographic coordinates
 * Essential for nearby restaurant search and delivery range validation
 */

/**
 * Calculate distance between two geographic points using Haversine formula
 * @param {number} lat1 - Latitude of first point (دائرة عرض النقطة الأولى)
 * @param {number} lon1 - Longitude of first point (خط طول النقطة الأولى)
 * @param {number} lat2 - Latitude of second point (دائرة عرض النقطة الثانية)
 * @param {number} lon2 - Longitude of second point (خط طول النقطة الثانية)
 * @returns {number} Distance in kilometers (المسافة بالكيلومتر)
 */
function haversineDistance(lat1, lon1, lat2, lon2) {
  // Earth's radius in kilometers
  const R = 6371;

  // Convert degrees to radians
  const dLat = toRadians(lat2 - lat1);
  const dLon = toRadians(lon2 - lon1);
  const radLat1 = toRadians(lat1);
  const radLat2 = toRadians(lat2);

  // Haversine formula
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(radLat1) * Math.cos(radLat2) * Math.sin(dLon / 2) * Math.sin(dLon / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  // Distance in kilometers
  const distance = R * c;

  return distance;
}

/**
 * Convert degrees to radians
 * @param {number} degrees - Angle in degrees
 * @returns {number} Angle in radians
 */
function toRadians(degrees) {
  return degrees * (Math.PI / 180);
}

/**
 * Convert radians to degrees
 * @param {number} radians - Angle in radians
 * @returns {number} Angle in degrees
 */
function toDegrees(radians) {
  return radians * (180 / Math.PI);
}

/**
 * Check if a point is within a given radius of another point
 * @param {number} lat1 - Center latitude
 * @param {number} lon1 - Center longitude
 * @param {number} lat2 - Point latitude
 * @param {number} lon2 - Point longitude
 * @param {number} radiusKm - Radius in kilometers
 * @returns {boolean} True if within radius
 */
function isWithinRadius(lat1, lon1, lat2, lon2, radiusKm) {
  const distance = haversineDistance(lat1, lon1, lat2, lon2);
  return distance <= radiusKm;
}

/**
 * Calculate bearing between two points
 * @param {number} lat1 - Start latitude
 * @param {number} lon1 - Start longitude
 * @param {number} lat2 - End latitude
 * @param {number} lon2 - End longitude
 * @returns {number} Bearing in degrees (0-360)
 */
function calculateBearing(lat1, lon1, lat2, lon2) {
  const radLat1 = toRadians(lat1);
  const radLat2 = toRadians(lat2);
  const dLon = toRadians(lon2 - lon1);

  const y = Math.sin(dLon) * Math.cos(radLat2);
  const x = Math.cos(radLat1) * Math.sin(radLat2) - Math.sin(radLat1) * Math.cos(radLat2) * Math.cos(dLon);

  const bearing = toDegrees(Math.atan2(y, x));

  // Normalize to 0-360
  return (bearing + 360) % 360;
}

/**
 * Sort array of items by distance from a reference point
 * @param {Array} items - Array of objects with latitude/longitude
 * @param {number} refLat - Reference latitude
 * @param {number} refLon - Reference longitude
 * @param {string} latField - Field name for latitude (default: 'latitude')
 * @param {string} lonField - Field name for longitude (default: 'longitude')
 * @returns {Array} Sorted array with added 'distance' field
 */
function sortByDistance(items, refLat, refLon, latField = 'latitude', lonField = 'longitude') {
  // Calculate distance for each item
  const itemsWithDistance = items.map((item) => {
    const distance = haversineDistance(refLat, refLon, item[latField], item[lonField]);
    return {
      ...item,
      distance: parseFloat(distance.toFixed(2)), // Round to 2 decimal places
    };
  });

  // Sort by distance (ascending)
  return itemsWithDistance.sort((a, b) => a.distance - b.distance);
}

/**
 * Filter items within a radius
 * @param {Array} items - Array of objects with latitude/longitude
 * @param {number} refLat - Reference latitude
 * @param {number} refLon - Reference longitude
 * @param {number} radiusKm - Radius in kilometers
 * @param {string} latField - Field name for latitude
 * @param {string} lonField - Field name for longitude
 * @returns {Array} Filtered array with added 'distance' field
 */
function filterByRadius(items, refLat, refLon, radiusKm, latField = 'latitude', lonField = 'longitude') {
  return items
    .map((item) => {
      const distance = haversineDistance(refLat, refLon, item[latField], item[lonField]);
      return {
        ...item,
        distance: parseFloat(distance.toFixed(2)),
      };
    })
    .filter((item) => item.distance <= radiusKm);
}

module.exports = {
  haversineDistance,
  toRadians,
  toDegrees,
  isWithinRadius,
  calculateBearing,
  sortByDistance,
  filterByRadius,
};
