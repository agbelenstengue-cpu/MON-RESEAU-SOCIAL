// Section 5 : écran d'accueil et inscription étape par étape.
import { t, getLang, setLang, LANGUAGES } from '../i18n.js';
import { post, get } from '../api.js';
import { html, mount, $, $$, logo, icon, errorText, debounce } from '../ui.js';
import { go, setUniverse, signedIn } from '../app.js';

const COUNTRIES = [
  ['CM', '🇨🇲', 'Cameroon', '+237'],
  ['GA', '🇬🇦', 'Gabon', '+241'],
  ['CG', '🇨🇬', 'Congo', '+242'],
  ['CD', '🇨🇩', 'DR Congo', '+243'],
  ['CI', '🇨🇮', "Côte d'Ivoire", '+225'],
  ['SN', '🇸🇳', 'Senegal', '+221'],
  ['NG', '🇳🇬', 'Nigeria', '+234'],
  ['GH', '🇬🇭', 'Ghana', '+233'],
  ['KE', '🇰🇪', 'Kenya', '+254'],
  ['FR', '🇫🇷', 'France', '+33'],
  ['BE', '🇧🇪', 'Belgium', '+32'],
  ['CH', '🇨🇭', 'Switzerland', '+41'],
  ['GB', '🇬🇧', 'United Kingdom', '+44'],
  ['US', '🇺🇸', 'United States', '+1'],
  ['CA', '🇨🇦', 'Canada', '+1'],
];

function langSelect() {
  return html`<select class="lang-select" data-lang aria-label="Language">
    ${LANGUAGES.map((l) => html`<option value="${l.code}" ${getLang() === l.code ? 'selected' : ''}>${l.name}</option>`)}
  </select>`;
}

function wireLang(root, rerender) {
  $('[data-lang]', root)?.addEventListener('change', async (e) => {
    await setLang(e.target.value);
    rerender();
  });
}

export function welcomeScreen(root) {
  setUniverse('me');
  const draw = () => {
    mount(
      root,
      html`<section class="welcome">
        ${logo(120)}
        <div>
          <h1>${t('onboarding.welcome')}</h1>
          <p class="tagline" style="margin-top:12px">${t('onboarding.tagline')}</p>
        </div>
        <div class="actions">
          <a class="btn block" href="#/auth/signup">${t('onboarding.create')}</a>
          <a class="btn ghost block" href="#/auth/login">${t('onboarding.login')}</a>
        </div>
        <div class="foot">
          ${langSelect()}
          <a href="#/welcome" class="muted">${t('onboarding.terms')}</a>
          <a href="#/welcome" class="muted">${t('onboarding.privacy')}</a>
        </div>
      </section>`
    );
    wireLang(root, draw);
  };
  draw();
}

export function authScreen(root) {
  setUniverse('me');
  const state = { step: 'phone', mode: 'otp', exists: false, country: 'CM', number: '', phone: '', devCode: null, ticket: null, birthDate: '', displayName: '', username: '', joinWorld: true };
  let resendTimer = null;

  const age = () => {
    const d = new Date(state.birthDate + 'T00:00:00');
    if (Number.isNaN(d.getTime())) return 0;
    const now = new Date();
    let a = now.getFullYear() - d.getFullYear();
    if (now < new Date(now.getFullYear(), d.getMonth(), d.getDate())) a--;
    return a;
  };

  const frame = (body) => html`<header class="topbar">
      <button class="icon-btn" data-prev aria-label="${t('common.back')}">${icon('back')}</button>
      <h1>${logo(28)}</h1>
      ${langSelect()}
    </header>
    <section class="steps">${body}</section>`;

  const prev = () => {
    const order = ['phone', state.mode === 'password' ? 'password' : 'code', 'birthday', 'identity', 'start'];
    const i = order.indexOf(state.step);
    if (i <= 0 || state.step === 'birthday') return go('welcome');
    state.step = order[i - 1];
    draw();
  };

  const showError = (msg) => {
    const el = $('[data-error]', root);
    if (el) el.textContent = msg;
  };

  const steps = {
    phone() {
      const c = COUNTRIES.find((x) => x[0] === state.country);
      return html`<h2>${t('auth.phoneTitle')}</h2>
        <p class="lead">${t('auth.phoneLead')}</p>
        <form data-form>
          <div class="field">
            <label for="country">${t('auth.country')}</label>
            <select class="input" id="country" data-country>
              ${COUNTRIES.map(([code, flag, name, dial]) => html`<option value="${code}" ${code === state.country ? 'selected' : ''}>${flag} ${name} ${dial}</option>`)}
            </select>
          </div>
          <div class="field">
            <label for="phone">${t('auth.phone')}</label>
            <div class="row">
              <span class="input" style="width:auto;flex:none">${c[3]}</span>
              <input class="input" id="phone" data-number type="tel" inputmode="tel" autocomplete="tel-national" placeholder="6 70 00 00 00" value="${state.number}" required />
            </div>
          </div>
          <p class="error" data-error role="alert"></p>
          <button class="btn block" type="submit">${t('auth.next')}</button>
        </form>`;
    },
    code() {
      return html`<h2>${t('auth.codeTitle')}</h2>
        <p class="lead">${t('auth.codeLead', { phone: state.phone })}</p>
        ${state.devCode ? html`<div class="dev-code">${t('auth.devCode', { code: state.devCode })}</div>` : ''}
        <form data-form>
          <div class="field">
            <input class="input code-input" data-code inputmode="numeric" autocomplete="one-time-code" maxlength="6" placeholder="••••••" required />
          </div>
          <p class="error" data-error role="alert"></p>
          <button class="btn block" type="submit">${t('auth.next')}</button>
          <button class="btn ghost block" type="button" data-resend style="margin-top:8px" disabled>${t('auth.resendIn', { s: 30 })}</button>
        </form>`;
    },
    // Serveur en ligne : mot de passe au lieu du code SMS.
    password() {
      return state.exists
        ? html`<h2>${t('auth.passwordTitle')}</h2>
            <p class="lead">${t('auth.passwordLead', { phone: state.phone })}</p>
            <form data-form>
              <div class="field">
                <label for="pw">${t('auth.password')}</label>
                <input class="input" id="pw" data-password type="password" autocomplete="current-password" required />
              </div>
              <p class="error" data-error role="alert"></p>
              <button class="btn block" type="submit">${t('auth.next')}</button>
            </form>`
        : html`<h2>${t('auth.newPasswordTitle')}</h2>
            <p class="lead">${t('auth.newPasswordLead', { phone: state.phone })}</p>
            <form data-form>
              <div class="field">
                <label for="pw">${t('auth.password')}</label>
                <input class="input" id="pw" data-password type="password" autocomplete="new-password" minlength="8" required />
              </div>
              <div class="field">
                <label for="pw2">${t('auth.passwordConfirm')}</label>
                <input class="input" id="pw2" data-password2 type="password" autocomplete="new-password" minlength="8" required />
              </div>
              <p class="error" data-error role="alert"></p>
              <button class="btn block" type="submit">${t('auth.next')}</button>
            </form>`;
    },
    birthday() {
      return html`<h2>${t('auth.birthdayTitle')}</h2>
        <p class="lead">${t('auth.birthdayLead')}</p>
        <form data-form>
          <div class="field"><input class="input" type="date" data-birth value="${state.birthDate}" max="${new Date().toISOString().slice(0, 10)}" required /></div>
          <p class="error" data-error role="alert"></p>
          <button class="btn block" type="submit">${t('auth.next')}</button>
        </form>`;
    },
    identity() {
      return html`<h2>${t('auth.identityTitle')}</h2>
        <p class="lead">${t('auth.identityLead')}</p>
        <form data-form>
          <div class="field">
            <label for="dn">${t('auth.displayName')}</label>
            <input class="input" id="dn" data-name maxlength="50" value="${state.displayName}" autocomplete="name" required />
          </div>
          <div class="field">
            <label for="un">${t('auth.username')}</label>
            <div class="row"><span class="muted">@</span><input class="input" id="un" data-username maxlength="30" value="${state.username}" autocapitalize="none" autocomplete="username" spellcheck="false" required /></div>
            <span class="hint" data-uhint>${t('auth.usernameHint')}</span>
          </div>
          <p class="error" data-error role="alert"></p>
          <button class="btn block" type="submit">${t('auth.next')}</button>
        </form>`;
    },
    start() {
      const adult = age() >= 18;
      return html`<h2>${t('auth.startTitle')}</h2>
        <form data-form>
          <label class="choice ${!state.joinWorld || !adult ? 'selected' : ''}" style="--accent:var(--me)">
            <input type="radio" name="start" value="private" ${!state.joinWorld || !adult ? 'checked' : ''} />
            <div><h4>${t('auth.stayPrivate')}</h4><p>${t('auth.stayPrivateDesc')}</p></div>
          </label>
          ${adult
            ? html`<label class="choice ${state.joinWorld ? 'selected' : ''}" style="--accent:var(--world)">
                <input type="radio" name="start" value="world" ${state.joinWorld ? 'checked' : ''} />
                <div><h4>${t('auth.joinWorld')}</h4><p>${t('auth.joinWorldDesc')}</p></div>
              </label>`
            : html`<p class="hint">${t('auth.minorNote')}</p>`}
          <p class="error" data-error role="alert"></p>
          <button class="btn block" type="submit">${t('auth.finish')}</button>
        </form>`;
    },
  };

  const startResend = () => {
    let s = 30;
    const btn = $('[data-resend]', root);
    clearInterval(resendTimer);
    resendTimer = setInterval(() => {
      s--;
      if (!btn.isConnected) return clearInterval(resendTimer);
      if (s <= 0) {
        clearInterval(resendTimer);
        btn.disabled = false;
        btn.textContent = t('auth.resend');
      } else btn.textContent = t('auth.resendIn', { s });
    }, 1000);
  };

  const requestCode = async () => {
    const r = await post('/auth/request-otp', { phone: state.phone });
    state.devCode = r.devCode || null;
    state.mode = r.mode === 'password' ? 'password' : 'otp';
    state.exists = !!r.exists;
  };

  const submit = {
    async phone() {
      const c = COUNTRIES.find((x) => x[0] === state.country);
      state.number = $('[data-number]', root).value.trim();
      state.phone = c[3] + state.number.replace(/\D/g, '').replace(/^0+/, '');
      await requestCode();
      state.step = state.mode === 'password' ? 'password' : 'code';
    },
    async password() {
      const password = $('[data-password]', root).value;
      if (state.exists) {
        const r = await post('/auth/password', { phone: state.phone, password });
        return signedIn(r.token, r.user);
      }
      if (password.length < 8) throw { code: 'password_too_short' };
      if (password !== $('[data-password2]', root).value) throw { code: 'password_mismatch' };
      const r = await post('/auth/password', { phone: state.phone, password, create: true });
      state.ticket = r.ticket;
      state.step = 'birthday';
    },
    async code() {
      const r = await post('/auth/verify', { phone: state.phone, code: $('[data-code]', root).value.trim() });
      if (r.token) return signedIn(r.token, r.user);
      state.ticket = r.ticket;
      state.step = 'birthday';
    },
    async birthday() {
      state.birthDate = $('[data-birth]', root).value;
      if (!state.birthDate) throw { code: 'invalid_birth_date' };
      state.step = 'identity';
    },
    async identity() {
      state.displayName = $('[data-name]', root).value.trim();
      state.username = $('[data-username]', root).value.trim().toLowerCase();
      const check = await get(`/auth/username?u=${encodeURIComponent(state.username)}`);
      if (!check.valid) throw { code: 'invalid_username' };
      if (!check.available) throw { code: 'username_taken' };
      state.step = 'start';
    },
    async start() {
      const choice = $('input[name="start"]:checked', root)?.value;
      state.joinWorld = choice === 'world';
      const r = await post('/auth/signup', {
        ticket: state.ticket,
        birthDate: state.birthDate,
        displayName: state.displayName,
        username: state.username,
        joinWorld: state.joinWorld,
        language: getLang(),
        country: state.country,
      });
      return signedIn(r.token, r.user);
    },
  };

  const draw = () => {
    mount(root, frame(steps[state.step]()));
    $('[data-prev]', root).addEventListener('click', prev);
    wireLang(root, draw);
    const form = $('[data-form]', root);
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const btn = $('button[type="submit"]', form);
      btn.disabled = true;
      try {
        const before = state.step;
        await submit[state.step]();
        if (state.step !== before) draw();
      } catch (err) {
        showError(errorText(err));
        if (err.code === 'signup_expired' || err.code === 'too_young') {
          state.step = 'phone';
          setTimeout(draw, 2500);
        }
      } finally {
        if (btn.isConnected) btn.disabled = false;
      }
    });
    if (state.step === 'phone') {
      $('[data-country]', root).addEventListener('change', (e) => {
        state.country = e.target.value;
        state.number = $('[data-number]', root).value;
        draw();
      });
      $('[data-number]', root).focus();
    }
    if (state.step === 'password') $('[data-password]', root).focus();
    if (state.step === 'code') {
      startResend();
      const input = $('[data-code]', root);
      input.focus();
      input.addEventListener('input', () => input.value.replace(/\D/g, '').length === 6 && form.requestSubmit());
      $('[data-resend]', root).addEventListener('click', async () => {
        try {
          await requestCode();
          draw();
        } catch (err) {
          showError(errorText(err));
        }
      });
    }
    if (state.step === 'identity') {
      const name = $('[data-name]', root);
      const user = $('[data-username]', root);
      const hint = $('[data-uhint]', root);
      name.focus();
      // Suggestions automatiques si le nom est pris (5.2, étape 4).
      const check = debounce(async () => {
        const u = user.value.trim().toLowerCase();
        if (!u) return;
        try {
          const r = await get(`/auth/username?u=${encodeURIComponent(u)}`);
          if (!r.valid) mount(hint, html`${t('auth.usernameHint')}`);
          else if (r.available) mount(hint, html`<span style="color:var(--world)">✓ ${t('auth.usernameOk')}</span>`);
          else {
            mount(hint, html`${t('auth.usernameTaken')} ${r.suggestions.map((s) => html`<a href="#" data-sug="${s}">@${s}</a> `)}`);
            $$('[data-sug]', hint).forEach((a) =>
              a.addEventListener('click', (e) => {
                e.preventDefault();
                user.value = a.dataset.sug;
                check();
              })
            );
          }
        } catch {
          /* ignore */
        }
      }, 300);
      // Le @username est proposé à partir du nom tant que la personne ne l'a pas modifié.
      let userEdited = !!user.value;
      user.addEventListener('input', () => {
        userEdited = true;
        user.value = user.value.toLowerCase().replace(/[^a-z0-9._]/g, '');
        check();
      });
      name.addEventListener('input', () => {
        if (userEdited) return;
        user.value = name.value.toLowerCase().normalize('NFD').replace(/[^a-z0-9._]/g, '').slice(0, 30);
        check();
      });
      if (user.value) check();
    }
    if (state.step === 'start') {
      $$('input[name="start"]', root).forEach((r) =>
        r.addEventListener('change', () => {
          $$('.choice', root).forEach((c) => c.classList.toggle('selected', c.contains(r) && r.checked));
        })
      );
    }
  };

  draw();
  return () => clearInterval(resendTimer);
}
