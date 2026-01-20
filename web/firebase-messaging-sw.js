/* eslint-disable no-undef */

importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js");

// ✅ MUST match your Firebase Web app config
firebase.initializeApp({
  apiKey: "AIzaSyARV8U2DtQJ94zqC3bdZZYiXkAH13cwo9k",
  authDomain: "fit-quest-853bc.firebaseapp.com",
  projectId: "fit-quest-853bc",
  storageBucket: "fit-quest-853bc.appspot.com",
  messagingSenderId: "236363127027",
  appId: "1:236363127027:web:1e23d6136782e5106d7f86",
});

const messaging = firebase.messaging();

// For “data-only” messages in background:
messaging.onBackgroundMessage((payload) => {
  const title = payload?.notification?.title || "Fit Quest";
  const body = payload?.notification?.body || "New notification";
  self.registration.showNotification(title, { body });
});
