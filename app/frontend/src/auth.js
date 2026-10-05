// =====================================================================
// Azure AD (Entra ID) sign-in with MSAL + token for the backend API.
// The token is sent as "Authorization: Bearer <token>" to APIM,
// and APIM's validate-jwt policy checks it before forwarding.
// =====================================================================
import { PublicClientApplication, InteractionRequiredAuthError } from "@azure/msal-browser";

const TENANT_ID = import.meta.env.VITE_AAD_TENANT_ID || "";
const CLIENT_ID = import.meta.env.VITE_AAD_CLIENT_ID || "";
const API_SCOPE = import.meta.env.VITE_API_SCOPE || "";

// No client ID = local mode (no login, calls the Vite proxy directly)
export const authEnabled = Boolean(TENANT_ID && CLIENT_ID && API_SCOPE);

const msal = authEnabled
  ? new PublicClientApplication({
      auth: {
        clientId: CLIENT_ID,
        authority: `https://login.microsoftonline.com/${TENANT_ID}`,
        // Must match the SPA redirect URIs registered in Entra (with trailing slash)
        redirectUri: window.location.origin + "/",
      },
      cache: { cacheLocation: "sessionStorage" },
    })
  : null;

let ready = null;
function init() {
  if (!msal) return Promise.resolve();
  ready ??= msal.initialize().then(() => msal.handleRedirectPromise());
  return ready;
}

export async function getAccount() {
  await init();
  return msal ? msal.getAllAccounts()[0] || null : null;
}

export async function signIn() {
  await init();
  const result = await msal.loginPopup({ scopes: [API_SCOPE] });
  return result.account;
}

export async function signOut() {
  await init();
  await msal.logoutPopup();
}

// Returns an access token for the backend API (silent first, popup if needed)
export async function getToken() {
  if (!authEnabled) return null;
  await init();
  const account = msal.getAllAccounts()[0];
  if (!account) throw new Error("Please sign in first");
  try {
    const r = await msal.acquireTokenSilent({ scopes: [API_SCOPE], account });
    return r.accessToken;
  } catch (e) {
    if (e instanceof InteractionRequiredAuthError) {
      const r = await msal.acquireTokenPopup({ scopes: [API_SCOPE], account });
      return r.accessToken;
    }
    throw e;
  }
}