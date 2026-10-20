import {initializeApp} from 'https://www.gstatic.com/firebasejs/12.4.0/firebase-app.js';
import {getAuth, setPersistence, inMemoryPersistence, signInWithEmailAndPassword,
  signOut, sendPasswordResetEmail} from 'https://www.gstatic.com/firebasejs/12.4.0/firebase-auth.js';
import {getFunctions, httpsCallable} from 'https://www.gstatic.com/firebasejs/12.4.0/firebase-functions.js';
import {initializeAppCheck, ReCaptchaEnterpriseProvider} from 'https://www.gstatic.com/firebasejs/12.4.0/firebase-app-check.js';
import {appCheckSiteKey} from './config.js';

const form = document.querySelector('#deletionForm');
const result = document.querySelector('#result');
const submit = document.querySelector('#submit');
const resetPassword = document.querySelector('#resetPassword');
const show = message => { result.textContent = message; };
let auth;
let deleteAccount;

try {
  if (!appCheckSiteKey || appCheckSiteKey.startsWith('SET_')) {
    throw new Error('Online deletion has not yet been configured.');
  }
  // Firebase Hosting serves project-specific public Web App configuration.
  const response = await fetch('/__/firebase/init.json', {cache:'no-store'});
  if (!response.ok) throw new Error('Firebase Hosting configuration unavailable.');
  const options = await response.json();
  if (!options.projectId || !options.appId) throw new Error('Firebase Web App not registered.');
  const app = initializeApp(options);
  initializeAppCheck(app, {
    provider: new ReCaptchaEnterpriseProvider(appCheckSiteKey),
    isTokenAutoRefreshEnabled: true,
  });
  auth = getAuth(app);
  await setPersistence(auth, inMemoryPersistence);
  deleteAccount = httpsCallable(getFunctions(app, 'europe-west1'), 'deleteAccount');
  submit.disabled = false;
  resetPassword.disabled = false;
  submit.textContent = 'Permanently delete account';
} catch (error) {
  show(error.message || 'Deletion service unavailable. Please try later.');
}

resetPassword.addEventListener('click', async () => {
  if (resetPassword.disabled || !auth) return;
  const email = form.elements.namedItem('email').value.trim();
  if (!email) {
    show('Enter your account email above first.');
    return;
  }
  resetPassword.disabled = true;
  try {
    await sendPasswordResetEmail(auth, email);
  } catch (_) {
    // Avoid exposing whether an email is registered with Firebase Auth.
  } finally {
    show('If this email is registered, a password reset message has been sent. Return here after resetting your password.');
    resetPassword.disabled = false;
  }
});

form.addEventListener('submit', async event => {
  event.preventDefault();
  if (submit.disabled || !deleteAccount) return;
  submit.disabled = true;
  show('Verifying your credentials and removing account data…');
  const passwordInput = form.elements.namedItem('password');
  const emailInput = form.elements.namedItem('email');
  const password = passwordInput.value;
  try {
    await signInWithEmailAndPassword(auth, emailInput.value.trim(), password);
    const response = await deleteAccount({
      deleteOwnedHousehold: form.querySelector('#owned').checked,
    });
    if (response.data?.deleted !== true) throw new Error('Server did not confirm deletion.');
    show('Your account deletion was confirmed. You can close this page.');
    form.reset();
    submit.textContent = 'Account deleted';
  } catch (error) {
    show('Deletion could not be confirmed. Check your password, the owner acknowledgment, and your connection. You can retry.');
    submit.disabled = false;
  } finally {
    passwordInput.value = '';
    if (auth?.currentUser) await signOut(auth).catch(() => {});
  }
});
