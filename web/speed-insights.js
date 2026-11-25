/**
 * Vercel Speed Insights integration for MindMate
 * This script injects the Speed Insights tracking for Flutter web app
 */

(function() {
  'use strict';
  
  // Speed Insights injection script
  // This will be loaded when the app is deployed on Vercel
  
  if (typeof window !== 'undefined') {
    // Initialize Speed Insights queue
    window.si = window.si || function () { 
      (window.siq = window.siq || []).push(arguments); 
    };
    
    // Load the Speed Insights script
    // The script path will be automatically configured by Vercel during deployment
    var script = document.createElement('script');
    script.defer = true;
    script.src = '/_vercel/speed-insights/script.js';
    
    // Append the script to the document
    if (document.head) {
      document.head.appendChild(script);
    } else {
      // Fallback if head is not yet available
      document.addEventListener('DOMContentLoaded', function() {
        document.head.appendChild(script);
      });
    }
  }
})();
