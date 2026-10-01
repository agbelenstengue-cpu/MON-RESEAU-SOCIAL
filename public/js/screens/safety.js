// Section 22 : mes signalements, statut du compte (avertissements, appel) et
// console de modération (27.4) pour les modérateurs.
import { t, relTime } from '../i18n.js';
import { store, get, post } from '../api.js';
import { html, mount, $, $$, icon, avatar, toast, showError, dialog, empty, skeleton } from '../ui.js';
import { layout, backButton, wireBack, go } from '../app.js';

const fmtDate = (ts) => new Intl.DateTimeFormat(document.documentElement.lang || 'en', { day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' }).format(ts);

export async function myReportsScreen(root) {
  const main = layout(root, { universe: 'me', title: t('safety.myReports'), left: backButton() });
  wireBack(root, 'me');
  mount(main, skeleton(3));
  const reports = await get('/me/reports').catch(() => []);
  mount(
    main,
    reports.length
      ? html`<ul class="list">${reports.map(
          (r) => html`<li class="list-item" style="cursor:default">
            ${icon('flag')}
            <span class="grow"><span class="title" style="display:block">${t(`report.${r.reason}`)} · ${t(`safety.target.${r.targetType}`)}</span>
              <span class="preview">${relTime(r.createdAt)} · ${r.status === 'open' ? t('safety.inReview') : t(`safety.decision.${r.decision}`)}</span></span>
            <span class="badge" style="${r.status === 'open' ? 'background:var(--brass)' : ''}">${r.status === 'open' ? '…' : '✓'}</span>
          </li>`
        )}</ul>`
      : empty(t('safety.noReports'), t('safety.noReportsLead'))
  );
}

// Page « Account status » (22.5).
export async function accountStatusScreen(root) {
  const main = layout(root, { universe: 'me', title: t('safety.status'), left: backButton() });
  wireBack(root, 'me');
  const draw = async () => {
    const s = await get('/me/status').catch((err) => (showError(err), null));
    if (!s) return;
    const ok = !s.strikes.length && !s.restrictedUntil && !s.suspendedUntil;
    mount(
      main,
      html`<div class="status-head ${ok ? 'good' : 'warn'}">
          ${icon(ok ? 'check' : 'flag')}
          <div><b>${ok ? t('safety.allGood') : t('safety.hasStrikes', { count: s.strikes.length })}</b>
            ${s.suspendedUntil ? html`<p>${t('safety.suspendedUntil', { date: fmtDate(s.suspendedUntil) })}</p>` : ''}
            ${s.restrictedUntil ? html`<p>${t('safety.restrictedUntil', { date: fmtDate(s.restrictedUntil) })}</p>` : ''}
          </div>
        </div>
        <p class="muted small section">${t('safety.ladder')}</p>
        ${s.strikes.length
          ? html`<div class="section-title">${t('safety.activeStrikes')}</div>
              <ul class="list">${s.strikes.map(
                (k) => html`<li class="list-item" style="cursor:default">
                  <span class="grow"><span class="title" style="display:block">${t(`report.${k.reason}`)}</span>
                    <span class="preview">${t('safety.expires', { date: fmtDate(k.expiresAt) })}</span></span>
                  ${k.appealStatus === 'none'
                    ? html`<button class="btn small ghost" data-appeal="${k.id}">${t('safety.appeal')}</button>`
                    : html`<span class="small muted">${t(`safety.appeal.${k.appealStatus}`)}</span>`}
                </li>`
              )}</ul>`
          : ''}`
    );
    $$('[data-appeal]', main).forEach((b) =>
      b.addEventListener('click', async () => {
        const text = await dialog({ title: t('safety.appeal'), body: t('safety.appealLead'), confirm: t('share.send'), input: { placeholder: t('safety.appealPlaceholder') } });
        if (text == null) return;
        try {
          await post(`/me/strikes/${b.dataset.appeal}/appeal`, { text });
          toast(t('safety.appealSent'));
          draw();
        } catch (err) {
          showError(err);
        }
      })
    );
  };
  await draw();
}

// ---------------- Console de modération ----------------
export async function moderationScreen(root, { tab = 'reports' } = {}) {
  if (store.me.role !== 'moderator') return go('me');
  const main = layout(root, { universe: 'me', title: t('mod.title'), left: backButton() });
  wireBack(root, 'me');
  const SEV = ['critical', 'high', 'medium', 'low', 'low'];

  const preview = (type, p) => {
    if (!p) return html`<p class="muted small">${t('mod.gone')}</p>`;
    if (type === 'message') {
      return html`<div class="mod-context">${(p.context || []).map((c) => html`<div class="small muted"><b>${c.sender}</b> : ${c.body || '…'}</div>`)}
        <div class="mod-reported"><b>${t('mod.reportedMessage')}</b> ${p.body || (p.media ? '📷' : '')}</div></div>`;
    }
    if (type === 'user') return html`<div class="small">${p.name}${p.publicName ? ` · ${p.publicName}` : ''}<br />${p.bio || p.about || ''}</div>`;
    return html`${p.body ? html`<div class="mod-body">${p.body}</div>` : ''}
      ${p.video ? html`<video class="mod-media" src="${p.video}" controls muted></video>` : p.media ? html`<img class="mod-media blur" data-unblur src="${p.media}" alt="" />` : ''}`;
  };

  const drawReports = async () => {
    mount($('[data-pane]', main), skeleton(3));
    const items = await get('/mod/reports').catch((err) => (showError(err), []));
    mount(
      $('[data-pane]', main),
      items.length
        ? html`${items.map(
            (r) => html`<article class="mod-card sev-${SEV[r.severity]}">
              <div class="row">
                <span class="sev">${t(`mod.sev.${SEV[r.severity]}`)}</span>
                <span class="grow small">${r.reasons.map((x) => t(`report.${x}`)).join(' · ')} · ${t(`safety.target.${r.targetType}`)}</span>
                <span class="small muted">×${r.count} · ${relTime(r.firstAt)}</span>
              </div>
              ${r.author ? html`<div class="row small" style="margin:8px 0">${avatar(r.author, 'xs')} <b>${r.author.name}</b> @${r.author.username} · ${t('mod.strikes', { count: r.authorStrikes })}</div>` : ''}
              ${preview(r.targetType, r.preview)}
              ${r.details.length ? html`<p class="small muted">« ${r.details.join(' » · « ')} »</p>` : ''}
              <div class="row mod-actions">
                <button class="btn small ghost" data-decide="${r.id}:dismiss">${t('mod.dismiss')}</button>
                <button class="btn small" data-decide="${r.id}:remove">${t('mod.remove')}</button>
                <button class="btn small danger" data-decide="${r.id}:ban">${t('mod.ban')}</button>
              </div>
            </article>`
          )}`
        : empty(t('mod.empty'))
    );
    $$('[data-unblur]', main).forEach((img) => img.addEventListener('click', () => img.classList.toggle('blur')));
    $$('[data-decide]', main).forEach((b) =>
      b.addEventListener('click', async () => {
        const [id, action] = b.dataset.decide.split(':');
        if (action === 'ban' && !(await dialog({ title: t('mod.ban'), body: t('mod.banLead'), confirm: t('mod.ban'), danger: true }))) return;
        try {
          const r = await post(`/mod/reports/${id}/decide`, { action });
          toast(r.sanction ? t(`mod.sanction.${r.sanction.kind}`) : t('common.done'));
          drawReports();
        } catch (err) {
          showError(err);
        }
      })
    );
  };

  const drawAppeals = async () => {
    const items = await get('/mod/appeals').catch((err) => (showError(err), []));
    mount(
      $('[data-pane]', main),
      items.length
        ? html`${items.map(
            (a) => html`<article class="mod-card">
              <div class="row small">${avatar(a.user, 'xs')} <b>${a.user?.name}</b> · ${t(`report.${a.reason}`)} · ${relTime(a.appealedAt)}</div>
              ${a.preview?.body ? html`<div class="mod-body">${a.preview.body}</div>` : ''}
              <p>« ${a.text || '—'} »</p>
              ${a.decidedBy === store.me.id ? html`<p class="small muted">${t('mod.ownDecision')}</p>` : ''}
              <div class="row mod-actions">
                <button class="btn small ghost" data-appeal="${a.id}:uphold">${t('mod.uphold')}</button>
                <button class="btn small world" data-appeal="${a.id}:overturn">${t('mod.overturn')}</button>
              </div>
            </article>`
          )}`
        : empty(t('mod.noAppeals'))
    );
    $$('[data-appeal]', main).forEach((b) =>
      b.addEventListener('click', async () => {
        const [id, decision] = b.dataset.appeal.split(':');
        try {
          await post(`/mod/appeals/${id}`, { decision });
          drawAppeals();
        } catch (err) {
          showError(err);
        }
      })
    );
  };

  mount(
    main,
    html`<div class="chips">
        <a class="chip ${tab === 'reports' ? 'active' : ''}" href="#/moderation">${t('mod.reports')}</a>
        <a class="chip ${tab === 'appeals' ? 'active' : ''}" href="#/moderation/appeals">${t('mod.appeals')}</a>
      </div>
      <p class="small muted" style="padding:0 16px">${t('mod.lead')}</p>
      <div data-pane></div>`
  );
  await (tab === 'appeals' ? drawAppeals() : drawReports());
}
