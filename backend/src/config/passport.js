const passport = require('passport');
const GoogleStrategy = require('passport-google-oauth20').Strategy;
const FacebookStrategy = require('passport-facebook').Strategy;

// Google Strategy
// Initialize unconditionally to see errors at startup
passport.use(new GoogleStrategy({
    clientID: process.env.GOOGLE_CLIENT_ID || 'dummy_google_id',
    clientSecret: process.env.GOOGLE_CLIENT_SECRET || 'dummy_google_secret',
    callbackURL: process.env.GOOGLE_CALLBACK_URL || 'http://localhost:5000/api/auth/google/callback'
},
    (accessToken, refreshToken, profile, done) => {
        return done(null, profile);
    }
));

// Facebook Strategy
// Initialize unconditionally to see errors at startup
passport.use(new FacebookStrategy({
    clientID: process.env.FACEBOOK_APP_ID || 'dummy',
    clientSecret: process.env.FACEBOOK_APP_SECRET || 'dummy',
    callbackURL: process.env.FACEBOOK_CALLBACK_URL || 'http://localhost:5000/api/auth/facebook/callback',
    profileFields: ['id', 'displayName', 'photos', 'email']
},
    (accessToken, refreshToken, profile, done) => {
        return done(null, profile);
    }
));

module.exports = passport;






